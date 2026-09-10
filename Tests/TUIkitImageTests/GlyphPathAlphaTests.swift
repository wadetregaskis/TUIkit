//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlyphPathAlphaTests.swift
//
//  §17's last open item: the glyph path composited over BLACK unconditionally,
//  so a logo with a transparent surround rendered as an explicit black
//  rectangle. It carries coverage now — §42.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("The glyph path carries coverage")
struct GlyphPathAlphaTests {

    /// A 4×4 opaque red square in the middle of an 8×8 transparent field.
    private static func logo(coverage: UInt8 = 255) -> RGBAImage {
        var pixels: [RGBA] = []
        for y in 0..<8 {
            for x in 0..<8 {
                let inside = (2..<6).contains(x) && (2..<6).contains(y)
                pixels.append(
                    inside
                        ? RGBA(r: 220, g: 40, b: 40, a: coverage)
                        : RGBA(r: 0, g: 0, b: 0, a: 0))
            }
        }
        return RGBAImage(width: 8, height: 8, pixels: pixels)
    }

    private func converter(_ set: ASCIICharacterSet = .blocks(.fine)) -> ASCIIConverter {
        ASCIIConverter(characterSet: set, shapeAware: false, colorMode: .trueColor)
    }

    // MARK: - The black rectangle

    /// **The default charset, and the case §17 named.**
    ///
    /// `.blocks(.fine)` paints a background in every cell, so a transparent surround
    /// composited over black was an explicit black rectangle: invisible on a dark
    /// theme, glaring on a light one. A cell with no coverage at either half now states
    /// no colour at all, which is what "nothing is here" means in a cell grid — the
    /// compositor leaves the cell behind it exactly as it was.
    @Test("A transparent surround states no colour at all")
    func transparentSurroundIsBlank() throws {
        let art = ColorDepth.withCurrent(.truecolor) {
            converter().convert(Self.logo(), width: 8, height: 4)
        }
        #expect(art.lines.count == 4)
        // Row 0 is entirely outside the square: no SGR at all, and nothing but spaces.
        let top = try #require(art.lines.first)
        #expect(!top.contains("\u{1B}"), "an untouched row emits no escapes: \(top.debugDescription)")
        #expect(top.allSatisfy { $0 == " " }, "\(top.debugDescription)")
        // And specifically not a black background, which is what it used to be.
        #expect(!art.lines.joined().contains("48;2;0;0;0"), "the black rectangle is gone")
    }

    /// The square itself must still be drawn, in its own colour — the fix is about the
    /// surround, and a test that only checked the surround would pass on a blank image.
    @Test("The covered cells still paint their colour")
    func coveredCellsStillPaint() {
        let art = ColorDepth.withCurrent(.truecolor) {
            converter().convert(Self.logo(), width: 8, height: 4)
        }
        #expect(art.lines.joined().contains("220;40;40"), "\(art.lines)")
        // An opaque logo owes no claim: coverage is 255 or 0, and 0 states no colour
        // rather than a faded one.
        #expect(art.coverage.isEmpty, "\(art.coverage)")
    }

    /// A HALF-covered square keeps its colour at full strength and reports what it was
    /// drawn at — the claim/bytes pairing, one module down from where the rest of the
    /// framework does it.
    @Test("Partial coverage keeps the colour and reports the coverage")
    func partialCoverageIsReported() {
        let art = ColorDepth.withCurrent(.truecolor) {
            converter().convert(Self.logo(coverage: 128), width: 8, height: 4)
        }
        #expect(art.lines.joined().contains("220;40;40"), "the colour is not dimmed: \(art.lines)")
        #expect(!art.coverage.isEmpty, "\(art.coverage)")
        // Both halves of a covered cell are the same pixel colour at the same coverage,
        // so the cell collapses to a space on a background — a FIELD claim.
        #expect(
            art.coverage.allSatisfy { $0.field == 128 && $0.ink == .max },
            "\(art.coverage)")
    }

    /// Runs, not cells. An image's alpha is mostly large uniform areas, and the claim
    /// count is what the resolver pays per covered row.
    @Test("Coverage coalesces into runs")
    func coverageCoalesces() {
        let art = ColorDepth.withCurrent(.truecolor) {
            converter().convert(Self.logo(coverage: 128), width: 8, height: 4)
        }
        // Two lines of the 4×4 square, four cells each, and each line is ONE run.
        #expect(art.coverage.count == 2, "\(art.coverage)")
        #expect(art.coverage.allSatisfy { $0.columns.count == 4 }, "\(art.coverage)")
    }

    // MARK: - The half-block cell's two halves

    /// **A half-block cell paints its two halves from DIFFERENT pixels**, so one can be
    /// there and the other not. The renderer only ever had `▄`-over-a-background,
    /// because the flatten meant every cell had both halves; the upper-half glyph is
    /// what a cell whose bottom pixel is absent actually needs.
    @Test("A cell with only its top half covered flips to the upper block")
    func topHalfOnlyFlipsTheGlyph() throws {
        // One cell: top pixel covered, bottom transparent.
        let image = RGBAImage(
            width: 1, height: 2,
            pixels: [RGBA(r: 10, g: 200, b: 90), RGBA(r: 0, g: 0, b: 0, a: 0)])
        let art = ColorDepth.withCurrent(.truecolor) {
            converter().convert(image, width: 1, height: 1)
        }
        let line = try #require(art.lines.first)
        #expect(line.contains("▀"), "the upper half block: \(line.debugDescription)")
        #expect(line.contains("38;2;10;200;90"), "in the top pixel's colour: \(line.debugDescription)")
        #expect(!line.contains("48;2"), "and over no background at all: \(line.debugDescription)")
    }

    @Test("A cell with only its bottom half covered keeps the lower block")
    func bottomHalfOnlyKeepsTheGlyph() throws {
        let image = RGBAImage(
            width: 1, height: 2,
            pixels: [RGBA(r: 0, g: 0, b: 0, a: 0), RGBA(r: 10, g: 200, b: 90)])
        let art = ColorDepth.withCurrent(.truecolor) {
            converter().convert(image, width: 1, height: 1)
        }
        let line = try #require(art.lines.first)
        #expect(line.contains("▄"), "\(line.debugDescription)")
        #expect(!line.contains("48;2"), "no background: \(line.debugDescription)")
    }

    /// **The uniform-cell optimisation gains an alpha term, and it had to.**
    ///
    /// Two pixels of one colour are emitted as a SPACE with only a background — 86.5% of
    /// a photograph's cells at sixteen colours, and load-bearing for the Warp
    /// contrast-lift banding. But two pixels of one colour at DIFFERENT coverages are
    /// not one field: collapsed to a single background, the cell would resolve at one of
    /// the two and the other half would be wrong.
    @Test("Two same-coloured pixels at different coverages do not collapse")
    func differentCoveragesDoNotCollapse() throws {
        let image = RGBAImage(
            width: 1, height: 2,
            pixels: [
                RGBA(r: 10, g: 200, b: 90, a: 255), RGBA(r: 10, g: 200, b: 90, a: 128),
            ])
        let art = ColorDepth.withCurrent(.truecolor) {
            converter().convert(image, width: 1, height: 1)
        }
        let line = try #require(art.lines.first)
        #expect(line.contains("▄"), "a glyph, not a space: \(line.debugDescription)")
        let run = try #require(art.coverage.first)
        #expect(run.field == 255 && run.ink == 128, "\(run)")
        // And the same colour at the SAME coverage still collapses, or the optimisation
        // is gone rather than corrected.
        let uniform = RGBAImage(
            width: 1, height: 2,
            pixels: [RGBA(r: 10, g: 200, b: 90, a: 128), RGBA(r: 10, g: 200, b: 90, a: 128)])
        let collapsed = ColorDepth.withCurrent(.truecolor) {
            converter().convert(uniform, width: 1, height: 1)
        }
        #expect(!(collapsed.lines.first ?? "").contains("▄"), "\(collapsed.lines)")
    }

    // MARK: - The other charsets

    /// A ramp paints ink and no field, so its transparent cells are spaces in no
    /// colour. Without the coverage test the flatten's removal would have let a
    /// transparent surround draw whatever the encoder left in those pixels.
    @Test("A ramp draws nothing where there is no coverage")
    func rampSkipsTransparentCells() throws {
        // Transparent pixels carrying a BRIGHT colour, which is what would have picked
        // the densest glyph: the decoders write black, but nothing guarantees it.
        var pixels = [RGBA](repeating: RGBA(r: 255, g: 255, b: 255, a: 0), count: 16)
        pixels[5] = RGBA(r: 255, g: 255, b: 255, a: 255)
        let art = ColorDepth.withCurrent(.truecolor) {
            converter(.ascii(glyphs: 4)).convert(
                RGBAImage(width: 4, height: 4, pixels: pixels), width: 4, height: 4)
        }
        // Three of the four rows never touch the covered pixel, and a row that painted
        // nothing emits no escapes at all.
        let untouched = art.lines.filter { !$0.contains("\u{1B}") }
        #expect(untouched.count == 3, "\(art.lines.map(\.debugDescription))")
        #expect(untouched.allSatisfy { $0.allSatisfy { $0 == " " } }, "\(untouched)")
        #expect(art.coverage.isEmpty, "opaque ink and no field: \(art.coverage)")
    }

    /// Braille lights a dot only where the pixel is THERE — the ½ rule §6a states for
    /// every glyph decision. A transparent dot used to light itself from whatever colour
    /// the encoder left in it.
    @Test("Braille lights no dot without coverage")
    func brailleNeedsCoverage() throws {
        let bright = [RGBA](repeating: RGBA(r: 255, g: 255, b: 255, a: 0), count: 8)
        let art = ColorDepth.withCurrent(.truecolor) {
            converter(.blocks(.braille)).convert(
                RGBAImage(width: 2, height: 4, pixels: bright), width: 1, height: 1)
        }
        let line = try #require(art.lines.first)
        #expect(line.contains("\u{2800}"), "the empty braille cell: \(line.debugDescription)")
    }

    /// Mono paints no colours at all, so coverage reaches it only as a glyph decision:
    /// a pixel that is not there cannot be ink.
    @Test("Mono treats an uncovered pixel as blank whatever its colour")
    func monoNeedsCoverage() {
        #expect(
            !ASCIIConverter.isMonoInk(RGBA(r: 255, g: 255, b: 255, a: 0), threshold: 128),
            "a transparent white pixel is not ink")
        #expect(
            ASCIIConverter.isMonoInk(RGBA(r: 255, g: 255, b: 255, a: 255), threshold: 128))
        #expect(
            !ASCIIConverter.isMonoInk(RGBA(r: 255, g: 255, b: 255, a: 127), threshold: 128),
            "below half coverage the destination keeps its cell")
    }
}
