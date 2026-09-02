//  🖥️ TUIkit — Terminal UI Kit for Swift
//  App.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

/// Whether the backtick frame-dump debug shortcut is armed — opt-in via
/// `TUIKIT_DEBUG_FRAME_DUMP=1`, same convention as `TUIKIT_DEBUG_FOCUS`.
/// File-scope (the runner is generic, which forbids static stored properties)
/// and read once: it's consulted per keystroke.
private let frameDumpEnabled: Bool =
    getenv("TUIKIT_DEBUG_FRAME_DUMP").map { String(cString: $0) == "1" } ?? false

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
    private let signals = SignalManager()

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
        // No style assignment here: the bars' default lives on their own state
        // (``ChromeStyle/rule``, so the two mirror each other) and an app picks
        // something else with `Scene.chromeStyle(...)`. Overriding it here made
        // that default dead code and the footer a box under a ruled header.
        self.statusBar = StatusBarState(appState: appState)
        self.terminal = Terminal()
        self.tuiContext = TUIContext()
    }
}

// MARK: - Internal API

extension AppRunner {
    /// The five-layer key-dispatch chain over the runner's collaborators.
    private func makeInputHandler() -> InputHandler {
        InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tuiContext.keyEventDispatcher,
            focusManager: focusManager,
            paletteManager: paletteManager,
            appearanceManager: appearanceManager,
            keyboardShortcuts: tuiContext.keyboardShortcuts,
            dragAndDropSession: tuiContext.dragAndDropSession,
            onQuit: { [weak self] in
                self?.isRunning = false
            },
            // Ctrl-Z, unconsumed by any view: give it its shell meaning by
            // re-raising the signal it would have been in cooked mode. The
            // SIGTSTP source observes it and the loop suspends between frames.
            onSuspend: {
                kill(getpid(), SIGTSTP)
            }
        )
    }

    func run() async {
        // Create run-loop dependencies (previously IUOs, now local variables)
        let inputHandler = makeInputHandler()
        // Wire the synthesised-key path: clicks on system status-
        // bar items (Back / Quit / Show — items with only a
        // triggerKey, no inline action) route their click through
        // the same 5-layer dispatch chain that a physical
        // keypress goes through. See StatusBar.swift's mouse
        // handler for the consumer side and TUIContext.swift's
        // `synthesizeKeyEvent` doc-comment for why this is a
        // closure threaded through the context.
        tuiContext.synthesizeKeyEvent = { _ = inputHandler.handle($0) }
        let cursorTimer = CursorTimer(renderNotifier: appState)
        // Coalesces the periodic re-render requests of every animating view
        // (Spinner, indeterminate ProgressView, …) into the fewest distinct render
        // instants, and tells the loop when the next one is due. See
        // AnimationScheduler / RenderContext.requestAnimation.
        let animationScheduler = AnimationScheduler()

        // Wakes the main loop on stdin data (a DispatchSource on STDIN_FILENO)
        // and on render-requests (via `wake()`). The loop awaits its
        // `waitForArrival(...)`. See StdinArrivalStream.swift. Created before the
        // signal install below because the signal sources' wake closure captures
        // it (a SIGWINCH / SIGINT / SIGTERM must rouse the idle-blocked loop).
        let stdinArrival = StdinArrivalNotifier()
        stdinArrival.start()
        defer { stdinArrival.stop() }

        // Setup: install the dispatch signal sources (SIGWINCH resize, SIGINT /
        // SIGTERM graceful shutdown). Each source's handler sets a flag the loop
        // drains and wakes the notifier. `await`s until every source is armed.
        await signals.install(wake: { [weak stdinArrival] in stdinArrival?.wake() })
        terminal.enterAlternateScreen()
        terminal.hideCursor()
        terminal.enableRawMode()

        // If nothing in the environment named the host, ask the terminal
        // itself — which is the only question that survives an ssh hop, where
        // `TERM_PROGRAM` does not (see TerminalHost.hostProgram). One write and
        // one round trip, and only in the case that is otherwise rendering
        // incorrectly: an Apple Terminal reached over ssh, painting every VS-16
        // emoji, lone regional indicator and SF Symbol two cells wide while
        // advancing one.
        //
        // BEFORE the render loop below, and deliberately: TerminalHost's
        // detectors are `static let`, so each freezes on first read, and the
        // loop's FrameDiffWriter reads all of them as its init defaults. Under
        // tmux there is nothing to ask — the pane's grid is tmux's, not the
        // client's, and `$TMUX` has already answered.
        if !TerminalHost.hostIsNamedByEnvironment, !TerminalHost.isTmux {
            TerminalHost.identify(using: terminal)
        }

        // AFTER identification, because the question is only safe to ask a host
        // known to answer it: DECRQM's `CSI ? Ps $ p` is the one CSI shape
        // Apple Terminal prints instead of consuming. Before the render loop,
        // for the same reason identification is — the advance model this
        // protects is frozen into `FrameDiffWriter` at construction.
        terminal.pinGraphemeClusteringIfNeeded()

        // The host's width traits, published before anything measures a view:
        // the claim follows the host now, so layout must see it from frame one.
        TerminalClient.applyWidthTraits()
        // And whether it honours OSC 8 hyperlinks, for the same reason: a
        // `Link` decides whether to emit one while rendering, and the render
        // path cannot ask a main-actor question.
        TerminalClient.applyHyperlinkSupport()

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

        // Under tmux, have it PUSH a SIGWINCH at us whenever a client attaches,
        // detaches, or changes session — the only events that can change which
        // terminal is painting our output (and so the emoji-chrome answer). A
        // same-size attach sends no SIGWINCH of its own, so without this the
        // answer could go stale until something happened to resize. Comes after
        // signals.install() so the SIGWINCH source exists before the first
        // hook can fire. Failure (a tmux too old for these hooks) is tolerated:
        // the app then adapts only on real resizes.
        if TerminalHost.isTmux {
            TerminalHost.installTmuxClientChangeHooks()
        }

        // Apply the initial mouse-tracking mode based on the scene's
        // configuration. We do this before the first render so the
        // terminal is reporting the right events by the time any
        // input is processed. The mode is re-evaluated each frame
        // (and only re-emitted when it actually changes) — see the
        // re-apply step inside the main loop below.
        terminal.applyMouseSupport(.standard)

        // Register for state changes: wake the (possibly idle-blocked) loop.
        // `setNeedsRender` already set `appState.needsRender` synchronously (the
        // loop polls it), so the observer's only job is to rouse the loop.
        // `setNeedsRender`'s observers can fire off the main actor, so hop to the
        // main actor to touch the MainActor-isolated notifier. `stdinArrival` is
        // captured weakly so this persistent observer doesn't keep it alive past
        // the run.
        appState.observe { [weak stdinArrival] in
            Task { @MainActor in stdinArrival?.wake() }
        }

        // Restart the breath and re-render when the focus moves, so the newly
        // focused control is at its brightest the moment it takes the focus
        // (the phase starts at its bright end — see `CursorTimer.pulsePhase`).
        focusManager.onFocusChange = { [weak cursorTimer, weak appState] in
            cursorTimer?.restartFocusPhase()
            appState?.setNeedsRender()
        }

        isRunning = true

        // Owns when a frame is due: never renders two frames closer together than
        // the app's rate (default 60 FPS), so a burst of render-requests — an
        // animation ticking faster than the cap, say — coalesces into at most one
        // render per frame. Otherwise purely demand-driven: with nothing pending
        // the loop blocks until woken, so a static screen does ZERO renders.
        var pacer = FramePacer(
            maxFrameRate: app.maxFrameRate,
            startedAtNanos: DispatchTime.now().uptimeNanoseconds)
        let renderOneFrame = {
            self.renderFrame(
                renderer: renderer,
                cursorTimer: cursorTimer,
                scheduler: animationScheduler)
        }

        // Initial render
        pacer.render(renderOneFrame)

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
                pacer.requestRender()
            }

            // Ctrl-Z (SIGTSTP): hand the terminal back to the shell, stop for
            // real, and rebuild everything when `fg` resumes us. Runs here —
            // not in the signal handler — because only the loop owns the
            // terminal state it has to tear down and rebuild.
            if signals.consumeSuspendFlag() {
                // The one scene-phase transition a terminal can actually
                // report. Render a frame at `.background` BEFORE stopping, so
                // an `onChange(of: scenePhase)` observer gets to run while the
                // process is still alive — an app that saves on the way down
                // has no other moment. See ``ScenePhase``.
                tuiContext.scenePhase = .background
                renderer.render(pulsePhase: cursorTimer.breathPhase, cursorTimer: cursorTimer)
                suspendUntilContinued(renderer: renderer)
                tuiContext.scenePhase = .active
                pacer.requestRender()
            }

            // Resumed from an *external* SIGSTOP, which cannot be caught, so
            // nothing was torn down and nothing needs rebuilding — but the
            // screen may have been disturbed while the process slept.
            if signals.consumeContinueFlag() {
                renderer.invalidateDiffCache()
                pacer.requestRender()
            }

            // Read + dispatch all pending terminal events (non-blocking),
            // BEFORE the render so a keypress / mouse action shows up in the
            // same frame it triggers. Extracted so the main loop stays legible.
            drainTerminalEvents(
                inputHandler: inputHandler,
                renderer: renderer,
                cursorTimer: cursorTimer)

            // Fold a state change, and any animation tick the cheap path could
            // not serve, into the pending-render flag.
            if foldPendingWork(
                alreadyPending: pacer.isRenderPending, renderer: renderer,
                cursorTimer: cursorTimer) {
                pacer.requestRender()
            }

            // One monotonic reading drives every decision this iteration — the
            // animation-fired test, the render-now test, and the wait length all
            // share it, so none can disagree about whether a deadline has passed.
            let now = DispatchTime.now().uptimeNanoseconds

            // Render if a frame is due — a state change, or an animation grid
            // whose deadline `now` has reached — AND the frame-rate cap has
            // cleared. The render moves both the cap and the next deadline
            // strictly past `now`, so the wait computed below is always a real
            // positive interval, never a spurious "block forever".
            pacer.renderIfDue(now: now, renderOneFrame)

            // How long to wait until the next render is due (cap and/or animation
            // folded into one instant), or nil to block until woken. While the
            // input parser holds something that resolves on a timeout — a lone
            // ESC being disambiguated from a sequence, or a split sequence
            // awaiting its tail — the wait is shortened to a poll, so the partial
            // resolves on a bounded wall-clock deadline (a prompt Escape) instead
            // of waiting for unrelated input or an animation tick.
            let waitNanos = pacer.waitNanos(
                now: now, pollingPendingInput: terminal.hasPendingInput)

            // Block until woken (stdin data or a render-request `wake()`), or —
            // when a render is pending or an animation is due — until that target.
            // The wait releases the main actor, so the observer's `wake()` hop and
            // other queued main-actor work run between frames.
            await stdinArrival.waitForArrival(timeoutNanoseconds: waitNanos)
        }

        // Stop the animation clock before cleanup
        cursorTimer.stop()

        // Cleanup
        cleanup(renderer: renderer)
    }
}

// MARK: - Private Helpers

extension AppRunner {
    /// Folds this iteration's reasons to render into one flag.
    ///
    /// A state change always needs a frame. An animation tick usually does not:
    /// it is served by advancing the animated cells of the frame already on
    /// screen. Replay is skipped when a render is due anyway — one is strictly
    /// better, and replaying first would paint the old frame's cells over
    /// content about to change.
    fileprivate func foldPendingWork(
        alreadyPending: Bool, renderer: RenderLoop<A>, cursorTimer: CursorTimer
    ) -> Bool {
        var pending = alreadyPending
        if appState.needsRender {
            appState.didRender()
            pending = true
        }
        if pending {
            // A full frame supersedes any tick, so drop them rather than let
            // them queue up and fire against the frame after next.
            _ = appState.consumePendingAnimationClocks()
            return true
        }
        return !serveAnimationTicks(renderer: renderer, cursorTimer: cursorTimer)
    }

    /// Advances any clocks that ticked, without rendering, when every one of
    /// them can be served from the frame already on screen.
    ///
    /// - Returns: `false` if a full render is needed instead — either some view
    ///   still builds its appearance from a phase as it renders, or there is no
    ///   frame to patch yet. That is the behaviour this replaces, so falling
    ///   back is always safe.
    fileprivate func serveAnimationTicks(
        renderer: RenderLoop<A>, cursorTimer: CursorTimer
    ) -> Bool {
        let ticked = appState.consumePendingAnimationClocks()
        guard !ticked.isEmpty else { return true }  // nothing ticked; nothing owed
        var elapsed: [AnimationClock: Double] = [:]
        for clock in ticked where renderer.lastActivity.canReplay(clock) {
            elapsed[clock] = cursorTimer.elapsed(for: clock)
        }
        guard elapsed.count == ticked.count else { return false }
        let served = renderer.replayAnimations(elapsed: elapsed)
        if served {
            // The runs are unchanged, but the time is not: recompute how long
            // the clock may sleep from where it now is.
            cursorTimer.advance(by: renderer.timeUntilNextChange(elapsed: cursorTimer.elapsed))
        }
        return served
    }

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
        cursorTimer: CursorTimer,
        scheduler: AnimationScheduler
    ) -> FramePacer.Frame {
        scheduler.beginFrame()
        let frameNow = Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)
        let activity = renderer.render(
            pulsePhase: cursorTimer.breathPhase,
            cursorTimer: cursorTimer,
            animationScheduler: scheduler,
            frameNowNanos: frameNow)
        scheduler.endFrame()
        // Demand-driven animation clock: kept ticking only while a frame
        // actually consumed it, so a static screen drives no further frames.
        // It keeps running while EITHER a view reads it as it renders or the
        // frame left runs on it — the second is the cheap path, and stopping
        // the clock because nobody read the phase would freeze it.
        // ANY clock: the frame may animate content without anything focused
        // reading the phase, and stopping the timer then freezes the
        // indeterminate bars.
        let clockLive =
            activity.usesPulse || activity.usesCursor || !activity.animatedClocks.isEmpty
        if clockLive {
            // Sleep exactly as long as nothing can change — see
            // `RenderLoop.timeUntilNextChange(elapsed:)`.
            cursorTimer.advance(by: renderer.timeUntilNextChange(elapsed: cursorTimer.elapsed))
            cursorTimer.start()
        } else {
            cursorTimer.stop()
        }
        let deadline = scheduler.nextFiring(after: frameNow).map { UInt64(bitPattern: $0) }
        // Re-evaluate the mouse-tracking mode (modifiers may elevate it this
        // frame); only re-emitted when it actually changes.
        let effective = renderer.effectiveMouseSupport()
        terminal.applyMouseSupport(effective)
        tuiContext.mouseEventDispatcher.setActiveSupport(effective, isFrameFinal: true)
        return FramePacer.Frame(
            renderedAtNanos: DispatchTime.now().uptimeNanoseconds,
            animationDeadlineNanos: deadline)
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
    /// The Ctrl-Z round trip: hands the terminal back to the shell exactly the
    /// way quitting would, stops the process for real, and — execution resumes
    /// at the next line when `fg` delivers SIGCONT — rebuilds the terminal
    /// exactly the way `run` set it up.
    ///
    /// `SIGSTOP` is used for the stop because it cannot be caught or ignored:
    /// SIGTSTP's default action is suppressed by the signal source's
    /// registration (stopping the instant it lands would strand the shell in
    /// raw mode on the alternate screen), so re-raising it would just re-enter
    /// the handler.
    ///
    /// The mouse mode is set to `.none` on the way down and NOT re-applied here
    /// on the way up: the loop re-evaluates the effective mode every frame and
    /// re-emits it on change, so the first frame after resume — forced by the
    /// diff-cache invalidation — restores whatever mode the scene wants.
    fileprivate func suspendUntilContinued(renderer: RenderLoop<A>) {
        terminal.applyMouseSupport(.disabled)
        // Before the screen goes back: a frame may have ended with styling in
        // force, and leaving the alternate screen does not restore SGR.
        renderer.restoreTerminalStyling()
        terminal.disableRawMode()
        terminal.showCursor()
        terminal.exitAlternateScreen()
        // Our own resume delivers a SIGCONT too; the repaint is already
        // forced below, so arm the source to swallow that one signal.
        // Arming (not consume-after-resume): the SIGCONT source runs on the
        // main queue, which cannot fire until this synchronous path has
        // finished — a consume here would run before the flag is ever set,
        // and the loop would double-repaint on the next iteration.
        signals.expectSelfResume()
        kill(getpid(), SIGSTOP)
        // ── stopped; `fg` resumes here ──
        //
        // So does `bg`, and a BACKGROUND process must not touch the terminal:
        // the escapes below would garble the shell's prompt, and grabbing raw
        // mode would steal the foreground shell's keystrokes. Re-stop until
        // the shell actually hands the terminal over (`fg` makes this group
        // the foreground group) — which is also what the kernel's SIGTTOU
        // default would do to a background job touching the tty, so `bg`
        // behaves the way it does for any full-screen program: the job
        // reports stopped again, and finishes its resume when foregrounded.
        // The `>= 0` guards a failed query (not a tty): never loop on an
        // answer that cannot change.
        while tcgetpgrp(STDIN_FILENO) >= 0, tcgetpgrp(STDIN_FILENO) != getpgrp() {
            signals.expectSelfResume()
            kill(getpid(), SIGSTOP)
        }
        terminal.enterAlternateScreen()
        terminal.hideCursor()
        terminal.enableRawMode()
        renderer.invalidateDiffCache()
    }

    fileprivate func drainTerminalEvents(
        inputHandler: InputHandler,
        renderer: RenderLoop<A>,
        cursorTimer: CursorTimer
    ) {
        var eventsProcessed = 0
        let maxEventsPerFrame = 128
        while eventsProcessed < maxEventsPerFrame, let input = terminal.readEvent() {
            switch input {
            case .key(let keyEvent):
                focusManager.noteInputSource(.keyboard)
                // "`": dump the current frame to a file (debug shortcut, not
                // consumed). Opt-in via TUIKIT_DEBUG_FRAME_DUMP=1 — unguarded,
                // every backtick ANYWHERE (typing one into a TextField, a
                // Markdown snippet in a TextEditor) silently wrote a frame
                // file into the user's working directory. Force a full
                // repaint first so the snapshot captures every line.
                if keyEvent.key == .character("`"), frameDumpEnabled {
                    renderer.invalidateDiffCache()
                    renderer.render(pulsePhase: cursorTimer.breathPhase, cursorTimer: cursorTimer)
                    terminal.dumpLastFrame()
                }
                if inputHandler.handle(keyEvent) {
                    appState.setNeedsRender()
                }

            case .mouse(let mouseEvent):
                focusManager.noteInputSource(.pointer)
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

    fileprivate func cleanup(renderer: RenderLoop<A>) {
        // Before the terminal teardown: this forks tmux, and doing it while our
        // pane is still alive is the tidy window. A crash skips this — then the
        // hooks' own `||` arm removes them on their next firing instead (see
        // `TerminalHost.tmuxClientChangeHookArguments`).
        if TerminalHost.isTmux {
            TerminalHost.removeTmuxClientChangeHooks()
        }
        // See the twin in `suspendUntilContinued`.
        renderer.restoreTerminalStyling()
        terminal.disableRawMode()
        terminal.showCursor()
        terminal.exitAlternateScreen()
        signals.stop()
        appState.clearObservers()
        focusManager.clear()
        tuiContext.reset()
        // Persistence writes are queued asynchronously (and coalesced), so a
        // value stored moments before quitting may not have reached disk yet.
        // Flush behind any queued save — without this, "change a setting and
        // quit" sometimes silently lost the setting.
        StorageDefaults.backend.synchronize()
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
        // Drop targets re-register as the tree renders (like focus), so the
        // drag session's per-frame registry resets here, before the pass.
        let dragSession = context.environment.dragAndDropSession
        dragSession?.beginFrame()

        let buffer = renderToBuffer(content, context: context)

        // Center the content in the available space, like SwiftUI does
        var centered = centerBuffer(
            buffer, inWidth: context.availableWidth, height: context.availableHeight)

        // The floating drag preview rides above everything. Attached AFTER
        // centering so its offsets are in the same absolute content-area
        // space as the mouse events driving it; where it sits relative to
        // the cursor is the drag's ``DragPreviewAnchor`` (grab-point by
        // default — the pressed cell stays under the cursor, macOS-style),
        // resolved by the session so drops report the same frame.
        //
        // The LIFTED frame: for the first ~120 ms the picture is still on its
        // way out of the row it came from. See `liftedPreviewFrame()` for why
        // that blend lives at the draw site rather than in the anchor math.
        if let frame = dragSession?.liftedPreviewFrame(),
            let content = dragSession?.liftedPreviewContent()
        {
            centered.overlays.append(
                OverlayLayer(
                    offsetX: frame.x,
                    offsetY: frame.y,
                    content: content,
                    level: .notification,
                    // Pinned to the pointer: clipped at the screen edge, never
                    // slid back onto it. Sliding is what made a wide preview
                    // stop following the cursor a few cells in.
                    clampsToScreen: false
                )
            )
        } else if let step = dragSession?.returnFlightFrame {
            // A cancelled drag on its way home: the same overlay, walking back
            // to where the row started. The render loop advances it and keeps
            // asking for frames; this draws wherever it has got to.
            centered.overlays.append(
                OverlayLayer(
                    offsetX: step.x, offsetY: step.y,
                    content: step.preview, level: .notification, clampsToScreen: false))
        }
        return centered
    }

    /// Centers a buffer within the target dimensions.
    private func centerBuffer(_ buffer: FrameBuffer, inWidth targetWidth: Int, height targetHeight: Int) -> FrameBuffer {
        // If buffer already fills the space exactly, return as-is
        if buffer.width == targetWidth && buffer.height == targetHeight {
            return buffer
        }

        // Total for ANY target, not just a sane one. `RenderLoop` clamps the
        // content area at zero, but this must not *depend* on that: a negative
        // target used to reach the row loop below as `0..<negative` and trap
        // ("Range requires lowerBound <= upperBound") — the app died on launch in
        // a terminal shorter than its own status bar plus app header. Clamping at
        // the source fixes the bug; clamping here keeps it fixed.
        let targetWidth = max(0, targetWidth)
        let targetHeight = max(0, targetHeight)

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
