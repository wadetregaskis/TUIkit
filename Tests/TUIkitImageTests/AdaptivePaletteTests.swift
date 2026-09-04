//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AdaptivePaletteTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// What "N colours" ought to mean, and the three answers.
///
/// ``ASCIIPalette/spread(_:)`` covers the GAMUT and knows nothing about the
/// picture, which is why turning its dial can change nothing: a photograph
/// occupies a small part of the gamut, so entries land where it has no pixels.
/// ``ASCIIPalette/adaptive(_:by:)`` asks the picture — by popularity, which
/// ranks, or by least error, which optimises.
@Suite("Adaptive palettes")
struct AdaptivePaletteTests {

    /// A synthetic picture shaped like the problem: a big, gently graded,
    /// near-neutral field that fills most of the frame in many slightly
    /// different shades — which is what a photograph is mostly made of and what
    /// a popularity ranking spends itself on — plus a small saturated red patch
    /// that matters far more to the eye than to the histogram.
    ///
    /// The grade matters as much as the patch: a picture of five flat colours
    /// has five colours to find, and both adaptations find them, so it could
    /// not tell the two apart.
    private static func subject(width: Int = 96, height: Int = 96) -> RGBAImage {
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                if y >= height - 9 && x >= width - 9 {
                    pixels.append(RGBA(r: 230, g: 30, b: 30))  // ~1% of the picture
                } else {
                    let shade = UInt8(clamping: 40 + (x * 180) / width)
                    let cool = UInt8(clamping: Int(shade) + 6 + (y * 24) / height)
                    pixels.append(RGBA(r: shade, g: shade, b: cool))
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// The mean OKLab distance from every pixel to the entry it maps to — the
    /// quantity `.leastError` exists to minimise, and the one a person reads as
    /// "how wrong does this look".
    private static func error(_ palette: ASCIIPalette, on image: RGBAImage) -> Double {
        var total = 0.0
        for pixel in image.pixels {
            let entry = palette.rgba(at: palette.nearestIndex(to: pixel))
            total += ASCIIPalette.distanceSquared(
                Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b),
                Color.oklab(red: entry.r, green: entry.g, blue: entry.b)
            ).squareRoot()
        }
        return total / Double(image.pixels.count)
    }

    // MARK: - The request, and the answer

    @Test("An underived adaptive palette stands in as greys rather than as nothing")
    func standsInBeforeItMeetsAnImage() {
        let palette = ASCIIPalette.adaptive(6, by: .leastError)
        #expect(palette.colors.count == 6)
        #expect(palette.colors == ASCIIPalette.shades(6).colors)
    }

    @Test("Deriving answers with the picture's own colours, and only once")
    func derivationIsIdempotent() {
        let image = Self.subject()
        let derived = ASCIIPalette.adaptive(6, by: .leastError).derived(from: image)
        #expect(derived.colors.count == 6)
        #expect(derived.colors != ASCIIPalette.shades(6).colors, "still the stand-in")
        // The result is an ORDINARY palette: nothing downstream can tell it was
        // ever a question, and asking again changes nothing.
        #expect(derived.derived(from: Self.subject(width: 20, height: 20)).colors == derived.colors)
    }

    @Test("A palette that was never a question is untouched by deriving")
    func fixedPalettesAreInert() {
        let fixed = ASCIIPalette([.rgb(1, 2, 3), .rgb(4, 5, 6)])
        #expect(fixed.derived(from: Self.subject()).colors == fixed.colors)
        #expect(ASCIIPalette.spread(8).derived(from: Self.subject()).colors
            == ASCIIPalette.spread(8).colors)
    }

    @Test("The same picture always answers the same palette")
    func derivationIsDeterministic() {
        let image = Self.subject()
        for method in ASCIIPalette.Adaptation.allCases {
            let first = ASCIIPalette.adaptive(8, by: method).derived(from: image)
            let second = ASCIIPalette.adaptive(8, by: method).derived(from: image)
            #expect(first.colors == second.colors, "\(method) is not deterministic")
        }
    }

    // MARK: - The two adaptations differ, and in the stated direction

    @Test("Least error beats popularity, and both beat the gamut spread")
    func leastErrorIsLeastError() {
        let image = Self.subject()
        for count in [4, 8, 16] {
            let spread = Self.error(ASCIIPalette.spread(count), on: image)
            let popular = Self.error(
                ASCIIPalette.adaptive(count, by: .popularity).derived(from: image), on: image)
            let optimal = Self.error(
                ASCIIPalette.adaptive(count, by: .leastError).derived(from: image), on: image)
            #expect(optimal < popular, "\(count): least error \(optimal) ≥ popularity \(popular)")
            #expect(popular < spread, "\(count): popularity \(popular) ≥ spread \(spread)")
        }
    }

    /// The red is ~1% of the pixels and nothing like anything else in the
    /// picture.
    private func reachesTheRed(_ palette: ASCIIPalette) -> Bool {
        palette.colors.contains { colour in
            guard let rgb = colour.rgbComponents else { return false }
            return rgb.red > 150 && rgb.green < 110 && rgb.blue < 110
        }
    }

    @Test("A ranking never reaches the small red; an optimiser does, once it is worth it")
    func theTwoAdaptationsPartOnTheSubject() {
        let image = Self.subject()
        // A graded field has more populous cells than the patch all the way up,
        // so a RANKING cannot reach it however many entries it is given.
        for count in [8, 16, 24] {
            #expect(
                !reachesTheRed(ASCIIPalette.adaptive(count, by: .popularity).derived(from: image)),
                "popularity found the red at \(count), so the fixture stopped showing the split")
        }
        // The optimiser does — but not until the field is served well enough
        // that the patch is the biggest thing left wrong.
        #expect(reachesTheRed(ASCIIPalette.adaptive(12, by: .leastError).derived(from: image)))
    }

    /// The assertion that says `.leastError` is OPTIMISING rather than missing.
    ///
    /// At eight colours it drops the red, which looks like the failure everyone
    /// expects of a least-squares quantiser. It is not: putting the red back
    /// costs more total error than the entry it displaces. The palette is right
    /// and the intuition is wrong, and the only way to tell those apart is to
    /// price the alternative.
    @Test("Where least error drops the red, keeping it would be worse")
    func droppingTheRedIsTheOptimum() {
        let image = Self.subject()
        let derived = ASCIIPalette.adaptive(8, by: .leastError).derived(from: image)
        #expect(!reachesTheRed(derived), "it kept the red, so there is nothing to price")
        var forced = derived.colors
        forced[forced.count - 1] = .rgb(230, 30, 30)
        let cost = Self.error(ASCIIPalette(forced), on: image)
        let chosen = Self.error(derived, on: image)
        #expect(cost > chosen, "forcing the red in was cheaper (\(cost) vs \(chosen))")
    }

    // MARK: - The dial does something at every step

    /// The complaint this feature answers: `.spread(_:)` has steps that change
    /// nothing at all, because it never looks at the picture.
    @Test("Every step of an adaptive count changes the palette")
    func everyStepCounts() {
        let image = Self.subject()
        for method in ASCIIPalette.Adaptation.allCases {
            var previous = ASCIIPalette.adaptive(2, by: method).derived(from: image).colors
            for count in 3...24 {
                let now = ASCIIPalette.adaptive(count, by: method).derived(from: image).colors
                #expect(now.count == count, "\(method) at \(count) answered \(now.count)")
                #expect(Set(now) != Set(previous), "\(method): \(count) is \(count - 1) again")
                previous = now
            }
        }
    }

    @Test("The converter derives from the picture it will draw, curve and all")
    func theConverterDerivesAfterTheToneCurve() {
        // A negative moves every colour in the picture. Deriving before it would
        // pick the palette of a picture nobody sees, and every pixel would then
        // map to the nearest of eight colours the render does not contain.
        let image = Self.subject()
        let converter = ASCIIConverter(
            colorMode: .palette(.adaptive(8, by: .leastError)), toneCurve: .init(.inverted))
        let drawn = converter.recoloured(image, width: 30, height: 30)
        let plain = ASCIIConverter(colorMode: .palette(.adaptive(8, by: .leastError)))
            .recoloured(image, width: 30, height: 30)
        #expect(drawn.pixels != plain.pixels, "the curve made no difference")
        // Every drawn pixel is one of the eight the INVERTED picture asked for.
        let expected = Set(
            ASCIIPalette.adaptive(8, by: .leastError)
                .derived(from: ASCIIConverter(colorMode: .trueColor, toneCurve: .init(.inverted))
                    .recoloured(image, width: 30, height: 30))
                .colors.compactMap(\.rgbComponents)
                .map { Int($0.red) << 16 | Int($0.green) << 8 | Int($0.blue) })
        let drawnColours = Set(drawn.pixels.map { Int($0.r) << 16 | Int($0.g) << 8 | Int($0.b) })
        #expect(drawnColours.isSubset(of: expected), "drew a colour the palette does not hold")
    }
}
