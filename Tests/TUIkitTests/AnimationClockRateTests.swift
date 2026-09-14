//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationClockRateTests.swift
//
//  An animation clock keeps the time on the wall however late its wakes are. Driven
//  on a clock of the test's own, at the Example's Spinners page's mix of intervals,
//  without racing a real `Task.sleep`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("An animation clock keeps wall-clock time")
struct AnimationClockRateTests {

    /// The distinct `SpinnerStyle` intervals on the Spinners page, in milliseconds.
    private static let spinnerIntervals: [UInt64] = [80, 90, 100, 110, 120, 125, 130, 140, 150]

    /// 90,090 s of uptime: far past any real monotonic reading in a test process, so the
    /// timer keeps the test's own times, and a whole number of every interval above.
    private static let base: UInt64 = 90_090 * 1_000_000_000

    /// One run per interval, each frame different from the next, so every step is a change.
    private static func runs(intervals: [Double]) -> [AnimatedCellRun] {
        intervals.map {
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1, frames: ["0", "1", "2", "3"],
                frameDuration: $0, clock: .content)
        }
    }

    private static var spinnerRuns: [AnimatedCellRun] {
        runs(intervals: spinnerIntervals.map { Double($0) / 1000 })
    }

    /// What `RenderLoop.timeUntilNextChange(elapsed:)` answers for a frame holding only `runs`.
    private static func planner(_ runs: [AnimatedCellRun]) -> ((AnimationClock) -> Double) -> Double {
        { elapsed in
            runs.map { $0.timeUntilChange(afterElapsed: elapsed($0.clock)) }.min()
                ?? AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks)
        }
    }

    /// A wake that lands late loses nothing: the clock reads the time the wake happened.
    ///
    /// It used to add the sleep it had asked for. Every wake on the Spinners page is late
    /// by about 9 ms (a `Task.sleep` resumed on the main actor), the page wakes about 52
    /// times a second, and every spinner ran at 1 / 1.48 of its speed — in this scenario,
    /// about 507 steps a minute where 750 are due.
    @Test("Wakes 9.3 ms late for a minute: the runs still step at their own rates")
    func lateWakesKeepTheRate() {
        let timer = CursorTimer(renderNotifier: AppState())
        timer.planner = Self.planner(Self.spinnerRuns)
        let lateness: UInt64 = 9_300_000
        let end = Self.base + 60_000_000_000
        var now = Self.base
        timer.creditWake(atNanos: now)
        let started = timer.elapsed(for: .content)
        var wakes = 0
        while true {
            let next = now + CursorTimer.sleepNanoseconds(timer.sleepSeconds) + lateness
            guard next <= end else { break }
            now = next
            timer.creditWake(atNanos: now)
            wakes += 1
        }
        let finished = timer.elapsed(for: .content)
        func steps(_ milliseconds: UInt64) -> Int64 {
            let duration = Double(milliseconds) / 1000
            return AnimationClock.step(atElapsed: finished, frameDuration: duration)
                - AnimationClock.step(atElapsed: started, frameDuration: duration)
        }
        #expect(wakes > 1000, "the scenario must actually wake at the page's rate: \(wakes)")
        #expect(abs(steps(80) - 750) <= 1, "the 80 ms run stepped \(steps(80)) times in a minute")
        #expect(abs(steps(140) - 428) <= 1, "the 140 ms run stepped \(steps(140)) times in a minute")
    }

    /// Ctrl-Z, an external SIGSTOP, a long stall: the clock jumps, and the wake after it is
    /// one wake — no catch-up burst of the strides slept through.
    @Test("A wake after a 10 s gap plans no more than one cycle, and posts one tick per clock")
    func aLongGapIsOneWake() {
        let appState = AppState()
        let timer = CursorTimer(renderNotifier: appState)
        let runs = Self.spinnerRuns
        timer.planner = Self.planner(runs)
        timer.creditWake(atNanos: Self.base)
        _ = appState.consumePendingAnimationClocks()

        timer.creditWake(atNanos: Self.base + 10_037_000_000)

        let longestCycle = runs.map(\.cycleDuration).max() ?? 0
        #expect(timer.sleepSeconds <= longestCycle, "planned \(timer.sleepSeconds) s")
        #expect(appState.consumePendingAnimationClocks() == Set(AnimationClock.allCases))
        #expect(appState.consumePendingAnimationClocks().isEmpty, "one wake, one tick per clock")
    }

    /// A sleep asks for the nanoseconds it planned, rounded.
    ///
    /// Truncated, a plan that has been through `Double(n) / 1e9` comes back 1 ns short on
    /// about 2% of plans. A real wake is milliseconds late and hides it; a clock that
    /// advances by exactly the sleep wakes 1 ns before its boundary, finds the change still
    /// 1 ns away and plans the 10 ms floor. Whole-millisecond gaps never show it, so the mix
    /// includes an indeterminate bar's 1/30 s frames.
    @Test("A clock that advances by exactly what was slept lands on every boundary it planned")
    func exactSleepsLandOnTheirBoundaries() {
        let timer = CursorTimer(renderNotifier: AppState())
        let intervals = Self.spinnerIntervals.map { Double($0) / 1000 } + [1.0 / 30]
        timer.planner = Self.planner(Self.runs(intervals: intervals))
        let durations = intervals.map { UInt64(AnimationClock.nanoseconds($0)) }
        let floor = UInt64(AnimationClock.nanoseconds(AnimationClock.minimumFrameDuration))
        // Off every boundary, so the first plan is an odd length too.
        var now = Self.base + 7_000_001
        var ideal = now
        timer.creditWake(atNanos: now)
        var divergence: (wake: Int, now: UInt64, ideal: UInt64)?
        for wake in 0..<1000 {
            // The schedule in integers: the soonest boundary of any run, or the floor.
            ideal += max(floor, durations.map { $0 - ideal % $0 }.min() ?? floor)
            now += CursorTimer.sleepNanoseconds(timer.sleepSeconds)
            guard now == ideal else {
                divergence = (wake, now, ideal)
                break
            }
            timer.creditWake(atNanos: now)
        }
        #expect(divergence == nil, "woke off the planned boundary: \(String(describing: divergence))")
    }
}
