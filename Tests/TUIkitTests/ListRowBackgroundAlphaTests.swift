//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowBackgroundAlphaTests.swift
//
//  `.listRowBackground(.red.opacity(0.5))` — a fill that is not a backdrop yet,
//  which is what makes it different from the opaque case.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A translucent list row background")
struct ListRowBackgroundAlphaTests {

    private func buffer<V: View>(_ view: V, width: Int = 12, height: Int = 1) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    private func faded(_ base: Color, _ alpha: UInt8) -> Color {
        var colour = base
        colour.alpha = alpha
        return colour
    }

    @Test("The fill claims the whole row, not the width of the words")
    func fillSpansTheRow() throws {
        let drawn = buffer(Text("hi").listRowBackground(faded(.ansi(.red), 128)), width: 12)
        let claim = try #require(drawn.opacityRegions.first { $0.fieldOpacity < 1 })
        #expect(claim.width == 12, "the row, not the two letters: \(claim)")
        #expect(claim.offsetX == 0)
        #expect(claim.fieldOpacity == 128.0 / 255)
        #expect(claim.inkOpacity == 1, "a fill says nothing about the row's ink")
    }

    @Test("The claim survives the content being composited over it")
    func claimSurvivesTheComposite() throws {
        // `composited(with:at:)` PUNCHES the destination's claims by the overlay's
        // footprint, which is right for cells the overlay replaced and wrong for a
        // row background: the text sits ON the fill and those cells still show it.
        // Punched, the row would render opaque under its own words and faded either
        // side — so this asserts the claim still covers column 0, where the `h` is.
        let drawn = buffer(Text("hi").listRowBackground(faded(.ansi(.red), 128)), width: 12)
        let claim = try #require(drawn.opacityRegions.first { $0.fieldOpacity < 1 })
        #expect(claim.offsetX == 0 && claim.width == 12, "unpunched: \(claim)")
    }

    @Test("An opaque fill claims nothing, and still resolves the row's own opacity")
    func opaqueFillResolvesContent() {
        // The branch that must not change: an opaque fill IS a backdrop, so
        // `.opacity(0.5)` on the row's text resolves against it here rather than
        // travelling up to be resolved against the page.
        let drawn = buffer(Text("hi").opacity(0.5).listRowBackground(Color.ansi(.red)), width: 12)
        #expect(
            drawn.opacityRegions.isEmpty,
            "the content's fade was spent against the fill: \(drawn.opacityRegions)")
    }

    @Test("A translucent fill carries the content's fade up rather than spending it")
    func translucentFillDefersContent() {
        // The other side of the same coin. The fill is not a backdrop, so blending
        // the text toward its opaque spelling now would be blending toward a colour
        // the fill is not going to be. Both claims travel and resolve together.
        let drawn = buffer(
            Text("hi").opacity(0.5).listRowBackground(faded(.ansi(.red), 128)), width: 12)
        #expect(
            drawn.opacityRegions.contains { $0.fieldOpacity < 1 }, "the fill's claim")
        #expect(
            drawn.opacityRegions.contains { $0.opacity < 1 },
            "and the content's, unspent: \(drawn.opacityRegions)")
    }

    @Test("The fill's bytes are the colour at full strength")
    func bytesAreOpaque() {
        let drawn = buffer(Text("hi").listRowBackground(faded(.ansi(.red), 128)), width: 12)
        #expect(
            drawn.lines[0].contains(Color.ansi(.red).backgroundCodes().joined(separator: ";")),
            "\(drawn.lines[0].debugDescription)")
    }

    @Test("A row with no fill is untouched")
    func noFill() {
        #expect(buffer(Text("hi").listRowBackground(nil), width: 12).opacityRegions.isEmpty)
    }
}
