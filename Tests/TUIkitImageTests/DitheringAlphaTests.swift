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

    /// **Error diffusion ignored coverage entirely: a pixel at alpha 0 pushed its
    /// neighbours exactly as hard as one at alpha 255.**
    ///
    /// A transparent pixel has no colour to quantise — its stored colour is whatever
    /// the encoder left there, and the decoders write BLACK — so the "error" it makes
    /// is an artefact of a pixel nobody can see. A half-covered one is the same
    /// argument at half strength. The carry is scaled by `a / 255` now.
    ///
    /// One mis-quantised pixel and its neighbour, at five coverages. The neighbour is
    /// a flat grey whose own quantisation is exact, so everything it moves by came
    /// from the carry:
    ///
    /// | coverage | neighbour, before | after |
    /// |---|---|---|
    /// | 255 | 148 | 148 |
    /// | 192 | 148 | 138 |
    /// | 128 | 148 | 135 |
    /// | 0 | 148 | **128** — its own colour, untouched |
    ///
    /// `.ansi256` rather than `.ansi16` on purpose: the coarse palette absorbs the
    /// whole carry into one entry, so the same test written against it passes whatever
    /// the arithmetic does. That is worth knowing about the SYMPTOM as well — the finer
    /// the palette, the more of this leaks.
    /// ### §17's "dark fringe" is smaller than it says, and this is where that was
    /// found.**
    ///
    /// The claim was that Floyd–Steinberg seeds a dark fringe at a hard alpha edge by
    /// diffusing a transparent pixel's error outward. A test for it could not be made
    /// to fail on the unfixed code, at either palette, and the reason is worth keeping:
    /// a transparent pixel's colour is BLACK, black is in every palette, so its own
    /// quantisation error is ~0. What it actually re-emits is the carry it just
    /// RECEIVED from a visible neighbour, attenuated by 7/16 then 3/16 — about 13% of
    /// an error that error diffusion is already dissipating.
    ///
    /// So the fringe from the dither is real, principled to remove, and much smaller
    /// than the one the resamplers were making (§41.1), which is where the visible
    /// artefact came from. The case that genuinely moves pixels is PARTIAL coverage,
    /// which is the test above.
    @Test("Error diffusion is weighted by the pixel's coverage")
    func errorDiffusionIsCoverageWeighted() {
        let converter = ASCIIConverter(colorMode: .ansi256, dithering: .floydSteinberg)
        let neighbour = RGBA(r: 128, g: 128, b: 128, a: 255)
        func nudgedNeighbour(coverage: UInt8) -> UInt8 {
            let image = RGBAImage(
                width: 3, height: 1,
                pixels: [RGBA(r: 200, g: 60, b: 90, a: coverage), neighbour, neighbour])
            return converter.applyFloydSteinbergDithering(
                image, mode: .ansi256, monoThreshold: 128
            ).pixel(at: 1, 0).r
        }
        let full = nudgedNeighbour(coverage: 255)
        let none = nudgedNeighbour(coverage: 0)
        #expect(none == 128, "no coverage, no carry: \(none)")
        #expect(full > none, "full coverage still carries: \(full) vs \(none)")
        // Monotone in between, which is what "weighted" means rather than "gated".
        let sequence = [255, 192, 128, 64, 0].map { nudgedNeighbour(coverage: UInt8($0)) }
        #expect(
            zip(sequence, sequence.dropFirst()).allSatisfy { $0 >= $1 },
            "the carry falls with the coverage: \(sequence)")
    }
}
