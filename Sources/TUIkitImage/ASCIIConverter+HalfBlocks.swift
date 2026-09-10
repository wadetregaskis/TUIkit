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
    ) -> ASCIIArt {
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
    ) -> ASCIIArt {
        let lowerHalfBlock: Character = "▄"
        let upperHalfBlock: Character = "▀"
        let bold = mode.foregroundSurvivesBold
        // The mode resolved ONCE for the whole picture: this renderer asks it
        // twice a cell, and asking the enum copies the palette out of its
        // payload and re-takes the search index's lock every time.
        let colours = CellColours(mode: mode)

        var lines = [String]()
        var coverage = CoverageMap()
        lines.reserveCapacity(height)

        // Straight off the pixel buffer: `pixel(at:)` is three retains and
        // three releases of the array per call in a debug build, twice a cell.
        image.pixels.withUnsafeBufferPointer { pixels in
            let stride = image.width
            for cellY in 0..<height {
                var row = ANSIRowBuilder(capacity: width * 32)  // foreground + background per cell
                let top = 2 * cellY * stride
                let bottom = top + stride

                for cellX in 0..<width {
                    let upper = pixels[top + cellX]
                    let lower = pixels[bottom + cellX]
                    // WHICH HALVES ARE THERE AT ALL decides the glyph, before any
                    // question about colour — and it is asked of the pixels' COVERAGE
                    // rather than of whether `colours` gave a colour, because that
                    // answers `nil` for a colourless MODE too.
                    let background = upper.a > 0 ? colours.color(for: upper) : nil
                    let below = lower.a > 0 ? colours.color(for: lower) : nil
                    switch (upper.a > 0, lower.a > 0) {
                    case (false, false):
                        // Neither half is there: a space stating no colour, which leaves
                        // the cell behind it exactly as it was. This is the cell that
                        // used to be an explicit black rectangle — §17's logo surround.
                        row.setColors(foreground: nil, background: nil, resetFirst: true)
                        row.append(ascii: 0x20)
                    case (false, true):
                        // Only the lower half. `▄` in its colour with NO background, so
                        // the upper half of the cell shows what is behind it.
                        row.setColors(
                            foreground: below, background: nil, bold: bold, resetFirst: true)
                        row.append(lowerHalfBlock)
                        coverage.note(line: cellY, column: cellX, ink: lower.a, field: .max)
                    case (true, false):
                        // Only the upper half, so the glyph FLIPS: `▀` in the top pixel's
                        // colour rather than `▄` over it. The mono variant has always
                        // had all four glyphs; the colour one only ever needed two
                        // because the flatten meant every cell had both halves.
                        row.setColors(
                            foreground: background, background: nil, bold: bold, resetFirst: true)
                        row.append(upperHalfBlock)
                        coverage.note(line: cellY, column: cellX, ink: upper.a, field: .max)
                    case (true, true):
                        // A uniform cell is a space on the background; a split one is
                        // a lower half-block in the bottom pixel's colour over the
                        // top pixel's. The reset the builder writes before a change
                        // clears bold too, so bold is re-asserted with each colour
                        // run — where the mode can afford it, and only for a cell
                        // that draws a glyph for it to weigh.
                        //
                        // The COVERAGES have to agree as well as the colours. Two pixels
                        // of one colour at different alphas are not one field: collapsed
                        // to a space with a single background, the cell would resolve at
                        // one of the two and the other half would be wrong. That
                        // optimisation is load-bearing for the Warp contrast-lift banding
                        // (see this function's own note), so it stays — with the alpha in
                        // its test.
                        let uniform = background == below && upper.a == lower.a
                        row.setColors(
                            foreground: uniform ? nil : below, background: background,
                            bold: bold && !uniform, resetFirst: true)
                        if uniform { row.append(ascii: 0x20) } else { row.append(lowerHalfBlock) }
                        coverage.note(
                            line: cellY, column: cellX,
                            ink: uniform ? .max : lower.a, field: upper.a)
                    }
                }
                lines.append(row.finish())
            }
        }
        return ASCIIArt(lines: lines, coverage: coverage.runs)
    }

    /// Monochrome variant: threshold both pixels and pick the block glyph that
    /// best represents which halves are lit.
    private func convertHalfBlocksMono(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        monoThreshold: Double
    ) -> ASCIIArt {
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
        // No coverage runs: mono paints no colours at all — the four glyphs carry the
        // whole picture — so there is no alpha to state. What coverage decides here is
        // whether a half is LIT, which `isMonoInk` answers.
        return ASCIIArt(lines: lines)
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
        // Covered before bright. A pixel that is not there cannot be ink, whatever
        // colour the encoder left in it, and "there" is the ½ rule §6a states for every
        // glyph decision — at or above half coverage the source's mark is drawn, below
        // it the destination keeps its cell. Mono paints no colours at all, so this is
        // the ONLY way coverage reaches it: there is no claim to make, only a glyph to
        // withhold.
        pixel.a >= 128 && pixel.luminance >= threshold
    }
}
