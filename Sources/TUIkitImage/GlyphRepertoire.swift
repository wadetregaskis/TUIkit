//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GlyphRepertoire.swift
//
//  The fundamental glyph charsets behind the image renderers, derived from
//  the one calibrated table (`generatedGlyphCalibration`), plus the
//  ideal-subset selection that makes a charset's SIZE configurable: density
//  ramps pick glyphs whose ink coverages span the range as evenly as
//  possible (preferring the flattest glyph at each level), and shape
//  vocabularies pick glyphs spread as widely as possible through shape
//  space (farthest-point selection).
//
//  Created by Wade Tregaskis
//  License: MIT

/// One calibrated glyph: measured total ink coverage, the 6-region shape
/// vector, and its derived flatness.
struct CalibratedGlyph: Sendable {
    let glyph: Character
    /// Mean ink over the whole cell, 0…1 (0 = space).
    let total: Double
    /// Raw per-region ink coverage at the six staggered sampling circles.
    let regions: [Double]
    /// How UNEVENLY the ink is distributed: the population standard
    /// deviation of the six regions. 0 = perfectly flat (space, `█`, the
    /// shades); high values mean the ink clumps (an `L`, a quadrant).
    let flatness: Double

    init(glyph: Character, total: Double, regions: [Double]) {
        self.glyph = glyph
        self.total = total
        self.regions = regions
        let mean = regions.reduce(0, +) / Double(regions.count)
        let variance =
            regions.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(regions.count)
        self.flatness = variance.squareRoot()
    }
}

/// The fundamental charsets, partitioned from the calibrated table by
/// Unicode range, and the ideal-subset selection over them.
enum GlyphRepertoire {

    /// Every calibrated glyph.
    static let all: [CalibratedGlyph] = generatedGlyphCalibration.map {
        CalibratedGlyph(glyph: $0.0, total: $0.1, regions: $0.2)
    }

    /// Whether a character is a Unicode Block Element (U+2580…U+259F) —
    /// the family the dedicated block modes own, and therefore excluded
    /// from the `unicode` charset.
    static func isBlockElement(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
            character.unicodeScalars.count == 1
        else { return false }
        return (0x2580...0x259F).contains(scalar.value)
    }

    /// The corner triangles: not Block Elements by Unicode range, but
    /// block-LIKE — solid half-cell ink with a diagonal edge — so the
    /// shape-aware blocks repertoire adopts them (they express the
    /// diagonals the quadrants can't).
    private static let cornerTriangles: Set<Character> = ["◢", "◣", "◤", "◥"]

    // MARK: - The fundamental charsets

    /// Printable ASCII.
    static let ascii: [CalibratedGlyph] = all.filter { entry in
        entry.glyph.unicodeScalars.count == 1 && entry.glyph.unicodeScalars.first!.value < 0x80
    }

    /// ASCII plus every non-block Unicode glyph (box drawing, geometric
    /// shapes, …). Block Elements are excluded — they belong to the
    /// dedicated block modes — and the calibration pipeline already limits
    /// the pool to single-cell glyphs that respect the foreground colour
    /// (no emoji or otherwise intrinsically-coloured characters).
    static let unicode: [CalibratedGlyph] = all.filter { !isBlockElement($0.glyph) }

    /// The shape-aware BLOCKS repertoire: space, the Block Elements
    /// (halves, quadrants, shades, eighth ladders, `█`), and the corner
    /// triangles `◢◣◤◥` for diagonal edges.
    static let blockShapes: [CalibratedGlyph] = all.filter {
        $0.glyph == " " || isBlockElement($0.glyph) || cornerTriangles.contains($0.glyph)
    }

    /// How many usefully-distinct density levels each sizeable pool offers
    /// a luminance ramp (its full-ramp length) — the effective ceiling for
    /// a non-shape `glyphs:` count. Cached: the full ramp is deterministic.
    static let asciiDensityLevels = densityRamp(from: ascii).count
    static let unicodeDensityLevels = densityRamp(from: unicode).count

    // MARK: - Density ramps (non-shape rendering)

    /// Near-equal coverages add banding, not tonal levels; within a group
    /// this close only the flattest glyph survives (matches the epsilon the
    /// old offline ramp generator used).
    private static let duplicateLevelEpsilon = 0.010

    /// How much flatness costs against density accuracy when choosing the
    /// glyph for a ramp level: a glyph may sit up to `weight × flatness`
    /// further from the target density and still win by being flatter.
    /// Density evenness stays primary; flatness breaks the real ties.
    private static let flatnessWeight = 0.25

    /// The ideal `count`-glyph density ramp from `pool`, ordered dark
    /// pixel → bright pixel (index 0 always renders black pixels, so it is
    /// always the space).
    ///
    /// `count` targets that many ink levels spaced evenly from zero to the
    /// pool's densest glyph; each target takes the unused glyph nearest in
    /// coverage, penalised by ``flatnessWeight`` × flatness so the flattest
    /// candidate wins among near-equals. `nil` (or a `count` beyond the
    /// pool's distinct levels) yields every usefully-distinct level. The
    /// result is sorted by coverage, so it is monotonic by construction.
    static func densityRamp(from pool: [CalibratedGlyph], count: Int? = nil) -> [Character] {
        // Distinct, flatness-preferred levels: sort by coverage, and within
        // duplicateLevelEpsilon of the previous KEPT level keep whichever
        // glyph is flatter.
        let sorted = pool.sorted { $0.total < $1.total }
        var levels: [CalibratedGlyph] = []
        for entry in sorted {
            if let last = levels.last, entry.total - last.total < duplicateLevelEpsilon {
                if entry.flatness < last.flatness {
                    levels[levels.count - 1] = entry
                }
            } else {
                levels.append(entry)
            }
        }
        guard levels.count > 1 else { return levels.map(\.glyph) }

        guard let count, count < levels.count else {
            return levels.map(\.glyph)
        }
        let clamped = max(2, count)

        // Evenly-spaced coverage targets across the pool's range; each takes
        // the unused level with the best density-plus-flatness score.
        let maxTotal = levels.last!.total
        var remaining = levels
        var picked: [CalibratedGlyph] = []
        for index in 0..<clamped {
            let target = Double(index) / Double(clamped - 1) * maxTotal
            let best = remaining.indices.min { lhs, rhs in
                score(remaining[lhs], target: target) < score(remaining[rhs], target: target)
            }!
            picked.append(remaining.remove(at: best))
        }
        return picked.sorted { $0.total < $1.total }.map(\.glyph)
    }

    private static func score(_ entry: CalibratedGlyph, target: Double) -> Double {
        abs(entry.total - target) + flatnessWeight * entry.flatness
    }

    // MARK: - Shape vocabularies (shape-aware rendering)

    /// The ideal `count`-glyph shape vocabulary from `pool`, as
    /// pool-normalised `(glyph, vector)` entries ready for
    /// ``ShapeTableColumns``.
    ///
    /// Vectors are normalised against the WHOLE pool's per-region maxima
    /// (so a subset's vectors mean the same thing at every size), then
    /// chosen by farthest-point (max-min distance) selection seeded with
    /// the space — each pick is the glyph farthest from everything already
    /// chosen, spreading the vocabulary as widely as possible through
    /// shape space. `nil` (or a count beyond the pool) is the whole pool.
    static func shapeVocabulary(
        from pool: [CalibratedGlyph], count: Int? = nil
    ) -> [(Character, [Double])] {
        let normalised = normalise(pool)
        guard let count, count < normalised.count else { return normalised }
        let clamped = max(2, count)

        // Seed with the space (empty cells must be able to render blank).
        var pickedIndices: [Int] = []
        if let spaceIndex = normalised.firstIndex(where: { $0.0 == " " }) {
            pickedIndices.append(spaceIndex)
        } else {
            pickedIndices.append(0)
        }

        // minDistance[i]: squared distance from entry i to its nearest
        // already-picked entry; each round picks the max and refreshes.
        var minDistance = [Double](repeating: .infinity, count: normalised.count)
        func refresh(around newIndex: Int) {
            let reference = normalised[newIndex].1
            for index in normalised.indices {
                var distance = 0.0
                let vector = normalised[index].1
                for component in vector.indices {
                    let delta = vector[component] - reference[component]
                    distance += delta * delta
                }
                if distance < minDistance[index] { minDistance[index] = distance }
            }
        }
        refresh(around: pickedIndices[0])

        while pickedIndices.count < clamped {
            var bestIndex = -1
            var bestDistance = -1.0
            for index in normalised.indices where !pickedIndices.contains(index) {
                if minDistance[index] > bestDistance {
                    bestDistance = minDistance[index]
                    bestIndex = index
                }
            }
            guard bestIndex >= 0 else { break }
            pickedIndices.append(bestIndex)
            refresh(around: bestIndex)
        }
        return pickedIndices.map { normalised[$0] }
    }

    /// Normalises each shape-vector component by the pool's maximum for
    /// that component, expanding the cluster to fill the unit cube (see
    /// the shape renderer's notes — without this every lookup gravitates
    /// to a corner of the space).
    private static func normalise(_ pool: [CalibratedGlyph]) -> [(Character, [Double])] {
        guard let regionCount = pool.first?.regions.count else { return [] }
        var maxima = [Double](repeating: 0, count: regionCount)
        for entry in pool {
            for index in entry.regions.indices where entry.regions[index] > maxima[index] {
                maxima[index] = entry.regions[index]
            }
        }
        return pool.map { entry in
            let vector = entry.regions.enumerated().map { index, value -> Double in
                maxima[index] > 0 ? value / maxima[index] : 0
            }
            return (entry.glyph, vector)
        }
    }
}
