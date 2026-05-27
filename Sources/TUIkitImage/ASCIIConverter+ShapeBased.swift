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

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Cell Shape Vector

/// The 6 sampling-circle indices that make up a cell's shape vector.
///
/// Layout, matching the alexharri.com article — left circles dropped a
/// little, right circles raised, so that staggering them fills the cell
/// with minimal gaps:
///
/// ```
///  [0]   [1]      ← upper row  (upper-left, upper-right)
///  [2]   [3]      ← middle row
///  [4]   [5]      ← lower row
/// ```
private enum ShapeRegion {
    /// Normalised sampling-circle centres `(x, y)` in `[0, 1]` cell space.
    static let centres: [(x: Double, y: Double)] = [
        (0.27, 0.22),  // 0 upper-left
        (0.73, 0.15),  // 1 upper-right
        (0.27, 0.52),  // 2 middle-left
        (0.73, 0.48),  // 3 middle-right
        (0.27, 0.82),  // 4 lower-left
        (0.73, 0.78),  // 5 lower-right
    ]

    /// Sampling-circle radius in normalised cell-width units.
    static let radius: Double = 0.30

    /// Number of samples taken per circle when computing a vector.
    static let samplesPerCircle: Int = 16
}

// MARK: - Character Bitmaps

/// A 5-wide × 10-tall binary bitmap for an ASCII character.
///
/// Each row is encoded as a five-character string of `"0"` / `"1"`. Both
/// the visual density of each row and the row's position contribute to
/// the character's shape vector, which is sampled from these bitmaps once
/// at startup.
private struct CharBitmap {
    let character: Character
    let rows: [String]
}

/// A small but expressive set of ASCII characters with hand-drawn bitmaps.
///
/// Picked to cover the major shape regions of the cell — upper-only
/// characters (`"`, `^`, `'`), lower-only (`.`, `,`, `_`), corner
/// characters (`L`, `J`), through to dense fills (`@`, `#`).
private let shapeBasedBitmaps: [CharBitmap] = [
    CharBitmap(character: " ", rows: [
        "00000", "00000", "00000", "00000", "00000",
        "00000", "00000", "00000", "00000", "00000",
    ]),
    CharBitmap(character: ".", rows: [
        "00000", "00000", "00000", "00000", "00000",
        "00000", "00000", "01110", "01110", "00000",
    ]),
    CharBitmap(character: ",", rows: [
        "00000", "00000", "00000", "00000", "00000",
        "00000", "00000", "01100", "01100", "11000",
    ]),
    CharBitmap(character: "'", rows: [
        "01110", "01110", "01000", "00000", "00000",
        "00000", "00000", "00000", "00000", "00000",
    ]),
    CharBitmap(character: "`", rows: [
        "11000", "01100", "00000", "00000", "00000",
        "00000", "00000", "00000", "00000", "00000",
    ]),
    CharBitmap(character: "\"", rows: [
        "11011", "11011", "00000", "00000", "00000",
        "00000", "00000", "00000", "00000", "00000",
    ]),
    CharBitmap(character: ":", rows: [
        "00000", "00100", "00100", "00000", "00000",
        "00000", "00000", "00100", "00100", "00000",
    ]),
    CharBitmap(character: ";", rows: [
        "00000", "00100", "00100", "00000", "00000",
        "00000", "00000", "00100", "00100", "01000",
    ]),
    CharBitmap(character: "-", rows: [
        "00000", "00000", "00000", "00000", "11111",
        "11111", "00000", "00000", "00000", "00000",
    ]),
    CharBitmap(character: "_", rows: [
        "00000", "00000", "00000", "00000", "00000",
        "00000", "00000", "00000", "11111", "11111",
    ]),
    CharBitmap(character: "~", rows: [
        "00000", "00000", "00000", "01001", "10110",
        "11001", "01000", "00000", "00000", "00000",
    ]),
    CharBitmap(character: "^", rows: [
        "00100", "01010", "10001", "00000", "00000",
        "00000", "00000", "00000", "00000", "00000",
    ]),
    CharBitmap(character: "|", rows: [
        "00100", "00100", "00100", "00100", "00100",
        "00100", "00100", "00100", "00100", "00100",
    ]),
    CharBitmap(character: "/", rows: [
        "00001", "00001", "00010", "00010", "00100",
        "00100", "01000", "01000", "10000", "10000",
    ]),
    CharBitmap(character: "\\", rows: [
        "10000", "10000", "01000", "01000", "00100",
        "00100", "00010", "00010", "00001", "00001",
    ]),
    CharBitmap(character: "+", rows: [
        "00000", "00000", "00100", "00100", "01110",
        "01110", "00100", "00100", "00000", "00000",
    ]),
    CharBitmap(character: "*", rows: [
        "00000", "00000", "00000", "10101", "01110",
        "01110", "10101", "00000", "00000", "00000",
    ]),
    CharBitmap(character: "=", rows: [
        "00000", "00000", "00000", "01110", "00000",
        "00000", "01110", "00000", "00000", "00000",
    ]),
    CharBitmap(character: "<", rows: [
        "00000", "00001", "00010", "00100", "01000",
        "01000", "00100", "00010", "00001", "00000",
    ]),
    CharBitmap(character: ">", rows: [
        "00000", "10000", "01000", "00100", "00010",
        "00010", "00100", "01000", "10000", "00000",
    ]),
    CharBitmap(character: "L", rows: [
        "10000", "10000", "10000", "10000", "10000",
        "10000", "10000", "10000", "10000", "11111",
    ]),
    CharBitmap(character: "J", rows: [
        "00001", "00001", "00001", "00001", "00001",
        "00001", "00001", "10001", "10001", "01110",
    ]),
    CharBitmap(character: "T", rows: [
        "11111", "11111", "00100", "00100", "00100",
        "00100", "00100", "00100", "00100", "00100",
    ]),
    CharBitmap(character: "V", rows: [
        "10001", "10001", "10001", "10001", "01010",
        "01010", "01010", "00100", "00100", "00100",
    ]),
    CharBitmap(character: "I", rows: [
        "11111", "00100", "00100", "00100", "00100",
        "00100", "00100", "00100", "00100", "11111",
    ]),
    CharBitmap(character: "O", rows: [
        "01110", "10001", "10001", "10001", "10001",
        "10001", "10001", "10001", "10001", "01110",
    ]),
    CharBitmap(character: "#", rows: [
        "01010", "01010", "11111", "01010", "01010",
        "01010", "01010", "11111", "01010", "01010",
    ]),
    CharBitmap(character: "%", rows: [
        "11001", "11010", "00010", "00100", "00100",
        "01000", "01000", "10001", "01011", "00011",
    ]),
    CharBitmap(character: "@", rows: [
        "01110", "10001", "10111", "10101", "10101",
        "10101", "10101", "10110", "10000", "01111",
    ]),
]

// MARK: - Shape Vectors

/// One pre-computed entry — a character paired with the 6D shape vector
/// derived from its bitmap.
private struct ShapeEntry {
    let character: Character
    let vector: [Double]  // length 6
}

/// The pre-computed (and normalised) shape table, one entry per bitmap.
///
/// The table is built once on first access and reused across every
/// conversion call. Sampling each character is cheap (a few hundred
/// integer operations) but the work is constant per process.
private let shapeTable: [ShapeEntry] = computeShapeTable()

/// Parallel-array view of ``shapeTable``: each of the six shape dimensions
/// laid out contiguously, plus the characters themselves.
///
/// The hot ``pickCharacter`` loop reads each dimension separately, so a
/// per-dimension flat array gives better locality than indirecting through
/// a struct-of-arrays. Materialised once on first access, then reused —
/// the previous code materialised these six maps + the characters array
/// on every call, costing seven allocations per `convertShapeBased` even
/// before the loop ran.
private let shapeTableColumns: (
    t0: [Double], t1: [Double], t2: [Double],
    t3: [Double], t4: [Double], t5: [Double],
    characters: [Character]
) = {
    let table = shapeTable
    return (
        t0: table.map { $0.vector[0] },
        t1: table.map { $0.vector[1] },
        t2: table.map { $0.vector[2] },
        t3: table.map { $0.vector[3] },
        t4: table.map { $0.vector[4] },
        t5: table.map { $0.vector[5] },
        characters: table.map { $0.character }
    )
}()

private func computeShapeTable() -> [ShapeEntry] {
    // Raw vectors before normalisation.
    var raw: [(Character, [Double])] = []
    raw.reserveCapacity(shapeBasedBitmaps.count)
    for bitmap in shapeBasedBitmaps {
        raw.append((bitmap.character, shapeVector(from: bitmap)))
    }

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

/// Computes a 6D shape vector for a character bitmap by sampling its
/// rasterised pixels inside each of the six sampling circles.
private func shapeVector(from bitmap: CharBitmap) -> [Double] {
    let width = bitmap.rows.first?.count ?? 0
    let height = bitmap.rows.count
    guard width > 0, height > 0 else {
        return [Double](repeating: 0, count: ShapeRegion.centres.count)
    }

    // Quick lookup: is the pixel at (x, y) of the bitmap "filled"?
    func filled(_ x: Int, _ y: Int) -> Bool {
        guard (0..<height).contains(y), (0..<width).contains(x) else { return false }
        let row = bitmap.rows[y]
        return row[row.index(row.startIndex, offsetBy: x)] == "1"
    }

    var vector: [Double] = []
    vector.reserveCapacity(ShapeRegion.centres.count)
    for centre in ShapeRegion.centres {
        var hits = 0
        for sampleIndex in 0..<ShapeRegion.samplesPerCircle {
            // Distribute sample points around the centre on a Vogel-like
            // sunflower spiral so they cover the circle evenly.
            let angle = Double(sampleIndex) * 2.39996  // golden angle
            let r = ShapeRegion.radius
                * (Double(sampleIndex) / Double(ShapeRegion.samplesPerCircle - 1)).squareRoot()
            let sx = centre.x + r * cos(angle)
            let sy = centre.y + r * sin(angle)
            // Map normalised cell coords back to bitmap pixel indices.
            let px = Int((sx * Double(width)).rounded(.down))
            let py = Int((sy * Double(height)).rounded(.down))
            if filled(px, py) {
                hits += 1
            }
        }
        vector.append(Double(hits) / Double(ShapeRegion.samplesPerCircle))
    }
    return vector
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
        mode: ASCIIColorMode
    ) -> [String] {
        guard !shapeTable.isEmpty else { return [] }

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

        // Pull the shape table's parallel-array columns once. These are
        // global, immutable, and materialised on first access — see
        // ``shapeTableColumns``.
        let columns = shapeTableColumns
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

                    let character = Self.pickCharacter(
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
        let sampleCount = ShapeRegion.samplesPerCircle
        let denom = max(1, sampleCount - 1)
        let maxX = max(0, cellPixelWidth - 1)
        let maxY = max(0, cellPixelHeight - 1)
        let widthD = Double(cellPixelWidth)
        let heightD = Double(cellPixelHeight)

        var offsets = [Int]()
        offsets.reserveCapacity(ShapeRegion.centres.count * sampleCount)
        for centre in ShapeRegion.centres {
            for sampleIndex in 0..<sampleCount {
                let angle = Double(sampleIndex) * 2.39996  // golden angle
                let r = ShapeRegion.radius
                    * (Double(sampleIndex) / Double(denom)).squareRoot()
                let sx = centre.x + r * cos(angle)
                let sy = centre.y + r * sin(angle)
                let px = min(maxX, max(0, Int(sx * widthD)))
                let py = min(maxY, max(0, Int(sy * heightD)))
                offsets.append(py * imageWidth + px)
            }
        }
        return offsets
    }
}
