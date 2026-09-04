//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteTableFidelityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// What the pixel renderer's quantisation table costs in accuracy.
///
/// It is an approximation, so the only honest way to ship it is to measure how
/// far off it is and say the number — and to pin that number, so a change to
/// the metric, the table's resolution or a palette's contents cannot quietly
/// make it worse.
///
/// Measured 2026-09-02, 60,000 stratified + scattered colours:
///
///     palette        disagreement   worst rank
///     ansi16              0.008%        1
///     shades(4)           0.003%        1
///     shades(16)          0.131%        1
///     3-stop tone ramp    0.017%        1
///
/// ``ASCIIPalette/ansi256`` is measured separately and on a different scale —
/// 13.6%, because 240 entries in the same 32,768 cells leaves most cells
/// straddling a boundary, and because its table has no exact fallback to rescue
/// them. See `terminalPaletteTableIsHonest` for why that is the right trade
/// there and nowhere else.
///
/// The plain table — before cells were spaced by lightness and before the
/// boundary cells were excluded from it — disagreed for **4.6%** of colours
/// and sometimes chose the FOURTH-nearest entry. Both numbers are in this
/// file's history for a reason: the difference between them is the difference
/// between an optimisation and a downgrade.
@Suite("Palette table fidelity")
struct PaletteTableFidelityTests {

    /// A deterministic spread of colours: a stratified grid so no region of the
    /// cube is missed, and a pseudo-random scatter so the samples do not all
    /// land on cell corners — which is exactly where a table is most accurate
    /// and would flatter it.
    private func sampleColours(_ count: Int) -> [RGBA] {
        var samples: [RGBA] = []
        samples.reserveCapacity(count)
        var seed: UInt64 = 0x5DEE_CE66_D000_0001
        for _ in 0..<count {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            samples.append(
                RGBA(
                    r: UInt8(truncatingIfNeeded: seed >> 16),
                    g: UInt8(truncatingIfNeeded: seed >> 32),
                    b: UInt8(truncatingIfNeeded: seed >> 48)))
        }
        for step in stride(from: 0, through: 255, by: 17) {
            for other in stride(from: 0, through: 255, by: 51) {
                samples.append(RGBA(r: UInt8(step), g: UInt8(other), b: UInt8(255 - step)))
                samples.append(RGBA(r: UInt8(other), g: UInt8(step), b: UInt8(step)))
            }
        }
        return samples
    }

    /// How often the table's answer differs from the exact search, and — for
    /// the ones that differ — whether the entry it chose was at least a NEAR
    /// neighbour rather than an arbitrary one.
    private func disagreement(_ palette: ASCIIPalette) -> (rate: Double, worstRank: Int) {
        guard let table = palette.quantisationTable() else { return (1, .max) }
        var differed = 0
        var worstRank = 0
        let samples = sampleColours(60_000)
        for pixel in samples {
            let exact = palette.nearestIndex(to: pixel)
            let cell = ASCIIPalette.quantisationCell(for: pixel)
            let approximate = table.trusted[cell]
                ? Int(table.answers[cell]) : palette.nearestIndex(to: pixel)
            guard approximate != exact else { continue }
            differed += 1
            // Where they differ, how far down the true ordering the table's
            // answer sits. Rank 1 means "the second-closest entry", which is
            // the only defensible kind of miss.
            let target = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
            let ordered = palette.entries.indices.sorted {
                ASCIIPalette.distanceSquared(
                    target,
                    (l: palette.entries[$0].lightness, a: palette.entries[$0].a,
                     b: palette.entries[$0].b))
                    < ASCIIPalette.distanceSquared(
                        target,
                        (l: palette.entries[$1].lightness, a: palette.entries[$1].a,
                         b: palette.entries[$1].b))
            }
            worstRank = max(worstRank, ordered.firstIndex(of: approximate) ?? .max)
        }
        return (Double(differed) / Double(samples.count), worstRank)
    }

    @Test("The sixteen: a small disagreement, and only ever with the runner-up")
    func ansi16IsCloseEnough() {
        let (rate, worstRank) = disagreement(.ansi16)
        #expect(rate < 0.0005, "\(rate * 100)% of colours took a different entry")
        #expect(worstRank <= 1, "the table chose an entry ranked \(worstRank), not the runner-up")
        print(String(format: "  ansi16   disagreement %.3f%%  worst rank %d", rate * 100, worstRank))
    }

    @Test("A tone-ramp palette is exact, because it does not search")
    func toneRampIsExact() {
        // `.asToneRamp()` indexes by tonal rank rather than by nearest colour,
        // and the table is built from the same function — so for these the
        // approximation is only the 5-bit rounding of the tone, which the ramp
        // steps swallow.
        let ramp = ASCIIPalette([.rgb(0, 0, 0), .rgb(128, 128, 128), .rgb(255, 255, 255)])
            .asToneRamp()
        let (rate, _) = disagreement(ramp)
        #expect(rate < 0.0005, "\(rate * 100)%")
        print(String(format: "  toneRamp disagreement %.3f%%", rate * 100))
    }

    @Test("A wide palette stays close too")
    func shadesStayClose() {
        for count in [4, 16] {
            let (rate, worstRank) = disagreement(.shades(count))
            #expect(rate < 0.002, "shades(\(count)): \(rate * 100)%")
            #expect(worstRank <= 1, "shades(\(count)) ranked \(worstRank)")
            print(String(format: "  shades(%d) disagreement %.3f%%  worst rank %d",
                         count, rate * 100, worstRank))
        }
    }

    /// The terminal's own 256, whose table is a different trade from every
    /// other palette's — and the only one where the number is large enough that
    /// it has to be said rather than assumed.
    ///
    /// `ASCIIPalette.terminalQuantisationTable` has no boundary fallback: with
    /// 240 entries only 33% of cells have six agreeing neighbours, so falling
    /// back would fire for three pixels in four at 450 ns each, which is a third
    /// of a second for a megapixel. The table answers everywhere instead, and
    /// this is what that costs.
    ///
    /// Measured 2026-09-04: **13.6%** of colours take a different entry than the
    /// exact search, landing on average 0.0044 further from the pixel in OKLab
    /// — 3% of the 0.13 that separates two adjacent cube levels — and 0.14
    /// further in the worst case, which is one whole step. The arithmetic this
    /// replaced differed for 85.0% and landed 0.0447 further on average, so the
    /// approximation is an order of magnitude closer than what it approximates
    /// used to be.
    ///
    /// This is the pixel renderer only. The character renderer passes no table
    /// and takes the exact answer, so a glyph's `38;5;n` is identical to the one
    /// the UI beside it is painted with — see `ImageQuantiserParityTests`.
    @Test("The terminal's 256: the table's misses are all near ties")
    func terminalPaletteTableIsHonest() {
        let palette = ASCIIPalette.ansi256
        let table = ASCIIPalette.terminalQuantisationTable
        let samples = sampleColours(20_000)
        var differed = 0
        var worstExcess = 0.0
        var totalExcess = 0.0
        for pixel in samples {
            let exact = palette.nearestIndex(to: pixel)
            let approximate = Int(table.answers[ASCIIPalette.quantisationCell(for: pixel)])
            guard approximate != exact else { continue }
            differed += 1
            // How much further the table's entry sits from the pixel than the
            // exact one — the honest measure of a miss, and the one that says
            // "between two entries" rather than "wrong".
            let target = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
            func distance(_ entry: Int) -> Double {
                ASCIIPalette.distanceSquared(
                    target,
                    (l: palette.entries[entry].lightness, a: palette.entries[entry].a,
                     b: palette.entries[entry].b)).squareRoot()
            }
            let excess = distance(approximate) - distance(exact)
            totalExcess += excess
            worstExcess = max(worstExcess, excess)
        }
        let rate = Double(differed) / Double(samples.count)
        let meanExcess = differed > 0 ? totalExcess / Double(differed) : 0
        print(String(format: "  ansi256  disagreement %.1f%%  excess mean %.4f worst %.4f OKLab",
                     rate * 100, meanExcess, worstExcess))
        #expect(rate < 0.16, "\(rate * 100)% of colours took a different entry")
        #expect(meanExcess < 0.02, "the average miss lands \(meanExcess) further away")
        #expect(worstExcess < 0.2, "the worst miss lands \(worstExcess) further away")
    }

    /// A palette the table cannot index declines it, rather than truncating an
    /// index into a byte and drawing the wrong colour entirely.
    @Test("Too many entries to index means no table, not a wrong one")
    func oversizePaletteDeclines() {
        let huge = ASCIIPalette((0..<300).map { .rgb(UInt8($0 % 256), 0, 0) })
        #expect(huge.entries.count > 256)
        #expect(huge.quantisationTable() == nil)
    }
}

/// The approximation must not reach the character renderer.
///
/// It is kept out by a **default argument**: `applyFloydSteinbergDithering`
/// and `quantizePixel` take `table:` defaulted to `nil`, and
/// `ASCIIConverter.convert` does not pass one, so the character path takes the
/// exact search. That is a fine mechanism and a poor guarantee — a defaulted
/// parameter is precisely what a later edit threads a value into without
/// noticing what it changed.
///
/// So this test does not check that the caller omits the argument. It finds a
/// colour the table and the exact search DISAGREE about, and checks the
/// character renderer draws the exact answer.
@Suite("The table stays out of the character renderer")
struct TableIsolationTests {

    /// A colour where the table's answer differs from the exact search, found
    /// rather than hardcoded — the disagreements move whenever the metric, the
    /// cell spacing or the palette does, and a stale constant would quietly
    /// make this test vacuous.
    private func disagreeingColour(in palette: ASCIIPalette) -> (RGBA, exact: Int, table: Int)? {
        guard let table = palette.quantisationTable() else { return nil }
        var state: UInt64 = 0x243F_6A88_85A3_08D3
        for _ in 0..<400_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let pixel = RGBA(
                r: UInt8(truncatingIfNeeded: state >> 16),
                g: UInt8(truncatingIfNeeded: state >> 32),
                b: UInt8(truncatingIfNeeded: state >> 48))
            let cell = ASCIIPalette.quantisationCell(for: pixel)
            guard table.trusted[cell] else { continue }
            let exact = palette.nearestIndex(to: pixel)
            let approximate = Int(table.answers[cell])
            if approximate != exact { return (pixel, exact, approximate) }
        }
        return nil
    }

    /// The guarantee, stated where it actually lives.
    ///
    /// An end-to-end assertion on `convert`'s output cannot say this: with
    /// dithering on, a flat colour legitimately draws as SEVERAL neighbouring
    /// entries, so seeing the table's answer on screen would prove nothing. The
    /// mechanism is the defaulted parameter, so that is what is pinned — asked
    /// about a colour the two genuinely disagree about, which is what stops the
    /// test passing for the wrong reason.
    @Test("Without a table, the answer is the exact one")
    func defaultIsTheExactSearch() throws {
        let palette = ASCIIPalette.ansi16
        let found = try #require(disagreeingColour(in: palette))
        let (pixel, exact, approximate) = found
        #expect(exact != approximate, "the search set found no real disagreement")

        let converter = ASCIIConverter(colorMode: .ansi16)
        // No `table:` — which is what `ASCIIConverter.convert` passes, and
        // therefore what the character renderer gets.
        let drawn = converter.quantizePixel(pixel, mode: .ansi16, monoThreshold: 128)
        #expect(drawn.r == palette.rgba(at: exact).r)
        #expect(drawn.g == palette.rgba(at: exact).g)
        #expect(drawn.b == palette.rgba(at: exact).b)

        // …and WITH one it may differ, which is the whole point of having it
        // and the reason the default matters.
        let table = try #require(palette.quantisationTable())
        let approximated = converter.quantizePixel(
            pixel, mode: .ansi16, monoThreshold: 128, table: table)
        #expect(approximated.r == palette.rgba(at: approximate).r)
    }
}
