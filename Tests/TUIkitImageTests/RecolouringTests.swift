//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RecolouringTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// The half of the renderer that is about the PICTURE rather than about
/// choosing a character for it — the half a terminal drawing real pixels
/// wants, and the reason both renderings of one picture agree about what the
/// picture is.
@Suite("Recolouring, without glyphs")
struct RecolouringTests {

    /// A four-pixel image: two colours, one of them transparent.
    private func swatch() -> RGBAImage {
        RGBAImage(
            width: 2, height: 2,
            pixels: [
                RGBA(r: 200, g: 30, b: 40, a: 255),
                RGBA(r: 20, g: 180, b: 60, a: 128),
                RGBA(r: 40, g: 50, b: 220, a: 255),
                RGBA(r: 240, g: 240, b: 240, a: 255),
            ])
    }

    @Test("True colour is the picture, resampled and nothing else")
    func trueColourIsAPassThrough() {
        let converter = ASCIIConverter(colorMode: .trueColor)
        let out = converter.recoloured(swatch(), width: 2, height: 2)
        #expect(out.width == 2 && out.height == 2)
        #expect(out.pixel(at: 0, 0) == swatch().pixel(at: 0, 0))
    }

    @Test("Greyscale flattens the hues and keeps the alpha")
    func greyscaleKeepsAlpha() {
        let out = ASCIIConverter(colorMode: .grayscale).recoloured(swatch(), width: 2, height: 2)
        for pixel in out.pixels {
            #expect(pixel.r == pixel.g && pixel.g == pixel.b, "grey has no hue")
        }
        #expect(out.pixel(at: 1, 0).a == 128, "and transparency survives the quantiser")
    }

    /// The recolouring stage the tone curve is: what a TONE becomes.
    @Test("A tone curve is applied")
    func toneCurveApplies() {
        let plain = ASCIIConverter(colorMode: .trueColor).recoloured(swatch(), width: 2, height: 2)
        let inverted = ASCIIConverter(colorMode: .trueColor, toneCurve: .inverted)
            .recoloured(swatch(), width: 2, height: 2)
        #expect(plain.pixels != inverted.pixels)
    }

    @Test("Edge contrast changes the picture")
    func edgeContrastApplies() {
        let flat = ASCIIConverter(colorMode: .trueColor).recoloured(swatch(), width: 8, height: 8)
        let lifted = ASCIIConverter(colorMode: .trueColor, edgeContrast: 0.9)
            .recoloured(swatch(), width: 8, height: 8)
        #expect(flat.pixels != lifted.pixels)
    }

    /// Dithering only means anything against a quantiser, which is the same
    /// gate the glyph path applies.
    @Test("Dithering separates two renders that quantise")
    func ditheringApplies() {
        let plain = ASCIIConverter(colorMode: .ansi16).recoloured(swatch(), width: 8, height: 8)
        let dithered = ASCIIConverter(colorMode: .ansi16, dithering: .floydSteinberg)
            .recoloured(swatch(), width: 8, height: 8)
        #expect(plain.pixels != dithered.pixels)
    }

    /// The glyph half is not consulted, so asking for a different charset — or
    /// shape matching, or supersampling — produces the same picture. This is
    /// what lets `Image` leave those out of the signature it re-transmits on.
    @Test("The glyph settings change nothing")
    func glyphSettingsAreNotConsulted() {
        let reference = ASCIIConverter(colorMode: .trueColor)
            .recoloured(swatch(), width: 8, height: 8)
        for converter in [
            ASCIIConverter(characterSet: .blocks(.braille), colorMode: .trueColor),
            ASCIIConverter(shapeAware: true, colorMode: .trueColor),
            ASCIIConverter(colorMode: .trueColor, supersampling: 4),
            ASCIIConverter(colorMode: .trueColor, edgeThreshold: 0.4),
        ] {
            #expect(converter.recoloured(swatch(), width: 8, height: 8).pixels == reference.pixels)
        }
    }

    /// The colour-depth ladder exists because SGR cannot express more than the
    /// terminal has. A transmitted image is not SGR, so a request for true
    /// colour survives a 256-colour terminal here where the glyph path would
    /// cap it.
    @Test("The colour depth cap does not apply to real pixels")
    func depthCapDoesNotApply() {
        ColorDepth.withCap(.palette256) {
            let out = ASCIIConverter(colorMode: .trueColor).recoloured(swatch(), width: 2, height: 2)
            #expect(out.pixel(at: 0, 0) == swatch().pixel(at: 0, 0), "not quantised to 256")
        }
    }

    @Test("A non-positive size produces nothing rather than trapping")
    func degenerateSizesAreEmpty() {
        let converter = ASCIIConverter(colorMode: .trueColor)
        #expect(converter.recoloured(swatch(), width: 0, height: 4).pixels.isEmpty)
        #expect(converter.recoloured(swatch(), width: 4, height: -1).pixels.isEmpty)
    }
}

/// Mono is the one mode whose colours pixels cannot inherit.
@Suite("Mono has to be given its colours")
struct MonoRecolouringTests {

    private func swatch() -> RGBAImage {
        RGBAImage(
            width: 2, height: 2,
            pixels: [
                RGBA(r: 250, g: 250, b: 250), RGBA(r: 10, g: 10, b: 10),
                RGBA(r: 200, g: 200, b: 200), RGBA(r: 30, g: 30, b: 30),
            ])
    }

    /// The character renderer emits no colour for mono and lets the page's
    /// showing through do the work. Pixels have nothing to show through, so
    /// with no colours named this is black and white — which is what mono
    /// means with no theme in the conversation.
    @Test("Unnamed, mono is black and white")
    func defaultsToBlackAndWhite() {
        let out = ASCIIConverter(colorMode: .mono).recoloured(swatch(), width: 2, height: 2)
        for pixel in out.pixels {
            #expect(
                (pixel.r == 0 && pixel.g == 0 && pixel.b == 0)
                    || (pixel.r == 255 && pixel.g == 255 && pixel.b == 255))
        }
    }

    /// …and named, it is those two colours and no others. This is the bug: a
    /// themed mono image drew in black and white whatever the theme said,
    /// because nothing was telling the pixels what mono meant.
    @Test("Named, mono is exactly the two colours it was given")
    func paintsTheNamedColours() {
        let ink = RGBA(r: 0, g: 220, b: 90)
        let paper = RGBA(r: 12, g: 20, b: 12)
        let out = ASCIIConverter(colorMode: .mono)
            .recoloured(swatch(), width: 2, height: 2, monoInk: ink, monoPaper: paper)
        let seen = Set(out.pixels.map { [$0.r, $0.g, $0.b] })
        #expect(seen.isSubset(of: [[0, 220, 90], [12, 20, 12]]), "saw \(seen)")
        #expect(seen.count == 2, "and both of them — the split still splits")
    }

    /// The pattern a mono dither produces is the same whichever two colours it
    /// is finally drawn in, which is why the recolouring happens after it.
    @Test("A dithered mono image is recoloured too, and keeps its pattern")
    func ditheredMonoIsRecoloured() {
        var ramp: [RGBA] = []
        for index in 0..<64 {
            let level = UInt8(index * 4)
            ramp.append(RGBA(r: level, g: level, b: level))
        }
        let bigger = RGBAImage(width: 8, height: 8, pixels: ramp)
        let converter = ASCIIConverter(colorMode: .mono, dithering: .floydSteinberg)
        let plain = converter.recoloured(bigger, width: 8, height: 8)
        let painted = converter.recoloured(
            bigger, width: 8, height: 8,
            monoInk: RGBA(r: 0, g: 220, b: 90), monoPaper: RGBA(r: 12, g: 20, b: 12))
        // Same decision per pixel, different two colours.
        let plainInk = plain.pixels.map { $0.r == 255 }
        let paintedInk = painted.pixels.map { $0.g == 220 }
        #expect(plainInk == paintedInk)
        let greens = Set(painted.pixels.map { $0.g })
        #expect(greens.isSubset(of: [220, 20]))
    }

    /// Only mono. Every other mode names its own colours, and substituting
    /// there would be inventing them.
    @Test("No other mode is touched by the mono colours")
    func onlyMonoIsAffected() {
        for mode in [ASCIIColorMode.trueColor, .grayscale, .ansi16, .ansi256] {
            let converter = ASCIIConverter(colorMode: mode)
            let plain = converter.recoloured(swatch(), width: 2, height: 2)
            let named = converter.recoloured(
                swatch(), width: 2, height: 2,
                monoInk: RGBA(r: 0, g: 220, b: 90), monoPaper: RGBA(r: 12, g: 20, b: 12))
            #expect(plain.pixels == named.pixels, "\(mode) moved")
        }
    }
}
