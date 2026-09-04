//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RunLoopFoldTests.swift
//
//  The three rules the run loop folds an iteration's work by: a due frame
//  supersedes any queued animation tick, a tick is replayed only when EVERY
//  ticked clock can be, and a served replay re-bases the sleep. Each is one
//  line inside `AppRunner`, each is the difference between a demand-driven
//  loop and an idle render storm, and none of them was asserted anywhere.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A scene with nothing animating: every clock is unreplayable against it.
private struct StillProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
        }
    }
}

/// A scene whose only content leaves an ``AnimatedCellRun`` on the
/// ``AnimationClock/content`` clock and reads no phase, so that clock — and
/// only that clock — is replayable against its frame.
private struct SpinningProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Spinner()
        }
    }
}

@MainActor
@Suite("Run-loop work folding", .serialized)
struct RunLoopFoldTests {

    /// Everything `RenderLoop` needs, assembled the way `AppRunner` does — the
    /// same shape as `RenderPassScopeTests.Harness`.
    @MainActor
    private final class Harness {
        let terminal = MockTerminal()
        let statusBar: StatusBarState
        let appHeader = AppHeaderState()
        let focusManager = FocusManager()
        let tuiContext = TUIContext()
        let paletteManager: ThemeManager
        let appearanceManager: ThemeManager

        init() {
            let appState = AppState()
            self.statusBar = StatusBarState(appState: appState)
            self.paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: {})
            self.appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: {})
        }

        func loop<A: App>(_ app: A) -> RenderLoop<A> {
            RenderLoop(
                app: app,
                terminal: terminal,
                statusBar: statusBar,
                appHeader: appHeader,
                focusManager: focusManager,
                paletteManager: paletteManager,
                appearanceManager: appearanceManager,
                tuiContext: tuiContext)
        }
    }

    /// `AppRunner` binds itself to `AppState.shared` — deliberately, since that
    /// is the instance every `@State` write signals through — so these tests
    /// share one queue and must start from a clean one. Hence `.serialized`.
    private func freshRunner<A: App>(_ app: A) -> AppRunner<A> {
        AppState.shared.didRender()
        _ = AppState.shared.consumePendingAnimationClocks()
        // `Terminal.init()` only reserves a buffer, so this touches no TTY.
        return AppRunner(app: app)
    }

    // MARK: - A due frame supersedes the ticks

    @Test("A frame that is already due drops the queued ticks rather than deferring them")
    func pendingRenderDropsTicks() {
        let runner = freshRunner(StillProbeApp())
        AppState.shared.setNeedsAnimationTick(.cursor)
        AppState.shared.setNeedsAnimationTick(.content)
        let harness = Harness()

        #expect(
            runner.foldPendingWork(
                alreadyPending: true, renderer: harness.loop(StillProbeApp()),
                cursorTimer: CursorTimer(renderNotifier: AppState.shared)))
        // The rule: a full frame serves every clock, so a tick left queued here
        // would fire against the frame AFTER the one about to be drawn — a wake
        // and a patch for a picture already correct.
        #expect(AppState.shared.consumePendingAnimationClocks().isEmpty)
    }

    @Test("A state change makes the frame due, and takes the ticks with it")
    func stateChangeDropsTicks() {
        let runner = freshRunner(StillProbeApp())
        AppState.shared.setNeedsAnimationTick(.cursor)
        AppState.shared.setNeedsRender()
        let harness = Harness()

        #expect(
            runner.foldPendingWork(
                alreadyPending: false, renderer: harness.loop(StillProbeApp()),
                cursorTimer: CursorTimer(renderNotifier: AppState.shared)))
        #expect(!AppState.shared.needsRender, "the flag must be consumed by the fold")
        #expect(AppState.shared.consumePendingAnimationClocks().isEmpty)
    }

    @Test("An idle iteration with nothing queued asks for no frame")
    func idleIterationIsQuiet() {
        let runner = freshRunner(StillProbeApp())
        let harness = Harness()

        #expect(
            !runner.foldPendingWork(
                alreadyPending: false, renderer: harness.loop(StillProbeApp()),
                cursorTimer: CursorTimer(renderNotifier: AppState.shared)))
        #expect(harness.terminal.writtenOutput.isEmpty)
    }

    // MARK: - Replay is all-or-nothing

    @Test("A tick no frame can serve falls back to a full render, writing nothing")
    func unreplayableTickFallsBack() {
        let runner = freshRunner(StillProbeApp())
        let harness = Harness()
        // Never rendered, so `replayable` is nil and `lastActivity` is the
        // all-false initial value: `canReplay` is false for every clock.
        let loop = harness.loop(StillProbeApp())
        AppState.shared.setNeedsAnimationTick(.cursor)

        #expect(!runner.serveAnimationTicks(renderer: loop, cursorTimer: CursorTimer(renderNotifier: AppState.shared)))
        #expect(harness.terminal.writtenOutput.isEmpty, "the fallback path must not write")
        // And the fold reports the same thing the other way round.
        AppState.shared.setNeedsAnimationTick(.cursor)
        #expect(
            runner.foldPendingWork(
                alreadyPending: false, renderer: loop,
                cursorTimer: CursorTimer(renderNotifier: AppState.shared)))
    }

    @Test("A ticked clock with nothing to advance does not force a render")
    func idleClockTickIsNotAFallback() {
        let runner = freshRunner(SpinningProbeApp())
        let harness = Harness()
        let loop = harness.loop(SpinningProbeApp())
        let timer = CursorTimer(renderNotifier: AppState.shared)
        let activity = loop.render(cursorTimer: timer)
        #expect(activity.canReplay(.content), "the spinner must leave a content-clock run")
        #expect(!activity.canReplay(.cursor), "nothing on this page animates the cursor clock")

        AppState.shared.setNeedsAnimationTick(.content)
        AppState.shared.setNeedsAnimationTick(.cursor)

        // The all-or-nothing rule is over the clocks that HAVE runs: the timer
        // posts every clock on every wake, so demanding that a clock nothing
        // animates on be replayable forced a full render at the tick rate for
        // any page animating one clock (`RenderActivity.replayableClocks`).
        // The cursor tick here has nothing to advance, so the spinner's tick
        // is served by replay and the fallback render is not taken. (What the
        // replay writes is `RenderLoopReplayTests`' subject, not this one's.)
        #expect(runner.serveAnimationTicks(renderer: loop, cursorTimer: timer))
    }

    // MARK: - A served replay re-bases the sleep

    @Test("A served replay advances the clock by the frame's own next change")
    func servedReplayRebasesTheSleep() {
        let runner = freshRunner(SpinningProbeApp())
        let harness = Harness()
        let loop = harness.loop(SpinningProbeApp())
        let timer = CursorTimer(renderNotifier: AppState.shared)
        _ = loop.render(cursorTimer: timer)
        #expect(timer.sleepSeconds == AnimationClock.cursor.tickInterval, "the clock starts on its own grid")

        AppState.shared.setNeedsAnimationTick(.content)
        #expect(runner.serveAnimationTicks(renderer: loop, cursorTimer: timer))

        // The point of the rule: the sleep is now the run's cadence (a `.dots`
        // spinner's 0.110 s), not the clock's 0.05 s grid — without it the loop
        // re-wakes on the old grid and compares identical pictures.
        let expected = loop.timeUntilNextChange(elapsed: timer.elapsed)
        #expect(expected != AnimationClock.cursor.tickInterval, "the run must ask for its own rate")
        #expect(abs(timer.sleepSeconds - expected) < 1e-9, "\(timer.sleepSeconds) vs \(expected)")
    }

    @Test("Nothing ticked is served trivially, without touching the frame")
    func noTicksIsServed() {
        let runner = freshRunner(SpinningProbeApp())
        let harness = Harness()
        let loop = harness.loop(SpinningProbeApp())
        let timer = CursorTimer(renderNotifier: AppState.shared)
        _ = loop.render(cursorTimer: timer)

        #expect(runner.serveAnimationTicks(renderer: loop, cursorTimer: timer))
        #expect(timer.sleepSeconds == AnimationClock.cursor.tickInterval, "no tick, no re-base")
    }
}
