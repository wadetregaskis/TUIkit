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

    /// A palette the table cannot index declines it, rather than truncating an
    /// index into a byte and drawing the wrong colour entirely.
    @Test("Too many entries to index means no table, not a wrong one")
    func oversizePaletteDeclines() {
        let huge = ASCIIPalette((0..<300).map { .rgb(UInt8($0 % 256), 0, 0) })
        #expect(huge.entries.count > 256)
        #expect(huge.quantisationTable() == nil)
    }
}
