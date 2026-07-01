//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ASCIIConverter+FineBlocks.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Fine-Block (Half-Block) Conversion

extension ASCIIConverter {

    /// Renders an image using upper-half-block cells (`▀`) with independent
    /// foreground / background colours, effectively doubling the vertical
    /// resolution compared with the coarse single-glyph-per-cell renderer.
    ///
    /// Each terminal cell encodes two image pixels stacked vertically:
    /// - The **top** pixel is painted as the foreground of `▀` (U+2580 Upper
    ///   Half Block), which fills the upper half of the cell.
    /// - The **bottom** pixel is painted as the cell's background colour, which
    ///   the terminal fills across the whole cell before the glyph overpaints
    ///   the top half.
    ///
    /// The *upper* half block is deliberate (rather than the lower `▄`): it
    /// keeps the colour boundary in the middle of the cell. Some terminals —
    /// notably Terminal.app with SF Mono at certain sizes, including the default
    /// 11 pt — don't rasterise a half-block glyph all the way to the cell's far
    /// edge. With the *lower* half block that shortfall lands at the cell's
    /// bottom edge, so the background (top-pixel) colour bleeds through as a thin
    /// horizontal band between rows. With the *upper* half block the same
    /// shortfall lands mid-cell against the background (bottom-pixel) colour it
    /// already sits on, so it is invisible.
    ///
    /// Because terminal characters are roughly twice as tall as they are
    /// wide, the resulting sub-cells are very nearly square — vertical and
    /// horizontal resolutions match, which is why this is the default
    /// (and recommended) mode for any colour terminal.
    ///
    /// In monochrome mode the two pixels are thresholded against
    /// mid-luminance and drawn as space / `▀` / `▄` / `█` so the silhouette
    /// remains recognisable even without colour.
    func convertFineBlocks(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        if mode == .mono {
            return convertFineBlocksMono(image, width: width, height: height)
        }
        return convertFineBlocksColor(image, width: width, height: height, mode: mode)
    }

    /// Colour variant: top pixel → foreground of `▀`, bottom pixel → background.
    private func convertFineBlocksColor(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        let upperHalfBlock: Character = "▀"

        var lines = [String]()
        lines.reserveCapacity(height)

        for cellY in 0..<height {
            var line = ""
            line.reserveCapacity(width * 32)  // foreground + background ANSI per cell
            var lastFg = ""
            var lastBg = ""

            for cellX in 0..<width {
                let topPixel = image.pixel(at: cellX, 2 * cellY)
                let bottomPixel = image.pixel(at: cellX, 2 * cellY + 1)

                let fgCode = foregroundColorCode(for: topPixel, mode: mode)
                let bgCode = backgroundColorCode(for: bottomPixel, mode: mode)

                if fgCode != lastFg || bgCode != lastBg {
                    if !lastFg.isEmpty || !lastBg.isEmpty {
                        line += ANSIEscape.reset
                    }
                    line += fgCode + bgCode
                    lastFg = fgCode
                    lastBg = bgCode
                }
                line.append(upperHalfBlock)
            }

            if !lastFg.isEmpty || !lastBg.isEmpty {
                line += ANSIEscape.reset
            }
            lines.append(line)
        }
        return lines
    }

    /// Monochrome variant: threshold both pixels at mid-luminance and pick
    /// the block glyph that best represents which halves are "dark".
    private func convertFineBlocksMono(
        _ image: RGBAImage,
        width: Int,
        height: Int
    ) -> [String] {
        // A pixel is rendered as "ink" if its luminance is below this
        // threshold — i.e. images of dark text on a light background look
        // sensible on a typical light-on-dark terminal.
        let inkThreshold: Double = 128

        var lines = [String]()
        lines.reserveCapacity(height)

        for cellY in 0..<height {
            var line = ""
            line.reserveCapacity(width)
            for cellX in 0..<width {
                let topDark = image.pixel(at: cellX, 2 * cellY).luminance < inkThreshold
                let bottomDark = image.pixel(at: cellX, 2 * cellY + 1).luminance < inkThreshold
                switch (topDark, bottomDark) {
                case (false, false):
                    line.append(" ")
                case (true, false):
                    line.append("▀")
                case (false, true):
                    line.append("▄")
                case (true, true):
                    line.append("█")
                }
            }
            lines.append(line)
        }
        return lines
    }
}
