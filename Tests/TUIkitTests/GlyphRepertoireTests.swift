//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GlyphRepertoireTests.swift
//
//  The fundamental charsets and the ideal-subset selection behind their
//  configurable size: density ramps must span the coverage range evenly
//  (flattest glyph per level, space-anchored, monotonic), shape
//  vocabularies must spread through shape space, and the pools must honour
//  the charset taxonomy (unicode excludes Block Elements; the block shape
//  repertoire includes the corner triangles).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitImage

@MainActor
@Suite("Glyph repertoire")
struct GlyphRepertoireTests {

    // MARK: - Calibration table

    @Test("Every calibrated glyph is single-cell by TUIkit's width tables")
    func calibratedGlyphsAreSingleCell() {
        // The renderers append exactly one glyph per output cell with no
        // width validation at render time, so a double-width entry in the
        // calibration table would shear every row it appears on. This is
        // the framework-side gate for glyphs added to the candidate sets in
        // Tools/GenerateImageGlyphs.
        for entry in GlyphRepertoire.all {
            #expect(String(entry.glyph).strippedLength == 1, "'\(entry.glyph)' is not single-cell")
        }
    }

    @Test("The pools honour the charset taxonomy")
    func poolTaxonomy() {
        let ascii = Set(GlyphRepertoire.ascii.map(\.glyph))
        let unicode = Set(GlyphRepertoire.unicode.map(\.glyph))
        let blocks = Set(GlyphRepertoire.blockShapes.map(\.glyph))

        // Coarse size pins, so a regressed regeneration (wrong font,
        // over-aggressive skip list) fails loudly rather than silently
        // shipping a starved matcher.
        #expect(ascii.count >= 90, "full printable ASCII: \(ascii.count)")
        #expect(unicode.count >= 120, "ascii + box drawing + shapes: \(unicode.count)")
        #expect(blocks.count >= 30, "blocks + quadrants + triangles: \(blocks.count)")

        #expect(ascii.allSatisfy { $0.isASCII })
        #expect(ascii.isSubset(of: unicode), "unicode includes all of ascii")
        #expect(
            !unicode.contains(where: { GlyphRepertoire.isBlockElement($0) }),
            "unicode excludes the Block Elements (they belong to the block modes)")

        // The block shape repertoire: space + Block Elements + the corner
        // triangles the user-facing docs promise for diagonal edges.
        for triangle in "◢◣◤◥" {
            #expect(blocks.contains(triangle), "'\(triangle)' missing from the block shapes")
        }
        for essential in "█▀▄▌▐░▒▓▘▝▖▗▚▞ " {
            #expect(blocks.contains(essential), "'\(essential)' missing from the block shapes")
        }
        #expect(
            blocks.allSatisfy {
                $0 == " " || GlyphRepertoire.isBlockElement($0) || "◢◣◤◥".contains($0)
            },
            "nothing else sneaks into the block shapes")
    }

    @Test("maximumGlyphs reports the real ceiling per charset and algorithm")
    func maximumGlyphsCeilings() {
        // Shape matching can use the whole pool; luminance mapping only its
        // usefully-distinct density levels.
        #expect(
            ASCIICharacterSet.ascii.maximumGlyphs(shapeAware: true)
                == GlyphRepertoire.ascii.count)
        #expect(
            ASCIICharacterSet.ascii.maximumGlyphs(shapeAware: false)
                == GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii).count)
        #expect(
            ASCIICharacterSet.unicode.maximumGlyphs(shapeAware: true)
                == GlyphRepertoire.unicode.count)
        #expect(
            ASCIICharacterSet.unicode.maximumGlyphs(shapeAware: false)
                == GlyphRepertoire.densityRamp(from: GlyphRepertoire.unicode).count)
        // No glyph-count axis on the block or custom charsets.
        #expect(ASCIICharacterSet.blocks(.half).maximumGlyphs(shapeAware: true) == nil)
        #expect(ASCIICharacterSet.blocks(.coarse).maximumGlyphs(shapeAware: false) == nil)
        #expect(ASCIICharacterSet.customRamp(" .#").maximumGlyphs(shapeAware: false) == nil)

        // Asking for the ceiling is exactly the full repertoire — counts
        // above it are equivalent to nil (pinned so UIs can clamp to it).
        let ceiling = ASCIICharacterSet.ascii.maximumGlyphs(shapeAware: false)!
        #expect(
            GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii, count: ceiling)
                == GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii))
    }

    // MARK: - Density ramps

    @Test("A density ramp is space-anchored, monotonic, and sized as asked")
    func densityRampContract() {
        for count in [2, 4, 6, 10, 14] {
            let ramp = GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii, count: count)
            #expect(ramp.count == count, "asked \(count), got \(ramp.count): \(ramp)")
            #expect(ramp.first == " ", "black pixels always render blank: \(ramp)")
            #expect(Set(ramp).count == ramp.count, "no duplicate glyphs: \(ramp)")

            // Monotonic by measured coverage.
            let coverage = ramp.map { glyph in
                GlyphRepertoire.ascii.first { $0.glyph == glyph }!.total
            }
            #expect(coverage == coverage.sorted(), "ramp is dark→bright: \(ramp)")
        }
    }

    @Test("A ramp's levels span the coverage range evenly")
    func densityRampEvenness() {
        // The user-facing contract: chosen glyphs represent the range of
        // fill densities as evenly as possible. Pin it as a bound on the
        // largest gap between consecutive levels relative to the ideal
        // (uniform) spacing.
        let pool = GlyphRepertoire.ascii
        let maxTotal = pool.map(\.total).max()!
        for count in [6, 10, 14] {
            let ramp = GlyphRepertoire.densityRamp(from: pool, count: count)
            let coverage = ramp.map { glyph in pool.first { $0.glyph == glyph }!.total }
            let ideal = maxTotal / Double(count - 1)
            let gaps = zip(coverage.dropFirst(), coverage).map(-)
            #expect(
                gaps.allSatisfy { $0 <= ideal * 2.0 },
                "no gap more than twice the uniform spacing (\(count) levels): \(ramp)")
        }
    }

    @Test("Unbounded ramps keep every usefully-distinct level, nothing more")
    func densityRampFull() {
        let full = GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii)
        #expect(full.count >= 14, "the calibrated ASCII pool has many distinct levels: \(full)")
        // Requesting more than exists yields the same distinct levels.
        let over = GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii, count: 500)
        #expect(over == full)
    }

    @Test("Flatness breaks density ties: shades beat clumped glyphs in a blocks ramp")
    func densityRampPrefersFlat() {
        // In the block pool several glyphs share similar coverages (a shade
        // vs a same-ink quadrant); the shade's even distribution must win a
        // luminance-ramp slot, because a luminance cell has no spatial
        // information to justify a clumped glyph.
        let ramp = GlyphRepertoire.densityRamp(from: GlyphRepertoire.blockShapes, count: 5)
        #expect(ramp.first == " ")
        #expect(
            ramp.contains(where: { Set("░▒▓█").contains($0) }),
            "the flat shades take mid-ramp slots: \(ramp)")
        #expect(
            !ramp.contains(where: { Set("▘▝▖▗").contains($0) }),
            "single quadrants don't beat equally-dark shades: \(ramp)")
    }

    // MARK: - Shape vocabularies

    @Test("A shape vocabulary is space-seeded, deduplicated, and sized as asked")
    func shapeVocabularyContract() {
        for count in [2, 8, 20, 40] {
            let vocabulary = GlyphRepertoire.shapeVocabulary(
                from: GlyphRepertoire.ascii, count: count)
            #expect(vocabulary.count == count)
            #expect(vocabulary.first?.0 == " ", "seeded with the space (blank cells)")
            #expect(Set(vocabulary.map(\.0)).count == count, "no duplicates")
        }
        let full = GlyphRepertoire.shapeVocabulary(from: GlyphRepertoire.ascii)
        #expect(full.count == GlyphRepertoire.ascii.count)
    }

    @Test("Farthest-point selection spreads wider than an arbitrary prefix")
    func shapeVocabularySpread() {
        // The chosen subset's minimum pairwise distance must beat taking
        // the first N pool entries — otherwise the selection isn't doing
        // its job of maximising shape-space coverage.
        func minPairwiseDistance(_ entries: [(Character, [Double])]) -> Double {
            var minimum = Double.infinity
            for i in entries.indices {
                for j in entries.indices where j > i {
                    let distance = zip(entries[i].1, entries[j].1)
                        .reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
                    minimum = min(minimum, distance)
                }
            }
            return minimum
        }
        let pool = GlyphRepertoire.unicode
        let chosen = GlyphRepertoire.shapeVocabulary(from: pool, count: 12)
        let prefix = Array(GlyphRepertoire.shapeVocabulary(from: pool).prefix(12))
        #expect(
            minPairwiseDistance(chosen) > minPairwiseDistance(prefix),
            "selection spreads glyphs wider than pool order")
    }

    @Test("Sized-down shape rendering still spans blank to dense")
    func sizedShapeRenderSpans() {
        // An 8-glyph ASCII shape vocabulary must still render a black/white
        // split as blank cells vs dense cells — the extremes survive sizing.
        var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: 100 * 30)
        for y in 0..<30 {
            for x in 50..<100 { pixels[y * 100 + x] = RGBA(r: 255, g: 255, b: 255) }
        }
        let img = RGBAImage(width: 100, height: 30, pixels: pixels)
        let out = ASCIIConverter(
            characterSet: .ascii(glyphs: 8), shapeAware: true,
            colorMode: .mono, dithering: .none, edgeThreshold: nil
        ).convert(img, width: 20, height: 3).joined().stripped
        #expect(out.contains(" "), "light cells render blank: '\(out)'")
        #expect(out.contains(where: { $0 != " " }), "dark cells render ink: '\(out)'")
    }
}
