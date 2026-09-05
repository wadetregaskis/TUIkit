//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AdaptivePaletteDepthTests.swift
//
//  An adaptive palette chooses its colours AFTER the colour mode has been
//  fitted to the terminal, so the fit has to run again on what it chose. It
//  did not: the picture's own colours went out as `38;2;r;g;b` on a
//  256-colour terminal, which Terminal.app reads as five separate SGR codes —
//  a channel value of 5 is blink, 30–37 the named colours — and "Most used"
//  drew as blinking primaries.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("Adaptive palettes at the terminal's depth")
struct AdaptivePaletteDepthTests {

    /// A picture with more distinct colours than any small palette holds, so
    /// the derived palette is not a handful of greys: a hue wheel over a
    /// brightness ramp.
    private static func subject(width: Int = 64, height: Int = 32) -> RGBAImage {
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let level = 40 + (y * 200) / height
                let hue = x.quotientAndRemainder(dividingBy: 3).remainder
                pixels.append(
                    RGBA(
                        r: UInt8(clamping: (hue == 0 ? level : 0) + x * 2),
                        g: UInt8(clamping: (hue == 1 ? level : 0) + y * 3),
                        b: UInt8(clamping: (hue == 2 ? level : 0) + (x + y))))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private static func sequences(in lines: [String], _ marker: String) -> Int {
        lines.joined().components(separatedBy: marker).count - 1
    }

    @Test(
        "A derived palette on a 256-colour terminal is spelt as indexes, never as triples",
        arguments: [ASCIIPalette.Adaptation.popularity, .leastError])
    func derivedPaletteIsFittedToPalette256(method: ASCIIPalette.Adaptation) {
        let lines = ColorDepth.withCurrent(.palette256) {
            ASCIIConverter(colorMode: .palette(.adaptive(64, by: method)))
                .convert(Self.subject(), width: 40, height: 12)
        }
        #expect(Self.sequences(in: lines, "[38;2;") == 0, "truecolor foregrounds on a 256-colour terminal")
        #expect(Self.sequences(in: lines, "[48;2;") == 0, "truecolor backgrounds on a 256-colour terminal")
        #expect(Self.sequences(in: lines, ";5;") > 0, "and the picture is drawn in indexed colour")
    }

    @Test("A derived palette on a 16-colour terminal is spelt as the sixteen names")
    func derivedPaletteIsFittedToBasic16() {
        let lines = ColorDepth.withCurrent(.basic16) {
            ASCIIConverter(colorMode: .palette(.adaptive(64, by: .popularity)))
                .convert(Self.subject(), width: 40, height: 12)
        }
        #expect(Self.sequences(in: lines, "[38;2;") == 0)
        #expect(Self.sequences(in: lines, ";5;") == 0, "no 256-colour indexes on a 16-colour terminal")
    }

    @Test("A truecolor terminal keeps the picture's own colours")
    func truecolorKeepsTriples() {
        let lines = ColorDepth.withCurrent(.truecolor) {
            ASCIIConverter(colorMode: .palette(.adaptive(64, by: .popularity)))
                .convert(Self.subject(), width: 40, height: 12)
        }
        #expect(Self.sequences(in: lines, "[38;2;") + Self.sequences(in: lines, "[48;2;") > 0)
    }
}
