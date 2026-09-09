//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CursorBlinkRegularityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A blink is on for as long as it is off, every time, at every speed.
///
/// It was not. The blink was defined in milliseconds and drawn on a 50 ms tick
/// grid, so a half-cycle boundary falling part-way through a tick was delivered
/// at whichever tick edge was nearer — and which edge that was changed from cycle
/// to cycle. At `.regular` (a 660 ms cycle, so a 6.6-tick half) the on/off runs
/// came out 350, 350, 300, 350, 300, 350, 350, 300 … ms: a period wobbling
/// between 600 and 700 ms. `.slow` and `.fast` were whole multiples of the tick
/// and looked fine, which is what made it read as one speed being broken rather
/// than as a rule being wrong.
///
/// The pulse was always regular, for the same reason in reverse: 1200 / 800 /
/// 500 ms are all whole multiples of 50.
@MainActor
@Suite("A cursor blink's period is regular")
struct CursorBlinkRegularityTests {

    /// The lengths, in ticks, of the alternating visible/hidden runs the blink
    /// formula produces over `ticks` ticks — dropping the first and last, which
    /// are partial by construction.
    private func runLengths(speed: TextCursorStyle.Speed, ticks: Int = 400) -> [Int] {
        var runs: [Int] = []
        var current = CursorTimer.blinkVisible(atTick: 0, speed: speed)
        var length = 0
        for tick in 0..<ticks {
            let visible = CursorTimer.blinkVisible(atTick: tick, speed: speed)
            if visible == current {
                length += 1
            } else {
                runs.append(length)
                current = visible
                length = 1
            }
        }
        return Array(runs.dropFirst())
    }

    @Test(
        "Every run is the same length, at every speed",
        arguments: [TextCursorStyle.Speed.slow, .regular, .fast])
    func runsAreUniform(speed: TextCursorStyle.Speed) {
        let runs = runLengths(speed: speed)
        #expect(runs.count > 20, "enough cycles to see a wobble: \(runs.count)")
        #expect(Set(runs).count == 1, "\(speed) runs: \(Array(runs.prefix(12)))")
    }

    @Test(
        "A run is half the cycle, and the two halves are the whole cycle",
        arguments: [TextCursorStyle.Speed.slow, .regular, .fast])
    func halvesMakeTheCycle(speed: TextCursorStyle.Speed) {
        let half = CursorTimer.blinkHalfTicks(for: speed)
        #expect(runLengths(speed: speed).first == half, "a run is a half-cycle")
        // The pre-rendered run's length has to BE the period, or a replayed
        // cursor and a live-rendered one drift apart — a 13-frame run for a
        // 660 ms cycle replayed 650 ms while the formula ran 660.
        #expect(
            CursorTimer.cycleTicks(for: speed, animation: .blink) == 2 * half,
            "the pre-rendered cycle is exactly both halves")
    }

    /// The declared cycles are already on the grid, so the rounding in
    /// ``CursorTimer/blinkHalfTicks(for:)`` is a guard rather than a correction —
    /// and this is what says so, for anyone changing one of the three numbers.
    @Test(
        "The declared cycle is the delivered cycle",
        arguments: [TextCursorStyle.Speed.slow, .regular, .fast])
    func declaredCycleIsDelivered(speed: TextCursorStyle.Speed) {
        let tickMs = Int(AnimationClock.cursor.tickInterval * 1000)
        #expect(
            CursorTimer.cycleTicks(for: speed, animation: .blink) * tickMs
                == speed.blinkCycleMs,
            "\(speed): \(speed.blinkCycleMs)ms declared")
    }

    /// The pulse's cycles are on the grid too. Stated here rather than assumed,
    /// because it is the only reason the breath never showed this defect.
    @Test(
        "Every pulse cycle is a whole number of ticks",
        arguments: [TextCursorStyle.Speed.slow, .regular, .fast])
    func pulseCyclesAreWholeTicks(speed: TextCursorStyle.Speed) {
        let tickMs = Int(AnimationClock.cursor.tickInterval * 1000)
        #expect(speed.pulseCycleMs.isMultiple(of: tickMs), "\(speed): \(speed.pulseCycleMs)ms")
    }
}
