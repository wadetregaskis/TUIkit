//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GreyRampBandTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// `.grayscale` is documented as 24 shades. Scaling luminance by 23 and
/// truncating gave 23 of them an 11-value band and the top one — #eeeeee —
/// exactly one input, pure white: every highlight clipped a step dark.
@Suite("Grey ramp bands")
struct GreyRampBandTests {

    @Test("Each of the 24 greys owns an equal slice of the luminance range")
    func bandsAreEqual() {
        let converter = ASCIIConverter(colorMode: .grayscale)
        var counts: [String: Int] = [:]
        for value in 0...255 {
            let pixel = RGBA(r: UInt8(value), g: UInt8(value), b: UInt8(value))
            counts[converter.foregroundColorCode(for: pixel, mode: .grayscale), default: 0] += 1
            #expect(
                converter.backgroundColorCode(for: pixel, mode: .grayscale).contains(
                    converter.foregroundColorCode(for: pixel, mode: .grayscale).dropFirst(5)),
                "the background copy agrees with the foreground: \(value)")
        }
        #expect(counts.count == 24)
        #expect(counts.values.max()! - counts.values.min()! <= 1, "\(counts.values.sorted())")
    }

    /// A grey in `.ansi256` takes the nearest grey the terminal HAS — which is
    /// not only the 24-step ramp.
    ///
    /// The ramp used to be the whole answer here: a near-grey pixel was matched
    /// against 8, 18, … 238 and nothing else. But the 6×6×6 cube has six greys
    /// of its own — 0, 95, 135, 175, 215, 255 — and four of them fall between
    /// ramp steps, so `(92,92,92)` is three units from the cube's `(95,95,95)`
    /// and four from the ramp's `(88,88,88)`. Searching the terminal's whole
    /// 256 rather than one strip of it finds them, which is one of the things
    /// that made the picture and the page beside it disagree.
    ///
    /// Stated as the property rather than as a table of answers: for a neutral
    /// pixel the hue and chroma terms of the metric are zero on every grey
    /// candidate, so "nearest" reduces to nearest in OKLab lightness, and the
    /// test can say exactly that. See ``ASCIIPalette/ansi256``.
    @Test("An ansi256 grey takes the nearest grey the terminal has")
    func ansi256GreysTakeTheNearestGrey() {
        let converter = ASCIIConverter(colorMode: .ansi256)
        let greys: [(index: Int, lightness: Double)] = (16...255).compactMap { index in
            let rgb = Color.palette256ToRGB(UInt8(index))
            guard rgb.red == rgb.green, rgb.green == rgb.blue else { return nil }
            return (index, Color.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue).l)
        }
        #expect(greys.count == 30, "24 ramp steps and the cube's six")

        for value in 0...255 {
            let level = UInt8(value)
            let lightness = Color.oklab(red: level, green: level, blue: level).l
            let nearest = greys.map { abs($0.lightness - lightness) }.min() ?? .infinity
            let code = converter.foregroundColorCode(
                for: RGBA(r: level, g: level, b: level), mode: .ansi256)
            let chosen = greys.first { code.contains("38;5;\($0.index)m") }
            // The DISTANCE, not the index. Level 1 sits exactly halfway between
            // black and the ramp's (8,8,8) — OKLab lightness is a cube root, so
            // `l(8)` is precisely twice `l(1)` — and which of two entries an
            // exact tie lands on is decided by the last bit of a `cbrt`, not by
            // anything this test has an opinion about.
            #expect(
                abs((chosen?.lightness ?? .infinity) - lightness) - nearest < 1e-12,
                "\(value) → \(code), \(nearest) away at best")
        }
    }

    /// Two answers worth naming, because both look wrong until the reason is
    /// said out loud.
    @Test("Where the cube's greys and sRGB's toe change the answer")
    func ansi256GreyLandmarks() {
        let converter = ASCIIConverter(colorMode: .ansi256)
        func index(_ level: UInt8) -> String {
            converter.foregroundColorCode(for: RGBA(r: level, g: level, b: level), mode: .ansi256)
        }
        // The cube's (95,95,95), not the ramp's (88,88,88) — three away rather
        // than four, and the ramp-only search could not see it.
        #expect(index(92).contains("38;5;59m"))
        // (8,8,8), not black. Six bytes above black and two above the input,
        // but sRGB's transfer function is steep in the shadows: in OKLab
        // lightness, (2,2,2) is nearer (8,8,8) than it is (0,0,0).
        #expect(index(2).contains("38;5;232m"))
        // Every exact ramp entry is still itself.
        for step in 0..<24 {
            let entry = UInt8(8 + 10 * step)
            #expect(index(entry).contains("38;5;\(232 + step)m"), "the entry \(entry) is itself")
        }
    }

    @Test("A near-white highlight reaches the top grey")
    func highlightReachesTheTop() {
        let converter = ASCIIConverter(colorMode: .grayscale)
        #expect(converter.foregroundColorCode(for: RGBA(r: 250, g: 250, b: 250), mode: .grayscale).contains("38;5;255"))
        #expect(converter.foregroundColorCode(for: RGBA(r: 255, g: 255, b: 255), mode: .grayscale).contains("38;5;255"))
        #expect(converter.foregroundColorCode(for: RGBA(r: 0, g: 0, b: 0), mode: .grayscale).contains("38;5;232"))
    }

    /// The same invariant `ImageQuantiserRuleTests` pins for `.ansi256` — what a
    /// picture is transmitted as is what the cell beside it would be painted —
    /// for the other mode whose cells are `38;5;n`. It was never checked for
    /// `.grayscale`, and `.grayscale` was the mode that broke it: the pixel path
    /// sent raw luminance, so 246 of the 256 neutral levels arrived as a
    /// different grey from their glyph, by up to 17 of 255.
    ///
    /// Driven through `recoloured` rather than the quantiser, because that is the
    /// stage `_ImageCore` calls and the stage the posterisation lives in — the
    /// quantiser deliberately still answers luminance, so the glyph path's own
    /// emitter is the only thing that bands.
    @Test("A transmitted grey is the grey its cell would have been painted")
    func transmittedGreyMatchesTheCellsGrey() throws {
        let converter = ASCIIConverter(colorMode: .grayscale)
        let ramp = RGBAImage(
            width: 16, height: 16,
            pixels: (0..<256).map { RGBA(r: UInt8($0), g: UInt8($0), b: UInt8($0)) })
        let drawn = converter.recoloured(ramp, width: 16, height: 16)

        for value in 0...255 {
            let pixel = RGBA(r: UInt8(value), g: UInt8(value), b: UInt8(value))
            let colour = try #require(converter.cellColor(for: pixel, mode: .grayscale))
            guard case .palette256(let index) = colour.value else {
                Issue.record("level \(value) named \(colour), which is not a ramp entry")
                continue
            }
            let painted = Color.palette256ToRGB(index)
            let transmitted = drawn.pixels[value]
            #expect(transmitted.r == painted.red, "level \(value) → 38;5;\(index)")
            #expect(transmitted.g == painted.green, "level \(value) → 38;5;\(index)")
            #expect(transmitted.b == painted.blue, "level \(value) → 38;5;\(index)")
        }
    }

    /// …and the whole picture, stated as the set it is allowed to be: the ramp's
    /// 24 greys, which reach neither black nor white.
    @Test("A transmitted greyscale picture holds only the ramp's 24 greys")
    func recolouredHoldsOnlyRampGreys() {
        let ramp = RGBAImage(
            width: 16, height: 16,
            pixels: (0..<256).map { RGBA(r: UInt8($0), g: UInt8($0), b: UInt8($0)) })
        let drawn = ASCIIConverter(colorMode: .grayscale).recoloured(ramp, width: 16, height: 16)
        let steps = Set((0..<24).map { UInt8(8 + 10 * $0) })
        let levels = Set(drawn.pixels.map(\.r))
        #expect(levels.isSubset(of: steps), "not the terminal's ramp: \(levels.sorted())")
        #expect(!levels.contains(0), "the ramp's darkest is #080808, not black")
        #expect(!levels.contains(255), "and its lightest is #eeeeee, not white")
    }
}
