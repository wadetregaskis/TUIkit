//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeTwinTests.swift
//
//  `composited(with:at:)` and `composite(with:at:)` are documented as
//  "identical in result" — one copies, one writes in place for the case the
//  copying one is quadratic in. Two implementations of one operation, which in
//  this codebase means they drift; this is what holds them together.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("The two compositing paths agree")
struct CompositeTwinTests {

    private func run(_ label: String) -> AnimatedCellRun {
        AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: [label, label + "'"], clock: .cursor)
    }

    private func region() -> HitTestRegion {
        HitTestRegion(
            offsetX: 0, offsetY: 0, width: 1, height: 1,
            handlerID: HitTestRegion.HandlerID(1), focusID: nil)
    }

    /// An overlay that draws nothing and carries everything — the case the two
    /// paths disagreed about.
    private func emptyCarrier() -> FrameBuffer {
        var carrier = FrameBuffer(lines: [])
        carrier.animatedCells = [run("a")]
        carrier.hitTestRegions = [region()]
        carrier.overlays = [
            OverlayLayer(offsetX: 0, offsetY: 0, content: FrameBuffer(lines: ["x"]))
        ]
        return carrier
    }

    @Test("A zero-size overlay's animated runs survive both paths")
    func zeroSizeOverlayKeepsItsRuns() {
        // The copying path tested for runs in its guard — "the overlay may
        // still carry its own nested layers / hit-test regions that need to be
        // lifted" — and then lifted everything except them. A dropped run is a
        // FROZEN animation, not a missing one: the loop keeps the clock alive
        // only from the runs that reach the final buffer.
        let base = FrameBuffer(lines: ["base"])
        let copied = base.composited(with: emptyCarrier(), at: (x: 2, y: 1))
        var inPlace = base
        inPlace.composite(with: emptyCarrier(), at: (x: 2, y: 1))

        #expect(copied.animatedCells.count == 1, "the copying path dropped the run")
        #expect(inPlace.animatedCells.count == 1, "the in-place path dropped the run")
        #expect(copied.animatedCells == inPlace.animatedCells, "the two paths placed it differently")
    }

    @Test("A zero-size overlay's regions and nested layers survive both paths")
    func zeroSizeOverlayKeepsTheRest() {
        let base = FrameBuffer(lines: ["base"])
        let copied = base.composited(with: emptyCarrier(), at: (x: 2, y: 1))
        var inPlace = base
        inPlace.composite(with: emptyCarrier(), at: (x: 2, y: 1))
        #expect(copied.hitTestRegions == inPlace.hitTestRegions)
        #expect(copied.overlays == inPlace.overlays)
    }

    @Test("An ordinary overlay lands identically through both paths")
    func drawnOverlayAgrees() {
        // The control: the paths must already agree about the common case, or
        // the assertions above would be comparing two kinds of wrong.
        var carrier = FrameBuffer(lines: ["ov"])
        carrier.animatedCells = [run("b")]
        carrier.hitTestRegions = [region()]

        let base = FrameBuffer(lines: ["base line", "second"])
        let copied = base.composited(with: carrier, at: (x: 1, y: 1))
        var inPlace = base
        inPlace.composite(with: carrier, at: (x: 1, y: 1))

        #expect(copied.lines == inPlace.lines)
        #expect(copied.animatedCells == inPlace.animatedCells)
        #expect(copied.hitTestRegions == inPlace.hitTestRegions)
    }
}
