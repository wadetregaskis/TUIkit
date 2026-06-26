//  🖥️ TUIKit — Terminal UI Kit for Swift
//  App.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch

// MARK: - App Protocol

/// The base protocol for TUIkit applications.
///
/// `App` is the entry point for every TUIkit application,
/// similar to `App` in SwiftUI.
///
/// # Example
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///     }
/// }
/// ```
@MainActor
public protocol App {
    /// The type of the main scene.
    associatedtype Body: Scene

    /// The main scene of the app.
    @SceneBuilder
    var body: Body { get }

    /// Initializes the app.
    init()

    /// The maximum render frame rate, in frames per second.
    ///
    /// Rendering is demand-driven: the app renders only when something changes,
    /// and never more often than this. A static screen (no animation, no input)
    /// renders nothing at all. Raise it for smoother animation, lower it to cap
    /// CPU while something is animating. Default: 60.
    var maxFrameRate: Int { get }
}

extension App {
    /// The maximum render frame rate (frames per second). Default 60; override
    /// `maxFrameRate` on your `App` to change it.
    public var maxFrameRate: Int { 60 }

    /// Starts the app.
    ///
    /// This method is called by the `@main` attribute and starts
    /// the main run loop of the application.
    ///
    /// `main()` is `async` so the run loop can suspend once per frame
    /// (via `Task.sleep`) instead of blocking the thread. Each suspension
    /// releases the main actor, so work scheduled with `Task { @MainActor }`,
    /// `MainActor.run`, or `DispatchQueue.main` runs interleaved with
    /// rendering — rather than being starved until the app exits.
    @MainActor
    public static func main() async {
        let app = Self()
        let runner = AppRunner<Self>(app: app)
        await runner.run()
    }
}

// MARK: - App Runner

/// Runs an App.
///
/// `AppRunner` is the main coordinator that owns the run loop and
/// delegates to specialized managers:
/// - `SignalManager` - POSIX signal handling (SIGINT, SIGWINCH)
/// - `InputHandler` - Key event dispatch (status bar, views, defaults)
/// - `RenderLoop` — Rendering pipeline (scene + status bar)
@MainActor
internal final class AppRunner<A: App> {
    private let app: A
    private let appearanceManager: ThemeManager
    private let appHeader: AppHeaderState
    private let appState: AppState
    private let focusManager: FocusManager
    private let paletteManager: ThemeManager
    private let statusBar: StatusBarState
    private let terminal: Terminal
    private let tuiContext: TUIContext
    private var isRunning = false
    private var signals = SignalManager()

    init(app: A) {
        self.app = app
        // MUST be the shared singleton: `@State`/`StateBox`, `@Observable`,
        // `Spinner`, `AppStorage`, etc. all signal re-renders through
        // `AppState.shared`. The run loop polls *this* instance's `needsRender`,
        // so it has to be the same object — otherwise state changes never reach
        // the loop. (This was masked while the pulse/cursor timers force-rendered
        // ~30×/sec; demand-driven rendering exposed it as a frozen screen.)
        self.appState = AppState.shared
        self.appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: { [appState] in appState.setNeedsRender() })
        self.appHeader = AppHeaderState()
        self.focusManager = FocusManager()
        self.paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: { [appState] in appState.setNeedsRender() })
        self.statusBar = StatusBarState(appState: appState)
        self.statusBar.style = .bordered
        self.terminal = Terminal()
        self.tuiContext = TUIContext()
    }
}

// MARK: - Internal API

extension AppRunner {
    func run() async {
        // Create run-loop dependencies (previously IUOs, now local variables)
        let inputHandler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tuiContext.keyEventDispatcher,
            focusManager: focusManager,
            paletteManager: paletteManager,
            appearanceManager: appearanceManager,
            onQuit: { [weak self] in
                self?.isRunning = false
            }
        )
        // Wire the synthesised-key path: clicks on system status-
        // bar items (Back / Quit / Show — items with only a
        // triggerKey, no inline action) route their click through
        // the same 5-layer dispatch chain that a physical
        // keypress goes through. See StatusBar.swift's mouse
        // handler for the consumer side and TUIContext.swift's
        // `synthesizeKeyEvent` doc-comment for why this is a
        // closure threaded through the context.
        tuiContext.synthesizeKeyEvent = { _ = inputHandler.handle($0) }
        let renderer = RenderLoop(
            app: app,
            terminal: terminal,
            statusBar: statusBar,
            appHeader: appHeader,
            focusManager: focusManager,
            paletteManager: paletteManager,
            appearanceManager: appearanceManager,
            tuiContext: tuiContext
        )
        let pulseTimer = PulseTimer(renderNotifier: appState)
        let cursorTimer = CursorTimer(renderNotifier: appState)
        // Coalesces the periodic re-render requests of every animating view
        // (Spinner, indeterminate ProgressView, …) into the fewest distinct render
        // instants, and tells the loop when the next one is due. See
        // AnimationScheduler / RenderContext.requestAnimation.
        let animationScheduler = AnimationScheduler()

        // Setup
        signals.install()
        terminal.enterAlternateScreen()
        terminal.hideCursor()
        terminal.enableRawMode()

        // Apply the initial mouse-tracking mode based on the scene's
        // configuration. We do this before the first render so the
        // terminal is reporting the right events by the time any
        // input is processed. The mode is re-evaluated each frame
        // (and only re-emitted when it actually changes) — see the
        // re-apply step inside the main loop below.
        terminal.applyMouseSupport(.standard)

        // Wakes the main loop on stdin data (a DispatchSource on STDIN_FILENO)
        // and on render-requests (via `wake()`). The loop awaits its
        // `waitForArrival(...)`. See StdinArrivalStream.swift.
        let stdinArrival = StdinArrivalNotifier()
        stdinArrival.start()
        // Also wake on signals via SignalManager's self-pipe (set up in
        // `signals.install()` above), so a resize / SIGINT wakes the
        // demand-driven loop even while it's blocked with nothing to render.
        stdinArrival.watchWakeFD(signals.signalWakeReadFD)
        defer { stdinArrival.stop() }

        // Register for state changes: flag a rerender AND wake the (possibly
        // idle-blocked) loop. `setNeedsRender`'s observers can fire off the main
        // actor, so hop to the main actor to touch the MainActor-isolated
        // notifier. `stdinArrival` is captured weakly so this persistent observer
        // doesn't keep it alive past the run.
        appState.observe { [signals, weak stdinArrival] in
            signals.requestRerender()
            Task { @MainActor in stdinArrival?.wake() }
        }

        // Reset pulse animation and trigger re-render when focus changes
        focusManager.onFocusChange = { [weak pulseTimer, weak appState] in
            pulseTimer?.reset()
            appState?.setNeedsRender()
        }

        isRunning = true

        // Frame-rate cap: never render more than `frameIntervalNanos` apart, so a
        // burst of render-requests (e.g. an animation ticking faster than the
        // cap) coalesces into at most one render per frame. Otherwise purely
        // demand-driven: with nothing pending the loop blocks until woken, so a
        // static screen does ZERO renders. Rate from the app (default 60 FPS).
        let frameIntervalNanos: UInt64 = 1_000_000_000 / UInt64(max(1, app.maxFrameRate))
        var lastRenderAtNanos = DispatchTime.now().uptimeNanoseconds
        var pendingRender = false
        // The soonest instant any live animation grid next fires, or nil when
        // nothing is animating (the loop then blocks until woken — zero idle work).
        // Set by `renderFrame` from the scheduler each render.
        var animationDeadlineNanos: UInt64?

        // Renders one frame and adopts the per-frame state it produces: the time
        // of this render (for the frame-rate cap) and the next animation deadline.
        let renderOneFrame = {
            (lastRenderAtNanos, animationDeadlineNanos) = self.renderFrame(
                renderer: renderer,
                pulseTimer: pulseTimer,
                cursorTimer: cursorTimer,
                scheduler: animationScheduler)
        }

        // Initial render
        renderOneFrame()

        // Main loop
        while isRunning {
            // Check for graceful shutdown request (from SIGINT handler)
            if signals.shouldShutdown {
                isRunning = false
                break
            }

            // Check for an in-app `@Environment(\.dismiss)` call. Lets a
            // view exit the run loop cleanly without resorting to `exit()`,
            // which would skip the terminal-restore teardown below. Routed
            // through the shared `AppState` because that's the singleton
            // every other in-app trigger uses (`Spinner`, `AppStorage`, …).
            if AppState.shared.consumeShouldExit() {
                isRunning = false
                break
            }

            // Terminal resize (SIGWINCH): rewrite every line at the new size.
            if signals.consumeResizeFlag() {
                renderer.invalidateDiffCache()
                pendingRender = true
            }
            // A render requested by the AppState observer / state change.
            if signals.consumeRerenderFlag() {
                pendingRender = true
            }

            // Read + dispatch all pending terminal events (non-blocking),
            // BEFORE the render so a keypress / mouse action shows up in the
            // same frame it triggers. Extracted so the main loop stays legible.
            drainTerminalEvents(
                inputHandler: inputHandler,
                renderer: renderer,
                pulseTimer: pulseTimer,
                cursorTimer: cursorTimer)

            // Fold a state-change request (incl. input handled above) into the
            // pending-render flag.
            if appState.needsRender {
                appState.didRender()
                pendingRender = true
            }

            // One monotonic reading drives every decision this iteration — the
            // animation-fired test, the render-now test, and the wait length all
            // share it, so none can disagree about whether a deadline has passed.
            let now = DispatchTime.now().uptimeNanoseconds

            // An animation grid fired (its deadline arrived): a frame is due.
            if let deadline = animationDeadlineNanos, now >= deadline {
                pendingRender = true
            }

            // Render if one is due AND the frame-rate cap has cleared. The render
            // moves `lastRenderAtNanos` and the next deadline strictly past `now`,
            // so the wait computed below is always a real positive interval — never
            // a spurious "block forever" right after a render.
            if pendingRender, now >= lastRenderAtNanos &+ frameIntervalNanos {
                renderOneFrame()
                pendingRender = false
            }

            // How long to wait until the next render is due (cap and/or animation
            // folded into one instant), or nil to block until woken.
            let waitNanos = Self.waitUntilNextRender(
                now: now,
                pendingRender: pendingRender,
                lastRenderAtNanos: lastRenderAtNanos,
                frameIntervalNanos: frameIntervalNanos,
                animationDeadlineNanos: animationDeadlineNanos)

            // Block until woken (stdin data or a render-request `wake()`), or —
            // when a render is pending or an animation is due — until that target.
            // The wait releases the main actor, so the observer's `wake()` hop and
            // other queued main-actor work run between frames.
            await stdinArrival.waitForArrival(timeoutNanoseconds: waitNanos)
        }

        // Stop pulse timer before cleanup
        pulseTimer.stop()

        // Cleanup
        cleanup()
    }
}

// MARK: - Private Helpers

extension AppRunner {
    /// Renders one frame and returns the per-frame state the run loop tracks: the
    /// timestamp of this render (for the frame-rate cap) and the soonest instant
    /// any live animation grid next fires (`nil` if nothing is animating).
    ///
    /// The scheduler is fenced begin…end around the render: animating views
    /// re-declare their rates *during* the render (via `requestAnimation`), then
    /// the next-firing query reads the union of every still-live grid. Both the
    /// grids and the query use `frameNow`, so "soonest firing after this frame" is
    /// exact integer arithmetic, not a clock that drifted between the two. Also
    /// republishes the demand-driven pulse/cursor clocks (kept ticking only while
    /// a frame consumed them) and the mouse-tracking mode.
    fileprivate func renderFrame(
        renderer: RenderLoop<A>,
        pulseTimer: PulseTimer,
        cursorTimer: CursorTimer,
        scheduler: AnimationScheduler
    ) -> (lastRenderAtNanos: UInt64, animationDeadlineNanos: UInt64?) {
        scheduler.beginFrame()
        let frameNow = Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)
        let activity = renderer.render(
            pulsePhase: pulseTimer.phase,
            cursorTimer: cursorTimer,
            animationScheduler: scheduler,
            frameNowNanos: frameNow)
        scheduler.endFrame()
        // Demand-driven animation clocks: keep each ticking only while a frame
        // actually consumed it, so a static screen drives no further frames.
        if activity.usesPulse { pulseTimer.start() } else { pulseTimer.stop() }
        if activity.usesCursor { cursorTimer.start() } else { cursorTimer.stop() }
        let deadline = scheduler.nextFiring(after: frameNow).map { UInt64(bitPattern: $0) }
        // Re-evaluate the mouse-tracking mode (modifiers may elevate it this
        // frame); only re-emitted when it actually changes.
        let effective = renderer.effectiveMouseSupport()
        terminal.applyMouseSupport(effective)
        tuiContext.mouseEventDispatcher.setActiveSupport(effective)
        return (DispatchTime.now().uptimeNanoseconds, deadline)
    }

    /// The delay until the next render is due, or `nil` to block until woken.
    ///
    /// Folds the frame-rate cap and the next animation deadline into ONE instant:
    /// `pendingRender` wants a frame as soon as the cap clears; an animation wants
    /// one at its deadline but never sooner than the cap (so `max` there). Waiting
    /// to this single target — rather than to the deadline, waking, finding the cap
    /// not yet cleared, and waiting again — is what holds the loop to one wait per
    /// render. With nothing pending and nothing animating the target is `nil` and
    /// the loop blocks until woken, so a static screen does no work at all.
    fileprivate static func waitUntilNextRender(
        now: UInt64,
        pendingRender: Bool,
        lastRenderAtNanos: UInt64,
        frameIntervalNanos: UInt64,
        animationDeadlineNanos: UInt64?
    ) -> UInt64? {
        let capDeadline = lastRenderAtNanos &+ frameIntervalNanos
        var target: UInt64?
        if pendingRender {
            target = capDeadline
        }
        if let deadline = animationDeadlineNanos {
            let animTarget = max(deadline, capDeadline)
            target = min(target ?? animTarget, animTarget)
        }
        return target.map { $0 > now ? $0 &- now : 0 }
    }

    /// Reads and dispatches every terminal event currently pending (up to a
    /// per-frame cap of 128, which avoids paste lag without letting a flood
    /// spin the loop). Called BEFORE the frame renders so a keypress / mouse
    /// action shows up in the same frame it triggers.
    ///
    /// A consumed key or mouse event requests a render: focus / scroll moves go
    /// through plain (non-`@State`) handler properties that don't themselves
    /// call `setNeedsRender()`, so without this an arrow-key List navigation
    /// would move the selection but never repaint.
    fileprivate func drainTerminalEvents(
        inputHandler: InputHandler,
        renderer: RenderLoop<A>,
        pulseTimer: PulseTimer,
        cursorTimer: CursorTimer
    ) {
        var eventsProcessed = 0
        let maxEventsPerFrame = 128
        while eventsProcessed < maxEventsPerFrame, let input = terminal.readEvent() {
            switch input {
            case .key(let keyEvent):
                // "`": dump the current frame to ~/tuikit-frame.ansi (debug
                // shortcut, not consumed). Force a full repaint first so the
                // snapshot captures every line.
                if keyEvent.key == .character("`") {
                    renderer.invalidateDiffCache()
                    renderer.render(pulsePhase: pulseTimer.phase, cursorTimer: cursorTimer)
                    terminal.dumpLastFrame()
                }
                if inputHandler.handle(keyEvent) {
                    appState.setNeedsRender()
                }

            case .mouse(let mouseEvent):
                // Hit-test regions are in content-area coordinates; translate
                // the terminal-space y by the header height before dispatch.
                let translated = MouseEvent(
                    button: mouseEvent.button,
                    phase: mouseEvent.phase,
                    x: mouseEvent.x,
                    y: mouseEvent.y - appHeader.height,
                    shift: mouseEvent.shift,
                    ctrl: mouseEvent.ctrl,
                    meta: mouseEvent.meta
                )
                // Re-render only when a handler consumed the event — with
                // any-event mouse mode the terminal reports every motion.
                if tuiContext.mouseEventDispatcher.dispatch(translated) {
                    appState.setNeedsRender()
                }
            }
            eventsProcessed += 1
        }
    }

    fileprivate func cleanup() {
        terminal.disableRawMode()
        terminal.showCursor()
        terminal.exitAlternateScreen()
        appState.clearObservers()
        focusManager.clear()
        tuiContext.reset()
    }
}

// MARK: - Scene Rendering Protocol

/// Bridge from the `Scene` hierarchy to the `View` rendering system.
///
/// `SceneRenderable` sits outside the `View`/`Renderable` dual system.
/// It connects the `App.body` (which produces a `Scene`) to the view
/// tree rendering via ``renderToBuffer(_:context:)``.
///
/// `RenderLoop` calls `renderScene(context:)` on the scene returned
/// by `App.body`. The scene (typically ``WindowGroup``) then invokes
/// the free function `renderToBuffer` on its content view, entering
/// the standard `Renderable`-or-`body` dispatch.
@MainActor
internal protocol SceneRenderable {
    /// Renders the scene's content into a ``FrameBuffer``.
    ///
    /// The caller (`RenderLoop`) is responsible for writing the buffer
    /// to the terminal via `FrameDiffWriter`.
    ///
    /// - Parameter context: The rendering context with layout constraints.
    /// - Returns: The rendered frame buffer.
    func renderScene(context: RenderContext) -> FrameBuffer
}

/// Renders the window group's content view into a ``FrameBuffer``.
///
/// This is the bridge from `Scene` to `View` rendering:
/// calls ``renderToBuffer(_:context:)`` on `content` and returns the
/// resulting ``FrameBuffer``. Terminal output (diffing, writing) is
/// handled by `RenderLoop` via `FrameDiffWriter`.
///
/// Renders the window group's content view into a ``FrameBuffer``.
///
/// Like SwiftUI, `WindowGroup` centers its content both horizontally
/// and vertically within the available terminal space.
extension WindowGroup: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        let buffer = renderToBuffer(content, context: context)

        // Center the content in the available space, like SwiftUI does
        return centerBuffer(buffer, inWidth: context.availableWidth, height: context.availableHeight)
    }

    /// Centers a buffer within the target dimensions.
    private func centerBuffer(_ buffer: FrameBuffer, inWidth targetWidth: Int, height targetHeight: Int) -> FrameBuffer {
        // If buffer already fills the space exactly, return as-is
        if buffer.width == targetWidth && buffer.height == targetHeight {
            return buffer
        }

        var result: [String] = []
        result.reserveCapacity(targetHeight)

        // Calculate offsets for centering
        let verticalOffset = max(0, (targetHeight - buffer.height) / 2)
        let horizontalOffset = max(0, (targetWidth - buffer.width) / 2)

        // The full-width blank rows are identical, so build one and reuse it.
        let blankRow = String(asciiSpaces(targetWidth))

        // Add top padding (empty lines)
        for _ in 0..<verticalOffset {
            result.append(blankRow)
        }

        // Add content lines with horizontal centering. Each centred line is built
        // in place — reserve once, then append the leading spaces, the line, and
        // the trailing spaces as borrowed runs. Byte-identical to
        // `leftPadding + line + String(repeating:)` without the temporaries.
        for row in 0..<min(buffer.height, targetHeight - verticalOffset) {
            let line = buffer.lines[row]
            let rightPadding = max(0, targetWidth - horizontalOffset - line.strippedLength)
            var centered = ""
            centered.reserveCapacity(line.utf8.count + horizontalOffset + rightPadding)
            if horizontalOffset > 0 { centered += asciiSpaces(horizontalOffset) }
            centered += line
            if rightPadding > 0 { centered += asciiSpaces(rightPadding) }
            result.append(centered)
        }

        // Add bottom padding (empty lines)
        let bottomPadding = max(0, targetHeight - verticalOffset - buffer.height)
        for _ in 0..<bottomPadding {
            result.append(blankRow)
        }

        // The content shifted right by `horizontalOffset` and down by
        // `verticalOffset`; carry overlay layers AND hit-test regions
        // by the same amount so they stay anchored to the content
        // they were emitted alongside. Using the bare
        // FrameBuffer(lines:) initializer here would silently discard
        // every region the view tree built up, with the highly
        // misleading symptom "clicks on TextFields / Buttons /
        // anything do nothing, but only on pages whose content
        // doesn't exactly fill the terminal".
        return buffer.replacingLines(
            result,
            overlayShiftX: horizontalOffset,
            overlayShiftY: verticalOffset
        )
    }
}
