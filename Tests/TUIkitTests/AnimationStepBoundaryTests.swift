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
/// seconds, which the loop raises to its 10 ms floor, so a steady 350 ms blink turned
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
            frameDuration: 0.05, clock: .cursor)
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
            frameDuration: 0.05, clock: .cursor)
        let atOff = blink.timeUntilChange(afterElapsed: summed(0.05, 7))
        #expect(abs(atOff - 0.35) < 1e-9, "at the off flip: \(atOff) s")
        let atOn = blink.timeUntilChange(afterElapsed: summed(0.05, 14))
        #expect(abs(atOn - 0.35) < 1e-9, "at the on flip: \(atOn) s")
    }

    /// A spinner draws its current frame itself AND leaves a run the loop replays, so
    /// both must pick the same step. `.dots` at 0.11 s: when the clock was a sum of
    /// sleeps it landed one ulp under its boundary at every step from 27 to 40, and a
    /// floor in seconds drew the frame before the one the run replays there — a
    /// one-frame stutter on every render that fell on such a wake. The clock is measured
    /// now, so its seconds are a nanosecond count divided by 1e9, a day and more into
    /// the process: no more the decimal they spell than the sum was.
    @Test("A spinner draws the frame its run replays at every step, deep into the clock")
    func spinnerDrawsTheFrameItsRunReplays() {
        let timer = CursorTimer(renderNotifier: AppState())
        let style = SpinnerStyle.dots
        // 110,000 s: a whole million 110 ms steps, so step `k` from here shows frame `k`.
        let base: UInt64 = 110_000 * 1_000_000_000
        var wrong: [(step: Int, drawn: String, replayed: String, due: String)] = []
        for step in 0..<60 {
            timer.creditWake(atNanos: base + UInt64(step) * 110_000_000)
            var context = RenderContext(
                availableWidth: 10, availableHeight: 1, tuiContext: TUIContext()
            ).isolatingRenderCache()
            context.environment.cursorTimer = timer
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
}
