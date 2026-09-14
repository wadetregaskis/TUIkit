//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoopReplayTests.swift
//
//  The animation-replay half of the run loop, driven through `RenderLoop`
//  itself rather than through the pieces it composes. `AnimationReplayTests`,
//  `ReplayCursorCompensationTests` and `CellSpanDiffTests` each cover one of
//  those pieces with test-built arguments; nothing called
//  `replayAnimations(elapsed:)` or `timeUntilNextChange(elapsed:)`, so the
//  decisions those two own alone — which runs are due, which tick lands on the
//  picture already showing, and how long the loop may sleep — were unasserted
//  while four regressions shipped in that file.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A still page: it animates nothing, so every frame it renders leaves no runs
/// and reads no phase. The runs under test are installed afterwards, which is
/// how a test gets an exactly-known frame to patch.
private struct StillProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
        }
    }
}

/// A page that builds its appearance from the pulse phase WHILE rendering, so
/// its frames report `usesPulse` and can never be replayed.
private struct PulseReaderApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            PulseReadingProbe()
        }
    }
}

private struct PulseReadingProbe: View, Renderable {
    var body: Never { fatalError("PulseReadingProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The read is the point: it goes through the volatile-read tracker, and
        // that is what `RenderActivity.usesPulse` is.
        FrameBuffer(text: context.environment.pulsePhase > 0.5 ? "bright" : "dim")
    }
}

/// A page leaving a 110 ms run under an app header leaving a 75 ms one, both on
/// ``AnimationClock/content``. Only a render advances the header's run, and the
/// loop has to know when it is due to render it.
private struct HeaderRunOverPageRunApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("p")
                .animatedCells([
                    AnimatedCellRun(
                        offsetX: 0, offsetY: 0, width: 1, frames: ["p", "q"],
                        frameDuration: 0.11, clock: .content)
                ])
                .appHeader {
                    Text("h").animatedCells([
                        AnimatedCellRun(
                            offsetX: 0, offsetY: 0, width: 1, frames: ["h", "i"],
                            frameDuration: 0.075, clock: .content)
                    ])
                }
        }
    }
}

@MainActor
@Suite("Animation replay: serving a tick by patching the frame on screen")
struct RenderLoopReplayTests {
    /// A two-frame blink on the given clock, one cell wide at the top-left.
    private func blink(clock: AnimationClock, frameDuration: Double = 0.1) -> AnimatedCellRun {
        AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["x", "y"],
            frameDuration: frameDuration, clock: clock)
    }

    /// A loop that has rendered once (so the diff writer knows what is on
    /// screen) with `runs` installed as the frame to patch.
    private func primedLoop(
        _ harness: RenderLoopHarness, runs: [AnimatedCellRun]
    ) -> RenderLoop<StillProbeApp> {
        let loop = harness.loop(StillProbeApp())
        _ = loop.render()
        loop.replayable = ReplayableFrame(
            contentLines: ["ab cd"], runs: runs,
            terminalWidth: 5, startRow: 1, backgroundCode: "")
        return loop
    }

    // MARK: - replayAnimations

    @Test("A due run is patched into the line and written")
    func patchesTheDueRun() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(harness, runs: [blink(clock: .cursor)])
        harness.terminal.reset()

        #expect(loop.replayAnimations(elapsed: [.cursor: 0]), "the tick was served")
        #expect(harness.terminal.allOutput.contains("x"), "frame 0 reached the terminal")
        #expect(
            !harness.terminal.allOutput.contains("y"),
            "and only frame 0: \(harness.terminal.allOutput.debugDescription)")
    }

    @Test("A tick on a clock the frame left no runs for is not served")
    func unservedClockNeedsARender() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(harness, runs: [blink(clock: .cursor)])
        harness.terminal.reset()

        #expect(
            !loop.replayAnimations(elapsed: [.content: 0]),
            "nothing on that clock animates, so the caller must render")
        #expect(harness.terminal.allOutput.isEmpty, "and nothing was written")
    }

    @Test("With no frame to patch there is nothing to replay")
    func noFrameNeedsARender() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(StillProbeApp())
        _ = loop.render()
        loop.replayable = nil
        harness.terminal.reset()

        #expect(!loop.replayAnimations(elapsed: [.cursor: 0]))
        #expect(harness.terminal.allOutput.isEmpty)
    }

    /// The saving `lastSteps` exists for: a blink spends most of its cycle on
    /// the same two pictures, so most ticks change nothing. The tick is still
    /// *served* — the caller must not render either — it just writes nothing.
    @Test("A tick that lands on the picture already showing writes nothing")
    func skipsATickThatChangesNothing() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(harness, runs: [blink(clock: .cursor)])
        harness.terminal.reset()

        #expect(loop.replayAnimations(elapsed: [.cursor: 0]))
        let afterFirst = harness.terminal.allOutput
        #expect(!afterFirst.isEmpty, "the first tick wrote the frame")

        // Half a frame duration later: same index, same picture.
        #expect(loop.replayAnimations(elapsed: [.cursor: 0.05]), "still served")
        #expect(
            harness.terminal.allOutput == afterFirst,
            "and nothing more was written: \(harness.terminal.allOutput.debugDescription)")
    }

    @Test("The next tick of the cycle writes the next frame")
    func advancesToTheNextFrame() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(harness, runs: [blink(clock: .cursor)])
        _ = loop.replayAnimations(elapsed: [.cursor: 0])
        harness.terminal.reset()

        #expect(loop.replayAnimations(elapsed: [.cursor: 0.1]))
        #expect(harness.terminal.allOutput.contains("y"), "frame 1 is on screen now")
    }

    /// Every patch starts from the RENDER's lines, never from the last patch —
    /// compositing leaves the replaced run's styling behind as an empty escape,
    /// so feeding a patched line back in grows the row on every tick. The
    /// pristine base is what keeps that bounded, and it is invisible unless a
    /// test looks at what the frame kept.
    @Test("The frame kept for patching stays the render's own lines")
    func patchesFromThePristineLine() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(harness, runs: [blink(clock: .cursor)])

        _ = loop.replayAnimations(elapsed: [.cursor: 0])
        _ = loop.replayAnimations(elapsed: [.cursor: 0.1])

        #expect(
            loop.replayable?.contentLines == ["ab cd"],
            "the base never becomes a patched line: \(loop.replayable?.contentLines ?? [])")
    }

    // MARK: - timeUntilNextChange

    @Test("With no runs the loop sleeps the clock's own interval")
    func noRunsSleepsTheInterval() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(harness, runs: [])

        #expect(loop.timeUntilNextChange(elapsed: { _ in 0 }) == AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks))
    }

    /// The point of asking the runs: a 0.11 s spinner is not resampled onto the
    /// 0.05 s grid, and the loop wakes when the run itself next changes.
    @Test("A run's own frame duration sets the sleep, not the clock's interval")
    func runsSetTheSleep() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(harness, runs: [blink(clock: .content, frameDuration: 0.11)])

        let sleep = loop.timeUntilNextChange(elapsed: { _ in 0 })
        #expect(abs(sleep - 0.11) < 1e-9, "woke at the run's own rate, not the grid's: \(sleep)")
        #expect(sleep > AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks), "and not on the clock's interval")
    }

    @Test("Several runs wake the loop at the soonest of them")
    func soonestRunWins() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(
            harness,
            runs: [
                blink(clock: .content, frameDuration: 0.5),
                blink(clock: .content, frameDuration: 0.11),
            ])

        let sleep = loop.timeUntilNextChange(elapsed: { _ in 0 })
        #expect(abs(sleep - 0.11) < 1e-9, "the sooner run set it: \(sleep)")
    }

    /// A frame where some view built its appearance from the phase as it
    /// rendered cannot say when it would next look different — only that view
    /// knows — so it keeps the clock's interval however slow its runs are.
    @Test("A frame that read the phase while rendering keeps the clock's interval")
    func phaseReaderKeepsTheInterval() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(PulseReaderApp())
        _ = loop.render()
        #expect(loop.lastActivity.usesPulse, "the probe's read was tracked")

        loop.replayable = ReplayableFrame(
            contentLines: ["ab cd"], runs: [blink(clock: .content, frameDuration: 1)],
            terminalWidth: 5, startRow: 1, backgroundCode: "")

        #expect(
            loop.timeUntilNextChange(elapsed: { _ in 0 }) == AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks),
            "a one-second run does not license a one-second sleep here")
    }

    /// A frame with a reader is re-rendered at the cursor clock's next 50 ms
    /// boundary: the lattice every 50 ms run on that clock steps on, and the one the
    /// reader's own blink or breath is defined on. Planning 50 ms from the wake put
    /// every render one wake's lateness past its boundary, and off the lattice the
    /// page's other wakes land on.
    ///
    /// The page's runs do not join the plan while a reader is present: every wake
    /// renders, and a render serves them.
    @Test("A frame that read the phase plans to the cursor clock's next 50 ms boundary")
    func readerPlansToTheCursorLattice() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(PulseReaderApp())
        _ = loop.render()
        #expect(loop.lastActivity.usesPulse, "the probe's read was tracked")
        // A page run that changes 11 ms from now, sooner than the reader's boundary.
        loop.replayable = ReplayableFrame(
            contentLines: ["ab cd"], runs: [blink(clock: .content, frameDuration: 0.1)],
            terminalWidth: 5, startRow: 1, backgroundCode: "")

        let sleep = loop.timeUntilNextChange(elapsed: { $0 == .cursor ? 0.137 : 5.089 })

        #expect(
            AnimationClock.nanoseconds(sleep) == 13_000_000,
            "0.137 s on the cursor clock is 13 ms from its 0.150 s boundary: \(sleep)")
    }

    /// A run in the app header is advanced only by a render, so the loop has to wake
    /// when it changes, beside whatever the page's runs ask for.
    @Test("A run in the app header plans at its own next change, and a sooner page run still wins")
    func chromeRunPlansAtItsOwnChange() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(HeaderRunOverPageRunApp())
        _ = loop.render(frameNowNanos: 1_030_000_000)
        let headerRuns = harness.appHeader.contentBuffer?.animatedCells ?? []
        let pageRuns = loop.replayable?.runs ?? []
        #expect(!headerRuns.isEmpty, "pre-condition: the header must leave a run")
        #expect(!pageRuns.isEmpty, "pre-condition: the page must leave a run")

        // At 1.030 s the header's 75 ms run ends at 1.050 s, the page's 110 ms one at 1.100 s.
        let beforeHeader = loop.timeUntilNextChange(elapsed: { _ in 1.030 })
        #expect(
            AnimationClock.nanoseconds(beforeHeader) == 20_000_000,
            "the header is due at 1.050 s: \(beforeHeader)")
        // At 1.095 s the page's run ends at 1.100 s, the header's at 1.125 s.
        let beforePage = loop.timeUntilNextChange(elapsed: { _ in 1.095 })
        #expect(
            AnimationClock.nanoseconds(beforePage) == 5_000_000,
            "the page is due at 1.100 s: \(beforePage)")
    }

    // MARK: - Which ticked clocks a frame owes a picture to

    /// `CursorTimer` posts EVERY clock on every wake, so a frame whose only
    /// animation is the caret is asked about `.content` too. The rule that
    /// decides is `replayableClocks(among:)`; it used to be spelled inside
    /// `AppRunner.serveAnimationTicks` as "every ticked clock must be
    /// replayable", which this frame fails — and failing it meant a full walk
    /// of the view tree, twenty times a second, to blink one cell.
    @Test("A frame animating one clock is still served when both clocks tick")
    func oneClockFrameStillReplays() {
        let ticked = Set(AnimationClock.allCases)
        let caretOnly = RenderActivity(
            usesPulse: false, usesCursor: false, animatedClocks: [.cursor])

        let replayable = caretOnly.replayableClocks(among: ticked)

        #expect(replayable == [.cursor], "the clock with runs, and only it")
        #expect(replayable.count != ticked.count, "the old rule's test, which it fails")
    }

    @Test("A frame that read a phase owes a render on every clock")
    func phaseReaderReplaysNothing() {
        let ticked = Set(AnimationClock.allCases)
        let reader = RenderActivity(
            usesPulse: true, usesCursor: false, animatedClocks: [.cursor, .content])

        #expect(reader.replayableClocks(among: ticked).isEmpty)
    }

    @Test("A frame with no runs at all owes a render too")
    func stillFrameReplaysNothing() {
        let still = RenderActivity(usesPulse: false, usesCursor: false, animatedClocks: [])

        #expect(still.replayableClocks(among: Set(AnimationClock.allCases)).isEmpty)
    }
}
