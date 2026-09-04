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
            let index = quantizeToANSI256(pixel)
            return "\(ANSIEscape.csi)38;5;\(index)m"

        case .ansi16:
            return codeForANSI16(pixel, background: false)

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
            let index = palette.nearestIndex(to: pixel)
            return "\(ANSIEscape.csi)\(palette.sgrParameters(at: index, background: false))m"
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
            let index = quantizeToANSI256(pixel)
            return "\(ANSIEscape.csi)48;5;\(index)m"

        case .ansi16:
            return codeForANSI16(pixel, background: true)

        case .grayscale:
            let index = 232 + min(Int(pixel.luminance / 255.0 * 24.0), 23)  // as above
            return "\(ANSIEscape.csi)48;5;\(index)m"

        case .mono:
            return ""

        case .palette(let palette):
            let index = palette.nearestIndex(to: pixel)
            return "\(ANSIEscape.csi)\(palette.sgrParameters(at: index, background: true))m"
        }
    }

    /// The SGR that selects the nearest of the terminal's sixteen.
    ///
    /// Through ``ASCIIPalette/ansi16`` rather than through a table of its own:
    /// the palette already holds the sixteen as `.standard`/`.bright` colours,
    /// already maps a pixel to the nearest of them in OKLab — the metric every
    /// other image mapping uses — and already knows that such a colour is
    /// spelled `30 + n` / `90 + n` rather than as an index or a triple.
    private func codeForANSI16(_ pixel: RGBA, background: Bool) -> String {
        let sixteen = ASCIIPalette.ansi16
        let parameters = sixteen.sgrParameters(
            at: sixteen.nearestIndex(to: pixel), background: background)
        return "\(ANSIEscape.csi)\(parameters)m"
    }

    /// Quantizes an RGB pixel to the nearest ANSI 256-color index.
    private func quantizeToANSI256(_ pixel: RGBA) -> UInt8 {
        // Check for near-grayscale
        let rDiff = abs(Int(pixel.r) - Int(pixel.g))
        let gDiff = abs(Int(pixel.g) - Int(pixel.b))
        if rDiff < 10, gDiff < 10 {
            // The NEAREST ramp entry, by luminance. The entries sit ten apart
            // (8, 18, … 238), and `(gray - 8) / 10` floored, so every level in
            // the upper half of a step came out an entry too dark — exact
            // entries included; and `< 8 → black` sent 5…7 to (0,0,0) with
            // (8,8,8) three away. Black and white are the cube's corners (16
            // and 231) and take over only where they are closer than the
            // ramp's ends.
            let level = pixel.luminance
            if level < 4 { return 16 }
            if level > 246.5 { return 231 }
            return UInt8(232 + min(23, max(0, Int(((level - 8) / 10).rounded()))))
        }

        // 6x6x6 color cube (indices 16-231)
        let r = UInt8((Double(pixel.r) / 255.0 * 5.0).rounded())
        let g = UInt8((Double(pixel.g) / 255.0 * 5.0).rounded())
        let b = UInt8((Double(pixel.b) / 255.0 * 5.0).rounded())
        return 16 + 36 * r + 6 * g + b
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
            let index = quantizeToANSI256(pixel)
            var quantized = ansi256ToRGB(index)
            quantized.a = pixel.a
            return quantized

        case .ansi16:
            let sixteen = ASCIIPalette.ansi16
            var quantized = sixteen.rgba(at: Self.index(of: pixel, in: sixteen, table: table))
            quantized.a = pixel.a
            return quantized

        case .grayscale:
            let gray = UInt8(clamping: Int(pixel.luminance))
            return RGBA(r: gray, g: gray, b: gray, a: pixel.a)

        case .mono:
            // The same split the mono renderers threshold on, so the error the
            // dither diffuses is the error they will actually make.
            let val: UInt8 = ASCIIConverter.isMonoInk(pixel, threshold: monoThreshold) ? 255 : 0
            return RGBA(r: val, g: val, b: val, a: pixel.a)

        case .palette(let palette):
            // The entry this pixel will actually be drawn as — so the error
            // diffused is the error the palette makes, which is what turns a
            // three-colour render from three flat regions into a gradient.
            var quantized = palette.rgba(at: Self.index(of: pixel, in: palette, table: table))
            quantized.a = pixel.a
            return quantized
        }
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

    /// Converts an ANSI 256-color index back to approximate RGB.
    private func ansi256ToRGB(_ index: UInt8) -> RGBA {
        let idx = Int(index)
        if idx < 16 {
            // Standard colors (approximate)
            let table: [(UInt8, UInt8, UInt8)] = [
                (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
                (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
                (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
                (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
            ]
            let (r, g, b) = table[idx]
            return RGBA(r: r, g: g, b: b)
        } else if idx < 232 {
            // 6x6x6 color cube
            let offset = idx - 16
            let r = offset / 36
            let g = (offset % 36) / 6
            let b = offset % 6
            return RGBA(
                r: r == 0 ? 0 : UInt8(55 + r * 40),
                g: g == 0 ? 0 : UInt8(55 + g * 40),
                b: b == 0 ? 0 : UInt8(55 + b * 40)
            )
        } else {
            // Grayscale ramp
            let gray = UInt8(8 + (idx - 232) * 10)
            return RGBA(r: gray, g: gray, b: gray)
        }
    }
}
