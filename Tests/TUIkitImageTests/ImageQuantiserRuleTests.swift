//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageQuantiserRuleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// The same colours as the page, and deliberately not the same rule.
///
/// On a 256-colour terminal `ASCIIColorMode.effective(for:)` sends every
/// truecolor image to ``ASCIIColorMode/ansi256``, so a photograph and the page
/// it sits on are drawn from the same 240 entries. That shared PALETTE is what
/// makes a screen coherent. Two attempts have now been made to also share the
/// RULE that picks an entry, and both were wrong in opposite directions:
///
/// - Dividing each channel by 51 onto the 6×6×6 cube. Per-channel rounding
///   rotates hue where the cube is coarsest, so a warm cream `#F2DEC9` came out
///   pink, and the near-grey short-circuit compared red against green and green
///   against blue but never red against blue.
/// - Borrowing `Color.downsampledToPalette256()`, the UI's quantiser. It is
///   about colour IDENTITY — hue weighted ×4, chroma LOSS charged ×4, and no
///   grey allowed to anything with a hue at all, which is what keeps a fading
///   accent from stepping through grey. Applied per pixel that gate fires for
///   99.8% of colours, so a photograph's metals and shadows are forbidden the
///   grey ramp and take a cube entry instead: `(96,100,106)` came out
///   `(95,95,135)`, a navy. The greys INVENTED A HUE.
///
/// So an image maps by nearest in OKLab, plainly, like every other
/// ``ASCIIPalette``. These tests pin that rule where it is visible — the pixel
/// a person would call wrong — rather than pinning indices, which are allowed
/// to move.
@Suite("The image 256-colour quantiser's rule")
struct ImageQuantiserRuleTests {

    /// The palette index inside a `38;5;n` / `48;5;n` escape.
    private func emitted(_ code: String) -> Int? {
        Int(code.dropFirst(2).dropLast().split(separator: ";").last ?? "")
    }

    private func index(of pixel: RGBA) throws -> Int {
        let converter = ASCIIConverter(colorMode: .ansi256)
        return try #require(emitted(converter.foregroundColorCode(for: pixel, mode: .ansi256)))
    }

    /// How far apart a colour's channels are — 0 for a neutral.
    private func spread(_ rgb: (red: UInt8, green: UInt8, blue: UInt8)) -> Int {
        Int(max(rgb.red, max(rgb.green, rgb.blue))) - Int(min(rgb.red, min(rgb.green, rgb.blue)))
    }

    /// A deterministic spread: a stratified walk so no region of the cube is
    /// missed, and a pseudo-random scatter so the samples do not all land on
    /// round numbers.
    private func sampleColours(_ count: Int) -> [RGBA] {
        var samples: [RGBA] = []
        samples.reserveCapacity(count)
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        for _ in 0..<count {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            samples.append(
                RGBA(
                    r: UInt8(truncatingIfNeeded: seed >> 16),
                    g: UInt8(truncatingIfNeeded: seed >> 32),
                    b: UInt8(truncatingIfNeeded: seed >> 48)))
        }
        for red in stride(from: 0, through: 255, by: 15) {
            for green in stride(from: 0, through: 255, by: 45) {
                samples.append(RGBA(r: UInt8(red), g: UInt8(green), b: UInt8(255 - red)))
                samples.append(RGBA(r: UInt8(green), g: UInt8(red), b: UInt8(red)))
                // Pale and near-neutral, which is where the cube was worst and
                // where a random scatter puts almost nothing.
                samples.append(
                    RGBA(r: UInt8(200 + red / 5), g: UInt8(195 + red / 6), b: UInt8(190 + red / 7)))
            }
        }
        return samples
    }

    // MARK: - The rule

    /// The property, swept: what is emitted is the nearest of the 240 in OKLab.
    ///
    /// The character renderer takes the exact search, so this is exact
    /// everywhere — the pixel renderer's table is an approximation of this same
    /// answer, and its cost is measured in `PaletteTableFidelityTests`.
    @Test("Every sampled colour emits the nearest of the 240 entries")
    func emissionIsTheNearestEntry() throws {
        var disagreements: [(RGBA, Int, Int)] = []
        for pixel in sampleColours(9_000) {
            let emitted = try index(of: pixel)
            let nearest = Self.nearestByOKLab(pixel)
            if emitted != nearest { disagreements.append((pixel, emitted, nearest)) }
        }
        #expect(disagreements.isEmpty, "\(disagreements.prefix(5))")
    }

    /// The nearest of indices 16…255 in plain OKLab, computed here from
    /// `Color`'s own conversion so the test does not restate the search it is
    /// checking.
    private static func nearestByOKLab(_ pixel: RGBA) -> Int {
        let target = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
        var best = 16
        var bestDistance = Double.infinity
        for index in 16...255 {
            let rgb = Color.palette256ToRGB(UInt8(index))
            let candidate = Color.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue)
            let distance = ASCIIPalette.distanceSquared(target, candidate)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    // MARK: - Greys keep their neutrality

    /// The regression that sent a picture's metals blue.
    ///
    /// Stated as neutrality rather than as an index, because that is what went
    /// wrong and the index is allowed to move: `(96,100,106)` is a dark
    /// blue-grey with barely any chroma, and it came back `(95,95,135)` — a
    /// forty-unit spread between channels where the source had ten.
    @Test(
        "A near-neutral pixel stays near-neutral",
        arguments: [
            RGBA(r: 96, g: 100, b: 106),  // was (95,95,135), a navy
            RGBA(r: 192, g: 196, b: 202),
            RGBA(r: 150, g: 154, b: 160),
            RGBA(r: 58, g: 60, b: 64),
            RGBA(r: 30, g: 31, b: 34),
            RGBA(r: 200, g: 196, b: 190),
        ])
    func nearNeutralsStayNeutral(_ pixel: RGBA) throws {
        let painted = Color.palette256ToRGB(UInt8(try index(of: pixel)))
        let source = spread((pixel.r, pixel.g, pixel.b))
        #expect(
            spread(painted) <= source + 8,
            "\(pixel) → \(painted): spread \(source) became \(spread(painted))")
    }

    /// …and the ramp it needs to do that is actually reachable.
    ///
    /// The grey ramp is the only fine detail this palette has — 24 steps of ten
    /// where the cube has six of forty — so a rule that excludes it does not
    /// merely shift a hue, it throws away the resolution a photograph's tonal
    /// range depends on. Swept rather than spot-checked, because the failure
    /// was total: the UI's rule reached the ramp for 0.23% of a random sweep.
    @Test("The grey ramp carries its share of a random sweep")
    func greyRampIsReachable() throws {
        var fromTheRamp = 0
        let samples = sampleColours(3_000)
        for pixel in samples where try index(of: pixel) >= 232 { fromTheRamp += 1 }
        #expect(
            fromTheRamp > samples.count / 50,
            "only \(fromTheRamp) of \(samples.count) colours reached indices 232…255")
    }

    /// An exact grey is its own ramp entry, and a grey between two rungs takes
    /// the nearer.
    @Test("Neutral greys land on the ramp they belong to")
    func neutralGreysLandOnTheRamp() throws {
        for step in 0..<24 {
            let value = UInt8(8 + step * 10)
            #expect(try index(of: RGBA(r: value, g: value, b: value)) == 232 + step, "grey \(value)")
        }
    }

    // MARK: - What the cube got wrong, which is still wrong

    /// `ColorDownsamplingTests.creamStaysWarm`, asked of the picture.
    ///
    /// Stated as an ordering rather than as an index, because that is what
    /// "warm" means and it is the assertion the cube's pink failed: 224 is
    /// `(255,215,215)`, whose green and blue are equal. Nearest in OKLab passes
    /// it for the same reason the UI's rule does — per-channel rounding was the
    /// fault, not the absence of a hue weight.
    @Test("Cream stays warm in the picture, not only in the page")
    func creamStaysWarmInImages() throws {
        let rgb = Color.palette256ToRGB(UInt8(try index(of: RGBA(r: 242, g: 222, b: 201))))
        #expect(rgb.red > rgb.green, "\(rgb)")
        #expect(rgb.green > rgb.blue, "\(rgb)")
    }

    // MARK: - One answer per pixel, wherever it is asked

    /// The background copy is the same answer in the other SGR, and nothing
    /// else — the half-block renderer puts a cell's two pixels in the two
    /// slots, so a rule that applied to one and not the other would split
    /// every cell.
    @Test("The background code answers exactly as the foreground does")
    func backgroundAgreesWithForeground() {
        let converter = ASCIIConverter(colorMode: .ansi256)
        for pixel in sampleColours(600) {
            let foreground = converter.foregroundColorCode(for: pixel, mode: .ansi256)
            let background = converter.backgroundColorCode(for: pixel, mode: .ansi256)
            #expect(emitted(foreground) == emitted(background), "\(pixel)")
            #expect(background.contains("48;5;"), "\(background.debugDescription)")
        }
    }

    /// What the dither diffuses is what will be painted.
    ///
    /// Floyd–Steinberg spreads `original − quantised`, so if `quantizePixel`
    /// answered with a different entry than `foregroundColorCode` emits, every
    /// cell would be corrected towards a colour that was never drawn.
    @Test("The dither's quantised pixel is the colour the cell will be painted")
    func ditherAgreesWithEmission() throws {
        let converter = ASCIIConverter(colorMode: .ansi256, dithering: .floydSteinberg)
        for pixel in sampleColours(600) {
            // No `table:` — the character renderer passes none, so this is the
            // exact answer, which is what the emission below also takes.
            let quantised = converter.quantizePixel(pixel, mode: .ansi256, monoThreshold: 128)
            let painted = Color.palette256ToRGB(UInt8(try index(of: pixel)))
            #expect(quantised.r == painted.red, "\(pixel)")
            #expect(quantised.g == painted.green, "\(pixel)")
            #expect(quantised.b == painted.blue, "\(pixel)")
            #expect(quantised.a == pixel.a, "alpha was not carried")
        }
    }

    /// A palette entry is its own answer.
    ///
    /// Not decoration: the dither relies on it. It quantises a pixel to an
    /// entry's colour and the renderer then quantises THAT colour to emit it,
    /// so a quantiser that moved an entry somewhere else would make the two
    /// halves disagree for every dithered pixel.
    @Test("Every one of the 240 entries quantises to itself")
    func entriesAreFixedPoints() throws {
        for index in 16...255 {
            let rgb = Color.palette256ToRGB(UInt8(index))
            #expect(
                try self.index(of: RGBA(r: rgb.red, g: rgb.green, b: rgb.blue)) == index,
                "entry \(index) \(rgb)")
        }
    }
}
