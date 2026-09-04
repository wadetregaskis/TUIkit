//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageQuantiserParityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// One screen, one answer.
///
/// On a 256-colour terminal `ASCIIColorMode.effective(for:)` sends every
/// truecolor image to ``ASCIIColorMode/ansi256``, so a photograph and the page
/// it sits on are quantised to the same 240 entries — and used to be quantised
/// to them by two different rules. The picture divided each channel by 51 onto
/// the 6×6×6 cube; the page searched OKLab with hue weighted, through
/// `Color.downsampledToPalette256()`. They disagreed for 85% of colours, and
/// visibly so: a warm cream came out pink in the picture and warm in the
/// background behind it.
///
/// These tests pin the agreement rather than the arithmetic, because agreement
/// is the property that matters and the arithmetic is allowed to change.
@Suite("The image 256-colour quantiser is the UI's")
struct ImageQuantiserParityTests {

    /// The palette index inside a `38;5;n` / `48;5;n` escape.
    private func emitted(_ code: String) -> Int? {
        Int(code.dropFirst(2).dropLast().split(separator: ";").last ?? "")
    }

    /// What the page beside the picture would be painted as.
    private func uiIndex(_ pixel: RGBA) -> Int? {
        guard case .palette256(let index) =
            Color.rgb(pixel.r, pixel.g, pixel.b).downsampledToPalette256().value
        else { return nil }
        return Int(index)
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

    /// The three the cube arithmetic got wrong, with the index the UI gives.
    ///
    /// `#F2DEC9` is the framework's own motivating colour — the one
    /// `ColorDownsamplingTests.creamStaysWarm` exists to pin for the UI — and
    /// the cube sent it to 224, `(255,215,215)`, a pink. `#C8D0D8` shows the
    /// other half of the old arithmetic: its near-grey test compared red
    /// against green and green against blue but never red against blue, so a
    /// pale blue was declared neutral and lost its tint to a flat grey.
    @Test(
        "The pale colours the cube got wrong now answer as the UI does",
        arguments: [
            (RGBA(r: 242, g: 222, b: 201), 223),  // was 224, (255,215,215)
            (RGBA(r: 250, g: 242, b: 234), 230),  // was 255, (238,238,238)
            (RGBA(r: 200, g: 208, b: 216), 152),  // was 252, (208,208,208)
        ])
    func palesQuantiseAsTheUIDoes(_ pixel: RGBA, _ expected: Int) {
        let converter = ASCIIConverter(colorMode: .ansi256)
        #expect(emitted(converter.foregroundColorCode(for: pixel, mode: .ansi256)) == expected)
        #expect(uiIndex(pixel) == expected, "the UI's own answer moved")
    }

    /// `ColorDownsamplingTests.creamStaysWarm`, asked of the picture.
    ///
    /// Stated as an ordering rather than as an index, because that is what
    /// "warm" means and it is the assertion the pink failed: 224 is
    /// `(255,215,215)`, whose green and blue are equal.
    @Test("Cream stays warm in the picture, not only in the page")
    func creamStaysWarmInImages() throws {
        let converter = ASCIIConverter(colorMode: .ansi256)
        let cream = RGBA(r: 242, g: 222, b: 201)
        let index = try #require(emitted(converter.foregroundColorCode(for: cream, mode: .ansi256)))
        let rgb = Color.palette256ToRGB(UInt8(index))
        #expect(rgb.red > rgb.green, "\(rgb)")
        #expect(rgb.green > rgb.blue, "\(rgb)")
    }

    /// The property, swept: not "close to" the UI's answer, the same one.
    ///
    /// Exact everywhere, because the character renderer takes the exact search
    /// — the quantisation table is the pixel renderer's, and its cost in
    /// accuracy is measured in `PaletteTableFidelityTests`.
    @Test("Every sampled colour emits the index the UI would paint")
    func emissionMatchesTheUIExactly() {
        let converter = ASCIIConverter(colorMode: .ansi256)
        var disagreements: [(RGBA, Int?, Int?)] = []
        for pixel in sampleColours(9_000) {
            let image = emitted(converter.foregroundColorCode(for: pixel, mode: .ansi256))
            let page = uiIndex(pixel)
            if image != page { disagreements.append((pixel, image, page)) }
        }
        #expect(disagreements.isEmpty, "\(disagreements.prefix(5))")
    }

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
    /// cell would be corrected towards a colour that was never drawn. They are
    /// the same search now, and this is the assertion that keeps them so.
    @Test("The dither's quantised pixel is the colour the cell will be painted")
    func ditherAgreesWithEmission() throws {
        let converter = ASCIIConverter(colorMode: .ansi256, dithering: .floydSteinberg)
        for pixel in sampleColours(600) {
            // No `table:` — the character renderer passes none, so this is the
            // exact answer, which is what the emission below also takes.
            let quantised = converter.quantizePixel(pixel, mode: .ansi256, monoThreshold: 128)
            let index = try #require(
                emitted(converter.foregroundColorCode(for: pixel, mode: .ansi256)))
            let painted = Color.palette256ToRGB(UInt8(index))
            #expect(quantised.r == painted.red, "\(pixel) → \(index)")
            #expect(quantised.g == painted.green, "\(pixel) → \(index)")
            #expect(quantised.b == painted.blue, "\(pixel) → \(index)")
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
    func entriesAreFixedPoints() {
        let converter = ASCIIConverter(colorMode: .ansi256)
        for index in 16...255 {
            let rgb = Color.palette256ToRGB(UInt8(index))
            let pixel = RGBA(r: rgb.red, g: rgb.green, b: rgb.blue)
            #expect(
                emitted(converter.foregroundColorCode(for: pixel, mode: .ansi256)) == index,
                "entry \(index) \(rgb)")
        }
    }
}
