//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ASCIIConverter+ShapeBased.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Shape-vector ASCII rendering after the technique described in
//  Alex Harri's "ASCII characters are not pixels"
//  (https://alexharri.com/blog/ascii-rendering).  Each character is
//  represented by a 6-dimensional shape vector sampled from a 2×3 grid of
//  staggered "sampling circles" over the cell, and each image cell is
//  matched to the character whose shape vector is closest in Euclidean
//  distance.  This captures the *shape* of each character — `L` is heavier
//  in the lower-left, `T` along the top, `^` in the upper middle — instead
//  of treating each cell as a single pixel.

// The sampling geometry (`ShapeRegion`: circle centres, radius, sample count,
// and the spiral that places the samples) lives in ShapeSampling.swift, a
// dependency-free file shared with the offline calibration tool so the two
// cannot drift apart.

// MARK: - Shape Vectors

/// One pre-computed entry — a character paired with the 6D shape vector
/// derived from its bitmap.
private struct ShapeEntry {
    let character: Character
    let vector: [Double]  // length 6
}

/// Parallel-array view of a shape table: each of the six shape dimensions
/// laid out contiguously, plus the characters themselves.
///
/// The hot ``pickCharacter`` loop reads each dimension separately, so a
/// per-dimension flat array gives better locality than indirecting through
/// a struct-of-arrays.
struct ShapeTableColumns {
    let t0: [Double], t1: [Double], t2: [Double]
    let t3: [Double], t4: [Double], t5: [Double]
    let characters: [Character]

    fileprivate init(_ table: [ShapeEntry]) {
        t0 = table.map { $0.vector[0] }
        t1 = table.map { $0.vector[1] }
        t2 = table.map { $0.vector[2] }
        t3 = table.map { $0.vector[3] }
        t4 = table.map { $0.vector[4] }
        t5 = table.map { $0.vector[5] }
        characters = table.map { $0.character }
    }
}

// The pre-computed (and normalised) shape tables — the ASCII set behind
// `.shapeBased` / `.shapeUnicode`, and the wide Unicode set (blocks,
// quadrants, shades, eighth-block ladders + the ASCII glyphs) behind
// `.unicodeDetailed`. Built once on first access and reused across every
// conversion call; materialising the column views up front spares seven
// allocations per convert call.
let asciiShapeColumns = ShapeTableColumns(computeShapeTable(raw: generatedShapeCoverage))
let unicodeShapeColumns = ShapeTableColumns(computeShapeTable(raw: generatedUnicodeShapeCoverage))

private func computeShapeTable(raw: [(Character, [Double])]) -> [ShapeEntry] {
    // Raw per-region coverage vectors measured from the reference font by
    // `Tools/GenerateImageGlyphs` (see ImageGlyphCalibration.generated.swift),
    // sampled at the same six circles the runtime uses.

    // Normalise each component by the maximum value across all characters,
    // so the cluster of vectors expands to fill the unit cube — without
    // this step every sample lookup would gravitate to a small handful of
    // characters in one corner of the space (per the article's plot).
    var maxima = [Double](repeating: 0, count: ShapeRegion.centres.count)
    for (_, vector) in raw {
        for index in vector.indices where vector[index] > maxima[index] {
            maxima[index] = vector[index]
        }
    }
    var entries: [ShapeEntry] = []
    entries.reserveCapacity(raw.count)
    for (character, vector) in raw {
        let normalised = vector.enumerated().map { index, value -> Double in
            let max = maxima[index]
            return max > 0 ? value / max : 0
        }
        entries.append(ShapeEntry(character: character, vector: normalised))
    }
    return entries
}

// MARK: - Conversion

extension ASCIIConverter {

    /// Renders an image using shape-based character lookup, per
    /// alexharri.com/blog/ascii-rendering.
    ///
    /// For each output cell we sample the (already-scaled) source image at
    /// the same six staggered points used to build the character shape
    /// table, then pick the character whose shape vector is closest in
    /// Euclidean distance.  The result follows curved edges far better
    /// than the simple per-cell-luminance approach because the picked
    /// character itself carries directional information.
    ///
    /// The hot loop pre-computes one set of pixel-space sample offsets and
    /// reuses it for every cell — the original implementation re-ran
    /// 96 trig calls per cell, which made larger images visibly slow.
    /// Foreground colour is averaged from the same sampled pixels rather
    /// than from a second full-cell scan.
    func convertShapeBased(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode,
        unicodeEdges: Bool = false,
        wideUnicode: Bool = false
    ) -> [String] {
        // The glyph table: the ASCII shape set, or the wide Unicode set
        // (blocks/quadrants/shades + the ASCII glyphs) for `.unicodeDetailed`.
        let columns = wideUnicode ? unicodeShapeColumns : asciiShapeColumns
        guard !columns.characters.isEmpty else { return [] }

        // The line glyphs used for a strongly-directional (edge) cell: ASCII
        // slashes, or Unicode box-drawing for the `.shapeUnicode` /
        // `.unicodeDetailed` modes.
        let edge: (horizontal: Character, vertical: Character, backslash: Character, slash: Character) =
            unicodeEdges ? ("─", "│", "╲", "╱") : ("-", "|", "\\", "/")

        // Each cell of the output covers `cellPixelWidth × cellPixelHeight`
        // pixels of the (pre-scaled) source image.
        let cellPixelWidth = max(1, image.width / max(1, width))
        let cellPixelHeight = max(1, image.height / max(1, height))

        // Precompute pixel offsets for every (centre, sample) pair once.
        // We collapse the 6 × 16 nested layout into a single flat array of
        // *linear* pixel-buffer offsets — each entry already includes the
        // image's row stride, so the per-sample work in the hot path is
        // just one add and one array read.
        let offsets = SampleOffsets.compute(
            cellPixelWidth: cellPixelWidth,
            cellPixelHeight: cellPixelHeight,
            imageWidth: image.width
        )
        let sampleCount = ShapeRegion.samplesPerCircle
        let centreCount = ShapeRegion.centres.count
        let inverseSampleCount = 1.0 / Double(sampleCount)
        let inverseAllSamples = 1.0 / Double(sampleCount * centreCount)
        let imageWidth = image.width

        // Pull the shape table's parallel-array columns once; global,
        // immutable, materialised on first access.
        let table0 = columns.t0
        let table1 = columns.t1
        let table2 = columns.t2
        let table3 = columns.t3
        let table4 = columns.t4
        let table5 = columns.t5
        let characters = columns.characters

        var lines = [String]()
        lines.reserveCapacity(height)

        // Render through an unsafe pointer to the pixel array — the hot
        // path makes 96 reads per cell, and we know all the indices are
        // in-bounds because the sample offsets were clamped during their
        // precomputation. Skipping bounds checks here lifts the renderer
        // a long way out of "noticeably slow" territory.
        lines = image.pixels.withUnsafeBufferPointer { pixelBuffer -> [String] in
            var lines = [String]()
            lines.reserveCapacity(height)

            // Scratch storage reused per cell.
            var sampling = [Double](repeating: 0, count: centreCount)

            for cellY in 0..<height {
                let baseY = cellY * cellPixelHeight
                var line = ""
                line.reserveCapacity(width * 20)
                var lastColor = ""

                for cellX in 0..<width {
                    let baseX = cellX * cellPixelWidth
                    let baseLinearIndex = baseY * imageWidth + baseX

                    // Sample the cell, accumulating per-circle darkness and
                    // a global RGB sum (for the foreground colour) in one
                    // pass over the precomputed flat offset table.
                    var sumR = 0
                    var sumG = 0
                    var sumB = 0
                    for centreIndex in 0..<centreCount {
                        var totalDarkness: Double = 0
                        let centreBase = centreIndex * sampleCount
                        for sampleIndex in 0..<sampleCount {
                            let pixel = pixelBuffer[
                                baseLinearIndex + offsets[centreBase + sampleIndex]
                            ]
                            totalDarkness += 1.0 - (pixel.luminance / 255.0)
                            sumR += Int(pixel.r)
                            sumG += Int(pixel.g)
                            sumB += Int(pixel.b)
                        }
                        sampling[centreIndex] = totalDarkness * inverseSampleCount
                    }

                    // A strong directional edge overrides the coverage match
                    // with the orientation-matched line glyph; otherwise fall
                    // back to the nearest-shape character.
                    let character =
                        Self.orientationGlyph(
                            sampling: sampling, edge: edge, threshold: edgeThreshold)
                        ?? Self.pickCharacter(
                            sampling: sampling,
                            t0: table0, t1: table1, t2: table2, t3: table3, t4: table4, t5: table5,
                            characters: characters)

                    // Use the sampled pixels' average as the foreground colour;
                    // the 96 samples cover the cell densely enough that a
                    // separate full-cell scan would be near-identical.
                    //
                    // Clamp the cast: `UInt8(_:)` on a Double traps when the
                    // value lies even a hair above 255, which is exactly
                    // what happens when every sample is at maximum (96 *
                    // 255 multiplied by the inexact `1.0 / 96.0` can come
                    // back as 255.000…001). Crashed the Image (File) demo
                    // in the wild.
                    let averageColor = RGBA(
                        r: UInt8(clamping: Int((Double(sumR) * inverseAllSamples).rounded())),
                        g: UInt8(clamping: Int((Double(sumG) * inverseAllSamples).rounded())),
                        b: UInt8(clamping: Int((Double(sumB) * inverseAllSamples).rounded())))
                    let colorCode = foregroundColorCode(for: averageColor, mode: mode)
                    if colorCode != lastColor {
                        if !lastColor.isEmpty {
                            line += ANSIEscape.reset
                        }
                        line += colorCode
                        lastColor = colorCode
                    }
                    line.append(character)
                }
                if !lastColor.isEmpty {
                    line += ANSIEscape.reset
                }
                lines.append(line)
            }
            return lines
        }
        return lines
    }

    /// Finds the character in the shape table whose shape vector is closest
    /// (Euclidean distance) to the given sampling vector — the squared
    /// version, since we only need ordering.
    ///
    /// The table is passed as six parallel `[Double]` arrays so the loop
    /// indexes contiguous buffers instead of indirecting through a struct
    /// per character, which materially helps the hot path.
    fileprivate static func pickCharacter(
        sampling: [Double],
        t0: [Double], t1: [Double], t2: [Double],
        t3: [Double], t4: [Double], t5: [Double],
        characters: [Character]
    ) -> Character {
        let s0 = sampling[0], s1 = sampling[1], s2 = sampling[2]
        let s3 = sampling[3], s4 = sampling[4], s5 = sampling[5]
        var bestIndex = 0
        var bestDistanceSquared = Double.infinity
        for index in characters.indices {
            let d0 = s0 - t0[index]
            let d1 = s1 - t1[index]
            let d2 = s2 - t2[index]
            let d3 = s3 - t3[index]
            let d4 = s4 - t4[index]
            let d5 = s5 - t5[index]
            let distanceSquared = d0 * d0 + d1 * d1 + d2 * d2 + d3 * d3 + d4 * d4 + d5 * d5
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                bestIndex = index
            }
        }
        return characters[bestIndex]
    }

    /// Returns the line glyph matching a cell's dominant edge orientation, or
    /// `nil` when the cell carries no strong directional edge (or edge glyphs
    /// are disabled: `threshold` `nil`).
    ///
    /// The gradient is a Sobel-style difference over the six staggered darkness
    /// regions (`[0][1]` top / `[2][3]` middle / `[4][5]` bottom): `gx` is the
    /// left-minus-right darkness, `gy` the top-minus-bottom. The edge runs
    /// perpendicular to the gradient — tangent `(-gy, gx)` — which classifies
    /// into horizontal / vertical / the two diagonals. Reuses the darkness
    /// vector already sampled for the coverage match, so it adds no image reads.
    fileprivate static func orientationGlyph(
        sampling: [Double],
        edge: (horizontal: Character, vertical: Character, backslash: Character, slash: Character),
        threshold: Double?
    ) -> Character? {
        guard let threshold else { return nil }
        let gx = (sampling[0] + sampling[2] + sampling[4]) - (sampling[1] + sampling[3] + sampling[5])
        let gy = (sampling[0] + sampling[1]) - (sampling[4] + sampling[5])
        guard (gx * gx + gy * gy).squareRoot() >= threshold else { return nil }

        // Edge tangent perpendicular to the gradient.
        let tangentX = -gy
        let tangentY = gx
        let ax = abs(tangentX)
        let ay = abs(tangentY)
        if ax >= 2 * ay { return edge.horizontal }
        if ay >= 2 * ax { return edge.vertical }
        // Same sign → down-right tangent → "\"; opposite → up-right → "/".
        return (tangentX * tangentY > 0) ? edge.backslash : edge.slash
    }
}

// MARK: - Precomputed Sample Offsets

/// Per-call pixel-space sample offsets, precomputed once per call to
/// `convertShapeBased`.
///
/// The renderer's hot path reads 96 (= 6 centres × 16 samples) pixels per
/// cell. With the source image stored as a flat row-major buffer, each
/// per-sample offset reduces to a single linear index relative to the
/// cell's top-left pixel — i.e. `sy * imageWidth + sx`. Precomputing those
/// linear indices once and laying them out as a single contiguous
/// `[Int]` (centre-major, sample-minor) means the inner loop is one array
/// fetch per sample, no nested array indirection or repeated multiplies.
private enum SampleOffsets {
    /// Computes the 96 linear offsets for the given cell footprint.
    ///
    /// The offsets only depend on the cell's pixel footprint, the image's
    /// stride, and the (constant) sampling-circle geometry, so the same
    /// table is reused for every cell — eliminating ~96 sin/cos calls per
    /// cell and any per-sample multiply-by-width.
    static func compute(cellPixelWidth: Int, cellPixelHeight: Int, imageWidth: Int) -> [Int] {
        // Both the spiral geometry and the point→pixel mapping are shared with
        // the calibration tool via `ShapeRegion` (ShapeSampling.swift); here we
        // only fold in this image's row stride. Computed once per call.
        let points = ShapeRegion.normalizedSamplePoints()
        var offsets = [Int]()
        offsets.reserveCapacity(points.count)
        for point in points {
            let (px, py) = ShapeRegion.pixel(
                for: point, width: cellPixelWidth, height: cellPixelHeight)
            offsets.append(py * imageWidth + px)
        }
        return offsets
    }
}
