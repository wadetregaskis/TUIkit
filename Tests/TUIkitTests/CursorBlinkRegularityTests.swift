//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CursorBlinkRegularityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A blink is on for as long as it is off, every time, at every speed, and a breath
/// lasts exactly its cycle. Measured in wall-clock time, on the runs the loop
/// replays.
///
/// It was not always regular. The blink was defined in milliseconds and drawn on a
/// 50 ms tick grid, so a half-cycle boundary falling part-way through a tick was
/// delivered at whichever tick edge was nearer, and which edge that was changed from
/// cycle to cycle. At a 660 ms cycle the on/off runs came out 350, 350, 300, 350,
/// 300, 350, 350, 300 … ms: a period wobbling between 600 and 700 ms.
///
/// These tests used to count ticks. They now ask a run how long each thing it shows
/// is held, through `AnimatedCellRun.timeUntilChange(afterElapsed:)`, the answer the
/// run loop sleeps on, and how long its cycle is. So they state what is seen, and
/// hold whatever a cycle is made of: fourteen 50 ms frames or two 350 ms ones.
@MainActor
@Suite("A cursor blink's period is regular")
struct CursorBlinkRegularityTests {
    /// The speeds under test, for the focus emphasis and the caret alike: the
    /// default, the presets, and two rates whose frames are not whole cursor ticks.
    ///
    /// `nonisolated`: `@Test(arguments:)` reads it from outside the main actor.
    nonisolated static let speeds: [IndicatorAnimationSpeed] = [
        .automatic, .halfSpeed, .doubleSpeed, 1.5, 3,
    ]

    /// 100,000 s of uptime, on the 50 ms lattice, so the focus clock's zero is here.
    private let base: UInt64 = 100_000 * 1_000_000_000

    /// An environment whose focus emphasis animates with `animation` at `speed`.
    private func emphasisEnvironment(
        _ animation: TextCursorStyle.Animation, _ speed: IndicatorAnimationSpeed
    ) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.selectionIndicatorStyle = animation
        environment.indicatorAnimationSpeeds.set(speed, for: .focusEmphasis)
        return environment
    }

    /// The focus emphasis's cycle for a focused element under `animation` at `speed`.
    private func emphasisCycle(
        _ animation: TextCursorStyle.Animation, _ speed: IndicatorAnimationSpeed
    ) -> SelectionEmphasisCycle {
        emphasisEnvironment(animation, speed).selectionEmphasis.cycle(true)
    }

    /// A focused blink's run, showing "on " while the emphasis is bright and "off"
    /// while it is dim.
    private func emphasisBlinkRun(_ speed: IndicatorAnimationSpeed) throws -> AnimatedCellRun {
        try #require(emphasisCycle(.blink, speed).run(offsetX: 0, offsetY: 0) { $0.blinkOn ? "on " : "off" })
    }

    /// The caret's blink cycle at `speed`.
    private func caretCycle(_ speed: IndicatorAnimationSpeed) -> TextFieldContentRenderer.CursorCycle {
        TextFieldContentRenderer.computeCursorCycle(
            baseColor: .red, over: .black, animation: .blink, speed: speed, cursorTimer: nil)
    }

    /// The caret's blink as the run a text field builds from it, showing "on " while
    /// the caret is visible and "off" while it is not.
    private func caretBlinkRun(_ speed: IndicatorAnimationSpeed) -> AnimatedCellRun {
        let cycle = caretCycle(speed)
        return AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 3, frames: cycle.states.map { $0.visible ? "on " : "off" },
            frameTicks: cycle.timing.frameTicks, clock: cycle.timing.clock)
    }

    /// A blink's standard half, 21 ticks (350 ms), at `speed`'s rate, as the nearest
    /// whole number of ticks: 11 ticks at twice the speed, 14 at 1.5. Every speed under
    /// test is exact but the default, whose 21 ticks are already divisible by 3, so its
    /// tolerance moves nothing.
    private func halfTicks(_ speed: IndicatorAnimationSpeed) -> Int {
        Int((21 / speed.rate).rounded())
    }

    /// The same half in nanoseconds, the unit a run's holds are measured in.
    private func halfNanos(_ speed: IndicatorAnimationSpeed) -> Int64 {
        AnimationClock.nanoseconds(AnimationClock.seconds(forTicks: halfTicks(speed)))
    }

    /// The first `count` things `run` shows from the start of its cycle, and how
    /// long it holds each, in nanoseconds.
    private func holds(of run: AnimatedCellRun, count: Int = 24) -> [(shows: String, nanos: Int64)] {
        var elapsed: Int64 = 0
        var holds: [(shows: String, nanos: Int64)] = []
        for _ in 0..<count {
            let seconds = Double(elapsed) / 1_000_000_000
            let hold = AnimationClock.nanoseconds(run.timeUntilChange(afterElapsed: seconds))
            holds.append((run.frame(atElapsed: seconds), hold))
            elapsed += hold
        }
        return holds
    }

    /// Visible first, then hidden, then visible, each for `half` nanoseconds.
    private func expectRegularBlink(
        _ run: AnimatedCellRun, half: Int64, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let seen = holds(of: run)
        #expect(
            seen.allSatisfy { $0.nanos == half },
            "\(label): holds of \(seen.prefix(8).map(\.nanos)) ns", sourceLocation: sourceLocation)
        #expect(
            seen.map(\.shows) == seen.indices.map { $0.isMultiple(of: 2) ? "on " : "off" },
            "\(label): \(seen.prefix(8).map(\.shows))", sourceLocation: sourceLocation)
    }

    @Test(
        "A focus blink holds visible and hidden for exactly half its cycle, at every speed",
        arguments: speeds)
    func emphasisBlinkIsRegular(_ speed: IndicatorAnimationSpeed) throws {
        expectRegularBlink(try emphasisBlinkRun(speed), half: halfNanos(speed), "\(speed)")
    }

    @Test("A caret blink holds visible and hidden for exactly half its cycle, at every speed", arguments: speeds)
    func caretBlinkIsRegular(_ speed: IndicatorAnimationSpeed) {
        expectRegularBlink(caretBlinkRun(speed), half: halfNanos(speed), "\(speed)")
    }

    /// A control that re-renders mid-blink draws what the live reader says, and the
    /// loop replays the run between renders. If the two disagree about when a half
    /// ends, the emphasis steps.
    @Test("A render that reads the blink sees what the replayed run shows, at every instant", arguments: speeds)
    func liveBlinkMatchesTheRun(_ speed: IndicatorAnimationSpeed) throws {
        let run = try emphasisBlinkRun(speed)
        let timer = CursorTimer(renderNotifier: AppState())
        var environment = emphasisEnvironment(.blink, speed)
        environment.cursorTimer = timer
        timer.observe(nowNanos: base)
        var disagreements: [Int] = []
        for milliseconds in stride(from: 0, to: 3_000, by: 7) {
            timer.observe(nowNanos: base + UInt64(milliseconds) * 1_000_000)
            let replayed = run.frame(atElapsed: timer.elapsed(for: .cursor)) == "on "
            let live = SelectionIndicator.resolve(isFocused: true, environment: environment).blinkOn
            if live != replayed { disagreements.append(milliseconds) }
        }
        #expect(disagreements.isEmpty, "\(speed): the live blink and the run disagree at \(disagreements) ms")
    }

    /// 0.8 s at the speed's rate, in frames of one 3-tick (50 ms) cursor step each: as
    /// many as come nearest to the cycle, so the cycle is a whole number of those
    /// frames.
    @Test("A focus breath is the whole number of 3-tick frames nearest its cycle, at every speed", arguments: speeds)
    func breathLastsItsCycle(_ speed: IndicatorAnimationSpeed) throws {
        let cycle = emphasisCycle(.pulse, speed)
        let run = try #require(cycle.run(offsetX: 0, offsetY: 0) { "\($0.phase)" })
        let count = max(2, Int((0.8 / speed.rate * 20).rounded()))
        #expect(run.frames.count == count)
        #expect(run.frameTicks == 3)
    }

    @Test("A render that reads the breath sees the phase the replayed run shows, at every instant", arguments: speeds)
    func liveBreathMatchesTheRun(_ speed: IndicatorAnimationSpeed) throws {
        let cycle = emphasisCycle(.pulse, speed)
        let run = try #require(cycle.run(offsetX: 0, offsetY: 0) { "\($0.phase)" })
        let timer = CursorTimer(renderNotifier: AppState())
        var environment = emphasisEnvironment(.pulse, speed)
        environment.cursorTimer = timer
        timer.observe(nowNanos: base)
        var disagreements: [Int] = []
        for milliseconds in stride(from: 0, to: 3_000, by: 7) {
            timer.observe(nowNanos: base + UInt64(milliseconds) * 1_000_000)
            let replayed = cycle.frames[run.index(atElapsed: timer.elapsed(for: .cursor))].phase
            let live = SelectionIndicator.resolve(isFocused: true, environment: environment).phase
            if live != replayed { disagreements.append(milliseconds) }
        }
        #expect(disagreements.isEmpty, "\(speed): the live breath and the run disagree at \(disagreements) ms")
    }

    /// The layout itself, which the holds above do not depend on: a blink is a
    /// discrete sequence of two frames that each last half the cycle, and a breath
    /// is a ramp sampled one cursor tick a frame.
    @Test("A focus blink is two frames of half its cycle, and a breath is sampled one cursor tick a frame")
    func emphasisCyclesAreLaidOutByKind() {
        let blink = emphasisCycle(.blink, .automatic)
        #expect(blink.frames.count == 2)
        #expect(blink.frameTicks == 21)
        let breath = emphasisCycle(.pulse, .automatic)
        #expect(breath.frames.count == 16)
        #expect(breath.frameTicks == 3)
    }

    @Test("A caret blink is two frames of half its cycle", arguments: speeds)
    func caretCycleIsLaidOutByKind(_ speed: IndicatorAnimationSpeed) {
        let caret = caretCycle(speed)
        #expect(caret.states.count == 2)
        #expect(caret.timing.frameTicks == halfTicks(speed))
    }
}
