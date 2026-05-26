//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ASCIIConverter+HalfBlocks.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Half-Block Conversion

extension ASCIIConverter {

    /// Renders an image using lower-half-block cells (`▄`) with independent
    /// foreground / background colours, effectively doubling the vertical
    /// resolution compared with the simple block renderer.
    ///
    /// Each terminal cell encodes two image pixels stacked vertically:
    /// - The **top** pixel is painted as the cell's background colour.
    /// - The **bottom** pixel is painted as the foreground of `▄` (U+2584
    ///   Lower Half Block), which fills the lower half of the cell.
    ///
    /// Because terminal characters are roughly twice as tall as they are
    /// wide, the resulting sub-cells are very nearly square — vertical and
    /// horizontal resolutions match, which is why this is the recommended
    /// "high-resolution" mode for any colour terminal.
    ///
    /// In monochrome mode the two pixels are thresholded against
    /// mid-luminance and drawn as space / `▀` / `▄` / `█` so the silhouette
    /// remains recognisable even without colour.
    func convertHalfBlocks(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        if mode == .mono {
            return convertHalfBlocksMono(image, width: width, height: height)
        }
        return convertHalfBlocksColor(image, width: width, height: height, mode: mode)
    }

    /// Colour variant: top pixel → background, bottom pixel → foreground of `▄`.
    private func convertHalfBlocksColor(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        let lowerHalfBlock: Character = "\u{2584}"

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
    private func convertHalfBlocksMono(
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
                    line.append("\u{2580}")  // ▀ Upper Half Block
                case (false, true):
                    line.append("\u{2584}")  // ▄ Lower Half Block
                case (true, true):
                    line.append("\u{2588}")  // █ Full Block
                }
            }
            lines.append(line)
        }
        return lines
    }
}
