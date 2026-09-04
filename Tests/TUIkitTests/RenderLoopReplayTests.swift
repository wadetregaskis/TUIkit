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

        #expect(loop.timeUntilNextChange(elapsed: { _ in 0 }) == AnimationClock.cursor.tickInterval)
    }

    /// The point of asking the runs: a 0.11 s spinner is not resampled onto the
    /// 0.05 s grid, and the loop wakes when the run itself next changes.
    @Test("A run's own frame duration sets the sleep, not the clock's interval")
    func runsSetTheSleep() {
        let harness = RenderLoopHarness()
        let loop = primedLoop(harness, runs: [blink(clock: .content, frameDuration: 0.11)])

        let sleep = loop.timeUntilNextChange(elapsed: { _ in 0 })
        #expect(abs(sleep - 0.11) < 1e-9, "woke at the run's own rate, not the grid's: \(sleep)")
        #expect(sleep > AnimationClock.cursor.tickInterval, "and not on the clock's interval")
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
            loop.timeUntilNextChange(elapsed: { _ in 0 }) == AnimationClock.cursor.tickInterval,
            "a one-second run does not license a one-second sleep here")
    }
}
