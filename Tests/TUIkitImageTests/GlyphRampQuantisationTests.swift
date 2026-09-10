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
        let out = converter.convert(gradient(width: 60, height: 4), width: 30, height: 2).lines
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
        let out = converter.convert(bright, width: 4, height: 2).lines
        #expect(
            distinctGlyphs(out) == [ramp[3]],
            "luminance 240 lands in the top band of 4: |\(out)| vs ramp \(ramp)")
    }

    @Test("Bands are equal: a 2-glyph ramp splits a gradient near the midpoint")
    func equalBands() {
        let converter = ASCIIConverter(
            characterSet: .ascii(glyphs: 2), colorMode: .mono, supersampling: 1)
        let out = converter.convert(gradient(width: 64, height: 2), width: 32, height: 1).lines
        let line = plain(out[0])
        let darkCells = line.prefix(while: { $0 == " " }).count
        #expect((14...18).contains(darkCells), "≈half the gradient is the dark level: |\(line)|")
    }

    // MARK: - The block-eighths ramp

    /// How much of its cell each block eighth inks, in eighths.
    private static let eighths: [Character: Int] = [
        "▏": 1, "▎": 2, "▍": 3, "▌": 4, "▋": 5, "▊": 6, "▉": 7, "█": 8,
        "▁": 1, "▂": 2, "▃": 3, "▄": 4, "▅": 5, "▆": 6, "▇": 7,
    ]

    @Test(".blocks(.ramp) stylises rather than reproduces tone")
    func blockRampIsStylised() {
        let converter = ASCIIConverter(
            characterSet: .blocks(.ramp), colorMode: .mono, supersampling: 1)
        let line = plain(converter.convert(gradient(width: 120, height: 2), width: 60, height: 1).lines[0])
        let coverage = line.compactMap { Self.eighths[$0] }
        #expect(coverage.count == line.count, "every glyph is a block eighth: |\(line)|")

        // The glyphs are in code point order — the bottom eighths filling up
        // to █, then the left eighths emptying back down to ▏ — so across a
        // black → white gradient ink rises to full at the middle and falls
        // away, painting highlights as fine vertical rules. Interleaving the
        // two families would make this monotone and faithful; the style is
        // chosen for the effect, so a "fix" that sorts by ink fails here.
        let peak = coverage.firstIndex(of: 8)
        #expect(peak != nil, "the ramp reaches full ink: \(coverage)")
        #expect(coverage.first == 1 && coverage.last == 1,
                "both ends are an eighth of ink: \(coverage)")
        if let peak {
            let rise = coverage[..<peak], fall = coverage[peak...]
            #expect(zip(rise, rise.dropFirst()).allSatisfy { $0 <= $1 },
                    "ink rises to the peak: \(Array(rise))")
            #expect(zip(fall, fall.dropFirst()).allSatisfy { $0 >= $1 },
                    "ink falls away after it: \(Array(fall))")
            #expect(peak > 0 && peak < coverage.count - 1, "the peak is interior: \(peak)")
        }
    }

    @Test(".blocks(.ramp) offers more levels than .coarse")
    func blockRampIsFinerThanCoarse() {
        func levels(_ set: ASCIICharacterSet) -> Int {
            let converter = ASCIIConverter(characterSet: set, colorMode: .mono, supersampling: 1)
            return distinctGlyphs(converter.convert(gradient(width: 120, height: 2),
                                                    width: 60, height: 1).lines).count
        }
        #expect(levels(.blocks(.ramp)) > levels(.blocks(.coarse)))
    }
}

// MARK: - Edge tracing without shape matching

/// Edge tracing and shape matching are orthogonal: one asks where the picture
/// has an edge, the other how a cell's ink is chosen. Edge tracing used to be
/// reachable only through the shape renderer, because the gradient was taken
/// from the six regions that renderer sampled inside each cell. The luminance
/// renderer takes it from the eight cells around each one instead.
@Suite("Edge tracing is independent of shape matching")
struct LuminanceEdgeTracingTests {

    /// A dark square on a light field: four clean edges and four corners.
    private func box(width: Int, height: Int) -> RGBAImage {
        var pixels: [RGBA] = []
        for y in 0..<height {
            for x in 0..<width {
                let inside = x > width / 4 && x < 3 * width / 4
                    && y > height / 4 && y < 3 * height / 4
                pixels.append(inside ? RGBA(r: 10, g: 10, b: 10) : RGBA(r: 245, g: 245, b: 245))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func render(shapeAware: Bool, edgeThreshold: Double?) -> String {
        let converter = ASCIIConverter(
            characterSet: .unicode(glyphs: 8), shapeAware: shapeAware, colorMode: .mono,
            supersampling: 1, edgeThreshold: edgeThreshold)
        return converter.convert(box(width: 60, height: 60), width: 24, height: 12).lines
            .joined(separator: "\n")
            .replacing(/\u{1B}\[[0-9;]*[A-Za-z]/, with: "")
    }

    /// The box-drawing line glyphs `.unicode` traces edges with.
    private static let lines: Set<Character> = ["─", "│", "╲", "╱"]

    @Test("The luminance renderer traces edges")
    func luminanceTracesEdges() {
        let traced = render(shapeAware: false, edgeThreshold: 0.9)
        #expect(traced.contains { Self.lines.contains($0) }, "no line glyphs: \(traced)")
        // Both axes and both diagonals: a box has all four, and a renderer
        // that only ever emitted one of them would still pass the check above.
        for glyph in Self.lines {
            #expect(traced.contains(glyph), "no \(glyph) around a box: \(traced)")
        }
    }

    @Test("…and does not when the threshold is nil")
    func luminanceWithoutEdgesDrawsNoLines() {
        let plain = render(shapeAware: false, edgeThreshold: nil)
        #expect(!plain.contains { Self.lines.contains($0) }, "traced with edges off: \(plain)")
    }

    @Test("The shape renderer still traces edges too")
    func shapeStillTracesEdges() {
        let traced = render(shapeAware: true, edgeThreshold: 0.9)
        #expect(traced.contains { Self.lines.contains($0) }, "no line glyphs: \(traced)")
    }

    @Test("A lower threshold traces at least as many edges")
    func lowerThresholdTracesMore() {
        func lineCount(_ threshold: Double) -> Int {
            render(shapeAware: false, edgeThreshold: threshold).count { Self.lines.contains($0) }
        }
        #expect(lineCount(0.4) >= lineCount(1.6))
        #expect(lineCount(0.4) > 0)
    }
}
