//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBufferCompositeInPlaceTests.swift
//
//  `composite(with:at:)` writes rows through the backing store rather than
//  through `lines`, so it does NOT get the cached geometry recomputed for it —
//  it maintains `width` / `linesAreUniformWidth` / `lineWidths` by hand. That
//  is the whole point (writing a row per child through the observer re-measured
//  the entire canvas per child), and it is also the whole risk: a bookkeeping
//  slip is invisible in the rendered text and shows up later as a mis-padded
//  parent.
//
//  So these check it against the copying `composited(with:at:)` — which does
//  get the recompute — on content AND geometry, across the cases where the
//  two paths could diverge: growth in either axis, negative and out-of-range
//  positions, styled bases, wide characters, and ragged input (which must fall
//  back to the copying path).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("FrameBuffer in-place composite")
struct FrameBufferCompositeInPlaceTests {

    /// In-place and copying composites must agree on everything observable.
    private func assertMatchesCopying(
        _ base: FrameBuffer,
        _ overlay: FrameBuffer,
        at position: (x: Int, y: Int),
        _ label: String
    ) {
        let copying = base.composited(with: overlay, at: position)
        var inPlace = base
        inPlace.composite(with: overlay, at: position)

        #expect(inPlace.lines == copying.lines, "\(label) lines")
        #expect(inPlace.width == copying.width, "\(label) width")
        #expect(inPlace.height == copying.height, "\(label) height")
        #expect(inPlace.overlays == copying.overlays, "\(label) overlays")
        #expect(inPlace.hitTestRegions == copying.hitTestRegions, "\(label) hit regions")

        // The hints are allowed to be conservative, never wrong: a `true`
        // uniformity claim must hold, and any carried per-line widths must be
        // the real ones. This is exactly what a hand-maintained width would
        // get wrong, and what every consumer that trusts the hint would then
        // mis-pad on.
        if inPlace.linesAreUniformWidth {
            #expect(
                inPlace.lines.allSatisfy { $0.strippedLength == inPlace.width },
                "\(label) claims uniform width \(inPlace.width) but is not")
        }
        if let widths = inPlace.lineWidths {
            #expect(widths == inPlace.lines.map(\.strippedLength), "\(label) lineWidths")
        }
        #expect(
            inPlace.width == inPlace.lines.map(\.strippedLength).max() ?? 0,
            "\(label) width is not the widest line")
    }

    @Test("Matches the copying path fully inside the canvas")
    func insideCanvas() {
        let base = FrameBuffer(lines: Array(repeating: "..........", count: 4))
        let chip = FrameBuffer(lines: ["ab"])
        for x in 0...8 {
            for y in 0...3 {
                assertMatchesCopying(base, chip, at: (x: x, y: y), "chip at \(x),\(y)")
            }
        }
    }

    @Test("Matches when the overlay grows the canvas in either axis")
    func growth() {
        let base = FrameBuffer(lines: Array(repeating: "....", count: 2))
        let chip = FrameBuffer(lines: ["XY"])
        assertMatchesCopying(base, chip, at: (x: 6, y: 0), "grows width")
        assertMatchesCopying(base, chip, at: (x: 0, y: 5), "grows height")
        assertMatchesCopying(base, chip, at: (x: 7, y: 4), "grows both")
        assertMatchesCopying(
            base, FrameBuffer(lines: ["AAAA", "BBBB", "CCCC"]), at: (x: 3, y: 1), "tall overlay")
    }

    @Test("Matches for styled bases and overlays")
    func styled() {
        let base = FrameBuffer(lines: [
            "\u{1B}[44m          \u{1B}[0m",
            "\u{1B}[4munderlined\u{1B}[0m",
        ])
        let chip = FrameBuffer(lines: ["\u{1B}[31mRR\u{1B}[0m"])
        for x in 0...8 {
            assertMatchesCopying(base, chip, at: (x: x, y: 0), "styled row 0 at \(x)")
            assertMatchesCopying(base, chip, at: (x: x, y: 1), "styled row 1 at \(x)")
        }
    }

    @Test("Matches over wide characters straddling the overlay's edges")
    func wideCharacters() {
        let base = FrameBuffer(lines: ["ab😀cd😀ef", "日本語テキスト"])
        let chip = FrameBuffer(lines: ["##"])
        for x in 0...10 {
            assertMatchesCopying(base, chip, at: (x: x, y: 0), "emoji base at \(x)")
            assertMatchesCopying(base, chip, at: (x: x, y: 1), "CJK base at \(x)")
        }
    }

    /// A NEGATIVE column: an overlay starting left of the canvas, as a custom `Layout`
    /// places one when it puts a subview's centre at x: 0. Both twins inserted the whole
    /// overlay at column 0 and slid the base's cells right behind it; the in-place one
    /// then claimed the canvas's width and uniformity over a row wider than both. The
    /// header above always said "negative positions" — no case here had a negative x.
    @Test("A negative column cuts the overlay instead of widening the row")
    func negativeColumn() {
        let base = FrameBuffer(lines: Array(repeating: String(repeating: ".", count: 12), count: 2))
        for x in -4...(-1) {
            assertMatchesCopying(base, FrameBuffer(lines: ["abc"]), at: (x: x, y: 0), "plain at \(x)")
            assertMatchesCopying(
                base, FrameBuffer(lines: ["\u{1B}[31mabc\u{1B}[0m"]), at: (x: x, y: 1),
                "styled at \(x)")
            assertMatchesCopying(base, FrameBuffer(lines: ["😀cd"]), at: (x: x, y: 0), "wide at \(x)")
        }

        let placed = base.composited(with: FrameBuffer(lines: ["abc"]), at: (x: -2, y: 0))
        let visible = placed.lines.map(\.stripped)
        #expect(visible == ["c...........", "............"], "only 'c' lands on the canvas: \(visible)")
        #expect(placed.width == 12)

        // A wide glyph straddling column 0 cannot be half-drawn: it goes, and the cell it
        // would have covered stays a space so everything after it keeps its column.
        let straddling = base.composited(with: FrameBuffer(lines: ["😀cd"]), at: (x: -1, y: 0))
        let straddlingVisible = straddling.lines.map(\.stripped)
        #expect(straddlingVisible.first == " cd.........", "\(straddlingVisible)")
    }

    /// Ragged lines are the documented bail-out: the incremental width
    /// bookkeeping is only valid on a uniform canvas, so the method must hand
    /// off to the copying path rather than quietly claim a width it did not
    /// verify.
    @Test("Ragged bases fall back to the copying path")
    func raggedFallsBack() {
        let base = FrameBuffer(lines: ["short", "much longer line", "mid line"])
        let chip = FrameBuffer(lines: ["Z"])
        for x in 0...4 {
            assertMatchesCopying(base, chip, at: (x: x, y: 1), "ragged at \(x)")
        }
    }

    /// An empty overlay draws nothing, but its nested layers and hit regions
    /// still have to lift — the early-out is the easiest place to drop them.
    @Test("An empty overlay still lifts layers and hit regions")
    func emptyOverlayLiftsMetadata() {
        var overlay = FrameBuffer()
        overlay.hitTestRegions = [
            HitTestRegion(
                offsetX: 1, offsetY: 2, width: 3, height: 1,
                handlerID: HitTestRegion.HandlerID(7), focusID: "id")
        ]
        assertMatchesCopying(
            FrameBuffer(lines: ["....", "...."]), overlay, at: (x: 2, y: 1), "empty overlay")
    }

    /// Repeated composites are the actual usage (`_LayoutCore` folds every
    /// placed subview into one canvas), and the case where a stale width would
    /// compound rather than show up once.
    @Test("Folding many children matches folding them the copying way")
    func manyChildren() {
        let placements = (0..<12).map { (x: ($0 * 7) % 30, y: $0 % 5) }
        var inPlace = FrameBuffer(lines: Array(repeating: String(repeating: " ", count: 30), count: 5))
        var copying = inPlace
        for (index, spot) in placements.enumerated() {
            let chip = FrameBuffer(lines: ["\u{1B}[7m\(index % 10)\(index % 7)\u{1B}[0m"])
            inPlace.composite(with: chip, at: spot)
            copying = copying.composited(with: chip, at: spot)
        }
        #expect(inPlace.lines == copying.lines)
        #expect(inPlace.width == copying.width)
        #expect(inPlace.width == inPlace.lines.map(\.strippedLength).max() ?? 0)
    }
}
