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

@Suite("Compositing punches what the overlay covers")
struct CompositePunchTests {

    private func spinner(atX x: Int, y: Int = 0) -> AnimatedCellRun {
        AnimatedCellRun(offsetX: x, offsetY: y, width: 3, frames: ["abc", "def"], clock: .cursor)
    }

    @Test("A run under the overlay's footprint is dropped, through both paths")
    func coveredRunsAreDropped() {
        // A run replays its cells over whatever is on screen: left in the
        // buffer, a spinner under a freshly-opened popover repaints itself
        // THROUGH the popup within one tick. The modal presenter cleared base
        // runs by hand for exactly this; the compositors now cover every
        // overlap — menus, popovers, toasts, ZStack siblings.
        var base = FrameBuffer(lines: ["0123456789"])
        base.animatedCells = [spinner(atX: 2)]
        let popup = FrameBuffer(lines: ["XXXX"])

        let copied = base.composited(with: popup, at: (x: 3, y: 0))
        #expect(copied.animatedCells.isEmpty, "the copying path replayed a covered run")

        var inPlace = base
        inPlace.composite(with: popup, at: (x: 3, y: 0))
        #expect(inPlace.animatedCells.isEmpty, "the in-place path replayed a covered run")
    }

    @Test("A run beside the footprint survives, and rows are respected")
    func uncoveredRunsSurvive() {
        var base = FrameBuffer(lines: ["0123456789", "0123456789"])
        base.animatedCells = [spinner(atX: 0), spinner(atX: 0, y: 1)]
        let popup = FrameBuffer(lines: ["XX"])

        // Covers columns 4-5 of row 0: neither run overlaps it.
        let beside = base.composited(with: popup, at: (x: 4, y: 0))
        #expect(beside.animatedCells.count == 2)

        // Covers columns 0-1 of row 1 only: the row-0 run survives.
        let below = base.composited(with: popup, at: (x: 0, y: 1))
        #expect(below.animatedCells.count == 1)
        #expect(below.animatedCells.first?.offsetY == 0)
    }

    @Test("A pending opacity region is punched identically through both paths")
    func regionPunchTwinsAgree() {
        var base = FrameBuffer(lines: ["0123456789"])
        base.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 10, height: 1, opacity: 0.5)
        ]
        let popup = FrameBuffer(lines: ["XXXX"])

        let copied = base.composited(with: popup, at: (x: 3, y: 0))
        var inPlace = base
        inPlace.composite(with: popup, at: (x: 3, y: 0))
        #expect(copied.opacityRegions == inPlace.opacityRegions)
        #expect(copied.opacityRegions.count == 2)
    }
}
