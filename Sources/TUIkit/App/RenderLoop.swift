//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoop.swift
//
//  Created by LAYERED.work
//  License: MIT  assembly, and status bar output.
//

// MARK: - Environment Snapshot

/// A snapshot of environment values that affect rendered output.
///
/// Used by `RenderLoop` to detect environment changes (theme, appearance)
/// between frames. When the snapshot differs from the previous frame, the
/// render cache is cleared so `EquatableView`-cached subtrees re-render
/// with the updated values.
///
/// Only tracks values that affect visual output — reference-type infrastructure
/// services (`FocusManager`, `ThemeManager`) are excluded.
private struct EnvironmentSnapshot: Equatable {
    /// The active palette identifier.
    let paletteID: String

    /// The active appearance identifier.
    let appearanceID: String

    /// Creates a snapshot from fully-built environment values.
    init(from environment: EnvironmentValues) {
        self.paletteID = environment.palette.id
        self.appearanceID = environment.appearance.id
    }
}

/// ANSI background codes for each render surface in a frame.
///
/// Keeping these grouped avoids accidentally rendering every surface
/// with `palette.background` and ignoring palette-specific tokens like
/// `statusBarBackground`.
internal struct RenderBackgroundCodes: Equatable {
    /// Main content area background code.
    let content: String

    /// App header background code.
    let appHeader: String

    /// Status bar background code.
    let statusBar: String

    init(palette: any Palette) {
        self.content = ANSIRenderer.backgroundCode(for: palette.background)
        self.appHeader = ANSIRenderer.backgroundCode(for: palette.appHeaderBackground)
        self.statusBar = ANSIRenderer.backgroundCode(for: palette.statusBarBackground)
    }
}

// MARK: - Render Loop

/// Manages the full rendering pipeline for each frame.
///
/// `RenderLoop` is owned by `AppRunner` and called once per frame.
/// It orchestrates the complete render pass from `App.body` to
/// terminal output.
///
/// ## Pipeline steps (per frame)
///
/// ```
/// render()
///   1. Clear per-frame state (key handlers, preferences, focus)
///   2. Begin lifecycle tracking
///   3. Build EnvironmentValues from all subsystems
///   4. Create RenderContext with layout constraints
///   5. Evaluate App.body fresh → Scene (WindowGroup)
///      @State values survive because State.init self-hydrates from StateStorage
///   6. Call SceneRenderable.renderScene() → FrameBuffer
///   7. Convert FrameBuffer to terminal-ready output lines
///   8. Begin buffered frame (terminal.beginFrame())
///   9. Diff against previous frame, write only changed lines to buffer
///  10. Render status bar into same buffer (with its own diff tracking)
///  11. Flush entire frame in one write() syscall (terminal.endFrame())
///  12. End lifecycle tracking (fires onDisappear for removed views)
/// ```
///
/// ## Diff-Based Rendering
///
/// `RenderLoop` uses a `FrameDiffWriter` to compare each frame's output
/// with the previous frame. Only lines that actually changed are written
/// to the terminal, reducing I/O by ~94% for mostly-static UIs.
///
/// ## Output Buffering
///
/// All diff writes (content + status bar) are collected in `Terminal`'s
/// frame buffer and flushed as a single `write()` syscall via
/// `Terminal.beginFrame()` / `Terminal.endFrame()`. This reduces
/// per-frame syscalls from ~40+ to exactly 1.
///
/// On terminal resize (SIGWINCH), the diff cache is invalidated to force
/// a full repaint.
///
/// ## Responsibilities
///
/// - Assembling ``EnvironmentValues`` from all subsystems
/// - Rendering the main scene content via `SceneRenderable`
/// - Rendering the status bar separately (never dimmed)
/// - Coordinating lifecycle tracking (appear/disappear)
/// - Diff-based terminal output via `FrameDiffWriter`
/// - Buffered frame output via `Terminal`
@MainActor
internal final class RenderLoop<A: App> {
    /// The user's app instance (provides `body`).
    let app: A

    /// The terminal for output and size queries.
    let terminal: Terminal

    /// The status bar state (height, items, appearance).
    let statusBar: StatusBarState

    /// The app header state (content buffer, visibility).
    let appHeader: AppHeaderState

    /// The focus manager (cleared each frame).
    let focusManager: FocusManager

    /// The palette manager (current theme for environment).
    let paletteManager: ThemeManager

    /// The appearance manager (current border style for environment).
    let appearanceManager: ThemeManager

    /// The central dependency container (lifecycle, key dispatch, preferences).
    let tuiContext: TUIContext

    /// The diff writer that tracks previous frames and writes only changed lines.
    private let diffWriter = FrameDiffWriter()

    /// The environment snapshot from the previous frame.
    ///
    /// Compared after `buildEnvironment()` each frame. When the snapshot
    /// differs (e.g. palette or appearance changed), the render cache is
    /// cleared automatically. This ensures `EquatableView`-cached subtrees
    /// never serve stale content after theme changes — without requiring
    /// callers to manually invalidate the cache.
    private var lastEnvironmentSnapshot: EnvironmentSnapshot?

    /// Whether the first frame has been rendered.
    ///
    /// On the first frame, we perform a "measurement pass" to determine
    /// the actual header height before outputting anything. This prevents
    /// visible content jumping when the estimated header height differs
    /// from the actual height.
    private var isFirstFrame = true

    init(
        app: A,
        terminal: Terminal,
        statusBar: StatusBarState,
        appHeader: AppHeaderState,
        focusManager: FocusManager,
        paletteManager: ThemeManager,
        appearanceManager: ThemeManager,
        tuiContext: TUIContext
    ) {
        self.app = app
        self.terminal = terminal
        self.statusBar = statusBar
        self.appHeader = appHeader
        self.focusManager = focusManager
        self.paletteManager = paletteManager
        self.appearanceManager = appearanceManager
        self.tuiContext = tuiContext
    }
}

// MARK: - Internal API

extension RenderLoop {
    /// Performs a full render pass: scene content + status bar.
    ///
    /// See the class-level documentation for the complete pipeline steps.
    ///
    /// - Parameters:
    ///   - pulsePhase: The current breathing indicator phase (0–1).
    ///     Passed from `PulseTimer` via `AppRunner`.
    ///   - cursorTimer: The cursor timer for TextField/SecureField animations.
    func render(pulsePhase: Double = 0, cursorTimer: CursorTimer? = nil) {
        beginRenderPass()

        // If an @Published property changed, clear the entire render cache
        // so EquatableView-cached subtrees re-render with new model data.
        if AppState.shared.consumeNeedsCacheClear() {
            tuiContext.renderCache.clearAll()
        }

        // Terminal size: single getSize() call avoids 2 ioctl syscalls per frame.
        let terminalSize = terminal.getSize()
        let statusBarHeight = statusBar.height
        let terminalWidth = terminalSize.width
        let terminalHeight = terminalSize.height

        // Create render context with environment
        var environment = buildEnvironment()
        environment.pulsePhase = pulsePhase
        environment.cursorTimer = cursorTimer

        let scene = evaluateAppBody(environment: environment)
        if let paletteOverrideScene = scene as? any RootPaletteOverrideProvidingScene,
            let paletteOverride = paletteOverrideScene.rootPaletteOverride()
        {
            environment.palette = paletteOverride
        }
        invalidateCacheIfEnvironmentChanged(environment: environment)

        // Determine header height. On the first frame, we perform a measurement
        // pass to discover the actual header height before outputting anything.
        // This prevents visible content jumping.
        let appHeaderHeight: Int
        if isFirstFrame {
            let measureContext = RenderContext(
                availableWidth: terminalWidth,
                availableHeight: terminalHeight - statusBarHeight,
                environment: environment
            )
            _ = renderScene(scene, context: measureContext.withChildIdentity(type: type(of: scene)))
            appHeaderHeight = appHeader.height
            isFirstFrame = false
        } else {
            appHeaderHeight = appHeader.estimatedHeight
        }

        let contentHeight = terminalHeight - statusBarHeight - appHeaderHeight

        var context = RenderContext(
            availableWidth: terminalWidth,
            availableHeight: contentHeight,
            environment: environment
        )
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true

        var buffer = renderScene(scene, context: context.withChildIdentity(type: type(of: scene)))

        // If the header height changed after rendering, re-render with the
        // correct height so centering is accurate.
        let actualHeaderHeight = appHeader.height
        if actualHeaderHeight != appHeaderHeight {
            diffWriter.invalidate()
            let actualContentHeight = terminalHeight - statusBarHeight - actualHeaderHeight
            var correctedContext = RenderContext(
                availableWidth: terminalWidth,
                availableHeight: actualContentHeight,
                environment: environment
            )
            correctedContext.hasExplicitWidth = true
            correctedContext.hasExplicitHeight = true
            buffer = renderScene(scene, context: correctedContext.withChildIdentity(type: type(of: scene)))
        }

        focusManager.endRenderPass()

        // Composite any free-floating overlay layers (Picker drop-downs,
        // popovers, …) emitted during rendering onto the content buffer.
        if !buffer.overlays.isEmpty {
            let overlayContentHeight = terminalHeight - statusBarHeight - appHeader.height
            buffer = compositeOverlays(
                buffer, maxWidth: terminalWidth, maxHeight: overlayContentHeight)
        }

        // Publish the now-composited hit-test regions so the dispatcher
        // can route mouse events arriving between this frame and the
        // next. Regions are kept in absolute content-area coordinates;
        // the App input loop translates terminal coords to content
        // coords before dispatching.
        tuiContext.mouseEventDispatcher.setRegions(buffer.hitTestRegions)

        writeFrame(
            buffer: buffer,
            environment: environment,
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight,
            statusBarHeight: statusBarHeight,
            headerHeight: appHeader.height
        )

        endRenderPass()
    }

    /// Invalidates the diff cache, forcing a full repaint on the next render.
    ///
    /// Call this when the terminal is resized (SIGWINCH).
    func invalidateDiffCache() {
        diffWriter.invalidate()
    }

    /// Builds a complete ``EnvironmentValues`` with all managed subsystems.
    ///
    /// - Returns: A fully populated environment.
    func buildEnvironment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.statusBar = statusBar
        environment.appHeader = appHeader
        environment.focusManager = focusManager
        environment.paletteManager = paletteManager
        if let palette = paletteManager.currentPalette {
            environment.palette = palette
        }
        environment.appearanceManager = appearanceManager
        if let appearance = appearanceManager.currentAppearance {
            environment.appearance = appearance
        }
        environment.notificationService = NotificationService.current

        // Runtime services (previously accessed via context.tuiContext)
        environment.stateStorage = tuiContext.stateStorage
        environment.lifecycle = tuiContext.lifecycle
        environment.keyEventDispatcher = tuiContext.keyEventDispatcher
        environment.mouseEventDispatcher = tuiContext.mouseEventDispatcher
        environment.renderCache = tuiContext.renderCache
        environment.preferenceStorage = tuiContext.preferences
        environment.localizationService = LocalizationService.shared

        return environment
    }
}

// MARK: - Private Helpers

extension RenderLoop {
    /// Clears all per-frame state and begins lifecycle/state/cache tracking.
    fileprivate func beginRenderPass() {
        tuiContext.keyEventDispatcher.clearHandlers()
        tuiContext.mouseEventDispatcher.beginRenderPass()
        tuiContext.preferences.beginRenderPass()
        focusManager.beginRenderPass()
        statusBar.clearSectionItems()
        // The transient escape-label override is published by whichever
        // open modal surface (Picker drop-down, etc.) renders in this
        // frame; clearing it here makes the default the absence of any
        // override, so a surface that disappeared on the previous frame
        // never leaves its stale label behind on the next page.
        statusBar.escapeLabelOverride = nil
        appHeader.beginRenderPass()
        statusBar.focusManager = focusManager
        tuiContext.lifecycle.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
    }

    /// Evaluates `App.body` with hydration and environment context active.
    ///
    /// Sets up ``StateRegistration`` so `@State` self-hydrates from `StateStorage`
    /// and `@Environment` reads from the current environment. Clears both
    /// contexts after body evaluation.
    fileprivate func evaluateAppBody(environment: EnvironmentValues) -> A.Body {
        let rootIdentity = ViewIdentity(rootType: A.self)
        StateRegistration.activeContext = HydrationContext(
            identity: rootIdentity,
            storage: tuiContext.stateStorage
        )
        StateRegistration.counter = 0
        StateRegistration.activeEnvironment = environment

        let scene = app.body

        StateRegistration.activeContext = nil
        StateRegistration.activeEnvironment = nil
        tuiContext.stateStorage.markActive(rootIdentity)

        return scene
    }

    /// Writes the assembled frame to the terminal using diff-based output.
    ///
    /// Builds terminal-ready output lines, then writes app header, content,
    /// and status bar inside a single buffered frame (one `write()` syscall).
    fileprivate func writeFrame(
        buffer: FrameBuffer,
        environment: EnvironmentValues,
        terminalWidth: Int,
        terminalHeight: Int,
        statusBarHeight: Int,
        headerHeight: Int
    ) {
        let backgroundCodes = RenderBackgroundCodes(palette: environment.palette)
        let reset = ANSIRenderer.reset
        let contentHeight = terminalHeight - statusBarHeight - headerHeight

        let outputLines = diffWriter.buildOutputLines(
            buffer: buffer,
            terminalWidth: terminalWidth,
            terminalHeight: contentHeight,
            bgCode: backgroundCodes.content,
            reset: reset
        )

        terminal.beginFrame()

        if appHeader.hasContent {
            renderAppHeader(
                atRow: 1,
                terminalWidth: terminalWidth,
                environment: environment,
                bgCode: backgroundCodes.appHeader,
                reset: reset
            )
        }

        diffWriter.writeContentDiff(
            newLines: outputLines,
            terminal: terminal,
            startRow: 1 + headerHeight,
            terminalWidth: terminalWidth,
            bgCode: backgroundCodes.content,
            reset: reset
        )

        if statusBar.hasItems {
            renderStatusBar(
                atRow: terminalHeight - statusBarHeight + 1,
                terminalWidth: terminalWidth,
                environment: environment,
                bgCode: backgroundCodes.statusBar,
                reset: reset
            )
        }

        terminal.endFrame()
    }

    /// Ends lifecycle, state, and cache tracking for this render pass.
    ///
    /// Fires `onDisappear` for removed views and removes state/cache
    /// entries for views no longer in the tree.
    fileprivate func endRenderPass() {
        tuiContext.lifecycle.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        tuiContext.renderCache.logFrameStats()
    }

    /// Clears the render cache when environment values affecting visual output changed.
    ///
    /// Compares the current palette and appearance identifiers with the previous
    /// frame's snapshot. On mismatch, all `EquatableView`-cached subtrees are
    /// invalidated so they re-render with the new theme/appearance.
    ///
    /// This runs once per frame (two string comparisons) and ensures
    /// developers never need to manually invalidate the cache after theme changes.
    fileprivate func invalidateCacheIfEnvironmentChanged(environment: EnvironmentValues) {
        let currentSnapshot = EnvironmentSnapshot(from: environment)
        if let lastSnapshot = lastEnvironmentSnapshot, lastSnapshot != currentSnapshot {
            tuiContext.renderCache.clearAll()
        }
        lastEnvironmentSnapshot = currentSnapshot
    }

    /// Renders a scene by delegating to `SceneRenderable`.
    fileprivate func renderScene<S: Scene>(_ scene: S, context: RenderContext) -> FrameBuffer {
        if let renderable = scene as? SceneRenderable {
            return renderable.renderScene(context: context)
        }
        return FrameBuffer()
    }

    /// Composites every free-floating overlay layer onto the content buffer.
    ///
    /// Layers are drawn in ascending order of ``OverlayLevel`` and then
    /// ``OverlayLayer/zIndex`` (ties keep emission order). Compositing a layer
    /// lifts any layers nested inside *its* content back onto the result, so
    /// the loop repeats until none remain — nesting therefore works for free.
    ///
    /// - Parameters:
    ///   - base: The rendered content buffer, carrying overlay layers.
    ///   - maxWidth: The width of the content area in columns.
    ///   - maxHeight: The height of the content area in rows.
    /// - Returns: The content buffer with all overlay layers composited in.
    fileprivate func compositeOverlays(
        _ base: FrameBuffer, maxWidth: Int, maxHeight: Int
    ) -> FrameBuffer {
        var result = base
        // A small pass cap guards against a pathological layer that somehow
        // keeps re-emitting itself; 16 levels of nesting is far beyond real use.
        var passesRemaining = 16
        while !result.overlays.isEmpty && passesRemaining > 0 {
            passesRemaining -= 1
            let layers = result.overlays
            result.overlays = []

            let ordered = layers.enumerated().sorted { lhs, rhs in
                if lhs.element.level != rhs.element.level {
                    return lhs.element.level < rhs.element.level
                }
                if lhs.element.zIndex != rhs.element.zIndex {
                    return lhs.element.zIndex < rhs.element.zIndex
                }
                return lhs.offset < rhs.offset
            }.map(\.element)

            for layer in ordered {
                let placed = placeOverlay(layer, maxWidth: maxWidth, maxHeight: maxHeight)
                result = result.composited(
                    with: placed.content, at: (x: placed.x, y: placed.y))
            }
        }
        return result
    }

    /// Resolves an overlay layer's on-screen position.
    ///
    /// The layer is clamped to the content area. If it would overflow the
    /// bottom edge it is flipped to sit above its anchor (when
    /// ``OverlayLayer/anchorHeight`` allows); otherwise it is nudged back
    /// on screen.
    fileprivate func placeOverlay(
        _ layer: OverlayLayer, maxWidth: Int, maxHeight: Int
    ) -> (content: FrameBuffer, x: Int, y: Int) {
        let content = layer.content.clamped(toWidth: maxWidth, height: maxHeight)
        let height = content.height
        let width = content.width

        var y = layer.offsetY
        if y + height > maxHeight {
            // Try flipping above the anchoring control.
            let flipped = layer.offsetY - layer.anchorHeight - height
            y = flipped >= 0 ? flipped : max(0, maxHeight - height)
        }
        y = max(0, y)

        var x = layer.offsetX
        if x + width > maxWidth {
            x = max(0, maxWidth - width)
        }
        x = max(0, x)

        return (content, x, y)
    }

    /// Renders the app header at the specified terminal row.
    fileprivate func renderAppHeader(
        atRow row: Int,
        terminalWidth: Int,
        environment: EnvironmentValues,
        bgCode: String,
        reset: String
    ) {
        guard let contentBuffer = appHeader.contentBuffer else { return }

        let headerView = AppHeader(contentBuffer: contentBuffer)

        let context = RenderContext(
            availableWidth: terminalWidth,
            availableHeight: appHeader.height,
            environment: environment
        )

        let buffer = renderToBuffer(headerView, context: context)

        let outputLines = diffWriter.buildOutputLines(
            buffer: buffer,
            terminalWidth: terminalWidth,
            terminalHeight: buffer.height,
            bgCode: bgCode,
            reset: reset
        )
        diffWriter.writeAppHeaderDiff(
            newLines: outputLines,
            terminal: terminal,
            startRow: row,
            terminalWidth: terminalWidth,
            bgCode: bgCode,
            reset: reset
        )
    }

    /// Renders the status bar at the specified terminal row.
    fileprivate func renderStatusBar(
        atRow row: Int,
        terminalWidth: Int,
        environment: EnvironmentValues,
        bgCode: String,
        reset: String
    ) {
        let palette = environment.palette

        let highlightColor =
            statusBar.highlightColor == .cyan
            ? palette.accent
            : statusBar.highlightColor
        let labelColor = statusBar.labelColor ?? palette.foreground

        let statusBarView = StatusBar(
            userItems: statusBar.currentUserItems,
            systemItems: statusBar.currentSystemItems,
            style: statusBar.style,
            alignment: statusBar.alignment,
            highlightColor: highlightColor,
            labelColor: labelColor
        )

        let context = RenderContext(
            availableWidth: terminalWidth,
            availableHeight: statusBarView.height,
            environment: environment
        )

        let buffer = renderToBuffer(statusBarView, context: context)

        let outputLines = diffWriter.buildOutputLines(
            buffer: buffer,
            terminalWidth: terminalWidth,
            terminalHeight: buffer.height,
            bgCode: bgCode,
            reset: reset
        )
        diffWriter.writeStatusBarDiff(
            newLines: outputLines,
            terminal: terminal,
            startRow: row,
            terminalWidth: terminalWidth,
            bgCode: bgCode,
            reset: reset
        )
    }
}
