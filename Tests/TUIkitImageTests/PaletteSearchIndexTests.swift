//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteSearchIndexTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// The candidate index against the walk it replaces.
///
/// The index is an optimisation of an exact search, so it is held to the
/// exact search's answers — including its tie-break — everywhere a cell's
/// bound could be wrong: at every cell corner, where a colour is farthest from
/// its cell's centre, and across a strided sample of the whole gamut.
///
/// ## Why one question is asked by several test functions
///
/// Nothing can split a single test, so the slowest one sets a floor under the
/// whole suite no matter how many processes run it — see `Tools/ParallelTest`.
/// These two checks were the two slowest tests in the package, 14.8 s and 7.6 s
/// of serial work, because their cost is pixels times palette entries and each
/// asked about every palette in one function.
///
/// The same work is therefore dealt out across functions along the two axes it
/// is already generated on. Nothing is sampled down and no tolerance moves: the
/// pixels and the palettes are exactly the ones this suite checked before.
///
/// * **By palette**, because cost is proportional to entry count and the two
///   large palettes dwarf the two small ones — and because a palette's
///   ``ASCIIPalette/SearchIndex`` is built once per process on first use, so a
///   function that touches two large palettes pays two builds. Splitting along
///   any other axis would multiply that fixed cost instead of dividing the work.
/// * **By stride phase**, for the gamut sample only, which is large enough that
///   one large palette is still too much for one function. Phase `p` of three
///   takes every third sample starting at the `p`th, so the three together are
///   the one stride they replace, exactly and without overlap.
///
/// ``everySubjectIsCovered`` and ``theGamutPhasesPartitionTheStride`` hold the
/// split to that claim: they fail if a palette or a sample ever stops being
/// covered by exactly one function.
@Suite("Palette search index")
struct PaletteSearchIndexTests {

    /// The walk, transcribed from `nearestIndex(to:)` before the index existed.
    private static func walked(_ palette: ASCIIPalette, _ pixel: RGBA) -> Int {
        let target = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
        var best = 0
        var bestDistance = Double.infinity
        for (index, entry) in palette.entries.enumerated() {
            let dl = target.l - entry.lightness, da = target.a - entry.a, db = target.b - entry.b
            let distance = dl * dl + da * da + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func corners() -> [RGBA] {
        var first = [Int](repeating: -1, count: 32)
        var last = [Int](repeating: 0, count: 32)
        for value in 0...255 {
            let bucket = Int(ASCIIPalette.quantisationBucket[value])
            if first[bucket] < 0 { first[bucket] = value }
            last[bucket] = value
        }
        // The perceptual spacing leaves a few buckets with no byte in them;
        // those cells have no corners, and no pixel ever reaches them.
        let filled = (0..<32).filter { first[$0] >= 0 }
        var out: [RGBA] = []
        for r in filled {
            for g in filled {
                for b in filled {
                    out.append(RGBA(r: UInt8(first[r]), g: UInt8(first[g]), b: UInt8(first[b])))
                    out.append(RGBA(r: UInt8(last[r]), g: UInt8(last[g]), b: UInt8(last[b])))
                }
            }
        }
        return out
    }

    private static func strided(from start: Int, step: Int) -> [RGBA] {
        var out: [RGBA] = []
        var value = start
        while value < 1 << 24 {
            out.append(RGBA(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF)))
            value += step
        }
        return out
    }

    /// The stride the gamut sample walks: every 97th colour of the 16,777,216.
    private static let gamutStep = 97

    /// How many functions share that stride between them.
    private static let gamutPhases = 3

    /// Phase `phase` of the whole gamut stride — every ``gamutPhases``th sample,
    /// starting at the `phase`th.
    ///
    /// The union over `0..<gamutPhases` is the whole stride and the phases do
    /// not overlap, because phase `p` is `{ step * (gamutPhases * m + p) }` and
    /// every whole number is one of `gamutPhases * m + p` for exactly one `p`.
    /// ``theGamutPhasesPartitionTheStride`` checks that against the stride
    /// itself rather than leaving it as arithmetic in a comment.
    private static func gamutSlice(_ phase: Int) -> [RGBA] {
        strided(from: phase * gamutStep, step: gamutStep * gamutPhases)
    }

    /// A graded field with a red patch — the shape of a photograph, so the
    /// adaptive palette derives something other than a ramp.
    private static func photograph() -> RGBAImage {
        var pixels: [RGBA] = []
        for y in 0..<64 {
            for x in 0..<64 {
                if y > 54 && x > 54 {
                    pixels.append(RGBA(r: 230, g: 30, b: 30))
                } else {
                    let shade = UInt8(clamping: 40 + (x * 180) / 64)
                    pixels.append(RGBA(r: shade, g: shade, b: UInt8(clamping: Int(shade) + 6 + y / 3)))
                }
            }
        }
        return RGBAImage(width: 64, height: 64, pixels: pixels)
    }

    private static let subjects: [String: ASCIIPalette] = [
        "ansi256": .ansi256,
        "shades256": .shades(256),
        "spread64": .spread(64),
        "optimal32": ASCIIPalette.adaptive(32, by: .leastError).derived(from: photograph(), depth: .truecolor),
    ]

    /// The palettes small enough that one function can hold both: 64 and 32
    /// entries, against the 240 and 256 the other two carry.
    private static let smallSubjects = ["optimal32", "spread64"]

    /// The terminal's 256, less the sixteen slots: 240 entries.
    private static let ansi256Subject = "ansi256"

    /// The largest palette here, and so the most expensive: 256 entries.
    private static let shades256Subject = "shades256"

    /// The one check, so that every function below makes byte-identical
    /// assertions and differs only in which pixels and which palette it is
    /// handed.
    private func agrees(_ name: String, _ pixels: [RGBA], _ what: String) throws {
        let palette = try #require(Self.subjects[name])
        var disagreements = 0
        for pixel in pixels where palette.nearestIndex(to: pixel) != Self.walked(palette, pixel) {
            disagreements += 1
        }
        #expect(disagreements == 0, "\(name): \(disagreements) \(what) differ from the walk")
    }

    // MARK: - Every cell corner

    @Test("Every cell corner agrees with the walk, tie-break included", arguments: smallSubjects)
    func cornersAgree(_ name: String) throws {
        try agrees(name, Self.corners(), "corner colours")
    }

    @Test("Every cell corner agrees with the walk for the terminal's 256")
    func cornersAgreeForANSI256() throws {
        try agrees(Self.ansi256Subject, Self.corners(), "corner colours")
    }

    @Test("Every cell corner agrees with the walk for 256 shades")
    func cornersAgreeForShades256() throws {
        try agrees(Self.shades256Subject, Self.corners(), "corner colours")
    }

    // MARK: - A stride across the gamut

    @Test("A stride across the gamut agrees with the walk", arguments: smallSubjects)
    func gamutSampleAgrees(_ name: String) throws {
        try agrees(name, Self.strided(from: 0, step: Self.gamutStep), "sampled colours")
    }

    @Test("A third of the gamut stride agrees with the walk for the terminal's 256")
    func gamutSampleAgreesForANSI256FirstThird() throws {
        try agrees(Self.ansi256Subject, Self.gamutSlice(0), "sampled colours")
    }

    @Test("The second third of the gamut stride agrees with the walk for the terminal's 256")
    func gamutSampleAgreesForANSI256SecondThird() throws {
        try agrees(Self.ansi256Subject, Self.gamutSlice(1), "sampled colours")
    }

    @Test("The last third of the gamut stride agrees with the walk for the terminal's 256")
    func gamutSampleAgreesForANSI256LastThird() throws {
        try agrees(Self.ansi256Subject, Self.gamutSlice(2), "sampled colours")
    }

    @Test("A third of the gamut stride agrees with the walk for 256 shades")
    func gamutSampleAgreesForShades256FirstThird() throws {
        try agrees(Self.shades256Subject, Self.gamutSlice(0), "sampled colours")
    }

    @Test("The second third of the gamut stride agrees with the walk for 256 shades")
    func gamutSampleAgreesForShades256SecondThird() throws {
        try agrees(Self.shades256Subject, Self.gamutSlice(1), "sampled colours")
    }

    @Test("The last third of the gamut stride agrees with the walk for 256 shades")
    func gamutSampleAgreesForShades256LastThird() throws {
        try agrees(Self.shades256Subject, Self.gamutSlice(2), "sampled colours")
    }

    // MARK: - The split covers what one function used to

    /// Every palette in ``subjects`` is checked by one of the functions above.
    ///
    /// The checks used to be parameterised over `subjects.keys` itself, so a
    /// palette added to that dictionary was checked by the act of adding it.
    /// Split by palette, the argument lists are the place a new one could be
    /// forgotten, and this is what notices.
    @Test("Every palette is covered by exactly one of the split argument lists")
    func everySubjectIsCovered() {
        let covered = Self.smallSubjects + [Self.ansi256Subject, Self.shades256Subject]
        #expect(Set(covered) == Set(Self.subjects.keys), "\(covered) against \(Self.subjects.keys.sorted())")
        #expect(Set(covered).count == covered.count, "a palette is checked twice: \(covered)")
    }

    /// The three phases are the one stride they replace: same samples, same
    /// number of them, none twice.
    ///
    /// Sample `index` of the whole stride is sample `index / gamutPhases` of
    /// phase `index % gamutPhases`, which is a bijection — so this is the
    /// partition, checked rather than argued.
    @Test("The gamut phases together are exactly the stride they replace")
    func theGamutPhasesPartitionTheStride() {
        let whole = Self.strided(from: 0, step: Self.gamutStep)
        let phases = (0..<Self.gamutPhases).map { Self.gamutSlice($0) }
        #expect(
            phases.reduce(0) { $0 + $1.count } == whole.count,
            "\(phases.map(\.count)) samples against the stride's \(whole.count)")
        // One expectation over the whole comparison, not one per sample: this
        // walks 172,961 of them, and an expectation apiece would cost more than
        // the tests it is guarding.
        let interleaves = whole.indices.allSatisfy { index in
            let phase = phases[index % Self.gamutPhases]
            let position = index / Self.gamutPhases
            return phase.indices.contains(position) && phase[position] == whole[index]
        }
        #expect(interleaves, "the phases do not deal the stride out between them")
    }

    // MARK: - The index itself

    @Test("The lists are short: a few candidates a cell, not the palette")
    func listsAreShort() throws {
        // 240 entries, so it is comfortably within the bound and has an index.
        let index = try #require(ASCIIPalette.ansi256.searchIndex)
        let perCell = Double(index.candidateCount) / Double(ASCIIPalette.quantisationCells)
        #expect(perCell < 12, "\(perCell) candidates a cell against 240 entries")
    }

    @Test("Palettes below the threshold still walk; every copy of a large one shares an index")
    func thresholdAndSharing() {
        #expect(ASCIIPalette.ansi16.entries.count == ASCIIPalette.indexedEntryThreshold)
        let one = ASCIIPalette.shades(256)
        let copy = one
        #expect(one.searchIndex === copy.searchIndex, "a copy shares its original's index")
        let another = ASCIIPalette.shades(256)
        #expect(one.searchIndex === another.searchIndex, "the same colours share one index across instances")
        #expect(one.searchIndex !== ASCIIPalette.ansi256.searchIndex)
    }

    /// A palette with more entries than a byte can name declines an index
    /// rather than truncating one, and still answers exactly.
    ///
    /// The candidate lists store an entry index in a `UInt8`, and nothing
    /// bounded the palette — so `UInt8(index)` trapped for the 257th entry,
    /// on the FIRST pixel ever looked up, taking the app with it. The sibling
    /// accelerator has declined above the same bound from the start; that is
    /// pinned by `PaletteTableFidelityTests.oversizePaletteDeclines`, and this
    /// is its twin.
    @Test("A palette too large to index declines one, and still answers exactly")
    func oversizePaletteDeclinesAnIndex() {
        // 300 distinct colours: past the bound, and no two alike, so the walk
        // has a single unambiguous answer to agree with.
        let huge = ASCIIPalette((0..<300).map { .rgb(UInt8($0 % 256), UInt8($0 / 256), 0) })
        #expect(huge.entries.count > ASCIIPalette.indexableEntryLimit)
        #expect(huge.searchIndex == nil, "it must decline rather than truncate an index")
        // The point of declining: the answers are still right. Before the
        // bound this line never ran — the lookup trapped.
        for pixel in [
            RGBA(r: 0, g: 0, b: 0, a: 255), RGBA(r: 255, g: 255, b: 255, a: 255),
            RGBA(r: 40, g: 1, b: 0, a: 255), RGBA(r: 200, g: 0, b: 0, a: 255),
        ] {
            #expect(huge.nearestIndex(to: pixel) == Self.walked(huge, pixel))
        }
    }
}
