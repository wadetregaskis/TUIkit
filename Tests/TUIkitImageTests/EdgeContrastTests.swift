//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EdgeContrastTests.swift
//
//  The third of the three independent things an image conversion can be asked:
//  how much separation there is to SEE, as against where the picture has an
//  edge (`edgeThreshold`) and how a cell's ink is chosen (`shapeAware`).
//
//  It is a local lift — an unsharp mask over the render's own pixel grid — so
//  the cases here are about locality: a flat field must not move at all, and a
//  boundary must move on both sides. That is what separates it from a tone
//  curve, which moves every pixel of a given tone wherever it sits.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage

@Suite("Local contrast before glyph selection")
struct EdgeContrastTests {

    /// A grey field with a vertical step in the middle: `left` on the left half,
    /// `right` on the right.
    private func step(width: Int, height: Int, left: UInt8, right: UInt8) -> RGBAImage {
        var pixels: [RGBA] = []
        for _ in 0..<height {
            for x in 0..<width {
                let v = x < width / 2 ? left : right
                pixels.append(RGBA(r: v, g: v, b: v))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func plain(_ text: String) -> String {
        text.replacing(/\u{1B}\[[0-9;]*[A-Za-z]/, with: "")
    }

    // MARK: - The pixels

    /// Every pixel of a flat field IS its own neighbourhood average, so there is
    /// nothing to push it away from. This is the whole difference from a
    /// contrast curve, which would move all of them together.
    @Test("A flat field does not move at all")
    func flatFieldIsUntouched() {
        let flat = step(width: 8, height: 4, left: 120, right: 120)
        let lifted = flat.sharpened(amount: 1.5)
        #expect(lifted.pixels.allSatisfy { $0.r == 120 && $0.g == 120 && $0.b == 120 })
    }

    /// …and a boundary moves on BOTH sides, each away from the other. The two
    /// columns beside the step are what a glyph is chosen from, so widening the
    /// gap between them is the entire point.
    @Test("A step edge gets steeper on both sides")
    func stepEdgeSteepens() {
        let image = step(width: 8, height: 1, left: 100, right: 160)
        let lifted = image.sharpened(amount: 1)
        // x = 3 is the last dark column, x = 4 the first bright one.
        #expect(lifted.pixels[3].r < 100, "the dark side darkened: \(lifted.pixels[3].r)")
        #expect(lifted.pixels[4].r > 160, "the bright side brightened: \(lifted.pixels[4].r)")
        // …and the far ends, two columns clear of the step, are untouched.
        #expect(lifted.pixels[0].r == 100)
        #expect(lifted.pixels[7].r == 160)
    }

    /// Alpha is the picture's own outline rather than anything inside it, so it
    /// is carried through unchanged even where the colour channels move.
    @Test("Alpha is carried through untouched")
    func alphaIsUntouched() {
        var pixels: [RGBA] = []
        for x in 0..<6 {
            pixels.append(RGBA(r: x < 3 ? 40 : 200, g: 0, b: 0, a: UInt8(10 * x)))
        }
        let lifted = RGBAImage(width: 6, height: 1, pixels: pixels).sharpened(amount: 1)
        #expect(lifted.pixels.map(\.a) == pixels.map(\.a))
        #expect(lifted.pixels[2].r != pixels[2].r, "the colour channel did move")
    }

    /// Zero is the identity, and a negative amount is treated as zero rather
    /// than as a blur — the option asks for MORE contrast or none.
    @Test("Zero and below leave the image alone")
    func zeroIsIdentity() {
        let image = step(width: 8, height: 2, left: 30, right: 220)
        #expect(image.sharpened(amount: 0).pixels == image.pixels)
        #expect(image.sharpened(amount: -3).pixels == image.pixels)
    }

    // MARK: - Through the converter

    /// The option reaches the render, and reaches it with NEITHER of the other
    /// two switched on: a plain luminance ramp is chosen from the pixels like
    /// everything else, so it gains separation at the glyph boundaries too.
    ///
    /// This is the case the design turns on. Nesting the control under either of
    /// its neighbours — which is where a reader expecting two options would put
    /// it — would make exactly this configuration unreachable.
    @Test("It changes a plain luminance ramp, with no shape matching and no edge tracing")
    func liftsALuminanceRamp() {
        let image = step(width: 40, height: 20, left: 90, right: 150)
        func render(_ amount: Double) -> [String] {
            ASCIIConverter(
                characterSet: .ascii,
                shapeAware: false,
                colorMode: .mono,
                edgeThreshold: nil,
                edgeContrast: amount
            ).convert(image, width: 20, height: 10).map(plain)
        }
        let flat = render(0)
        let lifted = render(1.5)
        #expect(!flat.isEmpty)
        #expect(lifted != flat, "the lift reached the render:\n\(flat)\nvs\n\(lifted)")
    }

    /// …and it is independent of the other two rather than a rewording of
    /// either: switching it on changes the picture under both of them as well.
    @Test("It is independent of shape matching and of edge tracing")
    func independentOfItsNeighbours() {
        let image = step(width: 40, height: 20, left: 90, right: 150)
        for (shape, threshold) in [(true, nil as Double?), (false, 0.9), (true, 0.9)] {
            func render(_ amount: Double) -> [String] {
                ASCIIConverter(
                    characterSet: .unicode,
                    shapeAware: shape,
                    colorMode: .mono,
                    edgeThreshold: threshold,
                    edgeContrast: amount
                ).convert(image, width: 20, height: 10).map(plain)
            }
            #expect(
                render(1.5) != render(0),
                "shape: \(shape), threshold: \(String(describing: threshold))")
        }
    }
}
