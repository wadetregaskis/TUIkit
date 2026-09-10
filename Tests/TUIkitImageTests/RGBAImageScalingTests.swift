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

    /// Both resamplers guarded the TARGET size and never the source. A 0x0
    /// source (which a decode can return as a success, and which `scaled(to:
    /// 0, 0)` produces) then indexed an empty array in `scaled(to:)` and read
    /// `source[-1]` through an unsafe buffer in `scaledBilinear`.
    @Test("An empty source scales to an empty image instead of trapping")
    func emptySourceScales() {
        let sources = [
            RGBAImage(width: 0, height: 0, pixels: []),
            RGBAImage(width: 3, height: 0, pixels: []),
            RGBAImage(width: 0, height: 2, pixels: []),
        ]
        for source in sources {
            #expect(source.scaled(to: 4, 4).pixels.isEmpty, "\(source.width)x\(source.height)")
            #expect(source.scaledBilinear(to: 4, 4).pixels.isEmpty, "\(source.width)x\(source.height)")
            #expect(source.boxReduced(by: 2).pixels.isEmpty, "\(source.width)x\(source.height)")
        }
    }

    /// Straight RGBA cannot be filtered channel-wise: the decoder writes a
    /// transparent pixel as BLACK, and it got full weight, so a soft edge
    /// pulled its opaque neighbour toward black — a dark fringe on every PNG
    /// with a transparent surround, on a terminal that composites pixels.
    @Test("A soft edge keeps its colour: the filter is premultiplied")
    func softEdgeKeepsItsColour() {
        let source = RGBAImage(
            width: 2, height: 1,
            pixels: [RGBA(r: 255, g: 0, b: 0, a: 255), RGBA(r: 0, g: 0, b: 0, a: 0)])
        let out = source.scaledBilinear(to: 4, 1)
        let edge = out.pixel(at: 1, 0)
        #expect(edge.r == 255 && edge.g == 0 && edge.b == 0, "\(edge)")
        #expect(edge.a == 128, "\(edge)")
        // A fully transparent sample has no colour to keep and does not trap.
        #expect(out.pixel(at: 3, 0).a == 0)
        // Opaque pictures are byte-identical to the plain filter.
        let opaque = RGBAImage(
            width: 2, height: 1, pixels: [RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 0, b: 255)])
        let mid = opaque.scaledBilinear(to: 4, 1).pixel(at: 1, 0)
        #expect(mid.r == 128 && mid.b == 128 && mid.a == 255, "\(mid)")
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

    /// **`boxReduced` averaged straight colour and alpha independently.**
    ///
    /// `scaledBilinear` premultiplies and says at its own loop exactly why: a
    /// transparent pixel's colour is meaningless, the decoder writes it BLACK, and
    /// giving it full weight pulls its opaque neighbours toward black. The box
    /// reduction is the third resampler and had the same hole — benign only because
    /// `ASCIIConverter` flattened over black *before* calling it, so every alpha it
    /// ever saw was 255. §41.
    ///
    /// Half a block of white at full coverage and half at none: the answer is WHITE at
    /// half coverage. Averaged independently it is GREY at half coverage, which is a
    /// dark halo around every soft edge.
    @Test("A box reduction averages colour by coverage, not beside it")
    func boxReductionIsAlphaWeighted() {
        let opaque = RGBA(r: 255, g: 255, b: 255, a: 255)
        let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
        let reduced = RGBAImage(
            width: 2, height: 2, pixels: [opaque, clear, opaque, clear]
        ).boxReduced(by: 2)
        let pixel = reduced.pixel(at: 0, 0)
        #expect(pixel.a == 127, "half coverage: \(pixel)")
        #expect(
            (pixel.r, pixel.g, pixel.b) == (255, 255, 255),
            "the white survives its transparent neighbours: \(pixel)")
    }

    /// And an OPAQUE block must come out byte-identical to what the unweighted average
    /// gave, because that is what every image in the pipeline is today: with every
    /// coverage equal the weights cancel, integer division included, so the fix cannot
    /// have moved a single existing pixel.
    @Test("An opaque box reduction is byte-identical to the plain average")
    func opaqueBoxReductionIsUnchanged() {
        let values: [UInt8] = [10, 20, 33, 44, 200, 201, 202, 203, 7, 8, 9, 250, 1, 2, 3, 4]
        let source = RGBAImage(
            width: 4, height: 4, pixels: values.map { RGBA(r: $0, g: $0 / 2, b: $0 / 3) })
        let reduced = source.boxReduced(by: 2)
        for y in 0..<2 {
            for x in 0..<2 {
                var sum = (r: 0, g: 0, b: 0)
                for dy in 0..<2 {
                    for dx in 0..<2 {
                        let p = source.pixel(at: x * 2 + dx, y * 2 + dy)
                        sum = (sum.r + Int(p.r), sum.g + Int(p.g), sum.b + Int(p.b))
                    }
                }
                let got = reduced.pixel(at: x, y)
                #expect(Int(got.r) == sum.r / 4, "\(x),\(y) red: \(got)")
                #expect(Int(got.g) == sum.g / 4, "\(x),\(y) green: \(got)")
                #expect(Int(got.b) == sum.b / 4, "\(x),\(y) blue: \(got)")
                #expect(got.a == 255, "\(x),\(y) alpha: \(got)")
            }
        }
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

/// The fast resampler against a transcription of the one it replaced.
///
/// `scaledBilinear` was rewritten to be call-free — unsafe buffers, concrete
/// `Double(Int(_:))` conversions, the interpolation written out — because at
/// `-Onone` its inner loop made 41 non-inlined calls and about 26 atomic
/// retain/release pairs per output pixel. The claim is that it is bit-exact,
/// and the character renderer's every glyph depends on that being true, so it
/// is checked against the arithmetic it replaced rather than asserted.
@Suite("Resampling is bit-exact")
struct ResamplingEquivalenceTests {

    /// The previous implementation, transcribed: `pixel(at:)` reads, a helper
    /// per channel, and `RGBA(r:g:b:)` — alpha aside, which was the bug.
    private func reference(_ image: RGBAImage, to targetWidth: Int, _ targetHeight: Int)
        -> [RGBA]
    {
        var result = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: targetWidth * targetHeight)
        let xRatio = Double(image.width) / Double(targetWidth)
        let yRatio = Double(image.height) / Double(targetHeight)
        for y in 0..<targetHeight {
            let srcY = Double(y) * yRatio
            let y0 = min(Int(srcY), image.height - 1)
            let y1 = min(y0 + 1, image.height - 1)
            let yFrac = srcY - Double(y0)
            for x in 0..<targetWidth {
                let srcX = Double(x) * xRatio
                let x0 = min(Int(srcX), image.width - 1)
                let x1 = min(x0 + 1, image.width - 1)
                let xFrac = srcX - Double(x0)
                let p00 = image.pixel(at: x0, y0)
                let p10 = image.pixel(at: x1, y0)
                let p01 = image.pixel(at: x0, y1)
                let p11 = image.pixel(at: x1, y1)
                // Premultiplied, in the SAME expression shape as the fast path
                // — this test is "the unsafe-buffer version equals the plain
                // one", and two associations of the same sum can differ in the
                // last bit, which a `.rounded()` on a half turns into a pixel.
                let w00 = (1 - xFrac) * (1 - yFrac)
                let w10 = xFrac * (1 - yFrac)
                let w01 = (1 - xFrac) * yFrac
                let w11 = xFrac * yFrac
                let k00 = w00 * Double(p00.a)
                let k10 = w10 * Double(p10.a)
                let k01 = w01 * Double(p01.a)
                let k11 = w11 * Double(p11.a)
                let alpha = k00 + k10 + k01 + k11
                func channel(_ c00: UInt8, _ c10: UInt8, _ c01: UInt8, _ c11: UInt8) -> Double {
                    alpha > 0
                        ? (Double(c00) * k00 + Double(c10) * k10 + Double(c01) * k01 + Double(c11) * k11) / alpha
                        : 0
                }
                let red = channel(p00.r, p10.r, p01.r, p11.r)
                let green = channel(p00.g, p10.g, p01.g, p11.g)
                let blue = channel(p00.b, p10.b, p01.b, p11.b)
                result[y * targetWidth + x] = RGBA(
                    r: UInt8(clamping: Int(red.rounded())),
                    g: UInt8(clamping: Int(green.rounded())),
                    b: UInt8(clamping: Int(blue.rounded())),
                    a: UInt8(clamping: Int(alpha.rounded())))
            }
        }
        return result
    }

    private func noise(_ width: Int, _ height: Int, seed: UInt64) -> RGBAImage {
        var state = seed | 1
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for _ in 0..<(width * height) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            pixels.append(
                RGBA(
                    r: UInt8(truncatingIfNeeded: state >> 16),
                    g: UInt8(truncatingIfNeeded: state >> 24),
                    b: UInt8(truncatingIfNeeded: state >> 32),
                    a: UInt8(truncatingIfNeeded: state >> 40)))
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Upscales, downscales, non-integer ratios, and the degenerate shapes
    /// where the clamping at the edges is what decides the answer.
    @Test("Every pixel matches the arithmetic it replaced")
    func matchesTheReference() {
        let shapes = [
            (7, 5, 13, 11), (13, 11, 7, 5), (16, 16, 16, 16),
            (1, 9, 5, 3), (9, 1, 3, 5), (2, 2, 31, 29), (31, 29, 2, 2),
            (1, 1, 4, 4), (23, 17, 23, 17),
        ]
        for (index, shape) in shapes.enumerated() {
            let source = noise(shape.0, shape.1, seed: UInt64(index) &* 7919 &+ 3)
            let fast = source.scaledBilinear(to: shape.2, shape.3)
            let slow = reference(source, to: shape.2, shape.3)
            #expect(fast.pixels == slow, "\(shape) diverged")
        }
    }
}
