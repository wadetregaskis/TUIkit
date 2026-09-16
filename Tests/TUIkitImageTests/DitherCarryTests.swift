//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DitherCarryTests.swift
//
//  Error diffusion keeps a region's average where it was by handing each
//  pixel's shortfall to its neighbours — which assumes the neighbours can make
//  it up. A grey palette cannot make up a blue, and carrying the blue anyway
//  pinned a channel at 255 and lifted the lightness of everything after it:
//  a haze beside every dark shape. A chosen palette now carries its error in
//  OKLab, boxed to what its entries span. These pin the lightness a dither
//  keeps, the runaway it no longer has, and the terminal palettes it leaves
//  byte-for-byte alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("Dither carry")
struct DitherCarryTests {

    private static func flat(_ pixel: RGBA, width: Int = 120, height: Int = 60) -> [RGBA] {
        [RGBA](repeating: pixel, count: width * height)
    }

    /// Mean OKLab lightness — the quantity a dither over a chosen palette is
    /// asked to keep.
    private static func meanLightness(_ pixels: [RGBA]) -> Double {
        pixels.reduce(0.0) { $0 + Color.oklab(red: $1.r, green: $1.g, blue: $1.b).l } / Double(pixels.count)
    }

    /// The threshold defaults to the mid-luminance split the binary renderers
    /// fall back to; every mode here but `.mono` ignores it entirely.
    private static func dithered(
        _ pixels: [RGBA], mode: ASCIIColorMode, width: Int = 120, height: Int = 60,
        monoThreshold: Double = ASCIIConverter.midLuminance
    ) -> [RGBA] {
        var out = pixels
        PixelQuantiser(mode: mode, monoThreshold: monoThreshold, table: nil)
            .dither(&out, width: width, height: height)
        return out
    }

    private static func mapped(_ pixels: [RGBA], mode: ASCIIColorMode) -> [RGBA] {
        var out = pixels
        PixelQuantiser(mode: mode, monoThreshold: 0.5, table: nil).apply(to: &out)
        return out
    }

    /// The demo's "Ice": eight blues, no red anywhere in it.
    private static let ice = ASCIIPalette([
        .palette256(17), .palette256(18), .palette256(25), .palette256(31),
        .palette256(38), .palette256(45), .palette256(123), .palette256(195),
    ])

    /// A dark blue through greys: before, the carried blue pinned at 255 and
    /// the greys chosen after it were far too light — 34 levels over the
    /// plain mapping's grey on this field.
    @Test("A colour through a grey palette dithers to the grey of its own lightness")
    func greysKeepLightness() {
        let source = Self.flat(RGBA(r: 20, g: 40, b: 120))
        let mode = ASCIIColorMode.palette(.shades(134))
        let plain = Self.meanLightness(Self.mapped(source, mode: mode))
        let dither = Self.meanLightness(Self.dithered(source, mode: mode))
        #expect(abs(dither - plain) < 0.02, "dithered L \(dither) against the plain mapping's \(plain)")
        #expect(abs(dither - Self.meanLightness(source)) < 0.03, "and against the source's \(Self.meanLightness(source))")
        #expect(
            Self.dithered(source, mode: mode).allSatisfy { $0.r == $0.g && $0.g == $0.b },
            "every dithered pixel is a grey")
    }

    /// A red through a palette of blues: the red the palette cannot reach
    /// stops at the palette's edge instead of piling up, and the lightness —
    /// which it can — is kept.
    @Test("A hue the palette lacks is not carried past the palette's edge")
    func chromaStopsAtThePalettesEdge() {
        let source = Self.flat(RGBA(r: 200, g: 30, b: 30))
        let mode = ASCIIColorMode.palette(Self.ice)
        let dither = Self.meanLightness(Self.dithered(source, mode: mode))
        #expect(abs(dither - Self.meanLightness(source)) < 0.06, "dithered L \(dither) against the source's \(Self.meanLightness(source))")
    }

    /// The dark blue the demo picture is mostly made of, through the same
    /// palette: before, +96 levels of luminance over the plain mapping.
    @Test("A dark colour through a small palette keeps its lightness")
    func darkColourKeepsLightness() {
        let source = Self.flat(RGBA(r: 20, g: 40, b: 120))
        let mode = ASCIIColorMode.palette(Self.ice)
        let dither = Self.meanLightness(Self.dithered(source, mode: mode))
        #expect(abs(dither - Self.meanLightness(source)) < 0.04, "dithered L \(dither) against the source's \(Self.meanLightness(source))")
    }

    @Test("The OKLab carry keeps each pixel's alpha")
    func alphaSurvives() {
        var source = Self.flat(RGBA(r: 90, g: 60, b: 30))
        source[7].a = 0
        source[8].a = 128
        let out = Self.dithered(source, mode: .palette(Self.ice))
        #expect(out[7].a == 0)
        #expect(out[8].a == 128)
        #expect(out[9].a == 255)
    }

    /// A grey ramp has no more chroma than a grey palette does. Before, a flat
    /// saturated red dithered to grey 59 and then 76 for every pixel after it
    /// — the red pinned at 255 and the two negative errors were discarded at 0
    /// — so eight identical source pixels drew 237, 239, 239, … out of the
    /// 24-step ramp, 17 levels lighter than the same field undithered.
    @Test("A grey ramp carries no chroma")
    func greyRampCarriesNoChroma() {
        let source = Self.flat(RGBA(r: 200, g: 0, b: 0), width: 8, height: 2)
        let out = Self.dithered(source, mode: .grayscale, width: 8, height: 2)
        #expect(out.allSatisfy { $0 == RGBA(r: 59, g: 59, b: 59) }, "\(Array(out.prefix(8)))")
        // The neutral part of a grey's error is under one level, so there is
        // nothing an integer buffer can carry: the dither IS the mapping.
        #expect(out == Self.mapped(source, mode: .grayscale))
    }

    /// The same rule through `.mono`, where the pinning destroyed the error
    /// rather than merely lightening it: that field's luminance is 59.8, so
    /// 23% of it is ink at a threshold of 128 — and all 1024 pixels came out
    /// paper, because the error went into red, pinned, and stopped the
    /// accumulation at luminance 106.
    @Test("A mono dither carries luminance, not chroma")
    func monoCarriesLuminance() {
        let source = Self.flat(RGBA(r: 200, g: 0, b: 0), width: 32, height: 32)
        let out = Self.dithered(source, mode: .mono, width: 32, height: 32)
        let ink = out.count(where: { $0.r == 255 })
        #expect(ink > 0, "a field of luminance 59.8 drew as solid paper")
        let density = Double(ink) / Double(out.count)
        #expect(abs(density - 59.8 / 255) < 0.02, "ink density \(density), expected about 0.234 (240 of 1024)")
        #expect(out.allSatisfy { $0.r == $0.g && $0.g == $0.b }, "every mono pixel is black or white")
    }

    /// The terminal's own palettes span the gamut, so nothing there needed
    /// boxing — and their dither is the sRGB carry it always was. A pinned
    /// sample: the first row of a two-colour field through the sixteen.
    @Test("The terminal's palettes keep the sRGB carry")
    func terminalPalettesUnchanged() {
        var source = Self.flat(RGBA(r: 120, g: 60, b: 200), width: 8, height: 2)
        source[3] = RGBA(r: 10, g: 250, b: 90)
        let sixteen = Self.dithered(source, mode: .ansi16, width: 8, height: 2)
        // Recorded from the path before the OKLab carry existed; the harness
        // checksums say the path is unchanged, and this says so per pixel.
        let expected: [RGBA] = [
            RGBA(r: 92, g: 92, b: 255), RGBA(r: 205, g: 0, b: 205), RGBA(r: 92, g: 92, b: 255),
            RGBA(r: 0, g: 255, b: 0), RGBA(r: 92, g: 92, b: 255), RGBA(r: 205, g: 0, b: 205),
            RGBA(r: 92, g: 92, b: 255), RGBA(r: 92, g: 92, b: 255),
        ]
        #expect(Array(sixteen.prefix(8)) == expected, "\(sixteen.prefix(8))")
    }
}
