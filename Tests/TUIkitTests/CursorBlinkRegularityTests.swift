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
    /// `nonisolated`: `@Test(arguments:)` reads it from outside the main actor.
    nonisolated static let speeds: [TextCursorStyle.Speed] = [.slow, .regular, .fast]

    /// 100,000 s of uptime, on the 50 ms lattice, so the focus clock's zero is here.
    private let base: UInt64 = 100_000 * 1_000_000_000

    /// The focus emphasis's cycle for a focused element under `animation` at `speed`.
    private func emphasisCycle(
        _ animation: TextCursorStyle.Animation, _ speed: TextCursorStyle.Speed
    ) -> SelectionEmphasisCycle {
        var environment = EnvironmentValues()
        environment.selectionIndicatorStyle = SelectionIndicatorStyle(animation: animation, speed: speed)
        return environment.selectionEmphasis.cycle(true)
    }

    /// A focused blink's run, showing "on " while the emphasis is bright and "off"
    /// while it is dim.
    private func emphasisBlinkRun(_ speed: TextCursorStyle.Speed) throws -> AnimatedCellRun {
        try #require(emphasisCycle(.blink, speed).run(offsetX: 0, offsetY: 0) { $0.blinkOn ? "on " : "off" })
    }

    /// The caret's blink cycle at `speed`.
    private func caretCycle(_ speed: TextCursorStyle.Speed) -> TextFieldContentRenderer.CursorCycle {
        TextFieldContentRenderer.computeCursorCycle(
            baseColor: .red, over: .black, animation: .blink, speed: speed, cursorTimer: nil)
    }

    /// The caret's blink as the run a text field builds from it, showing "on " while
    /// the caret is visible and "off" while it is not.
    private func caretBlinkRun(_ speed: TextCursorStyle.Speed) -> AnimatedCellRun {
        let cycle = caretCycle(speed)
        return AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 3, frames: cycle.states.map { $0.visible ? "on " : "off" },
            frameDuration: cycle.timing.frameDuration, clock: cycle.timing.clock)
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

    /// Visible first, then hidden, then visible, each for half the cycle.
    private func expectRegularBlink(
        _ run: AnimatedCellRun, _ speed: TextCursorStyle.Speed,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let half = Int64(speed.blinkCycleMs) * 1_000_000 / 2
        let seen = holds(of: run)
        #expect(
            seen.allSatisfy { $0.nanos == half },
            "\(speed): holds of \(seen.prefix(8).map(\.nanos)) ns", sourceLocation: sourceLocation)
        #expect(
            seen.map(\.shows) == seen.indices.map { $0.isMultiple(of: 2) ? "on " : "off" },
            "\(speed): \(seen.prefix(8).map(\.shows))", sourceLocation: sourceLocation)
    }

    @Test("A focus blink holds visible and hidden for exactly half its cycle, at every speed", arguments: speeds)
    func emphasisBlinkIsRegular(_ speed: TextCursorStyle.Speed) throws {
        expectRegularBlink(try emphasisBlinkRun(speed), speed)
    }

    @Test("A caret blink holds visible and hidden for exactly half its cycle, at every speed", arguments: speeds)
    func caretBlinkIsRegular(_ speed: TextCursorStyle.Speed) {
        expectRegularBlink(caretBlinkRun(speed), speed)
    }

    /// A field that re-renders mid-blink draws what the live reader says, and the loop
    /// replays the run between renders. If the two disagree about when a half ends,
    /// the caret steps.
    @Test("A render that reads the blink sees what the replayed run shows, at every instant", arguments: speeds)
    func liveBlinkMatchesTheRun(_ speed: TextCursorStyle.Speed) throws {
        let run = try emphasisBlinkRun(speed)
        let timer = CursorTimer(renderNotifier: AppState())
        timer.observe(nowNanos: base)
        var disagreements: [Int] = []
        for milliseconds in stride(from: 0, to: 3_000, by: 7) {
            timer.observe(nowNanos: base + UInt64(milliseconds) * 1_000_000)
            let replayed = run.frame(atElapsed: timer.elapsed(for: .cursor)) == "on "
            if timer.blinkVisible(for: speed) != replayed { disagreements.append(milliseconds) }
        }
        #expect(disagreements.isEmpty, "\(speed): the live blink and the run disagree at \(disagreements) ms")
    }

    @Test("A focus breath lasts exactly its cycle, one 50 ms frame at a time, at every speed", arguments: speeds)
    func breathLastsItsCycle(_ speed: TextCursorStyle.Speed) throws {
        let cycle = emphasisCycle(.pulse, speed)
        let run = try #require(cycle.run(offsetX: 0, offsetY: 0) { "\($0.phase)" })
        #expect(AnimationClock.nanoseconds(run.cycleDuration) == Int64(speed.pulseCycleMs) * 1_000_000)
        #expect(AnimationClock.nanoseconds(run.frameDuration) == 50_000_000)
    }

    @Test("A render that reads the breath sees the phase the replayed run shows, at every instant", arguments: speeds)
    func liveBreathMatchesTheRun(_ speed: TextCursorStyle.Speed) throws {
        let cycle = emphasisCycle(.pulse, speed)
        let run = try #require(cycle.run(offsetX: 0, offsetY: 0) { "\($0.phase)" })
        let timer = CursorTimer(renderNotifier: AppState())
        timer.observe(nowNanos: base)
        var disagreements: [Int] = []
        for milliseconds in stride(from: 0, to: 3_000, by: 7) {
            timer.observe(nowNanos: base + UInt64(milliseconds) * 1_000_000)
            let replayed = cycle.frames[run.index(atElapsed: timer.elapsed(for: .cursor))].phase
            if timer.pulsePhase(for: speed) != replayed { disagreements.append(milliseconds) }
        }
        #expect(disagreements.isEmpty, "\(speed): the live breath and the run disagree at \(disagreements) ms")
    }

    /// The layout itself, which the holds above do not depend on: a blink is a
    /// discrete sequence of two frames that each last half the cycle, and a breath
    /// is a ramp sampled one cursor tick a frame.
    @Test("A blink is two frames of half its cycle, and a breath is sampled one cursor tick a frame", arguments: speeds)
    func cyclesAreLaidOutByKind(_ speed: TextCursorStyle.Speed) {
        let half = Int64(speed.blinkCycleMs) * 1_000_000 / 2
        let blink = emphasisCycle(.blink, speed)
        #expect(blink.frames.count == 2)
        #expect(AnimationClock.nanoseconds(blink.frameDuration) == half)
        let caret = caretCycle(speed)
        #expect(caret.states.count == 2)
        #expect(AnimationClock.nanoseconds(caret.timing.frameDuration) == half)
        let breath = emphasisCycle(.pulse, speed)
        #expect(breath.frames.count == speed.pulseCycleMs / 50)
        #expect(AnimationClock.nanoseconds(breath.frameDuration) == 50_000_000)
    }
}
