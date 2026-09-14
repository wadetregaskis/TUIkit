//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationStepBoundaryTests.swift
//
//  Which frame a run shows, and when it next changes, at the instants the clock
//  actually reaches — binary doubles, not the decimals they spell.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// An animation clock used to count elapsed time by ADDING what it slept, so the
/// instant that should be exactly 0.35 s was `0.05` added seven times — and in binary
/// that is one ulp under the boundary. (It is measured now; the conversions below still
/// have to be exact for any double they are handed.) `floor(0.35 / 0.05)` is 6, not 7; a clock summed from
/// 0.05 s steps floors one step short at every step from 6 to 12.
///
/// A flip due on that wake did not happen. `timeUntilChange` then answered ~5.6e-17
/// seconds, which the loop raised to its then 10 ms floor, so a steady 350 ms blink turned
/// into plans alternating 0.35 → 0.01 → 0.34 s. Together with the timer sleeping on the
/// PREVIOUS wake's plan that became the owner's "complex period": holds of ~370, ~700
/// and ~45 ms, repeating every ~1.1 s.
@MainActor
@Suite("An animation step lands on its boundary")
struct AnimationStepBoundaryTests {

    /// `seconds` added `count` times, the way a clock that sleeps and credits reaches it.
    private func summed(_ seconds: Double, _ count: Int) -> Double {
        var elapsed = 0.0
        for _ in 0..<count { elapsed += seconds }
        return elapsed
    }

    /// Forty distinct frames, so an index is visible in the frame it selects.
    private func countingRun() -> AnimatedCellRun {
        AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 2,
            frames: (0..<40).map { $0 < 10 ? "0\($0)" : "\($0)" },
            frameTicks: 3, clock: .cursor)
    }

    @Test("Every step of a summed clock selects its own frame")
    func summedStepsSelectTheirOwnFrame() {
        let run = countingRun()
        var wrong: [(step: Int, shown: Int)] = []
        for step in 0..<40 {
            let shown = run.index(atElapsed: summed(0.05, step))
            if shown != step { wrong.append((step, shown)) }
        }
        #expect(wrong.isEmpty, "steps that showed the frame before their own: \(wrong)")
    }

    /// The decimal literal is no better than the sum: `0.35 / 0.05` is 6.999…
    @Test("The literal boundary selects its own frame too")
    func literalBoundary() {
        #expect(countingRun().index(atElapsed: 0.35) == 7)
        #expect(countingRun().index(atElapsed: 0.7) == 14)
    }

    /// A `.regular` blink: seven frames on, seven off, 50 ms each.
    ///
    /// At the moment the off half begins, the picture holds for the whole half. The
    /// floor-short step answered that the change was ~1e-17 s away — raised to a 10 ms
    /// re-wake, which is the flicker.
    @Test("At a blink's flip the next change is a whole half away")
    func flipWaitsAWholeHalf() {
        let blink = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1,
            frames: Array(repeating: "█", count: 7) + Array(repeating: " ", count: 7),
            frameTicks: 3, clock: .cursor)
        let atOff = blink.timeUntilChange(afterElapsed: summed(0.05, 7))
        #expect(abs(atOff - 0.35) < 1e-9, "at the off flip: \(atOff) s")
        let atOn = blink.timeUntilChange(afterElapsed: summed(0.05, 14))
        #expect(abs(atOn - 0.35) < 1e-9, "at the on flip: \(atOn) s")
    }

    /// A spinner draws its current frame itself AND leaves a run the loop replays, so
    /// both must pick the same step. `.dots`, then at 0.11 s: when the clock was a sum of
    /// sleeps it landed one ulp under its boundary at every step from 27 to 40, and a
    /// floor in seconds drew the frame before the one the run replays there — a
    /// one-frame stutter on every render that fell on such a wake. The clock is measured
    /// now, so its seconds are a nanosecond count divided by 1e9, a day and more into
    /// the process: no more the decimal they spell than the sum was.
    @Test("A spinner draws the frame its run replays at every step, deep into the clock")
    func spinnerDrawsTheFrameItsRunReplays() {
        let timer = CursorTimer(renderNotifier: AppState())
        let style = SpinnerStyle.dots
        // A whole million 7-tick steps of 116,666,667 ns, so step `k` from here shows
        // frame `k`.
        let base: UInt64 = 116_666_667 * 1_000_000
        var wrong: [(step: Int, drawn: String, replayed: String, due: String)] = []
        for step in 0..<60 {
            // One instant for both, as the run loop gives a frame: the replay reads the
            // timer's snapshot, the spinner the frame's stamp.
            let now = base + UInt64(step) * 116_666_667
            timer.creditWake(atNanos: now)
            var context = RenderContext(
                availableWidth: 10, availableHeight: 1, tuiContext: TUIContext()
            ).isolatingRenderCache()
            context.environment.cursorTimer = timer
            context.environment.frameNowNanos = Int64(now)
            let buffer = renderToBuffer(Spinner(style: style), context: context)
            guard let run = buffer.animatedCells.first else {
                Issue.record("the spinner left no run at step \(step)")
                return
            }
            let drawn = buffer.lines.first?.stripped ?? ""
            let replayed = run.frames[run.index(atElapsed: timer.elapsed(for: .content))].stripped
            let due = style.frames[step % style.frames.count]
            if drawn != replayed || drawn != due {
                wrong.append((step, drawn, replayed, due))
            }
        }
        #expect(wrong.isEmpty, "steps whose drawn frame was not the replayed one: \(wrong)")
    }

    /// A run of forty distinct frames of `frameTicks` ticks on `clock`, so every step is
    /// a change and the loop has something to wake for at each.
    private func countingRun(frameTicks: Int, clock: AnimationClock) -> AnimatedCellRun {
        AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 2, frames: countingRun().frames,
            frameTicks: frameTicks, clock: clock)
    }

    /// What `RenderLoop.timeUntilNextChange(elapsed:)` answers for a frame holding only
    /// `runs`.
    private func planner(_ runs: [AnimatedCellRun]) -> ((AnimationClock) -> Double) -> Double {
        { elapsed in
            runs.map { $0.timeUntilChange(afterElapsed: elapsed($0.clock)) }.min()
                ?? AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks)
        }
    }

    /// A step begins when a tick begins: step `s` of an `n`-tick run is tick `s·n`.
    ///
    /// It used to last its frame's length rounded to whole nanoseconds, and a rounded
    /// frame drifts off the tick it was meant to be: 2 ticks rounded to 33,333,333 ns, so
    /// at 1.037 s, in step 31, the step ended at 1,066,666,656, 11 ns before tick 64
    /// begins at 1,066,666,667.
    @Test("A 2-tick step showing at 1.037 s ends when tick 64 begins")
    func stepEndIsATickInstant() {
        #expect(AnimationClock.stepEndNanos(atElapsed: 1.037, frameTicks: 2) == AnimationClock.nanoseconds(atTick: 64))
        #expect(AnimationClock.nanoseconds(atTick: 64) == 1_066_666_667)
    }

    /// Deep into the clock, where a rounded frame had drifted furthest: a million steps of
    /// 116,666,667 ns end 333,333 ns after the tick that seven million ticks lead to.
    @Test("Step 1,000,000 of a 7-tick run ends when tick 7,000,007 begins")
    func deepStepEndIsATickInstant() {
        let inside = Double(AnimationClock.nanoseconds(atTick: 7_000_003)) / 1_000_000_000
        #expect(AnimationClock.step(atElapsed: inside, frameTicks: 7) == 1_000_000)
        #expect(
            AnimationClock.stepEndNanos(atElapsed: inside, frameTicks: 7)
                == AnimationClock.nanoseconds(atTick: 7_000_007))
    }

    /// Two runs whose frames are whole ticks change on the same tick wherever their
    /// multiples meet, so the timer wakes there once.
    ///
    /// With rounded frames they missed each other by nanoseconds: at tick 35, 583,333,334
    /// ns, the 5-tick run changed at 583,333,331 (seven steps of 83,333,333) and the
    /// 7-tick run at 583,333,335 (five of 116,666,667). The timer woke for the first, found
    /// the second 4 ns away, and slept its 10 ms floor: two wakes, and a 7-tick spinner
    /// drawn 10 ms late.
    @Test("A 7-tick and a 5-tick run change together when tick 35 begins, and the plan from there is a whole frame")
    func runsMeetingOnATickWakeOnce() {
        let runs = [countingRun(frameTicks: 7, clock: .content), countingRun(frameTicks: 5, clock: .content)]
        let timer = CursorTimer(renderNotifier: AppState())
        timer.planner = planner(runs)
        // Tick 33.
        var now: UInt64 = 550_000_000
        timer.creditWake(atNanos: now)
        now += CursorTimer.sleepNanoseconds(timer.sleepSeconds)
        #expect(now == 583_333_334, "the wake after tick 33 lands when tick 35 begins")
        #expect(runs.map { $0.index(atElapsed: Double(now) / 1_000_000_000) } == [5, 7], "both runs have changed")
        timer.creditWake(atNanos: now)
        #expect(
            CursorTimer.sleepNanoseconds(timer.sleepSeconds) == 83_333_333,
            "the next change is the 5-tick run's, when tick 40 begins at 666,666,667 ns")
    }

    /// A run on the cursor clock steps on tick instants too, because the focus epoch is
    /// floored to 3 ticks, 50,000,000 ns, the smallest number of ticks that is a whole
    /// number of nanoseconds: the epoch plus tick `j`'s instant is the instant of the
    /// epoch's tick plus `j`, exactly.
    ///
    /// With rounded frames a 2-tick bar's 24th step ended at 799,999,992 ns and a 21-tick
    /// blink, from an epoch of 100,000,000, at 800,000,000: the timer woke 8 ns before the
    /// blink's flip, and flipped it 10 ms late.
    @Test("A 2-tick content run and a 21-tick cursor run end their steps at the same instant, 800,000,000 ns")
    func contentAndCursorRunsMeetOnATick() {
        let bar = countingRun(frameTicks: 2, clock: .content)
        let blink = countingRun(frameTicks: 21, clock: .cursor)
        let timer = CursorTimer(renderNotifier: AppState())
        timer.planner = planner([bar, blink])
        // The focus epoch floors to 100,000,000.
        timer.observe(nowNanos: 120_000_000)
        var now: UInt64 = 785_000_000
        timer.creditWake(atNanos: now)
        now += CursorTimer.sleepNanoseconds(timer.sleepSeconds)
        #expect(now == 800_000_000, "tick 48 of the content clock, tick 42 of the cursor clock")
        #expect(bar.index(atElapsed: timer.elapsed(for: .content)) == 23, "before the wake, the bar is on step 23")
        timer.creditWake(atNanos: now)
        #expect(bar.index(atElapsed: timer.elapsed(for: .content)) == 24, "the bar changed at the wake")
        #expect(blink.index(atElapsed: timer.elapsed(for: .cursor)) == 2, "and the blink changed at the same wake")
        #expect(
            CursorTimer.sleepNanoseconds(timer.sleepSeconds) == 33_333_334,
            "the bar's next step begins with tick 50, at 833,333,334 ns")
    }
}
