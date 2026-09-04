//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIConverter+Dithering.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Color Output

extension ASCIIConverter {

    /// Returns the ANSI foreground color escape code for a pixel.
    ///
    /// Callers must pass the *effective* color mode (the requested mode
    /// downsampled to one the terminal can actually render). See
    /// ``ASCIIColorMode/effective(for:)``.
    func foregroundColorCode(for pixel: RGBA, mode: ASCIIColorMode) -> String {
        switch mode {
        case .trueColor:
            return "\(ANSIEscape.csi)38;2;\(pixel.r);\(pixel.g);\(pixel.b)m"

        case .ansi256:
            return code(for: pixel, in: .ansi256, background: false)

        case .ansi16:
            return code(for: pixel, in: .ansi16, background: false)

        case .grayscale:
            // By `count`, not `count - 1`, then clamped — the rule the
            // character ramp already uses. Scaling by 23 and truncating gave
            // levels 0…22 an 11-value band each and the top grey (#eeeeee)
            // exactly one input, pure white: every highlight clipped a step
            // dark, and "24 shades" delivered 23 usable ones.
            let index = 232 + min(Int(pixel.luminance / 255.0 * 24.0), 23)
            return "\(ANSIEscape.csi)38;5;\(index)m"

        case .mono:
            return ""

        case .palette(let palette):
            return code(for: pixel, in: palette, background: false)
        }
    }

    /// Returns the ANSI background color escape code for a pixel.
    ///
    /// Mirrors ``foregroundColorCode(for:mode:)`` but emits SGR 48 (background)
    /// instead of SGR 38 (foreground). Used by half-block rendering, where the
    /// cell's two image pixels are split between foreground and background.
    func backgroundColorCode(for pixel: RGBA, mode: ASCIIColorMode) -> String {
        switch mode {
        case .trueColor:
            return "\(ANSIEscape.csi)48;2;\(pixel.r);\(pixel.g);\(pixel.b)m"

        case .ansi256:
            return code(for: pixel, in: .ansi256, background: true)

        case .ansi16:
            return code(for: pixel, in: .ansi16, background: true)

        case .grayscale:
            let index = 232 + min(Int(pixel.luminance / 255.0 * 24.0), 23)  // as above
            return "\(ANSIEscape.csi)48;5;\(index)m"

        case .mono:
            return ""

        case .palette(let palette):
            return code(for: pixel, in: palette, background: true)
        }
    }

    /// The SGR that selects the nearest entry of `palette`, spelled in whatever
    /// form that entry's colour takes — `30`–`37`/`90`–`97` for one of the
    /// terminal's sixteen, `38;5;n` for one of its 256, a triple for a colour
    /// of the app's own.
    ///
    /// One function for all three modes that name colours, because they ask one
    /// question. ``ASCIIColorMode/ansi16`` and ``ASCIIColorMode/ansi256`` are
    /// not quantisers of their own: they are the terminal's two palettes, and a
    /// palette already knows how to be searched and how to be said. `.ansi256`
    /// was the holdout — a 6×6×6 cube indexed by dividing each channel by 51 —
    /// and that arithmetic disagreed with the way the UI beside it was
    /// quantised for 85% of colours. See ``ASCIIPalette/ansi256``.
    private func code(for pixel: RGBA, in palette: ASCIIPalette, background: Bool) -> String {
        let parameters = palette.sgrParameters(
            at: palette.nearestIndex(to: pixel), background: background)
        return "\(ANSIEscape.csi)\(parameters)m"
    }
}

// MARK: - Floyd-Steinberg Dithering

extension ASCIIConverter {

    /// Applies Floyd-Steinberg error diffusion dithering.
    ///
    /// Distributes quantization error to neighboring pixels:
    /// - Right:       7/16
    /// - Bottom-left: 3/16
    /// - Bottom:      5/16
    /// - Bottom-right: 1/16
    ///
    /// Quantizes against the *effective* color mode so dithering matches
    /// what will actually be emitted. See ``ASCIIColorMode/effective(for:)``.
    func applyFloydSteinbergDithering(
        _ image: RGBAImage, mode: ASCIIColorMode, monoThreshold: Double,
        table: ASCIIPalette.QuantisationTable? = nil
    ) -> RGBAImage {
        var result = image

        for y in 0..<image.height {
            for x in 0..<image.width {
                let oldPixel = result.pixel(at: x, y)
                let newPixel = quantizePixel(
                    oldPixel, mode: mode, monoThreshold: monoThreshold, table: table)
                result.setPixel(at: x, y, value: newPixel)

                let rErr = Int16(oldPixel.r) - Int16(newPixel.r)
                let gErr = Int16(oldPixel.g) - Int16(newPixel.g)
                let bErr = Int16(oldPixel.b) - Int16(newPixel.b)

                // Distribute error to neighbors
                if x + 1 < image.width {
                    result.addError(
                        at: x + 1,
                        y,
                        rError: rErr * 7 / 16,
                        gError: gErr * 7 / 16,
                        bError: bErr * 7 / 16
                    )
                }
                if y + 1 < image.height {
                    if x > 0 {
                        result.addError(
                            at: x - 1,
                            y + 1,
                            rError: rErr * 3 / 16,
                            gError: gErr * 3 / 16,
                            bError: bErr * 3 / 16
                        )
                    }
                    result.addError(
                        at: x,
                        y + 1,
                        rError: rErr * 5 / 16,
                        gError: gErr * 5 / 16,
                        bError: bErr * 5 / 16
                    )
                    if x + 1 < image.width {
                        result.addError(
                            at: x + 1,
                            y + 1,
                            rError: rErr / 16,
                            gError: gErr / 16,
                            bError: bErr / 16
                        )
                    }
                }
            }
        }

        return result
    }

    /// Quantizes a pixel to its nearest representative value for the given
    /// color mode, keeping its alpha.
    ///
    /// Alpha is carried rather than defaulted. A glyph has no transparency to
    /// be wrong about, so this was invisible while the only consumer was the
    /// character renderer — and it stops being invisible the moment the same
    /// quantisation is applied to pixels that go to the TERMINAL, which is
    /// what composites them over the page. Same defect as the one
    /// `RGBAImage.scaledBilinear` had, in the same shape: `RGBA(r:g:b:)`
    /// defaults alpha to opaque.
    func quantizePixel(
        _ pixel: RGBA, mode: ASCIIColorMode, monoThreshold: Double,
        table: ASCIIPalette.QuantisationTable? = nil
    ) -> RGBA {
        switch mode {
        case .trueColor:
            return pixel

        case .ansi256:
            return Self.quantized(pixel, in: .ansi256, table: table)

        case .ansi16:
            return Self.quantized(pixel, in: .ansi16, table: table)

        case .grayscale:
            let gray = UInt8(clamping: Int(pixel.luminance))
            return RGBA(r: gray, g: gray, b: gray, a: pixel.a)

        case .mono:
            // The same split the mono renderers threshold on, so the error the
            // dither diffuses is the error they will actually make.
            let val: UInt8 = ASCIIConverter.isMonoInk(pixel, threshold: monoThreshold) ? 255 : 0
            return RGBA(r: val, g: val, b: val, a: pixel.a)

        case .palette(let palette):
            return Self.quantized(pixel, in: palette, table: table)
        }
    }

    /// The entry `pixel` will actually be drawn as, keeping its alpha — so the
    /// error the dither diffuses is the error the palette makes, which is what
    /// turns a three-colour render from three flat regions into a gradient.
    private static func quantized(
        _ pixel: RGBA, in palette: ASCIIPalette, table: ASCIIPalette.QuantisationTable?
    ) -> RGBA {
        var quantized = palette.rgba(at: index(of: pixel, in: palette, table: table))
        quantized.a = pixel.a
        return quantized
    }

    /// The palette entry for `pixel`: through `table` when the caller built one
    /// (the pixel renderer, asking a million times), exactly otherwise (the
    /// character renderer, asking once per cell).
    private static func index(
        of pixel: RGBA, in palette: ASCIIPalette, table: ASCIIPalette.QuantisationTable?
    ) -> Int {
        guard let table else { return palette.nearestIndex(to: pixel) }
        let cell = ASCIIPalette.quantisationCell(for: pixel)
        guard table.trusted[cell] else { return palette.nearestIndex(to: pixel) }
        return Int(table.answers[cell])
    }
}
