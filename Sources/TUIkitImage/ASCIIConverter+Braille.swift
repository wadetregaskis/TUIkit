//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    ///   coefficients ``RGBA.luminance`` uses, but as integer arithmetic
    ///   against a scaled threshold — comparing `r*299 + g*587 + b*114`
    ///   to `128_000` matches the Double form bit-for-bit at this
    ///   precision and avoids the per-pixel `Double` conversions.
    func convertBraille(_ image: RGBAImage, width: Int, height: Int, mode: ASCIIColorMode) -> [String] {
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

        // 0.299*255 + 0.587*255 + 0.114*255 = 255; threshold is half the
        // unscaled range, so the integer-scaled threshold is
        // 128 * (0.299+0.587+0.114) * 1000 ≈ 128_000.
        let scaledThreshold = 128_000

        var lines = [String]()
        lines.reserveCapacity(height)

        let result = image.pixels.withUnsafeBufferPointer { buffer -> [String] in
            var lines = [String]()
            lines.reserveCapacity(height)

            for charY in 0..<height {
                var line = ""
                line.reserveCapacity(width * 20)
                var lastColor = ""
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
                    var count = 0

                    for index in 0..<8 {
                        let dy = index / 2
                        let dx = index % 2
                        if dy >= cellHeight || dx >= cellWidth { continue }
                        let pixel = buffer[baseIndex + cellOffsets[index]]
                        let r = Int(pixel.r)
                        let g = Int(pixel.g)
                        let b = Int(pixel.b)
                        totalR += r
                        totalG += g
                        totalB += b
                        count += 1

                        // Integer-scaled BT.601 luminance against the
                        // matching scaled threshold; matches the Double
                        // form to within rounding.
                        if r * 299 + g * 587 + b * 114 >= scaledThreshold {
                            pattern |= 1 << dotBitsFlat[index]
                        }
                    }

                    // Braille character: U+2800 + pattern.
                    let brailleChar = Character(Unicode.Scalar(0x2800 + UInt32(pattern))!)

                    let avgPixel: RGBA
                    if count > 0 {
                        avgPixel = RGBA(
                            r: UInt8(clamping: totalR / count),
                            g: UInt8(clamping: totalG / count),
                            b: UInt8(clamping: totalB / count)
                        )
                    } else {
                        avgPixel = RGBA(r: 0, g: 0, b: 0)
                    }

                    let colorCode = foregroundColorCode(for: avgPixel, mode: mode)
                    if colorCode != lastColor {
                        if !lastColor.isEmpty {
                            line += ANSIEscape.reset
                        }
                        line += colorCode
                        lastColor = colorCode
                    }
                    line.append(brailleChar)
                }

                if !lastColor.isEmpty {
                    line += ANSIEscape.reset
                }
                lines.append(line)
            }

            return lines
        }

        return result
    }
}
