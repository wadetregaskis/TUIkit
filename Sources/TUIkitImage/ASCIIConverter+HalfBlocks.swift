//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIConverter+HalfBlocks.swift
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
    /// In monochrome mode the two pixels are thresholded — at
    /// `monoThreshold`, measured from the image by ``monoInkThreshold(for:)``
    /// — and drawn as space / `▀` / `▄` / `█` so the silhouette remains
    /// recognisable even without colour.
    func convertHalfBlocks(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode,
        monoThreshold: Double
    ) -> [String] {
        if mode == .mono {
            return convertHalfBlocksMono(
                image, width: width, height: height, monoThreshold: monoThreshold)
        }
        return convertHalfBlocksColor(image, width: width, height: height, mode: mode)
    }

    /// Colour variant: top pixel → background, bottom pixel → foreground of `▄`.
    ///
    /// **A cell whose two pixels paint the same colour is emitted as a SPACE
    /// with only a background**, not as a block wearing one colour twice. Most
    /// of a picture is such cells — 41.8% of the demo photograph's at true
    /// colour, 73.6% at 256, **86.5% at sixteen**, because the coarser the
    /// palette the more often two neighbouring pixels land on one entry — and
    /// spelling them as a glyph costs three ways:
    ///
    /// - It states a foreground the cell does not use, which is bytes, and on
    ///   Warp it is worse than bytes: `enforce_minimum_contrast` defaults to
    ///   `only_named_colors`, so a foreground NAMED as one of the sixteen and
    ///   unreadable against its background gets lightened for legibility. A
    ///   half block with foreground == background is the most unreadable text
    ///   there is, so every such cell had its lower half lifted to grey while
    ///   its upper half stayed put: the picture came out banded at cell pitch.
    ///   A space has no text to make readable.
    /// - It asks the font for a glyph whose shape cannot matter, which is
    ///   rasterisation work per cell and the rasterisation gap below.
    /// - It is not what the cell means. One colour is a field, not a shape.
    ///
    /// The comparison is of the two halves' BACKGROUND codes, so both are
    /// asked the same question in the same spelling: this is about the colour
    /// that will be PAINTED, and neighbouring pixels differ far more often
    /// than the colours they quantise to. The foreground is then computed only
    /// for the cells that turn out to need one.
    ///
    /// The `▄` glyph is emitted **bold** (SGR 1) — but only where bold is a
    /// weight and nothing else. At some SF Mono sizes in Terminal.app (incl.
    /// the default 11 pt) the regular-weight lower-half block is rasterised a
    /// hair short of the cell's bottom edge, so the cell background (the *top*
    /// pixel's colour) bleeds through as a thin band along each row's bottom.
    /// Bold selects a heavier glyph that fills to the edge on the affected
    /// sizes, and against an explicit RGB triple it can do nothing else.
    ///
    /// Against one of the terminal's sixteen it can, and does: a host that
    /// implements "bold means bright" paints SGR 1 + `30`–`37` in the BRIGHT
    /// twin. Every cell's lower half then comes out the wrong colour while its
    /// upper half — the background, which bold never touches — stays right,
    /// which draws the whole picture in horizontal stripes at cell pitch. So
    /// the weight is spent only where ``ASCIIColorMode/foregroundSurvivesBold``
    /// says it costs nothing; elsewhere the hairline is the lesser evil, and
    /// it is a hairline on one host rather than a ruined image on several.
    private func convertHalfBlocksColor(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        let lowerHalfBlock: Character = "▄"
        let bold = mode.foregroundSurvivesBold ? "\(ANSIEscape.csi)1m" : ""

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

                let bgCode = backgroundColorCode(for: topPixel, mode: mode)
                let bottomCode = backgroundColorCode(for: bottomPixel, mode: mode)
                let uniform = bgCode == bottomCode
                let fgCode = uniform ? "" : foregroundColorCode(for: bottomPixel, mode: mode)

                if fgCode != lastFg || bgCode != lastBg {
                    // The reset clears bold too, so re-assert it with each colour
                    // run (bold persists across cells that reuse the same colours).
                    // `bold` is empty in the modes that cannot afford it, and a
                    // uniform cell draws no glyph for it to weigh.
                    line += ANSIEscape.reset
                    line += (uniform ? "" : bold) + fgCode + bgCode
                    lastFg = fgCode
                    lastBg = bgCode
                }
                line.append(uniform ? " " : lowerHalfBlock)
            }

            if !lastFg.isEmpty || !lastBg.isEmpty {
                line += ANSIEscape.reset
            }
            lines.append(line)
        }
        return lines
    }

    /// Monochrome variant: threshold both pixels and pick the block glyph that
    /// best represents which halves are lit.
    private func convertHalfBlocksMono(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        monoThreshold: Double
    ) -> [String] {
        var lines = [String]()
        lines.reserveCapacity(height)

        for cellY in 0..<height {
            var line = ""
            line.reserveCapacity(width)
            for cellX in 0..<width {
                let topLit = ASCIIConverter.isMonoInk(
                    image.pixel(at: cellX, 2 * cellY), threshold: monoThreshold)
                let bottomLit = ASCIIConverter.isMonoInk(
                    image.pixel(at: cellX, 2 * cellY + 1), threshold: monoThreshold)
                switch (topLit, bottomLit) {
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

extension ASCIIConverter {
    /// Whether `pixel` is drawn as ink in monochrome mode.
    ///
    /// **Bright pixels are the ink.** Monochrome has one ink colour and one
    /// background, and the framework's convention throughout — see
    /// ``ASCIICharacterSet/customRamp(_:)``, whose ramp runs darkest pixel →
    /// brightest and starts with a space "so dark regions stay blank on a dark
    /// terminal" — is that a black pixel paints nothing and a white one paints
    /// the densest glyph available. Every text charset already renders that
    /// way in mono, because they all map luminance through that ramp.
    ///
    /// The block modes used to threshold the other way round, on the reasoning
    /// that a scan of dark text on white paper should come out looking like the
    /// page. It does — and everything else comes out a photographic negative.
    /// A dark photograph, which is most photographs, inverted to almost all
    /// ink: the shipped demo image is 87% below mid-luminance, so `.blocks`
    /// mono rendered it as a near-solid slab of `█` with the subject barely
    /// legible inside it, and `.solid` mono as a featureless filled rectangle.
    /// Both read as "mono draws nothing".
    /// - Parameter threshold: The luminance at or above which a pixel is ink,
    ///   measured from the image by ``monoInkThreshold(for:)``. A fixed
    ///   mid-luminance split misses a dark photograph's tones entirely — which
    ///   is the other half of why mono "drew nothing".
    static func isMonoInk(_ pixel: RGBA, threshold: Double) -> Bool {
        pixel.luminance >= threshold
    }
}
