//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RGBAImageScalingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage

/// The resamplers, and the channel one of them was quietly throwing away.
@Suite("Image scaling keeps every channel")
struct RGBAImageScalingTests {

    /// A 2x2 image whose top-left pixel is fully transparent.
    private func cornerCutout() -> RGBAImage {
        RGBAImage(
            width: 2, height: 2,
            pixels: [
                RGBA(r: 10, g: 20, b: 30, a: 0),
                RGBA(r: 10, g: 20, b: 30, a: 255),
                RGBA(r: 10, g: 20, b: 30, a: 255),
                RGBA(r: 10, g: 20, b: 30, a: 255),
            ])
    }

    /// `scaledBilinear` interpolated red, green and blue and then built its
    /// pixel with `RGBA(r:g:b:)`, whose alpha defaults to opaque — so every
    /// transparent picture it touched came out solid.
    ///
    /// Nothing noticed while its only consumers read luminance or RGB to pick
    /// a glyph. A renderer that hands the pixels to the TERMINAL notices at
    /// once, because the terminal is what composites them over the page.
    @Test("Bilinear scaling carries alpha")
    func bilinearKeepsAlpha() {
        let scaled = cornerCutout().scaledBilinear(to: 4, 4)
        #expect(scaled.pixel(at: 0, 0).a == 0, "the transparent corner is still transparent")
        #expect(scaled.pixel(at: 3, 3).a == 255, "and the opaque one is still opaque")
        #expect(
            scaled.pixels.contains { $0.a > 0 && $0.a < 255 },
            "and the edge between them is interpolated, not stepped")
    }

    /// The other two resamplers already did this; the test is here so a future
    /// edit to any of the three fails in the same place.
    @Test("The other resamplers carry it too")
    func siblingsKeepAlpha() {
        #expect(cornerCutout().scaled(to: 4, 4).pixel(at: 0, 0).a == 0, "nearest neighbour")
        let reduced = RGBAImage(
            width: 2, height: 2,
            pixels: [RGBA](repeating: RGBA(r: 1, g: 2, b: 3, a: 0), count: 4)
        ).boxReduced(by: 2)
        #expect(reduced.pixel(at: 0, 0).a == 0, "box reduction")
    }

    /// Colour is unchanged by the fix — the interpolation that was already
    /// there still is.
    @Test("Colour interpolation is unchanged")
    func colourStillInterpolates() {
        let ramp = RGBAImage(
            width: 2, height: 1,
            pixels: [RGBA(r: 0, g: 0, b: 0), RGBA(r: 255, g: 255, b: 255)])
        let scaled = ramp.scaledBilinear(to: 4, 1)
        #expect(scaled.pixel(at: 0, 0).r == 0)
        #expect(scaled.pixel(at: 3, 0).r > 0)
        #expect(scaled.pixels.allSatisfy { $0.a == 255 }, "an opaque image stays opaque")
    }
}
