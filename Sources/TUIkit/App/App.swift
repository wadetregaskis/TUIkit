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
        tuiContext.synthesizeKeyEvent = { inputHandler.handle($0) }
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

        // Animation clocks are demand-driven: after each render the loop keeps a
        // clock ticking only while that frame actually consumed it. A static
        // screen (no focus pulse, no text cursor) leaves both stopped, so it
        // requests no further frames and the loop idles instead of re-rendering
        // identical output ~30×/sec.
        let applyAnimationActivity: (RenderActivity) -> Void = { activity in
            if activity.usesPulse { pulseTimer.start() } else { pulseTimer.stop() }
            if activity.usesCursor { cursorTimer.start() } else { cursorTimer.stop() }
        }

        // Frame-rate cap: never render more than `frameIntervalNanos` apart, so a
        // burst of render-requests (e.g. an animation ticking faster than the
        // cap) coalesces into at most one render per frame. Otherwise purely
        // demand-driven: with nothing pending the loop blocks until woken, so a
        // static screen does ZERO renders. Rate from the app (default 60 FPS).
        let frameIntervalNanos: UInt64 = 1_000_000_000 / UInt64(max(1, app.maxFrameRate))
        var lastRenderAtNanos = DispatchTime.now().uptimeNanoseconds
        var pendingRender = false

        // Initial render
        applyAnimationActivity(
            renderer.render(pulsePhase: pulseTimer.phase, cursorTimer: cursorTimer))

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

            // Read + dispatch all pending terminal events (non-blocking). Done
            // BEFORE the render so a keypress / mouse action shows up in the same
            // frame it triggers. A high cap avoids paste lag without spinning.
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
                    inputHandler.handle(keyEvent)

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

            // Fold a state-change request (incl. input handled above) into the
            // pending-render flag.
            if appState.needsRender {
                appState.didRender()
                pendingRender = true
            }

            // Render at most once per frame interval. If a render is pending but
            // the previous one was less than one interval ago, wait out the
            // remainder (the cap) instead of rendering now. With nothing pending,
            // leave `waitNanos` nil: the loop blocks until a wake (stdin or a
            // render-request), so a static screen does no work at all.
            var waitNanos: UInt64? = nil
            if pendingRender {
                let now = DispatchTime.now().uptimeNanoseconds
                let elapsed = now &- lastRenderAtNanos
                if elapsed >= frameIntervalNanos {
                    applyAnimationActivity(
                        renderer.render(pulsePhase: pulseTimer.phase, cursorTimer: cursorTimer))
                    // Re-evaluate the mouse-tracking mode (modifiers may elevate
                    // it this frame); only re-emitted when it actually changes.
                    let effective = renderer.effectiveMouseSupport()
                    terminal.applyMouseSupport(effective)
                    tuiContext.mouseEventDispatcher.setActiveSupport(effective)
                    lastRenderAtNanos = DispatchTime.now().uptimeNanoseconds
                    pendingRender = false
                } else {
                    waitNanos = frameIntervalNanos &- elapsed
                }
            }

            // Block until woken (stdin data or a render-request `wake()`), or —
            // when rate-limited — until the frame deadline. The wait releases the
            // main actor, so the observer's `wake()` hop and other queued
            // main-actor work run between frames.
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
        let leftPadding = String(repeating: " ", count: horizontalOffset)

        // Add top padding (empty lines)
        for _ in 0..<verticalOffset {
            result.append(String(repeating: " ", count: targetWidth))
        }

        // Add content lines with horizontal centering
        for row in 0..<min(buffer.height, targetHeight - verticalOffset) {
            let line = buffer.lines[row]
            let rightPadding = max(0, targetWidth - horizontalOffset - line.strippedLength)
            result.append(leftPadding + line + String(repeating: " ", count: rightPadding))
        }

        // Add bottom padding (empty lines)
        let bottomPadding = max(0, targetHeight - verticalOffset - buffer.height)
        for _ in 0..<bottomPadding {
            result.append(String(repeating: " ", count: targetWidth))
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
