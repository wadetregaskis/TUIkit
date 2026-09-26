//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TranslucentVeilTests.swift
//
//  A veil translucent by its COLOUR — a translucent colour as a view, or a
//  translucent `.background` on blanks — laid over text. Its blank cells have no
//  ink, so their ink channel is their field (rule 7), and that covers the glyph
//  under it by the field's own alpha, as it covers the field around it (rule 3).
//  `Opacity as composition.md` §104.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A translucent colour veils the text under it by its own alpha")
struct TranslucentVeilTests {

    private func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    private func codes(_ color: Color) -> String {
        color.foregroundCodes().joined(separator: ";")
    }

    private func backgroundCodes(_ color: Color) -> String {
        color.backgroundCodes().joined(separator: ";")
    }

    /// The same veil, translucent by its COLOUR rather than by a layer fade: a
    /// blank's ink channel is its field, so it covers the glyph under it by the
    /// field's alpha, as it covers the field around it. Folded with the ink's
    /// alpha instead — 1, a blank having no ink of its own — the glyph took the
    /// veil's colour whole: `ZStack { Text("hello"); Color.blue.opacity(0.5) }`
    /// drew the letters in the blue, on a field half way to it.
    @Test("A translucent colour's blank covers the text under it by the colour's alpha", arguments: [0.25, 0.5, 0.75])
    func aTranslucentFieldVeilsTheGlyphByItsOwnAlpha(alpha: Double) {
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("world", foreground: .red)])
        var source = FrameBuffer(lines: [ANSIRenderer.colorize("     ", background: .rgb(0, 0, 255))])
        source.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 1, fieldOpacity: alpha)
        ]
        let resolved = source.resolvingOpacity(
            over: destination, surface: .rgb(0, 0, 0), palette: palette())

        #expect(resolved.lines[0].stripped == "world")
        let ink = Color.rgb(0, 0, 255).opacity(alpha, over: .red)
        #expect(resolved.lines[0].contains(codes(ink)), "the letters are \(resolved.lines[0].debugDescription)")
        let field = Color.rgb(0, 0, 255).opacity(alpha, over: .rgb(0, 0, 0))
        #expect(resolved.lines[0].contains(backgroundCodes(field)))
    }

    /// Through the public API, the shapes a veil is written in: a translucent colour
    /// as a view, and a translucent `.background` on blanks, each over text in a
    /// `ZStack`. The letters stand, in their own ink half way to the veil's colour.
    @Test("A translucent veil over text leaves the text half way to it", arguments: [false, true])
    func aTranslucentVeilOverText(asBackground: Bool) throws {
        let veil = Color.rgb(0, 0, 200).opacity(0.5)
        let rows =
            asBackground
            ? writtenRows(of: ZStack { Text("hello"); Text("     ").background(veil) })
            : writtenRows(of: ZStack { Text("hello"); veil.frame(width: 5, height: 1) })
        let row = try #require(rows.first)
        let unveiled = try #require(writtenRows(of: Text("hello")).first)
        guard case .rgb(let red, let green, let blue) = unveiled[0].ink else {
            Issue.record("the unveiled text's ink is \(String(describing: unveiled[0].ink))")
            return
        }
        // At the alpha the colour carries, which is a byte: 128 of 255.
        let ink = try #require(
            Color.rgb(0, 0, 200).opacity(
                OpacityRegion.opacity(of: veil.alpha), over: .rgb(UInt8(red), UInt8(green), UInt8(blue))
            ).rgbComponents)
        #expect(row.prefix(5).map(\.glyph) == ["h", "e", "l", "l", "o"])
        #expect(
            row[0].ink == .rgb(Int(ink.red), Int(ink.green), Int(ink.blue)),
            "h is in \(String(describing: row[0].ink))")
    }
}
