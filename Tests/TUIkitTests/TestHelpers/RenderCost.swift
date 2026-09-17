//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCost.swift
//
//  One measurement for every test in this target that bounds a cost.
//
//  Three suites had grown a private copy of the same helper — the fastest of
//  several batches, read on the per-thread CPU clock with the wall clock as the
//  fallback — and a fourth was still on the wall clock alone, which is the
//  defect `3fadcb1d` fixed in the first of them. A measurement that is worth
//  getting right is worth having once.
//
//  WHY CPU TIME. A wall clock counts the microseconds the scheduler spent
//  running something else. Under the parallel harness at `-j 12`, or on a CI
//  runner sharing a box, that turns a cost guard into a guard on the machine's
//  mood: `FrameBufferCombineScalingTests` read 36.3x and 57.6x against a bound
//  of 20 under load, and 8.7x alone. `threadCPUNanoseconds()` is the
//  framework's own answer — it exists because render budgets measured in wall
//  time failed on loaded runners with nothing changed — so this reuses it
//  rather than hand-rolling a second clock.
//
//  WHY THE MINIMUM. A ratio inflates from below as readily as from above, so
//  the two defences are independent: the minimum of several batches drops the
//  runs that were interrupted, and thread CPU time means an interrupted run was
//  never counted as slower in the first place.
//
//  WHAT IT DOES NOT REMOVE: cache and memory-bandwidth contention are real CPU
//  time and still land on the number. It removes the largest term, preemption,
//  not every term.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

/// Seconds of CPU time on THIS THREAD for the fastest of `batches` runs of
/// `block`.
///
/// The wall clock is the fallback only where a platform has no per-thread CPU
/// clock (`threadCPUNanoseconds()` answers `nil`), which today is neither of
/// the two this suite runs on.
func bestCPUSeconds(batches: Int = 5, _ block: () -> Void) -> TimeInterval {
    var best = TimeInterval.infinity
    for _ in 0..<batches {
        let startCPU = threadCPUNanoseconds()
        let startWall = Date()
        block()
        let elapsed: TimeInterval
        if let startCPU, let endCPU = threadCPUNanoseconds() {
            elapsed = TimeInterval(endCPU &- startCPU) / 1_000_000_000
        } else {
            elapsed = Date().timeIntervalSince(startWall)
        }
        best = min(best, elapsed)
    }
    return best
}
