//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBufferCombineScalingTests.swift
//
//  A stack appends its children into one accumulating buffer. When the combine
//  rebuilt that accumulator — `var combined = lines; combined.append(...)`, plus
//  `a + b` for the three carried side-channels — every child copied everything
//  placed before it, making a container O(n²) in its child count and retaining
//  every accumulated row each time. These guard the shape of the growth, not an
//  absolute speed, so they stay meaningful on any machine.
//
//  The same shape came back a second time, as measuring rather than copying: the
//  debug `lineWidths` invariant re-walked the whole accumulator on every append.
//  The guards below were blind to it because their children carry no per-line
//  widths, so the last of them stacks children that do.
//
//  They are measured in CPU time on the calling thread, not wall time. A ratio
//  of a big accumulation to a small one is exactly the shape a loaded machine
//  distorts: the big arm runs 8x longer and so is exposed to 8x the preemption,
//  and the ratio climbs with the load rather than with the growth. Under the
//  parallel harness at `-j 12` these read 36.3x and 57.6x against a bound of
//  20; the same tests alone, on an idle box, read 8.7x — and wall and CPU then
//  agree to four significant figures (8.697 vs 8.696), which is what says the
//  two measure the same thing when there is nothing to steal the CPU away.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

@Suite("Frame buffer combine scaling")
struct FrameBufferCombineScalingTests {
    /// Seconds of CPU time on THIS THREAD for the fastest of several batches.
    ///
    /// Two independent defences against noise, because the statistic here is a
    /// ratio and a ratio inflates from below as readily as from above. The
    /// minimum of several batches drops the runs that were interrupted; thread
    /// CPU time means an interrupted run was never counted as slower in the
    /// first place. `threadCPUNanoseconds()` is the framework's own answer to
    /// this — it exists because render budgets measured in wall time failed on
    /// loaded CI runners with nothing changed — so this reuses it rather than
    /// hand-rolling a second clock.
    ///
    /// The wall clock is the fallback only where a platform has no per-thread
    /// CPU clock (the function answers `nil`), which today is neither of the
    /// two these tests run on.
    private func best(of batches: Int = 5, _ block: () -> Void) -> TimeInterval {
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

    private func accumulateVertically(_ count: Int) -> TimeInterval {
        let child = FrameBuffer(lines: ["a row of text wide enough to be worth copying"])
        return best {
            var result = FrameBuffer()
            for _ in 0..<count { result.appendVertically(child, spacing: 0) }
            precondition(result.height == count)
        }
    }

    /// Linear growth costs 8× for 8× the children; quadratic costs 64×. The
    /// bound sits between, far from both: measured 6.6× linear against the 48×
    /// the copying accumulator cost.
    @Test("Stacking N children stays sub-quadratic in N")
    func verticalAppendIsNotQuadratic() {
        let small = accumulateVertically(500)
        let large = accumulateVertically(4000)
        let ratio = large / small
        #expect(
            ratio < 20,
            """
            appendVertically grew \(String(format: "%.1f", ratio))× for 8× the children \
            (linear ≈ 8×, quadratic ≈ 64×) — the accumulator is being copied per child again.
            """)
    }

    /// The carried overlays / hit regions / animated cells were concatenated with
    /// `a + b`, which allocates and copies both sides every child — quadratic in
    /// the accumulated count even when the rows themselves are cheap.
    @Test("Carried hit regions stay sub-quadratic in the child count")
    func carriedRegionsAreNotQuadratic() {
        func accumulate(_ count: Int) -> TimeInterval {
            var child = FrameBuffer(lines: ["row"])
            child.hitTestRegions = [
                HitTestRegion(
                    offsetX: 0, offsetY: 0, width: 3, height: 1,
                    handlerID: HitTestRegion.HandlerID(1))
            ]
            return best {
                var result = FrameBuffer()
                for _ in 0..<count { result.appendVertically(child, spacing: 0) }
                precondition(result.hitTestRegions.count == count)
            }
        }
        let ratio = accumulate(4000) / accumulate(500)
        #expect(
            ratio < 20,
            """
            carried hit regions grew \(String(format: "%.1f", ratio))× for 8× the children \
            — the side-channels are being concatenated rather than appended.
            """)
    }

    @Test("Combining still produces the same buffer it always did")
    func combineRemainsCorrect() {
        var result = FrameBuffer()
        result.appendVertically(FrameBuffer(lines: ["ab"]), spacing: 0)
        result.appendVertically(FrameBuffer(lines: ["cde"]), spacing: 2)
        result.appendVertically(FrameBuffer(lines: ["f"]), spacing: 1)

        #expect(result.lines == ["ab", "", "", "cde", "", "f"])
        #expect(result.width == 3)
        // Ragged content: the uniform-width hint must stay conservative.
        #expect(result.linesAreUniformWidth == false)

        // An empty child contributes neither a row nor a spacing slot.
        var withEmpty = FrameBuffer(lines: ["x"])
        withEmpty.appendVertically(FrameBuffer(), spacing: 5)
        #expect(withEmpty.lines == ["x"])
    }

    @Test("Per-line widths survive the in-place growth")
    func lineWidthsAreCarried() {
        let left = FrameBuffer(lines: ["ab"], width: 2, uniformWidth: true, lineWidths: [2])
        let right = FrameBuffer(lines: ["cd"], width: 2, uniformWidth: true, lineWidths: [2])
        var joined = left
        joined.appendVertically(right, spacing: 1)
        #expect(joined.lineWidths == [2, 0, 2])

        // One unknown side makes the result unknown, never stale. A ragged
        // buffer measured on the way in carries no widths and is not uniform,
        // so it knows nothing to spell out.
        var unknown = left
        unknown.appendVertically(FrameBuffer(lines: ["efg", "h"]), spacing: 0)
        #expect(unknown.lineWidths == nil)

        // A uniform side with no array still KNOWS every width — one number —
        // and spells it out for the merge rather than making the result
        // unknown: a stack of uniform rows at two widths is every page.
        var spelled = left
        spelled.appendVertically(FrameBuffer(lines: ["efg"]), spacing: 0)
        #expect(spelled.lineWidths == [2, 3])
    }

    /// The guards above stack children built by `FrameBuffer(lines:)`, which
    /// carries no per-line widths — so `lineWidths` stays `nil` the whole way and
    /// the debug invariant check returns at its first `guard`. That is exactly
    /// why they never saw the second quadratic: children that DO know their
    /// widths take the other path, and the check used to re-measure the entire
    /// accumulator on every append — `N(N+1)/2` row measures to verify N rows,
    /// the same O(n²) in the child count moved from copying into measuring.
    /// Debug-only, like the check, which is where the suite and every developer
    /// build live.
    @Test("Stacking children that know their widths stays sub-quadratic too")
    func verticalAppendWithKnownWidthsIsNotQuadratic() {
        func accumulate(_ count: Int) -> TimeInterval {
            // Two widths, so the result is RAGGED and the merged array is really
            // carried: a uniform result drops it to nil and checks nothing.
            // Widths measured, never hand-counted — a wrong `width:` here is a
            // lie the check would (rightly) trap on rather than a failed test.
            let narrowText = "a row of text wide enough to be worth measuring"
            let wideText = "a row of text wide enough to be worth measuring twice over"
            let narrow = FrameBuffer(
                lines: [narrowText], width: narrowText.strippedLength, uniformWidth: true)
            let wide = FrameBuffer(
                lines: [wideText], width: wideText.strippedLength, uniformWidth: true)
            return best {
                var result = FrameBuffer()
                for index in 0..<count {
                    result.appendVertically(index.isMultiple(of: 2) ? narrow : wide, spacing: 0)
                }
                precondition(result.lineWidths?.count == count)
            }
        }
        let ratio = accumulate(4000) / accumulate(500)
        #expect(
            ratio < 20,
            """
            appendVertically grew \(String(format: "%.1f", ratio))× for 8× the children \
            (linear ≈ 8×, quadratic ≈ 64×) — the debug line-width invariant is re-measuring \
            the whole accumulator per child again.
            """)
    }
}
