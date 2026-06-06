//  🖥️ TUIKit — Terminal UI Kit for Swift
//  App.swift
//
//  Created by LAYERED.work
//  License: MIT

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
}

extension App {
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
        self.appState = AppState()
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

        // Register for state changes
        appState.observe { [signals] in
            signals.requestRerender()
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

        // Wake the main loop the moment stdin has data,
        // instead of always sleeping for ~24 ms regardless of
        // input. The notifier wraps a DispatchSource on
        // STDIN_FILENO; the main loop awaits its
        // `waitForArrival(timeoutNanoseconds:)` in lieu of a
        // bare `Task.sleep`. See StdinArrivalStream.swift for
        // the why.
        let stdinArrival = StdinArrivalNotifier()
        stdinArrival.start()
        defer { stdinArrival.stop() }

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

            // Invalidate diff cache on terminal resize so every line
            // is rewritten with the new dimensions.
            if signals.consumeResizeFlag() {
                renderer.invalidateDiffCache()
            }

            // Check if terminal was resized or state changed
            if signals.consumeRerenderFlag() || appState.needsRender {
                appState.didRender()
                applyAnimationActivity(
                    renderer.render(pulsePhase: pulseTimer.phase, cursorTimer: cursorTimer))
                // Re-evaluate the mouse-tracking mode now that
                // modifiers have had a chance to elevate the base
                // configuration this frame. The terminal only emits a
                // mode-change escape if the effective mode actually
                // changed.
                let effective = renderer.effectiveMouseSupport()
                terminal.applyMouseSupport(effective)
                tuiContext.mouseEventDispatcher.setActiveSupport(effective)
            }

            // Read terminal events (non-blocking with VTIME=0).
            // Process all available events per frame. A high limit
            // prevents input buffering lag during paste operations while
            // still avoiding infinite loops if input arrives faster than
            // we can process.
            var eventsProcessed = 0
            let maxEventsPerFrame = 128
            while eventsProcessed < maxEventsPerFrame,
                let input = terminal.readEvent()
            {
                switch input {
                case .key(let keyEvent):
                    // "`": dump the current frame to ~/tuikit-frame.ansi.
                    // Permanent debug shortcut — does not consume the
                    // event so view-level "`" handlers can still
                    // respond if needed.
                    //
                    // lastFrameData only contains what the *diff* wrote,
                    // which is empty on a static screen.  Force a full
                    // repaint first so the frame buffer captures every
                    // line, then dump that snapshot.
                    if keyEvent.key == .character("`") {
                        renderer.invalidateDiffCache()
                        renderer.render(pulsePhase: pulseTimer.phase, cursorTimer: cursorTimer)
                        terminal.dumpLastFrame()
                    }

                    inputHandler.handle(keyEvent)

                case .mouse(let mouseEvent):
                    // Mouse hit-test regions are in content-area
                    // coordinates (origin = top-left of the content
                    // area), so translate the terminal-space y by the
                    // header height before dispatching. x is already
                    // aligned since the header spans the full width.
                    let translated = MouseEvent(
                        button: mouseEvent.button,
                        phase: mouseEvent.phase,
                        x: mouseEvent.x,
                        y: mouseEvent.y - appHeader.height,
                        shift: mouseEvent.shift,
                        ctrl: mouseEvent.ctrl,
                        meta: mouseEvent.meta
                    )
                    // Only request a re-render when a handler actually
                    // consumed the event. With any-event mouse mode
                    // (?1003h) the terminal fires a motion report on
                    // every cursor twitch — re-rendering for every one
                    // would peg the render loop and starve key input.
                    if tuiContext.mouseEventDispatcher.dispatch(translated) {
                        appState.setNeedsRender()
                    }
                }
                eventsProcessed += 1
            }

            // Wait for either:
            //   - up to ~24 ms (the animation cadence, ~42 FPS), or
            //   - stdin to have data (the moment the user types
            //     or the terminal sends a mouse / focus report).
            // Whichever fires first wakes the loop. The arrival
            // path drops a keystroke's worth of latency: before
            // this change, even a single keypress could sit in
            // the kernel buffer for up to ~24 ms before the loop
            // drained it.
            //
            // The notifier's wait is a real suspension point —
            // it releases the main actor while we wait, so work
            // queued via `Task { @MainActor }`, `MainActor.run`,
            // or `DispatchQueue.main` runs between frames just
            // as it did with the old bare `Task.sleep`.
            await stdinArrival.waitForArrival(timeoutNanoseconds: 23_800_000)
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
