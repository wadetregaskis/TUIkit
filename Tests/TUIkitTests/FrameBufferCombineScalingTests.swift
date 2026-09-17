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
    private func accumulateVertically(_ count: Int) -> TimeInterval {
        let child = FrameBuffer(lines: ["a row of text wide enough to be worth copying"])
        return bestCPUSeconds {
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
            return bestCPUSeconds {
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
    /// Two widths, so a stack of these is RAGGED and the merged array is really
    /// carried: a uniform result drops it to `nil` and merges nothing. Widths are
    /// measured, never hand-counted — a wrong `width:` here is a lie the debug
    /// invariant check would (rightly) trap on rather than a failed test.
    private static func widthCarryingChildren() -> (narrow: FrameBuffer, wide: FrameBuffer) {
        let narrowText = "a row of text wide enough to be worth measuring"
        let wideText = "a row of text wide enough to be worth measuring twice over"
        return (
            FrameBuffer(lines: [narrowText], width: narrowText.strippedLength, uniformWidth: true),
            FrameBuffer(lines: [wideText], width: wideText.strippedLength, uniformWidth: true)
        )
    }

    @Test("Stacking children that know their widths stays sub-quadratic too")
    func verticalAppendWithKnownWidthsIsNotQuadratic() {
        func accumulate(_ count: Int) -> TimeInterval {
            let (narrow, wide) = Self.widthCarryingChildren()
            return bestCPUSeconds {
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

    /// The guards above bound the SHAPE of the growth in CPU time. This one
    /// counts instead, which is both stronger and cheaper: a count is
    /// deterministic and immune to load, and it says which of the two shapes the
    /// code HAS rather than how fast today's machine ran it. Same reasoning as
    /// `3fadcb1d`, which moved a growth guard off the wall clock, taken to its
    /// conclusion.
    ///
    /// What it caught: the merge handed `lineWidths` a NEW buffer on every
    /// append. It bound `mine` from the field and copied it (`var merged = mine`)
    /// while the field still referenced that buffer, so the accumulator was never
    /// uniquely referenced and the whole of it was copied per child — a residual
    /// O(n²) in the child count which, unlike the invariant re-measure above, is
    /// NOT `#if DEBUG` and so shipped in release builds.
    ///
    /// The oracle is the STORAGE IDENTITY, not `capacity`. Capacity was tried
    /// first and is not a guard at all: it counted fewer than 400 changes across
    /// the 4,000 copies above and so passed the defect it was meant to catch.
    /// `Array` allocates the malloc size class rather than the exact figure
    /// asked for, so a copy into a fresh buffer usually lands at the capacity the
    /// old one had. A new buffer, though, cannot share an address with the old
    /// one — the old is still live, which is the whole reason it was copied — so
    /// the address changing is exactly "was given a new buffer". It is reported
    /// alongside for diagnosis; only the identity count is asserted on.
    @Test("The carried widths grow in place rather than being copied per child")
    func carriedWidthsAreNotCopiedPerChild() {
        let (narrow, wide) = Self.widthCarryingChildren()
        let count = 4000
        var result = FrameBuffer()
        var freshBuffers = 0
        var capacityChanges = 0
        var lastIdentity = UInt.max
        var lastCapacity = -1

        for index in 0..<count {
            result.appendVertically(index.isMultiple(of: 2) ? narrow : wide, spacing: 0)
            // Read BETWEEN appends and never held across one: a binding that
            // outlived its statement would share the buffer itself, and so cause
            // the very copy being counted here.
            let identity =
                result.lineWidths?.withUnsafeBufferPointer { widths in
                    widths.baseAddress.map { UInt(bitPattern: UnsafeRawPointer($0)) } ?? 0
                } ?? 0
            let capacity = result.lineWidths?.capacity ?? -1
            if identity != lastIdentity { freshBuffers += 1 }
            if capacity != lastCapacity { capacityChanges += 1 }
            lastIdentity = identity
            lastCapacity = capacity
        }

        // Byte-identical widths: growing in place is an implementation detail and
        // must change nothing about the answer.
        #expect(result.lineWidths == result.lines.map(\.strippedLength))

        // ~12 reallocations for 4,000 appends if geometric, 4,000 if per-append.
        // The bound sits far from both rather than pinning a growth factor.
        #expect(
            freshBuffers < count / 10,
            """
            the carried lineWidths array was given a new buffer \(freshBuffers) times for \
            \(count) appends (capacity changed \(capacityChanges) times) — the merge is \
            copying the whole accumulator per child again.
            """)
    }
}
