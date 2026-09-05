//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DitheringAlphaTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage

/// Error diffusion rebuilds every neighbour it touches, and a rebuilt pixel
/// whose alpha was left to default is an opaque one. The pixel renderer hands
/// dithered pixels to the terminal, which composites them over the page — so
/// a transparent picture dithered to a palette came out solid.
@Suite("Dithering keeps alpha")
struct DitheringAlphaTests {

    /// A checkerboard of colour on a transparent field, so the error reaches
    /// transparent pixels from every direction.
    private static func subject() -> RGBAImage {
        var pixels: [RGBA] = []
        for y in 0..<16 {
            for x in 0..<16 {
                if (x + y).isMultiple(of: 3) {
                    pixels.append(RGBA(r: 200, g: 60, b: 90, a: 255))
                } else {
                    pixels.append(RGBA(r: 0, g: 0, b: 0, a: 0))
                }
            }
        }
        return RGBAImage(width: 16, height: 16, pixels: pixels)
    }

    @Test("A transparent pixel stays transparent after the error of its neighbours reaches it")
    func errorDiffusionKeepsAlpha() {
        let image = Self.subject()
        let converter = ASCIIConverter(colorMode: .ansi16, dithering: .floydSteinberg)
        let dithered = converter.applyFloydSteinbergDithering(image, mode: .ansi16, monoThreshold: 128)
        for (before, after) in zip(image.pixels, dithered.pixels) {
            #expect(after.a == before.a)
        }
        #expect(dithered.pixels.contains { $0.a == 0 }, "the field is still transparent")
    }

    @Test("The recoloured pixels a graphics terminal is handed keep their alpha under dithering")
    func recolouredKeepsAlpha() {
        let image = Self.subject()
        let converter = ASCIIConverter(colorMode: .ansi16, dithering: .floydSteinberg)
        let recoloured = converter.recoloured(image, width: 16, height: 16)
        #expect(recoloured.pixels.contains { $0.a == 0 })
        #expect(recoloured.pixels.allSatisfy { $0.a == 0 || $0.a == 255 })
    }

    @Test("addError itself keeps the alpha it was handed")
    func addErrorKeepsAlpha() {
        var image = RGBAImage(width: 1, height: 1, pixels: [RGBA(r: 10, g: 10, b: 10, a: 7)])
        image.addError(at: 0, 0, rError: 5, gError: 5, bError: 5)
        #expect(image.pixel(at: 0, 0) == RGBA(r: 15, g: 15, b: 15, a: 7))
    }
}
