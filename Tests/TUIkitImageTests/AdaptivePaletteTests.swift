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
        let derived = ASCIIPalette.adaptive(6, by: .leastError).derived(from: image, depth: .truecolor)
        #expect(derived.colors.count == 6)
        #expect(derived.colors != ASCIIPalette.shades(6).colors, "still the stand-in")
        // The result is an ORDINARY palette: nothing downstream can tell it was
        // ever a question, and asking again changes nothing.
        #expect(derived.derived(from: Self.subject(width: 20, height: 20), depth: .truecolor).colors == derived.colors)
    }

    @Test("A palette that was never a question is untouched by deriving")
    func fixedPalettesAreInert() {
        let fixed = ASCIIPalette([.rgb(1, 2, 3), .rgb(4, 5, 6)])
        #expect(fixed.derived(from: Self.subject(), depth: .truecolor).colors == fixed.colors)
        #expect(ASCIIPalette.spread(8).derived(from: Self.subject(), depth: .truecolor).colors
            == ASCIIPalette.spread(8).colors)
    }

    @Test("The same picture always answers the same palette")
    func derivationIsDeterministic() {
        let image = Self.subject()
        for method in ASCIIPalette.Adaptation.allCases {
            let first = ASCIIPalette.adaptive(8, by: method).derived(from: image, depth: .truecolor)
            let second = ASCIIPalette.adaptive(8, by: method).derived(from: image, depth: .truecolor)
            #expect(first.colors == second.colors, "\(method) is not deterministic")
        }
    }

    // MARK: - The two adaptations differ, and in the stated direction

    /// At ``ColorDepth/truecolor``, which is the unconstrained derivation — these
    /// three are compared on CONTINUOUS error, and a palette constrained to a
    /// depth is not competing for that. See ``ASCIIPalette/AdaptationTarget`` and
    /// `AdaptationTargetTests`, which prices the constrained ones against each
    /// other.
    @Test("Least error beats popularity, and both beat the gamut spread")
    func leastErrorIsLeastError() {
        let image = Self.subject()
        for count in [4, 8, 16] {
            let spread = Self.error(ASCIIPalette.spread(count), on: image)
            let popular = Self.error(
                ASCIIPalette.adaptive(count, by: .popularity).derived(from: image, depth: .truecolor), on: image)
            let optimal = Self.error(
                ASCIIPalette.adaptive(count, by: .leastError).derived(from: image, depth: .truecolor), on: image)
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
                !reachesTheRed(ASCIIPalette.adaptive(count, by: .popularity).derived(from: image, depth: .truecolor)),
                "popularity found the red at \(count), so the fixture stopped showing the split")
        }
        // The optimiser does — but not until the field is served well enough
        // that the patch is the biggest thing left wrong.
        #expect(reachesTheRed(ASCIIPalette.adaptive(12, by: .leastError).derived(from: image, depth: .truecolor)))
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
        let derived = ASCIIPalette.adaptive(8, by: .leastError).derived(from: image, depth: .truecolor)
        #expect(!reachesTheRed(derived), "it kept the red, so there is nothing to price")
        var forced = derived.colors
        forced[forced.count - 1] = .rgb(230, 30, 30)
        let cost = Self.error(ASCIIPalette(forced), on: image)
        let chosen = Self.error(derived, on: image)
        #expect(cost > chosen, "forcing the red in was cheaper (\(cost) vs \(chosen))")
    }

    // MARK: - The one thing in the derivation that is written twice

    /// `Histogram` spells `ASCIIPalette.quantisationCell(for:)`'s arithmetic
    /// out against a borrowed copy of the bucket table, because calling it is
    /// three `static let` accesses per pixel and it runs once per pixel of a
    /// megapixel. That is a copy of a rule, so this is the test that the copy
    /// still says what the rule says — bucketed by hand, through the function
    /// itself, and compared cell for cell.
    ///
    /// What it pins is the PARTITION — which pixels land together — and not the
    /// index formula, which is the weaker claim and the true one. Measured: swap
    /// the green and blue fields in the copy and this still passes, because a
    /// field swap relabels the cells bijectively and the multiset of buckets is
    /// unchanged (every derived palette is unchanged too, so nothing is hiding
    /// behind it). Drop one bit of blue and it fails 96 times. The partition is
    /// what decides the picture, so that is the thing worth pinning.
    @Test("The histogram buckets exactly where the shared cell arithmetic says")
    func histogramAgreesWithTheSharedCellArithmetic() {
        // Deliberately not a round size, so no dimension divides the cell grid.
        let image = Self.subject(width: 37, height: 23)
        var reference: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        for pixel in image.pixels {
            let cell = ASCIIPalette.quantisationCell(for: pixel)
            var total = reference[cell] ?? (0, 0, 0, 0)
            total.count += 1
            total.red += Int(pixel.r)
            total.green += Int(pixel.g)
            total.blue += Int(pixel.b)
            reference[cell] = total
        }
        let histogram = ASCIIPalette.Histogram(of: image)
        #expect(histogram.buckets.count == reference.count)
        // The buckets come out in cell order, so they walk against the
        // reference's own keys in that order.
        for (bucket, cell) in zip(histogram.buckets, reference.keys.sorted()) {
            guard let total = reference[cell] else { continue }
            #expect(bucket.weight == total.count)
            #expect(
                bucket.rgba
                    == RGBA(
                        r: UInt8(clamping: total.red / total.count),
                        g: UInt8(clamping: total.green / total.count),
                        b: UInt8(clamping: total.blue / total.count)))
        }
    }

    // MARK: - The dial does something at every step

    /// The complaint this feature answers: `.spread(_:)` has steps that change
    /// nothing at all, because it never looks at the picture.
    @Test("Every step of an adaptive count changes the palette")
    func everyStepCounts() {
        let image = Self.subject()
        for method in ASCIIPalette.Adaptation.allCases {
            var previous = ASCIIPalette.adaptive(2, by: method).derived(from: image, depth: .truecolor).colors
            for count in 3...24 {
                let now = ASCIIPalette.adaptive(count, by: method).derived(from: image, depth: .truecolor).colors
                #expect(now.count == count, "\(method) at \(count) answered \(now.count)")
                #expect(Set(now) != Set(previous), "\(method): \(count) is \(count - 1) again")
                previous = now
            }
        }
    }

    // MARK: - An entry that draws nothing is not taking a useful colour's place

    /// `image`'s distinct colours in OKLab, each with how many pixels are it.
    ///
    /// Not the derivation's `Histogram`: its buckets are 5-bit cell MEANS, and
    /// this is the error the pixels themselves see. Summed once per distinct
    /// colour rather than once per pixel, which is the same sum over a fraction
    /// of the walk.
    private static func distinctColours(
        of image: RGBAImage
    ) -> [(lab: (l: Double, a: Double, b: Double), weight: Double)] {
        var weights: [Int: Int] = [:]
        for pixel in image.pixels where pixel.a != 0 {
            weights[Int(pixel.r) << 16 | Int(pixel.g) << 8 | Int(pixel.b), default: 0] += 1
        }
        return weights.sorted { $0.key < $1.key }.map { key, weight in
            (
                Color.oklab(
                    red: UInt8(truncatingIfNeeded: key >> 16), green: UInt8(truncatingIfNeeded: key >> 8),
                    blue: UInt8(truncatingIfNeeded: key)),
                Double(weight)
            )
        }
    }

    /// The counts in `counts` whose `.leastError` palette at `depth` holds an
    /// entry no pixel of `image` is nearest to while a colour of the target's
    /// lattice that the palette does NOT hold would still lower the pixel error.
    ///
    /// An entry that draws nothing is not the fault on its own. Once every lattice
    /// colour some pixel is nearest to is in the palette, the error is as low as
    /// that lattice allows and a larger count has nothing left to draw; those
    /// entries are kept. The fault is an entry drawing nothing while a colour
    /// that would draw something is left out.
    ///
    /// An invariant rather than "each count draws a picture the count below did
    /// not", because WHERE the repeats fall moves with the picture and its size,
    /// and past the ceiling a repeat is the right answer.
    private static func wastedCounts(
        _ image: RGBAImage, depth: ColorDepth, counts: ClosedRange<Int>
    ) -> [String] {
        guard let lattice = ASCIIPalette.representable(at: depth) else {
            Issue.record("\(depth) has no lattice to choose from")
            return []
        }
        let colours = distinctColours(of: image)
        let labs = lattice.entries.indices.map { lattice.labOfEntry($0) }
        var wasted: [String] = []
        for count in counts {
            let palette = ASCIIPalette.adaptive(count, by: .leastError).derived(from: image, depth: depth)
            let chosen = palette.colors.compactMap { lattice.colors.firstIndex(of: $0) }
            guard !chosen.isEmpty, chosen.count == palette.colors.count else {
                Issue.record("\(count): the palette holds a colour the lattice does not")
                continue
            }
            // Each colour's squared distance to the entry it is drawn in, and the
            // entries that draw anything at all.
            var nearest = [Double](repeating: .infinity, count: colours.count)
            var drawing: Set<Int> = []
            for (index, colour) in colours.enumerated() {
                var best = chosen[0]
                for entry in chosen {
                    let distance = ASCIIPalette.distanceSquared(colour.lab, labs[entry])
                    if distance < nearest[index] {
                        nearest[index] = distance
                        best = entry
                    }
                }
                drawing.insert(best)
            }
            let idle = chosen.count - drawing.count
            guard idle > 0 else { continue }
            let held = Set(chosen)
            for candidate in labs.indices where !held.contains(candidate) {
                var gain = 0.0
                for (index, colour) in colours.enumerated() {
                    let distance = ASCIIPalette.distanceSquared(colour.lab, labs[candidate])
                    gain += colour.weight * max(0, nearest[index] - distance)
                }
                if gain > 1e-9 {
                    wasted.append("\(count): \(idle) drawing nothing, while \(lattice.colors[candidate].value) gains \(gain)")
                    break
                }
            }
        }
        return wasted
    }

    /// Reported by the owner at 256 colours: counts that drew the identical
    /// picture, although every step bought a distinct entry
    /// (`AdaptationTargetTests.everyStepBuysAColour`). The extra entries were
    /// colours no pixel is nearest to.
    @Test("At 256 colours a least-error entry draws nothing only when no unused colour would help")
    func noEntryIsWastedAtTwoFiftySix() {
        let wasted = Self.wastedCounts(Self.subject(), depth: .palette256, counts: 10...40)
        #expect(wasted.isEmpty, "\(wasted)")
    }

    @Test("At 16 colours a least-error entry draws nothing only when no unused colour would help")
    func noEntryIsWastedAtSixteen() {
        let wasted = Self.wastedCounts(Self.subject(), depth: .basic16, counts: 3...12)
        #expect(wasted.isEmpty, "\(wasted)")
    }

    /// The owner's own picture, at the size fine blocks sample it for 96×47 cells
    /// (one pixel per half cell). Found by `#filePath`, which the package's other
    /// tests already rely on: the tests run from the checkout.
    @Test("On the Example's demo picture a least-error entry draws nothing only when no unused colour would help")
    func noEntryIsWastedOnTheDemoPicture() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TUIkitImageTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package
            .appendingPathComponent("Sources/Example/Resources/demo-image.jpg").path
        let image = try PlatformImageLoader().loadImage(from: path).scaledBilinear(to: 96, 94)
        let wasted = Self.wastedCounts(image, depth: .palette256, counts: 20...64)
        #expect(wasted.isEmpty, "\(wasted)")
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
                .derived(
                    from: ASCIIConverter(colorMode: .trueColor, toneCurve: .init(.inverted))
                        .recoloured(image, width: 30, height: 30),
                    // The graphics path's own depth: these pixels leave as RGB.
                    depth: .truecolor)
                .colors.compactMap(\.rgbComponents)
                .map { Int($0.red) << 16 | Int($0.green) << 8 | Int($0.blue) })
        let drawnColours = Set(drawn.pixels.map { Int($0.r) << 16 | Int($0.g) << 8 | Int($0.b) })
        #expect(drawnColours.isSubset(of: expected), "drew a colour the palette does not hold")
    }

    // MARK: - Only what is drawn is counted

    /// A logo's shape: 60% transparent surround, 30% red, 10% blue. The surround
    /// is `(0, 0, 0, 0)`, which is what both resamplers write wherever there is no
    /// coverage, whatever the file held.
    private static func logo(blueCoverage: UInt8) -> RGBAImage {
        var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0, a: 0), count: 60)
        pixels += [RGBA](repeating: RGBA(r: 255, g: 0, b: 0), count: 30)
        pixels += [RGBA](repeating: RGBA(r: 0, g: 0, b: 255, a: blueCoverage), count: 10)
        return RGBAImage(width: 10, height: 10, pixels: pixels)
    }

    /// At two colours the surround used to take one of them — the top-ranked cell by
    /// popularity, and a box of its own at least error's first median cut — and the
    /// blue mark drew red, because red is nearer blue in OKLab than black is. A mark
    /// at a quarter coverage is still drawn in its own colour, so it still earns its
    /// entry: that argument pins the rule as "any coverage", not the glyphs' ½.
    @Test("A transparent surround spends no entry, and a partly covered mark keeps one", arguments: [UInt8.max, 64])
    func transparentPixelsAreNotBlack(blueCoverage: UInt8) {
        let image = Self.logo(blueCoverage: blueCoverage)
        for method in ASCIIPalette.Adaptation.allCases {
            let palette = ASCIIPalette.adaptive(2, by: method).derived(from: image, depth: .truecolor)
            let colours = palette.colors.compactMap(\.rgbComponents)
            let blacks = colours.filter { $0.red < 40 && $0.green < 40 && $0.blue < 40 }
            #expect(blacks.isEmpty, "\(method) spent an entry on the surround: \(colours)")
            let blue = palette.rgba(at: palette.nearestIndex(to: RGBA(r: 0, g: 0, b: 255)))
            #expect(blue.b > blue.r, "\(method) draws the blue mark as \(blue)")
        }
    }
}
