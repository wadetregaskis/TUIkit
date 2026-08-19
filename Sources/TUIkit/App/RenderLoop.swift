//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoop.swift
//
//  Manages the rendering pipeline: scene rendering, environment
//  assembly, and status bar output.
//
//  Created by LAYERED.work
//  License: MIT

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
///
/// Internal (not private) so tests can pin which values participate: a value
/// missing from here is a class of "changed but stale subtrees keep the old
/// look" bug, and it is invisible in headless single-render tests.
internal struct EnvironmentSnapshot: Equatable {
    /// The active palette identifier.
    let paletteID: String

    /// The active appearance identifier.
    let appearanceID: String

    /// What the `.automatic` toggle character set resolves to this frame. Under tmux this
    /// CHANGES mid-run when a different client attaches; without it in the
    /// snapshot, `EquatableView`/`ForEach`-memoized subtrees kept serving
    /// buffers with the OLD glyphs, so the screen showed a mix — rows the user
    /// touched re-rendered in the new style while untouched rows stayed in the
    /// old one (observed live: iTerm2 attached to a running app and the default
    /// toggles stayed ■/□ while the answer had flipped to emoji).
    let resolvedAutomaticToggleCharacterSet: ToggleCharacterSet

    /// The frame's locale, republished from the app language each frame. A
    /// language switch re-renders — but the memoized subtrees compare by
    /// VALUE, and the view values (localization keys) don't change with the
    /// language, so without this every `EquatableView`/`ForEach`-memoized row
    /// kept serving buffers in the OLD language: the same mixed-screen class
    /// as the toggle-glyph field above, in a different coat.
    let localeIdentifier: String

    /// Creates a snapshot from fully-built environment values.
    init(from environment: EnvironmentValues) {
        self.paletteID = environment.palette.id
        self.appearanceID = environment.appearance.id
        self.resolvedAutomaticToggleCharacterSet = environment.resolvedAutomaticToggleCharacterSet
        self.localeIdentifier = environment.locale.identifier
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
    /// A view read the `pulsePhase` seam this frame (see
    /// ``EnvironmentValues/pulsePhase``).
    let usesPulse: Bool
    /// A view resolved the clock this frame — a focused control breathing, a
    /// focused field blinking.
    let usesCursor: Bool

    /// Clocks the frame left ``AnimatedCellRun``s for.
    ///
    /// A clock listed here can be advanced by replaying those runs against the
    /// frame already on screen. A clock some view READ cannot: that view built
    /// its appearance from the phase *while rendering*, so the only way to
    /// advance it is to render again. The two are not exclusive — a page
    /// mid-migration has both — and when they disagree the reader wins, because
    /// a frozen indicator is worse than a wasted frame.
    let animatedClocks: Set<AnimationClock>

    /// Whether `clock` can be advanced without walking the view tree.
    func canReplay(_ clock: AnimationClock) -> Bool {
        animatedClocks.contains(clock) && !usesPulse && !usesCursor
    }
}

/// The height of the content area: whatever the terminal has left after the
/// chrome laid out around it (the status bar, and the app header if any).
///
/// **Never negative.** A terminal can be shorter than its own chrome — the
/// status bar and header are laid out first and keep their full height — which
/// makes the raw subtraction negative. A negative height is not a size: it
/// reached `WindowGroup.centerBuffer` and `FrameDiffWriter.buildOutputLines` as
/// `0..<negative` and trapped ("Range requires lowerBound <= upperBound"), so
/// the app died on launch in a short terminal rather than drawing a squeezed
/// frame. Zero means "no room": the content renders empty, the chrome still shows.
///
/// This exists as one function because the subtraction was open-coded at four
/// sites and only some of them clamped — fixing three of four just moved the
/// crash from `centerBuffer` to `FrameDiffWriter`. One definition, one clamp.
@inline(__always)
internal func contentAreaHeight(
    terminalHeight: Int, statusBarHeight: Int, headerHeight: Int = 0
) -> Int {
    max(0, terminalHeight - statusBarHeight - headerHeight)
}

/// The last frame written, kept so an animation tick can be served by patching
/// it instead of by rendering again. See ``AnimatedCellRun``.
@MainActor
private struct ReplayableFrame {
    var contentLines: [String]
    var runs: [AnimatedCellRun]
    var terminalWidth: Int
    var startRow: Int
    var backgroundCode: String

    /// The step each clock was last *written* at, so a tick that lands on the
    /// same picture can be skipped.
    ///
    /// The comparison has to be frame-to-frame, not line-to-line: compositing
    /// leaves the replaced run's colour code behind as an empty escape, so a
    /// patched line always differs in bytes from the line it was patched from,
    /// even when it looks identical. Diffing the lines therefore reports a
    /// change on every tick — a blinking caret would emit twenty times a second
    /// to change picture twice.
    var lastSteps: [AnimationClock: Int] = [:]
}

@MainActor
internal final class RenderLoop<A: App> {
    /// The last frame written, for ``replayAnimations(steps:)``.
    private var replayable: ReplayableFrame?

    /// Whether the previous frame drew a status bar, so its appearing or
    /// disappearing can invalidate the diff — see where it is set.
    private var lastFrameHadStatusBar = false

    /// What the last render reported, so the run loop can decide whether an
    /// animation tick can be replayed without rendering again.
    private(set) var lastActivity = RenderActivity(
        usesPulse: false, usesCursor: false, animatedClocks: [])

    /// The user's app instance (provides `body`).
    let app: A

    /// The terminal for output and size queries.
    ///
    /// Held as the protocol rather than the concrete `Terminal` so a test can
    /// drive a whole render pass against a `MockTerminal`. Without that, the
    /// only way to exercise this class was to run the app, and the bugs that
    /// live here — the per-pass registries the scene walk writes into — are
    /// invisible to every unit test on either side of it.
    let terminal: any TerminalProtocol

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

    /// The push-refreshed emoji-chrome answer (see ``ClientCapabilityRefresher``):
    /// seeded synchronously before the first frame, re-probed asynchronously
    /// when the tmux client-change hooks (or a real resize) send a SIGWINCH,
    /// and a full invalidate + render request when a landed answer differs.
    ///
    /// Instance state on the @MainActor render loop, deliberately NOT a global:
    /// a shared mutable static would be read by every headless render and test
    /// in the process, which is precisely the shape that produced the
    /// render-cache and colour-depth parallel-test flakes.
    ///
    /// Lazy because its `onChange` needs `diffWriter`, which is not available
    /// until `self` is. The capture list takes `diffWriter` itself, not `self`
    /// — a generic `self` in the closure would drag the non-Sendable `A.Type`
    /// into the refresher's detached task.
    private lazy var clientCapabilities = ClientCapabilityRefresher(
        isRefreshable: TerminalHost.isTmux,
        probe: {
            guard TerminalHost.isTmux else {
                // Native: the chrome is the static allowlist, and skin tones
                // are the writer's per-host business (each native path strips
                // or keeps them itself) — `true` here means "don't ALSO strip".
                return ClientCapabilities(
                    emojiChrome: TerminalHost.supportsEmojiChrome,
                    skinTonesSafe: true,
                    mayImproveShortly: false)
            }
            // nil propagates ("could not ask; keep the previous answer") —
            // deliberately NOT collapsed to false. Fail-closed is right when
            // there is nothing better (the launch seed), but wrong for a
            // refresh, where flipping every glyph on a transient probe failure
            // is strictly worse than keeping a possibly-stale style.
            return TerminalHost.probeTmuxClients().map {
                TerminalHost.clientCapabilities(tmuxClients: $0)
            }
        },
        onChange: { [diffWriter] in
            // Every glyph on screen could differ (■ vs ⬛ change cell widths):
            // full-repaint invalidation, plus a wake so the redraw happens NOW
            // even if the loop is idle-blocked awaiting input — the point is a
            // proactive refresh, not one deferred to the next keypress.
            diffWriter.invalidate()
            AppState.shared.setNeedsRender()
        })

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
        terminal: any TerminalProtocol,
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
    ///   - pulsePhase: The current breathing phase (0–1), from the one
    ///     animation clock (`CursorTimer.breathPhase`) via `AppRunner`.
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
        // Drag auto-scroll: drive ONE tick against the PREVIOUS frame's zones
        // and region rects — before `beginRenderPass()` clears the dispatcher's
        // regions and before the tree re-registers this frame's zones. The drag
        // cursor is current, so a scroll near an edge shows in the frame we're
        // about to render, with no visible lag. This must precede
        // `beginRenderPass()`: that call empties `mouseEventDispatcher.regions`,
        // and `driveAutoScroll` resolves each zone's on-screen rect through the
        // dispatcher — run it after, and every `regionRect` lookup is nil and the
        // viewport never scrolls. While engaged the loop must keep ticking even
        // if the cursor holds still, so request a grid at the auto-scroll cadence.
        //
        // Sourced from `tuiContext` (not `environment`, which isn't built until
        // below) — the same session either way (see ServiceEnvironment).
        if tuiContext.dragAndDropSession.driveAutoScroll(
            nowNanos: UInt64(bitPattern: frameNowNanos))
        {
            _ = animationScheduler?.request(
                "drag-autoscroll", AnimationRequest(frequency: 18), now: frameNowNanos)
        }

        // A cancelled drag walks its preview home over ~200 ms. Same shape as
        // the auto-scroll tick above: the loop is demand-driven, so the flight
        // has to ask for its own frames or it would draw one and freeze.
        if tuiContext.dragAndDropSession.driveReturnFlight(
            nowNanos: UInt64(bitPattern: frameNowNanos)) != nil
        {
            _ = animationScheduler?.request(
                "drag-return", AnimationRequest(frequency: 30), now: frameNowNanos)
        }

        beginRenderPass()

        // If an @Published property changed, clear the entire render cache
        // so EquatableView-cached subtrees re-render with new model data.
        if AppState.shared.consumeNeedsCacheClear() {
            tuiContext.renderCache.clearAll()
        }

        // Terminal size: single getSize() call avoids 2 ioctl syscalls per frame.
        let terminalSize = terminal.getSize()
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
        // A scene-level `.appearance(...)` override wins over the appearance
        // manager's current selection for the WHOLE frame — content tree and the
        // out-of-tree app header / status bar alike. `nil` (no scene override)
        // leaves the manager-derived appearance from `buildEnvironment()` intact,
        // so F2/F3/the appearance picker keep working.
        if let appearanceOverrideScene = scene as? any RootAppearanceOverrideProvidingScene,
            let appearanceOverride = appearanceOverrideScene.rootAppearanceOverride()
        {
            environment.appearance = appearanceOverride
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
        applyChromeStyle(from: scene)
        let statusBarHeight = statusBar.height
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
            let overlayContentHeight = contentAreaHeight(
                terminalHeight: terminalHeight, statusBarHeight: statusBarHeight,
                headerHeight: appHeader.height)
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
        let appHeaderBuffer: FrameBuffer? =
            appHeader.hasContent
            ? buildAppHeaderBuffer(terminalWidth: terminalWidth, environment: environment) : nil

        let statusBarBuffer: FrameBuffer? =
            statusBar.hasItems
            ? buildStatusBarBuffer(terminalWidth: terminalWidth, environment: environment) : nil
        noteStatusBarPresence(statusBarBuffer != nil)

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

        return recordActivity(
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
        // Auto-detect the terminal cell's pixel aspect for undistorted images;
        // terminals that don't report their pixel size keep the 2.0 default (or
        // a `.imageCellAspect(_:)` override deeper in the tree).
        // Concrete-only: reporting the cell's pixel size is a real-terminal
        // capability, not part of the protocol every host must implement.
        if let cellAspect = (terminal as? Terminal)?.cellPixelAspect() {
            environment.imageCellAspect = cellAspect
        }
        // Determine header height. On the first frame, we perform a measurement
        // pass to discover the actual header height before outputting anything.
        // This prevents visible content jumping.
        // The render tree is rooted at `rootIdentity` — the SAME identity
        // `evaluateAppBody` hydrates `@State` under (see that property's note).
        let appHeaderHeight: Int
        if isFirstFrame {
            var measureContext = RenderContext(
                availableWidth: terminalWidth,
                // Clamped: a terminal shorter than its own chrome makes this
                // subtraction negative, and a negative available height is not a
                // size any view can be asked for — it reaches `centerBuffer` as
                // `0..<negative` and traps. See `contentHeight` below.
                availableHeight: contentAreaHeight(
                    terminalHeight: terminalHeight, statusBarHeight: statusBarHeight),
                environment: environment,
                identity: rootIdentity
            )
            // This walk's buffer is thrown away — only `appHeader.height`
            // survives it — so it is a measurement, and every guard written as
            // `!context.isMeasuring` must apply: `onAppear`, `.task`, focus and
            // mouse registration, `onChange`. Without this the discarded walk
            // was indistinguishable from a real render, so a view present here
            // and NOT in the drawn walk (the two see different heights, since
            // this one has not subtracted the header yet) would appear, mount a
            // task, and then be told it disappeared, having never been drawn.
            //
            // `AppHeaderModifier` is deliberately NOT guarded that way, which is
            // what lets this walk still do its one job. Anything that guards
            // itself on the measure phase must not be load-bearing for the
            // header's height.
            measureContext.isMeasuring = true
            _ = renderScene(scene, context: measureContext.withChildIdentity(type: type(of: scene)))
            appHeaderHeight = appHeader.height
            isFirstFrame = false
        } else {
            appHeaderHeight = appHeader.estimatedHeight
        }

        // Clamped at zero: the status bar and app header are laid out first and
        // keep their full height, so a terminal shorter than the two of them
        // together leaves the content area with LESS than nothing. Unclamped,
        // that negative height propagated into every view's `availableHeight`
        // and trapped in `WindowGroup.centerBuffer` ("Range requires lowerBound
        // <= upperBound") before the first frame was drawn — the app died on
        // launch in a short terminal. Zero means "no room"; the content renders
        // empty and the chrome still shows.
        let contentHeight = contentAreaHeight(
            terminalHeight: terminalHeight, statusBarHeight: statusBarHeight,
            headerHeight: appHeaderHeight)
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
            let actualContentHeight = contentAreaHeight(
                terminalHeight: terminalHeight, statusBarHeight: statusBarHeight,
                headerHeight: actualHeaderHeight)
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
        // A SIGWINCH is also our signal that the tmux CLIENT may have changed —
        // either a real resize (attaching from a different-sized terminal), or
        // the synthetic one our tmux hooks send for a SAME-size attach/detach
        // (see `TerminalHost.installTmuxClientChangeHooks`). Re-ask tmux which
        // terminals are watching — asynchronously: frames keep rendering with
        // the previous answer, and if the new one differs the screen is fully
        // invalidated and redrawn when it lands.
        clientCapabilities.refresh()
    }

    /// What the attached terminal(s) can render this frame: the emoji-chrome
    /// answer for the environment, and the skin-tone answer for the writer.
    ///
    /// A pure cache read after the first call — the cache is push-refreshed by
    /// the tmux client-change hooks, off the render path; see
    /// ``ClientCapabilityRefresher``.
    func resolveClientCapabilities() -> ClientCapabilities {
        clientCapabilities.resolve()
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

        // Terminal-adaptive defaults belong to the app run loop, where a real
        // terminal exists — the bare EnvironmentValues defaults stay
        // terminal-independent so headless renders and tests are
        // deterministic. `.toggleCharacterSet(_:)` modifiers below still override.
        //
        // `resolveClientCapabilities()` rather than the static `.automatic`,
        // because under tmux the answer depends on the CLIENT terminal's font
        // and only tmux can name it — a question that costs a subprocess, so it
        // is cached here and push-refreshed by the tmux client-change hooks
        // (see `ClientCapabilityRefresher`). Off tmux it is the same static
        // allowlist. The DEFAULT is the `.automatic` marker, and the answer it
        // stands for goes alongside it. Injecting the marker (rather than a
        // style already resolved here) is what makes an app's own explicit
        // `.toggleCharacterSet(.automatic)` adapt too — it overrides this
        // default with the same marker, and the render site resolves whichever
        // arrives.
        let capabilities = resolveClientCapabilities()
        environment.toggleCharacterSet = .automatic
        environment.resolvedAutomaticToggleCharacterSet = .automatic(
            emojiChrome: capabilities.emojiChrome)
        environment.supportsEmojiChrome = capabilities.emojiChrome
        // The writer's tmux skin-tone plane follows the same per-client answer:
        // keep SMP-base tones only when every attached client renders them
        // (Ghostty alone). Set per frame; a change always arrives via the
        // refresher's onChange, whose full invalidation keeps the writer's
        // line-reuse cache from serving lines stripped under the old policy.
        diffWriter.tmuxSkinToneBasePlane =
            capabilities.skinTonesSafe ? .bmpOnly : .all

        // Runtime services (shared with ViewRenderer's one-off path so
        // the wired set can't drift — see EnvironmentValues.applyRuntimeServices).
        environment.applyRuntimeServices(from: tuiContext)

        return environment
    }
}

// MARK: - Private Helpers

extension RenderLoop {
    /// Clears all per-frame state and begins lifecycle/state/cache tracking.
    ///
    /// Only the registries that genuinely belong to the FRAME live here. The
    /// ones that belong to a single walk of the scene are reset by
    /// ``beginSceneRender()`` instead — see that method for why the difference
    /// matters and how to decide which list a new registry joins.
    fileprivate func beginRenderPass() {
        // Per-PASS. `focusManager.beginRenderPass()` snapshots `previousSections`
        // and must therefore run BEFORE anything clears the current ring.
        focusManager.beginRenderPass()
        appHeader.beginRenderPass()
        statusBar.focusManager = focusManager
        tuiContext.lifecycle.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        // Per-WALK, reset again before each scene render.
        beginSceneRender()
    }

    /// Clears the registries that belong to ONE walk of the scene tree.
    ///
    /// `renderContent` may walk the scene more than once inside a single
    /// ``beginRenderPass()``/``endRenderPass()`` bracket: a throwaway walk on
    /// the first frame to discover the app header's height, and a correction
    /// re-render on any frame where the header's actual height disagrees with
    /// the estimate it was laid out against. Only the LAST walk's buffer is
    /// drawn — so only the last walk's registrations should survive.
    ///
    /// Resetting these once per PASS instead let the discarded walk's entries
    /// pile up on top of the drawn walk's:
    ///
    /// - `stateStorage`'s onChange counters are claimed POSITIONALLY, so the
    ///   second walk's `.onChange` claimed index 1 where the first claimed 0,
    ///   found that slot empty, and fired again — every app's
    ///   `.onChange(of:initial:true)` ran twice at launch, and the junk left in
    ///   slot 1 could fire a spurious `action(stale, new)` on a later corrected
    ///   frame even with the default `initial: false`. `.onPreferenceChange`
    ///   shares the counter and was corrupted the same way.
    /// - key handlers APPEND, and dispatch walks every entry until one
    ///   consumes, so a handler that declines with a side effect (the blessed
    ///   log-the-key pattern) ran its side effect once per duplicate.
    /// - preference values are REDUCED into a stack, so an accumulating
    ///   `reduce` collected every published value twice.
    /// - mouse handler ids are positional and restart at 0 each reset, so a
    ///   two-walk frame shifted every control's id and the hover tracker's
    ///   cross-frame comparison sent `.exited` to a *different* control.
    /// - focus sections accumulate (registration merely de-duplicates by
    ///   focusID), so a corrected frame's Tab ring was the union of both walks
    ///   in the DISCARDED walk's order — which was built at the wrong content
    ///   height, and so could contain focusables the drawn frame does not show.
    ///
    /// Called from ``renderScene(_:context:)`` — the one funnel every walk goes
    /// through — rather than at each call site, so a future third walk is
    /// correct without anyone remembering this. `WindowGroup.renderScene`
    /// already resets the drag-and-drop session the same way.
    ///
    /// What must NOT move here, and why: `focusManager.beginRenderPass()`
    /// (snapshots last frame's ring so a focus LOSS can still reach its
    /// element), `appHeader.beginRenderPass()` (snapshots the height estimate
    /// this pass is laid out against), `lifecycle` and `renderCache` (a token
    /// or cache entry seen only in a discarded walk surviving one extra frame
    /// is the conservative direction — no spurious `onDisappear`, no premature
    /// eviction), and above all `stateStorage.beginRenderPass()`, which also
    /// clears `activeIdentities` — already carrying `evaluateAppBody`'s
    /// `markActive(rootIdentity)` by the time a walk starts, so clearing it
    /// mid-pass would let `endRenderPass` prune the App's own root `@State` on
    /// every corrected frame. That is why `beginSceneRender` on `StateStorage`
    /// is deliberately narrower than its `beginRenderPass`.
    fileprivate func beginSceneRender() {
        tuiContext.keyEventDispatcher.clearHandlers()
        tuiContext.mouseEventDispatcher.beginRenderPass()
        tuiContext.keyboardShortcuts.beginRenderPass()
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginSceneRender()
        focusManager.beginSceneRender()
        statusBar.clearSectionItems()
        // The transient escape-label override is published by whichever
        // open modal surface (Picker drop-down, etc.) renders in this
        // frame; clearing it here makes the default the absence of any
        // override, so a surface that disappeared on the previous frame
        // never leaves its stale label behind on the next page. The
        // grabs-input flag travels with it (modal by default; a list's
        // lightweight selection claim lowers it each frame it applies).
        statusBar.escapeLabelOverride = nil
        statusBar.escapeClaimGrabsInput = true
    }

    /// Evaluates `App.body` with the environment published so `@Environment`
    /// reads from it. (`@State` binds to each view's render identity later, in
    /// `renderToBuffer` — not at construction here.)
    fileprivate func evaluateAppBody(environment: EnvironmentValues) -> A.Body {
        // An `App` is not a `View`, so nothing populates its `@Environment`
        // boxes — publishing the environment around `body` is the only way its
        // reads resolve. The scope ends with the call, so nothing outside it
        // ever sees this value.
        let scene = StateRegistration.withHydration(environment: environment) { app.body }
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
        let contentHeight = contentAreaHeight(
            terminalHeight: terminalHeight, statusBarHeight: statusBarHeight,
            headerHeight: headerHeight)

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

        // Keep what an animation tick would need to patch: the lines actually on
        // screen, the runs composited into absolute positions, and the geometry
        // the diff was written with. Only runs that ANIMATE are kept — a
        // one-frame run is a still picture the render above already drew.
        replayable = ReplayableFrame(
            contentLines: outputLines,
            runs: buffer.animatedCells.filter(\.isAnimating),
            terminalWidth: terminalWidth,
            startRow: 1 + headerHeight,
            backgroundCode: backgroundCodes.content)

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

    /// Invalidates the diff when the status bar appears or disappears.
    ///
    /// A bar that went away and came back is not "unchanged". While it is
    /// hidden the content area grows into its row and paints over it, but the
    /// diff's record of that region still describes the old bar — so a bar
    /// restored with byte-identical items compared equal and was never written,
    /// leaving the bottom row blank with the shortcuts gone. The app header
    /// self-heals the same way when its height turns out different from the
    /// estimate.
    private func noteStatusBarPresence(_ present: Bool) {
        guard present != lastFrameHadStatusBar else { return }
        lastFrameHadStatusBar = present
        diffWriter.invalidate()
    }

    /// Stores and returns what this frame reported, so the run loop can decide
    /// whether the next animation tick needs a render at all.
    private func recordActivity(usesPulse: Bool, usesCursor: Bool) -> RenderActivity {
        lastActivity = RenderActivity(
            usesPulse: usesPulse,
            usesCursor: usesCursor,
            animatedClocks: Set((replayable?.runs ?? []).lazy.map(\.clock)))
        return lastActivity
    }

    /// How many ticks the clock may sleep before anything on screen would look
    /// different — 1 whenever that cannot be known.
    ///
    /// A frame whose animation is entirely in ``AnimatedCellRun``s knows
    /// exactly: each run carries its whole cycle, already rendered, so the next
    /// tick that changes a cell is a lookup. A frame where some view built its
    /// appearance from the phase *while rendering* does not — only that view
    /// knows what it would draw next — so the clock keeps its finest step.
    ///
    /// This is what makes the quantised pulse cheap on a 256-colour terminal:
    /// the ramp repeats each shade it can actually paint for two or three
    /// ticks, and there is no reason to wake for the repeats.
    func ticksUntilNextChange(from step: Int) -> Int {
        guard !lastActivity.usesPulse, !lastActivity.usesCursor else { return 1 }
        let runs = replayable?.runs ?? []
        guard !runs.isEmpty else { return 1 }
        return runs.map { $0.ticksUntilChange(after: step) }.min() ?? 1
    }

    /// Advances the animated cells of the frame already on screen, without
    /// rendering anything.
    ///
    /// The saving is the whole view walk: no measure, no layout, no render, no
    /// state or lifecycle bookkeeping. Each run's next frame is spliced into the
    /// line it sits on, and the result goes through the ordinary content diff —
    /// which, seeing only those cells differ, emits only those cells.
    ///
    /// - Parameter steps: The current step of each clock being advanced.
    /// - Returns: `true` if the tick was served. `false` means the caller must
    ///   render: there is no frame to patch yet, or nothing on screen animates
    ///   on those clocks.
    @discardableResult
    func replayAnimations(steps: [AnimationClock: Int]) -> Bool {
        guard let frame = replayable, !frame.runs.isEmpty else { return false }
        let due = frame.runs.filter { steps[$0.clock] != nil }
        guard !due.isEmpty else { return false }

        // Skip a tick that lands on the picture already showing. A blink spends
        // most of its cycle on the same two frames, and a quantised pulse
        // repeats shades, so most ticks change nothing. See `lastSteps`.
        let unchanged = due.allSatisfy { run in
            guard let last = frame.lastSteps[run.clock], let step = steps[run.clock] else {
                return false  // nothing written since the render: assume it moved
            }
            return run.frame(at: last) == run.frame(at: step)
        }
        guard !unchanged else { return true }

        // Always patched from the frame the last RENDER produced — never from
        // the last patch. Compositing replaces a cell's glyph but keeps the
        // styling around it, so the colour code of the frame being replaced
        // stays behind as an empty run. Feed a patched line back in and those
        // dead escapes accumulate, one per tick: the row still looks correct
        // and never changes width, but it grew without bound and reached the
        // terminal as ~60 kB/s to animate two cells. Patching the pristine line
        // is also strictly less work, since it never gets longer.
        var lines = frame.contentLines
        var touched = false
        for run in due {
            guard let step = steps[run.clock] else { continue }
            let row = run.offsetY
            guard lines.indices.contains(row) else { continue }
            // Spliced through the compositor rather than by hand: it already
            // knows how to drop a styled run into a styled line at a visible
            // column and restore the surrounding state afterwards, and getting
            // that wrong is how a background stops halfway across a row. The
            // run-specific entry point rather than plain `composited` because
            // this row is already on screen, so nothing will paint a background
            // over it afterwards — see `patchingAnimatedRun(_:atStep:)`.
            let patched = FrameBuffer.patchingAnimatedCells(
                in: lines[row], with: run.frame(at: step),
                atColumn: run.offsetX, width: run.width)
            if patched != lines[row] {
                lines[row] = patched
                touched = true
            }
        }
        // Every run landed on the frame it was already showing. Emitting would
        // be a no-op the diff would discard anyway, so skip the write and keep
        // the cached frame as it was.
        guard touched else { return true }

        terminal.beginFrame()
        diffWriter.writeContentDiff(
            newLines: lines,
            terminal: terminal,
            startRow: frame.startRow,
            terminalWidth: frame.terminalWidth,
            bgCode: frame.backgroundCode,
            reset: ANSIRenderer.reset
        )
        terminal.endFrame()
        // `replayable.contentLines` deliberately keeps the RENDER's lines, not
        // these. The diff writer already tracks what is on screen; this is the
        // clean base every future tick patches from. See the note above.
        for (clock, step) in steps { replayable?.lastSteps[clock] = step }
        return true
    }

    /// Adopts a scene-level `.chromeStyle(...)` for this frame.
    ///
    /// Must run BEFORE anything asks either bar's height: the style decides how
    /// many rows they take, and the page's height is whatever is left. That is
    /// why the status bar's height is read straight after this call rather than
    /// alongside the terminal size, where it used to sit.
    fileprivate func applyChromeStyle(from scene: some Scene) {
        guard let chromeScene = scene as? any RootChromeStyleProvidingScene else { return }
        let chrome = chromeScene.rootChromeStyle()
        if let style = chrome.appHeader { appHeader.style = style }
        if let style = chrome.statusBar { statusBar.style = style }
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
    ///
    /// The one funnel every walk of the scene passes through, which is why the
    /// per-walk registries are reset here — see ``beginSceneRender()``.
    fileprivate func renderScene<S: Scene>(_ scene: S, context: RenderContext) -> FrameBuffer {
        beginSceneRender()
        // The walk window. A `@State` write reaching the invalidation funnel
        // from THIS thread while this is open is a body mutation — it asks for
        // another frame from inside the frame being built. Opened and closed
        // here because this is the one funnel, so every walk is covered and no
        // walk is covered twice.
        let diagnostic = tuiContext.renderCache.bodyMutationDiagnostic
        diagnostic?.beginTraversal()
        defer { diagnostic?.endTraversal() }
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

        let headerView = AppHeader(contentBuffer: contentBuffer, style: appHeader.style)

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
