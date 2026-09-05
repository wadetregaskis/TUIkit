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
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

@Suite("Frame buffer combine scaling")
struct FrameBufferCombineScalingTests {
    /// Fastest of several batches: scheduler noise under the parallel suite only
    /// ever inflates a timing, so the minimum is the closest estimate of the true
    /// cost. Mirrors `RenderBottleneckTests.measure`.
    private func best(of batches: Int = 5, _ block: () -> Void) -> TimeInterval {
        var best = TimeInterval.infinity
        for _ in 0..<batches {
            let start = Date()
            block()
            best = min(best, Date().timeIntervalSince(start))
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
}
