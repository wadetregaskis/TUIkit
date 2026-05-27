//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ASCIIConverter+FineBlocks.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Fine-Block (Half-Block) Conversion

extension ASCIIConverter {

    /// Renders an image using lower-half-block cells (`▄`) with independent
    /// foreground / background colours, effectively doubling the vertical
    /// resolution compared with the coarse single-glyph-per-cell renderer.
    ///
    /// Each terminal cell encodes two image pixels stacked vertically:
    /// - The **top** pixel is painted as the cell's background colour.
    /// - The **bottom** pixel is painted as the foreground of `▄` (U+2584
    ///   Lower Half Block), which fills the lower half of the cell.
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

    /// Colour variant: top pixel → background, bottom pixel → foreground of `▄`.
    private func convertFineBlocksColor(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        let lowerHalfBlock: Character = "▄"

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

                let fgCode = foregroundColorCode(for: bottomPixel, mode: mode)
                let bgCode = backgroundColorCode(for: topPixel, mode: mode)

                if fgCode != lastFg || bgCode != lastBg {
                    if !lastFg.isEmpty || !lastBg.isEmpty {
                        line += ANSIEscape.reset
                    }
                    line += fgCode + bgCode
                    lastFg = fgCode
                    lastBg = bgCode
                }
                line.append(lowerHalfBlock)
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
