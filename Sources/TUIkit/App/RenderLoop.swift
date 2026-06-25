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
/// What animation clocks a render frame actually consumed.
///
/// The run loop uses this to keep a clock ticking only while a frame is still
/// consuming it — so a static screen drives no further frames. (Top-level, not
/// nested in the generic `RenderLoop`, so callers can name it without its type
/// parameter.)
struct RenderActivity {
    /// A view read `pulsePhase` this frame (a focus indicator is animating).
    let usesPulse: Bool
    /// A view read the cursor clock this frame (a text field is focused).
    let usesCursor: Bool
}

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

    /// The identity at the root of the view tree.
    ///
    /// **Load-bearing invariant:** ``evaluateAppBody`` hydrates the app's
    /// `@State` under this identity, and ``renderContent`` renders the scene
    /// under it too. The two MUST agree. If they diverge, App-level `@State`
    /// (e.g. a root view's selection index) lives at one root while the views it
    /// drives render under another — so it is not an ancestor of them, and
    /// `StateBox.didSet → RenderCache.clearAffected` matches none of their cache
    /// entries. The visible symptom is a value-memoized child (a `ForEach`
    /// selection highlight) frozen on its old value even though the state
    /// changed. Deriving both from this single property is what guarantees they
    /// can't drift apart.
    private var rootIdentity: ViewIdentity { ViewIdentity(rootType: A.self) }

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

    /// The mouse-support configuration extracted from the scene this
    /// frame. The effective configuration (after view modifiers add
    /// per-frame requests) is `baseMouseSupport.union(with: requested)`.
    /// AppRunner reads ``effectiveMouseSupport`` after each render.
    private var baseMouseSupport: MouseSupport = .standard

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
    ///   - animationScheduler: The run loop's animation scheduler, made available
    ///     to animating views via `context.requestAnimation(...)`. `nil` for
    ///     one-off renders (the backtick frame dump) that schedule no animation.
    ///   - frameNowNanos: The monotonic-clock timestamp (ns) this frame's
    ///     animation grids anchor to — the same `now` the run loop uses to compute
    ///     the next animation deadline, so grid and deadline agree exactly.
    @discardableResult
    func render(
        pulsePhase: Double = 0,
        cursorTimer: CursorTimer? = nil,
        animationScheduler: AnimationScheduler? = nil,
        frameNowNanos: Int64 = 0
    ) -> RenderActivity {
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
        // Animating views declare their re-render rate through the scheduler
        // (see `RenderContext.requestAnimation`); they anchor new grids to this
        // frame's `now` so the loop's next-firing query agrees with them exactly.
        environment.animationScheduler = animationScheduler
        environment.frameNowNanos = frameNowNanos
        // Install a fresh volatile-read tracker at the render root so that, after
        // the frame, we can tell whether anything actually consumed the pulse
        // clock (the row memo reuses this same tracker further down). Likewise
        // reset the cursor clock's per-frame read flag. These drive demand-driven
        // animation: the run loop keeps a clock ticking only while a frame uses
        // it, so a static screen produces no further frames.
        environment.volatileReadTracker = VolatileReadTracker()
        cursorTimer?.beginFrameReadTracking()

        let scene = evaluateAppBody(environment: environment)
        if let paletteOverrideScene = scene as? any RootPaletteOverrideProvidingScene,
            let paletteOverride = paletteOverrideScene.rootPaletteOverride()
        {
            environment.palette = paletteOverride
        }
        // Capture the scene's base ``MouseSupport`` configuration; the
        // effective per-frame configuration is the union of this and
        // any features requested by view modifiers during render. The
        // AppRunner consults `effectiveMouseSupport` after the render
        // pass completes to update the terminal tracking mode.
        if let scene = scene as? MouseSupportProvidingScene {
            // `nil` means no `.mouseSupport(...)` was applied (only pass-through
            // scene wrappers like `.palette(...)`); fall back to `.standard`.
            baseMouseSupport = scene.resolvedMouseSupport() ?? .standard
        } else {
            baseMouseSupport = .standard
        }
        // Make the active support available to handlers right now so
        // any events queued from the previous frame are filtered
        // against the right config.
        tuiContext.mouseEventDispatcher.setActiveSupport(baseMouseSupport)
        invalidateCacheIfEnvironmentChanged(environment: environment)

        // Render the scene into the content area — resolving the app-header
        // height first (a first-frame measure pass), then re-rendering once if
        // the header turned out a different height than estimated. See
        // `renderContent`.
        let (renderedBuffer, contentHeight) = renderContent(
            scene: scene,
            environment: environment,
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight,
            statusBarHeight: statusBarHeight)
        var buffer = renderedBuffer

        focusManager.endRenderPass()

        // Composite any free-floating overlay layers (Picker drop-downs,
        // popovers, …) emitted during rendering onto the content buffer.
        if !buffer.overlays.isEmpty {
            let overlayContentHeight = terminalHeight - statusBarHeight - appHeader.height
            buffer = compositeOverlays(
                buffer, maxWidth: terminalWidth, maxHeight: overlayContentHeight,
                palette: environment.palette)
        }

        // Build the app-header and status-bar buffers up front
        // so we can merge their hit-test regions into the
        // dispatcher's region set before writing.
        //
        // Coordinate translation:
        //   - The App input loop subtracts appHeader.height
        //     from incoming events' y, so content-area
        //     coordinates start at y = 0 and run to
        //     y = contentHeight - 1.
        //   - The app header sits ABOVE the content area in
        //     terminal-space, so its events arrive with
        //     negative y after translation. Regions emitted
        //     inside the header therefore need offsetY
        //     shifted by -appHeader.height.
        //   - The status bar sits BELOW the content area in
        //     terminal-space, so its events arrive with
        //     y >= contentHeight. Status-bar regions need
        //     offsetY shifted by +contentHeight.
        let appHeaderBuffer: FrameBuffer? = appHeader.hasContent
            ? buildAppHeaderBuffer(
                terminalWidth: terminalWidth, environment: environment)
            : nil

        let statusBarBuffer: FrameBuffer? = statusBar.hasItems
            ? buildStatusBarBuffer(
                terminalWidth: terminalWidth, environment: environment)
            : nil

        var mergedRegions = buffer.hitTestRegions
        if let appHeaderBuffer {
            for region in appHeaderBuffer.hitTestRegions {
                var shifted = region
                shifted.offsetY -= appHeader.height
                mergedRegions.append(shifted)
            }
        }
        if let statusBarBuffer {
            for region in statusBarBuffer.hitTestRegions {
                var shifted = region
                shifted.offsetY += contentHeight
                mergedRegions.append(shifted)
            }
        }

        // Publish the now-composited hit-test regions so the dispatcher
        // can route mouse events arriving between this frame and the
        // next. Regions are kept in absolute content-area coordinates;
        // the App input loop translates terminal coords to content
        // coords before dispatching.
        tuiContext.mouseEventDispatcher.setRegions(mergedRegions)

        writeFrame(
            buffer: buffer,
            appHeaderBuffer: appHeaderBuffer,
            statusBarBuffer: statusBarBuffer,
            environment: environment,
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight,
            statusBarHeight: statusBarHeight,
            headerHeight: appHeader.height
        )

        endRenderPass()

        return RenderActivity(
            usesPulse: (environment.volatileReadTracker?.reads ?? 0) > 0,
            usesCursor: cursorTimer?.didReadThisFrame ?? false)
    }

    /// Renders the scene into the content area and returns the buffer together
    /// with the content height it was laid out against.
    ///
    /// On the first frame this runs a throwaway measure pass to discover the
    /// app header's real height before producing any visible output, which
    /// prevents the content from jumping. Every frame it then renders at the
    /// resolved content height and, if the header turned out a different height
    /// than estimated, re-renders once at the corrected height so centering
    /// stays accurate. The returned content height is the original
    /// (pre-correction) value — the same one the caller uses to translate
    /// status-bar hit-test regions into content-area coordinates.
    private func renderContent(
        scene: A.Body,
        environment: EnvironmentValues,
        terminalWidth: Int,
        terminalHeight: Int,
        statusBarHeight: Int
    ) -> (buffer: FrameBuffer, contentHeight: Int) {
        // Publish the true screen height into the environment so overlays (e.g. a
        // Picker drop-down) can size to the visible area. Unlike a context's
        // `availableHeight` — which a ScrollView inflates to a tall measure budget —
        // this is set once at the root and never overridden, so it survives intact
        // however deep the consumer sits.
        var environment = environment
        environment.terminalHeight = terminalHeight
        environment.terminalWidth = terminalWidth
        // Determine header height. On the first frame, we perform a measurement
        // pass to discover the actual header height before outputting anything.
        // This prevents visible content jumping.
        // The render tree is rooted at `rootIdentity` — the SAME identity
        // `evaluateAppBody` hydrates `@State` under (see that property's note).
        let appHeaderHeight: Int
        if isFirstFrame {
            let measureContext = RenderContext(
                availableWidth: terminalWidth,
                availableHeight: terminalHeight - statusBarHeight,
                environment: environment,
                identity: rootIdentity
            )
            _ = renderScene(scene, context: measureContext.withChildIdentity(type: type(of: scene)))
            appHeaderHeight = appHeader.height
            isFirstFrame = false
        } else {
            appHeaderHeight = appHeader.estimatedHeight
        }

        let contentHeight = terminalHeight - statusBarHeight - appHeaderHeight
        // Publish the content-area height so anchored overlays (a Picker
        // drop-down) size to the area the compositor will clamp them to — above
        // the status bar — rather than to the full `terminalHeight` (which would
        // leave their bottom rows shaved off against the status bar).
        environment.overlayContentHeight = contentHeight

        var context = RenderContext(
            availableWidth: terminalWidth,
            availableHeight: contentHeight,
            environment: environment,
            identity: rootIdentity
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
            environment.overlayContentHeight = actualContentHeight
            var correctedContext = RenderContext(
                availableWidth: terminalWidth,
                availableHeight: actualContentHeight,
                environment: environment,
                identity: rootIdentity
            )
            correctedContext.hasExplicitWidth = true
            correctedContext.hasExplicitHeight = true
            buffer = renderScene(scene, context: correctedContext.withChildIdentity(type: type(of: scene)))
        }

        return (buffer, contentHeight)
    }

    /// Invalidates the diff cache, forcing a full repaint on the next render.
    ///
    /// Call this when the terminal is resized (SIGWINCH).
    func invalidateDiffCache() {
        diffWriter.invalidate()
    }

    /// The effective ``MouseSupport`` configuration after combining
    /// the scene-level base with per-frame feature requests from view
    /// modifiers.
    ///
    /// Read by the AppRunner once per frame to bring the terminal
    /// tracking mode in sync.
    func effectiveMouseSupport() -> MouseSupport {
        tuiContext.mouseEventDispatcher.effectiveSupport(baseConfig: baseMouseSupport)
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

        // Runtime services (shared with ViewRenderer's one-off path so
        // the wired set can't drift — see EnvironmentValues.applyRuntimeServices).
        environment.applyRuntimeServices(from: tuiContext)

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

    /// Evaluates `App.body` with the environment published so `@Environment`
    /// reads from it. (`@State` binds to each view's render identity later, in
    /// `renderToBuffer` — not at construction here.)
    fileprivate func evaluateAppBody(environment: EnvironmentValues) -> A.Body {
        StateRegistration.activeEnvironment = environment

        let scene = app.body

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
        appHeaderBuffer: FrameBuffer?,
        statusBarBuffer: FrameBuffer?,
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
            reset: reset,
            reusingFor: .content
        )

        terminal.beginFrame()

        if let appHeaderBuffer {
            writeAppHeaderBuffer(
                appHeaderBuffer,
                atRow: 1,
                terminalWidth: terminalWidth,
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

        if let statusBarBuffer {
            writeStatusBarBuffer(
                statusBarBuffer,
                atRow: terminalHeight - statusBarHeight + 1,
                terminalWidth: terminalWidth,
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
        _ base: FrameBuffer, maxWidth: Int, maxHeight: Int, palette: any Palette
    ) -> FrameBuffer {
        base.compositingOverlays(maxWidth: maxWidth, maxHeight: maxHeight, palette: palette)
    }

    /// Builds the app-header buffer (with its hit-test regions
    /// carried through from the user's `.appHeader { ... }`
    /// content) and returns it. The caller is responsible for
    /// merging the regions into the dispatcher's set — same
    /// split as the status-bar build / write pair below, for
    /// the same reason (regions emitted at render time would
    /// otherwise be discarded before reaching the dispatcher).
    fileprivate func buildAppHeaderBuffer(
        terminalWidth: Int,
        environment: EnvironmentValues
    ) -> FrameBuffer? {
        guard let contentBuffer = appHeader.contentBuffer else { return nil }

        let headerView = AppHeader(contentBuffer: contentBuffer)

        let context = RenderContext(
            availableWidth: terminalWidth,
            availableHeight: appHeader.height,
            environment: environment
        )

        return renderToBuffer(headerView, context: context)
    }

    /// Writes a previously-built app-header buffer to the
    /// terminal at the specified row. Companion to
    /// ``buildAppHeaderBuffer(terminalWidth:environment:)``.
    fileprivate func writeAppHeaderBuffer(
        _ buffer: FrameBuffer,
        atRow row: Int,
        terminalWidth: Int,
        bgCode: String,
        reset: String
    ) {
        let outputLines = diffWriter.buildOutputLines(
            buffer: buffer,
            terminalWidth: terminalWidth,
            terminalHeight: buffer.height,
            bgCode: bgCode,
            reset: reset,
            reusingFor: .appHeader
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

    /// Renders the status bar into a `FrameBuffer` and returns
    /// it. The buffer carries the per-item hit-test regions that
    /// ``StatusBar/applyHitTestRegions`` emitted at status-bar
    /// local coordinates — the caller is responsible for
    /// shifting those into content-area coordinates and merging
    /// them into the dispatcher's region set before
    /// ``writeStatusBarBuffer(_:atRow:terminalWidth:bgCode:reset:)``
    /// writes the diff out.
    fileprivate func buildStatusBarBuffer(
        terminalWidth: Int,
        environment: EnvironmentValues
    ) -> FrameBuffer {
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

        return renderToBuffer(statusBarView, context: context)
    }

    /// Writes a previously-built status-bar buffer to the
    /// terminal at the specified row. The build and write
    /// phases are split so the caller can intercept the
    /// buffer's hit-test regions between them.
    fileprivate func writeStatusBarBuffer(
        _ buffer: FrameBuffer,
        atRow row: Int,
        terminalWidth: Int,
        bgCode: String,
        reset: String
    ) {
        let outputLines = diffWriter.buildOutputLines(
            buffer: buffer,
            terminalWidth: terminalWidth,
            terminalHeight: buffer.height,
            bgCode: bgCode,
            reset: reset,
            reusingFor: .statusBar
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
