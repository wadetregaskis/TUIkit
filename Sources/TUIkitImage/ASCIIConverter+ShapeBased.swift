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

        var lines = [String]()
        lines.reserveCapacity(height)

        for cellY in 0..<height {
            var line = ""
            line.reserveCapacity(width * 20)
            var lastColor = ""

            for cellX in 0..<width {
                let sampling = samplingVector(
                    image: image,
                    cellX: cellX,
                    cellY: cellY,
                    cellPixelWidth: cellPixelWidth,
                    cellPixelHeight: cellPixelHeight)
                let character = pickCharacter(for: sampling)

                // Use the cell's average colour as the character foreground.
                let averageColor = averagePixel(
                    image: image,
                    cellX: cellX,
                    cellY: cellY,
                    cellPixelWidth: cellPixelWidth,
                    cellPixelHeight: cellPixelHeight)
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

    /// Builds a 6D sampling vector for one cell by averaging the *darkness*
    /// (`1 - luminance / 255`) of the pixels under each sampling circle.
    private func samplingVector(
        image: RGBAImage,
        cellX: Int, cellY: Int,
        cellPixelWidth: Int, cellPixelHeight: Int
    ) -> [Double] {
        var vector: [Double] = []
        vector.reserveCapacity(ShapeRegion.centres.count)
        for centre in ShapeRegion.centres {
            var totalDarkness: Double = 0
            var count = 0
            for sampleIndex in 0..<ShapeRegion.samplesPerCircle {
                let angle = Double(sampleIndex) * 2.39996
                let r = ShapeRegion.radius
                    * (Double(sampleIndex) / Double(ShapeRegion.samplesPerCircle - 1)).squareRoot()
                let sx = centre.x + r * cos(angle)
                let sy = centre.y + r * sin(angle)
                let pixelX = cellX * cellPixelWidth
                    + min(cellPixelWidth - 1, max(0, Int(sx * Double(cellPixelWidth))))
                let pixelY = cellY * cellPixelHeight
                    + min(cellPixelHeight - 1, max(0, Int(sy * Double(cellPixelHeight))))
                let pixel = image.pixel(at: pixelX, pixelY)
                totalDarkness += 1.0 - (pixel.luminance / 255.0)
                count += 1
            }
            vector.append(count > 0 ? totalDarkness / Double(count) : 0)
        }
        return vector
    }

    /// Returns the average pixel value for a cell's footprint, used to pick
    /// the character's foreground colour.
    private func averagePixel(
        image: RGBAImage,
        cellX: Int, cellY: Int,
        cellPixelWidth: Int, cellPixelHeight: Int
    ) -> RGBA {
        var sumR = 0
        var sumG = 0
        var sumB = 0
        var count = 0
        let xStart = cellX * cellPixelWidth
        let yStart = cellY * cellPixelHeight
        let xEnd = min(image.width, xStart + cellPixelWidth)
        let yEnd = min(image.height, yStart + cellPixelHeight)
        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                let p = image.pixel(at: x, y)
                sumR += Int(p.r)
                sumG += Int(p.g)
                sumB += Int(p.b)
                count += 1
            }
        }
        guard count > 0 else { return RGBA(r: 0, g: 0, b: 0) }
        return RGBA(
            r: UInt8(sumR / count),
            g: UInt8(sumG / count),
            b: UInt8(sumB / count))
    }

    /// Finds the character in the shape table whose shape vector is closest
    /// (Euclidean distance) to the given sampling vector.
    private func pickCharacter(for samplingVector: [Double]) -> Character {
        var best: Character = " "
        var bestDistanceSquared = Double.infinity
        for entry in shapeTable {
            var distanceSquared: Double = 0
            for index in samplingVector.indices {
                let delta = samplingVector[index] - entry.vector[index]
                distanceSquared += delta * delta
            }
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                best = entry.character
            }
        }
        return best
    }
}

// MARK: - Trig (avoid pulling in Foundation just for sin/cos)

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
