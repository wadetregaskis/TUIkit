//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIConverter+Braille.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Braille Conversion

extension ASCIIConverter {

    /// Converts using 2x4 Braille character cells for maximum resolution.
    ///
    /// Each Braille character (U+2800-U+28FF) represents a 2x4 pixel grid.
    /// The dot pattern encodes which pixels are "on" based on a luminance
    /// threshold. Colour is taken from the average of the cell's pixels.
    ///
    /// Hot-path notes:
    /// - The eight 2x4-grid → braille-bit mappings are precomputed as a
    ///   flat 8-element table, indexed by `dy * 2 + dx`, instead of the
    ///   nested array literal the old implementation looked up per pixel.
    /// - Pixel access goes through an `UnsafeBufferPointer` over the
    ///   image's pixel array — the per-pixel bounds check otherwise costs
    ///   a comparison and a branch on every one of the 8 reads per cell.
    /// - Each cell's eight pixel offsets are precomputed once as flat
    ///   linear indices (`dy * imageWidth + dx`) and reused for every
    ///   cell along a row, so the hot loop is one add + one read per
    ///   pixel rather than two adds, a multiply, and a bounds check.
    /// - Luminance is computed inline with the same 0.299/0.587/0.114
    ///   coefficients ``RGBA/luminance`` uses, but as integer arithmetic
    ///   against a scaled threshold — comparing `r*299 + g*587 + b*114`
    ///   to the threshold scaled by 1000 matches the Double form to within
    ///   rounding and avoids the per-pixel `Double` conversions.
    ///
    /// - Parameter monoThreshold: The luminance at or above which a dot is lit.
    ///   Braille takes it in EVERY colour mode, not only monochrome: its dots
    ///   are always a binary decision — colour is averaged per cell separately
    ///   — so a threshold sitting outside a dark image's tones leaves a colour
    ///   render as blank as a mono one. See ``monoInkThreshold(for:)``.
    func convertBraille(
        _ image: RGBAImage, width: Int, height: Int, mode: ASCIIColorMode, monoThreshold: Double
    ) -> ASCIIArt {
        // Braille bit index for each (dy, dx) of the 2x4 cell.
        // Indexed by `dy * 2 + dx`.
        //   (0,0)=0  (0,1)=3
        //   (1,0)=1  (1,1)=4
        //   (2,0)=2  (2,1)=5
        //   (3,0)=6  (3,1)=7
        let dotBitsFlat: [UInt8] = [0, 3, 1, 4, 2, 5, 6, 7]

        // Cell-local linear pixel offsets relative to the cell's top-left.
        // The eight offsets cover (dy, dx) in the same row-major order as
        // `dotBitsFlat` so a single linear loop drives both.
        let imageWidth = image.width
        let imageHeight = image.height
        let cellOffsets: [Int] = (0..<8).map { index in
            let dy = index / 2
            let dx = index % 2
            return dy * imageWidth + dx
        }

        // 0.299*255 + 0.587*255 + 0.114*255 = 255, so a luminance threshold
        // scales into this integer form by 1000. (Mid-luminance, the old fixed
        // value, was 128 * 1000 = 128_000.)
        let scaledThreshold = Int(monoThreshold * 1000)

        // The mode resolved once for the whole picture — see `CellColours`.
        let colours = CellColours(mode: mode)

        return image.pixels.withUnsafeBufferPointer { buffer -> ASCIIArt in
            var lines = [String]()
            var coverage = CoverageMap()
            lines.reserveCapacity(height)

            for charY in 0..<height {
                var row = ANSIRowBuilder(capacity: width * 20)
                let pixelY = charY * 4

                for charX in 0..<width {
                    let pixelX = charX * 2
                    let baseIndex = pixelY * imageWidth + pixelX

                    // Drop out cleanly if the cell would walk off the
                    // bottom or right edge of the (already-scaled) source.
                    // The common case — a perfectly aligned image — never
                    // hits this branch in the inner loop.
                    let cellHeight = min(4, imageHeight - pixelY)
                    let cellWidth = min(2, imageWidth - pixelX)
                    guard cellHeight > 0, cellWidth > 0 else { continue }

                    var pattern: UInt8 = 0
                    var totalR = 0
                    var totalG = 0
                    var totalB = 0
                    var totalA = 0
                    var count = 0

                    for index in 0..<8 {
                        let dy = index / 2
                        let dx = index % 2
                        if dy >= cellHeight || dx >= cellWidth { continue }
                        let pixel = buffer[baseIndex + cellOffsets[index]]
                        let coverage = Int(pixel.a)
                        let r = Int(pixel.r)
                        let g = Int(pixel.g)
                        let b = Int(pixel.b)
                        // PREMULTIPLIED, for the reason `boxReduced(by:)` and
                        // `scaledBilinear(to:_:)` are (§41.1): a transparent dot's colour
                        // is meaningless and the decoders write it black, so averaging it
                        // straight pulls the cell's ink toward black. Eight dots is a
                        // small enough neighbourhood that one transparent corner visibly
                        // darkened a whole cell.
                        totalR += r * coverage
                        totalG += g * coverage
                        totalB += b * coverage
                        totalA += coverage
                        count += 1

                        // Integer-scaled BT.601 luminance against the
                        // matching scaled threshold; matches the Double
                        // form to within rounding.
                        //
                        // A dot must be THERE before it can be lit, and "there" is the
                        // ½ rule §6a states for every glyph decision: at or above half
                        // coverage the source's mark is drawn, below it the destination
                        // keeps its cell. Without this a transparent dot lit itself from
                        // whatever colour the encoder left in it.
                        if coverage >= 128, r * 299 + g * 587 + b * 114 >= scaledThreshold {
                            pattern |= 1 << dotBitsFlat[index]
                        }
                    }

                    // Braille character: U+2800 + pattern.
                    let brailleChar = Character(Unicode.Scalar(0x2800 + UInt32(pattern))!)

                    let avgPixel: RGBA
                    if totalA > 0 {
                        avgPixel = RGBA(
                            r: UInt8(clamping: totalR / totalA),
                            g: UInt8(clamping: totalG / totalA),
                            b: UInt8(clamping: totalB / totalA),
                            a: UInt8(clamping: totalA / max(1, count))
                        )
                    } else {
                        avgPixel = RGBA(r: 0, g: 0, b: 0, a: 0)
                    }

                    coverage.note(line: charY, column: charX, ink: avgPixel.a, field: .max)
                    row.setColors(foreground: colours.color(for: avgPixel), background: nil)
                    row.append(brailleChar)
                }
                lines.append(row.finish())
            }

            return ASCIIArt(lines: lines, coverage: coverage.runs)
        }
    }
}
