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
