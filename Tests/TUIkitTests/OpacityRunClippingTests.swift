//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityRunClippingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A run whose cells are not all on the buffer that carries it.
///
/// `OverlayLayer`'s leading cut moves every payload by `-dropX` / `-dropY` and
/// deliberately leaves what it cut naming columns that are gone, on the grounds
/// that translation and clipping commute for a run and the screen drops the
/// remainder. The opacity resolution was named in that rationale as reading such
/// an offset as `max(0, …)`; it did not, and the blend indexes its source array by
/// absolute column. See `Documentation/Opacity as composition.md` §70.
@MainActor
@Suite("Opacity resolution: runs outside the buffer")
struct OpacityRunClippingTests {

    private func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    /// A run left at a NEGATIVE column by a leading cut is cut here, not indexed.
    ///
    /// `OverlayLayer`'s leading cut (`cutting`) moves every payload by `-dropX` and
    /// leaves a run naming columns the surviving buffer does not have. That was
    /// justified by the claim that the opacity resolution "already read as
    /// `max(0, …)`" — only the frame's alignment prefix ever did, and the blend
    /// indexes its source array by absolute column, so the run aborted the process
    /// at `sourceCells[-1]` in release as well as debug. A drag preview carrying a
    /// `Spinner` dragged past the screen's left edge is the live route.
    @Test("A run straddling column 0 is cut to the cells that exist")
    func aRunStraddlingTheLeadingEdgeIsCut() throws {
        // Four cells wide starting two columns left of the buffer: "CD" survive.
        var buffer = FrameBuffer(lines: ["CD"])
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: -2, offsetY: 0, width: 4, frames: ["ABCD", "abcd"],
                clock: .content)
        ]
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 0.5)
        ]

        let resolved = buffer.resolvingOpacity(
            over: FrameBuffer(lines: ["xy"]), at: (x: 0, y: 0), surface: .black,
            palette: palette())

        let run = try #require(resolved.animatedCells.first, "the surviving cells keep animating")
        #expect(run.offsetX == 0, "cut to the buffer's own first column")
        #expect(run.width == 2)
        #expect(run.frames.map(\.stripped) == ["CD", "cd"], "\(run.frames.map(\.stripped))")
    }

    /// The whole run is left of the edge: nothing of it is on this buffer.
    ///
    /// Dropped rather than kept at column 0, which would splice cells the render
    /// never drew over whatever does occupy them. Nothing is lost with it — a run
    /// can be the sole carrier of a per-frame alpha, but only for cells it covers,
    /// and it covers none here.
    @Test("A run wholly left of column 0 is dropped")
    func aRunWhollyLeftOfTheEdgeIsDropped() {
        var buffer = FrameBuffer(lines: ["CD"])
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: -4, offsetY: 0, width: 4, frames: ["ABCD", "abcd"],
                clock: .content)
        ]
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 0.5)
        ]

        let resolved = buffer.resolvingOpacity(
            over: FrameBuffer(lines: ["xy"]), at: (x: 0, y: 0), surface: .black,
            palette: palette())

        #expect(resolved.animatedCells.isEmpty)
    }

    /// The same cut, reached the way the app reaches it: a pointer-anchored layer
    /// that declines to be clamped loses its overhang out of its CONTENT, and the
    /// run rides the cut. No `.opacity(_:)` is needed — a run carrying a
    /// translucent `AnimatedRunAlpha` (a caret, an animated border) satisfies the
    /// resolver's entry guard on its own.
    @Test("A pointer-anchored layer dragged off the left edge resolves its run")
    func aPointerAnchoredLayerDraggedOffTheLeftEdgeResolvesItsRun() throws {
        var preview = FrameBuffer(lines: ["ABCD"])
        preview.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 4, frames: ["ABCD", "abcd"],
                clock: .content,
                alpha: AnimatedRunAlpha(
                    perFrame: [
                        [AnimatedRunAlpha.Span(start: 0, cells: 4, ink: 0.5)],
                        [AnimatedRunAlpha.Span(start: 0, cells: 4, ink: 1)],
                    ],
                    drawnIndex: 0))
        ]
        var page = FrameBuffer(lines: ["wxyz", "....."])
        page.overlays = [
            OverlayLayer(
                offsetX: -2, offsetY: 0, content: preview, clampsToScreen: false,
                isOpaque: false)
        ]

        let flat = page.compositingOverlays(maxWidth: 5, maxHeight: 2, palette: palette())

        let run = try #require(flat.animatedCells.first)
        #expect(run.offsetX == 0, "the two cells that fell off the edge are gone")
        #expect(run.width == 2)
        #expect(run.frames.map(\.stripped) == ["CD", "cd"], "\(run.frames.map(\.stripped))")
    }
}
