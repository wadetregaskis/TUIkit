//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedCellRunTests.swift
//
//  A run is a claim about particular CELLS, so it has to travel with them
//  through every way a buffer can be assembled — and be dropped when they are
//  clipped away. A run that survives its own cells would repaint over whatever
//  took their place, on a clock, forever.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("Animated cell runs")
struct AnimatedCellRunTests {

    private func run(x: Int, y: Int, width: Int = 1, frames: [String] = ["a", "b"])
        -> AnimatedCellRun
    {
        AnimatedCellRun(offsetX: x, offsetY: y, width: width, frames: frames, clock: .cursor)
    }

    private func buffer(_ lines: [String], runs: [AnimatedCellRun] = []) -> FrameBuffer {
        var buffer = FrameBuffer(lines: lines)
        buffer.animatedCells = runs
        return buffer
    }

    @Test("A cycle is indexed modulo its length, in both directions")
    func framesCycle() {
        let sample = run(x: 0, y: 0, frames: ["a", "b", "c"])
        #expect(sample.frame(atIndex: 0) == "a")
        #expect(sample.frame(atIndex: 4) == "b")
        // A clock that has wrapped past zero must not trap or index backwards
        // off the front.
        #expect(sample.frame(atIndex: -1) == "c")
    }

    @Test("One frame is a still picture, not an animation")
    func singleFrameIsNotAnimating() {
        // Producers are allowed to build a run unconditionally — a disabled
        // control, a cursor style that does not blink — and let this filter it,
        // rather than each one deciding not to.
        #expect(!run(x: 0, y: 0, frames: ["only"]).isAnimating)
        #expect(!run(x: 0, y: 0, frames: []).isAnimating)
        #expect(run(x: 0, y: 0, frames: ["a", "b"]).isAnimating)
    }

    @Test("Stacking vertically moves the lower buffer's runs down")
    func appendVerticallyShifts() {
        var top = buffer(["one", "two"], runs: [run(x: 1, y: 0)])
        let bottom = buffer(["three"], runs: [run(x: 2, y: 0)])
        top.appendVertically(bottom)
        #expect(top.animatedCells.count == 2)
        #expect(top.animatedCells[0].offsetY == 0)
        #expect(top.animatedCells[1].offsetY == 2, "the lower run rides its own lines down")
        #expect(top.animatedCells[1].offsetX == 2, "and does not move sideways")
    }

    @Test("Stacking horizontally moves the right buffer's runs right")
    func appendHorizontallyShifts() {
        var left = buffer(["abc"], runs: [run(x: 0, y: 0)])
        let right = buffer(["de"], runs: [run(x: 1, y: 0)])
        left.appendHorizontally(right)
        #expect(left.animatedCells.count == 2)
        #expect(left.animatedCells[1].offsetX == 4, "3 columns of `abc`, then its own 1")
        #expect(left.animatedCells[1].offsetY == 0)
    }

    @Test("A zero-height buffer still hands over its runs")
    func emptyOtherStillCarriesRuns() {
        // The empty-buffer early return is a separate code path, and it used to
        // be the one that quietly dropped things: a buffer with no visible lines
        // can still carry overlays, hit regions — and now runs.
        var base = buffer(["x"])
        var empty = FrameBuffer()
        empty.animatedCells = [run(x: 0, y: 0)]
        base.appendVertically(empty)
        #expect(base.animatedCells.count == 1)
    }

    @Test("Compositing moves the overlay's runs to where it landed")
    func compositingShifts() {
        let base = buffer(["....", "....", "...."])
        let overlay = buffer(["ab"], runs: [run(x: 0, y: 0)])
        let result = base.composited(with: overlay, at: (x: 2, y: 1))
        #expect(result.animatedCells.count == 1)
        #expect(result.animatedCells[0].offsetX == 2)
        #expect(result.animatedCells[0].offsetY == 1)
    }

    @Test("Clamping drops the runs whose cells it clipped away")
    func clampingDropsClippedRuns() {
        // The point of the whole type: a run IS its cells. Scrolled out of a
        // viewport, it must stop — otherwise it repaints on a clock over
        // whatever moved into that position.
        let runs = [
            run(x: 0, y: 0),  // kept
            run(x: 0, y: 5),  // clipped by height
            run(x: 9, y: 0, width: 3),  // clipped by width (9 + 3 > 10)
        ]
        let wide = buffer(Array(repeating: String(repeating: "x", count: 20), count: 8), runs: runs)
        let clamped = wide.clamped(toWidth: 10, height: 3)
        #expect(clamped.animatedCells.count == 1, "got: \(clamped.animatedCells)")
        #expect(clamped.animatedCells[0].offsetY == 0)
    }

    @Test("Clamping within bounds keeps every run")
    func clampingWithinBoundsKeepsRuns() {
        let small = buffer(["ab", "cd"], runs: [run(x: 0, y: 0), run(x: 1, y: 1)])
        #expect(small.clamped(toWidth: 40, height: 40).animatedCells.count == 2)
    }

    @Test("Two buffers differing only in their runs are not equal")
    func equalityIncludesRuns() {
        // Equality drives the render cache; a subtree whose animation changed
        // but whose glyphs did not must still count as changed.
        let plain = buffer(["ab"])
        let animated = buffer(["ab"], runs: [run(x: 0, y: 0)])
        #expect(plain != animated)
    }
}
