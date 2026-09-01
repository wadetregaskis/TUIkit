//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlyphRampQuantisationTests.swift
//
//  Regression tests for the luminance → density-ramp mapping. The converter
//  scaled luminance by `ramp.count - 1` and truncated, so a ramp's TOP glyph
//  was reachable only at luminance exactly 255: imperceptible on the full
//  ~15-level ASCII ramp, but a small `glyphs:` count starved of its brightest
//  levels — `.ascii(glyphs: 2)` rendered virtually every pixel as its dark
//  level (the space), i.e. a blank image (the "Glyphs: 2 renders nothing"
//  report). The mapping is equal luminance bands, one per ramp level.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage

@Suite("Glyph ramp quantisation")
struct GlyphRampQuantisationTests {

    /// A full black → white horizontal gradient, one row per output line.
    private func gradient(width: Int, height: Int) -> RGBAImage {
        var pixels: [RGBA] = []
        for _ in 0..<height {
            for x in 0..<width {
                let v = UInt8(min(255, x * 255 / max(1, width - 1)))
                pixels.append(RGBA(r: v, g: v, b: v))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Strips CSI escape sequences (mono output should carry none, but the
    /// tests must not depend on that).
    private func plain(_ text: String) -> String {
        text.replacing(/\u{1B}\[[0-9;]*[A-Za-z]/, with: "")
    }

    private func distinctGlyphs(_ lines: [String]) -> Set<Character> {
        Set(plain(lines.joined()))
    }

    @Test("A 2-glyph ramp renders BOTH its levels across a full gradient", arguments: [2, 3, 5])
    func smallRampUsesEveryLevel(count: Int) {
        let converter = ASCIIConverter(
            characterSet: .ascii(glyphs: count), colorMode: .mono, supersampling: 1)
        let out = converter.convert(gradient(width: 60, height: 4), width: 30, height: 2)
        let used = distinctGlyphs(out)
        #expect(
            used.count == count,
            "every ramp level appears across a full gradient: got \(used.sorted()) for glyphs:\(count)")
    }

    @Test("The top ramp glyph is reachable below pure white")
    func topLevelReachableBelowPureWhite() {
        // A uniform bright-but-not-white image must use the ramp's brightest
        // glyph — under the old `count - 1` truncation only luminance 255
        // reached it.
        let bright = RGBAImage(
            width: 8, height: 4,
            pixels: Array(repeating: RGBA(r: 240, g: 240, b: 240), count: 32))
        let ramp = GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii, count: 4)
        let converter = ASCIIConverter(
            characterSet: .ascii(glyphs: 4), colorMode: .mono, supersampling: 1)
        let out = converter.convert(bright, width: 4, height: 2)
        #expect(
            distinctGlyphs(out) == [ramp[3]],
            "luminance 240 lands in the top band of 4: |\(out)| vs ramp \(ramp)")
    }

    @Test("Bands are equal: a 2-glyph ramp splits a gradient near the midpoint")
    func equalBands() {
        let converter = ASCIIConverter(
            characterSet: .ascii(glyphs: 2), colorMode: .mono, supersampling: 1)
        let out = converter.convert(gradient(width: 64, height: 2), width: 32, height: 1)
        let line = plain(out[0])
        let darkCells = line.prefix(while: { $0 == " " }).count
        #expect((14...18).contains(darkCells), "≈half the gradient is the dark level: |\(line)|")
    }

    // MARK: - The block-eighths ramp

    /// How much of its cell each block eighth inks, in eighths. A luminance
    /// ramp is only a ramp if this never goes backwards along it.
    private static let eighths: [Character: Int] = [
        "▏": 1, "▎": 2, "▍": 3, "▌": 4, "▋": 5, "▊": 6, "▉": 7, "█": 8,
        "▁": 1, "▂": 2, "▃": 3, "▄": 4, "▅": 5, "▆": 6, "▇": 7,
    ]

    @Test(".blocks(.ramp) never gets darker as the image gets brighter")
    func blockRampIsMonotoneInInk() {
        let converter = ASCIIConverter(
            characterSet: .blocks(.ramp), colorMode: .mono, supersampling: 1)
        let line = plain(converter.convert(gradient(width: 120, height: 2), width: 60, height: 1)[0])
        let coverage = line.compactMap { Self.eighths[$0] }
        #expect(coverage.count == line.count, "every glyph is a block eighth: |\(line)|")
        // Listed in code point order the eighths run ▁▂▃▄▅▆▇█▉▊▋▌▍▎▏, whose
        // coverage rises to full and falls back to an eighth; used as a ramp
        // that paints the BRIGHTEST pixels with the thinnest glyphs. This is
        // the property that ordering by ink buys, and the only one that
        // distinguishes the two orderings.
        #expect(zip(coverage, coverage.dropFirst()).allSatisfy { $0 <= $1 },
                "coverage never decreases across a black → white gradient: \(coverage)")
        #expect(coverage.first == 1 && coverage.last == 8, "both ends are reached: \(coverage)")
    }

    @Test(".blocks(.ramp) offers more levels than .coarse")
    func blockRampIsFinerThanCoarse() {
        func levels(_ set: ASCIICharacterSet) -> Int {
            let converter = ASCIIConverter(characterSet: set, colorMode: .mono, supersampling: 1)
            return distinctGlyphs(converter.convert(gradient(width: 120, height: 2),
                                                    width: 60, height: 1)).count
        }
        #expect(levels(.blocks(.ramp)) > levels(.blocks(.coarse)))
    }
}
