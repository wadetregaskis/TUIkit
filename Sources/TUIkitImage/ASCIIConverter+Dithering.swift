//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIConverter+Dithering.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - Color Output

extension ASCIIConverter {

    /// Returns the ANSI foreground color escape code for a pixel.
    ///
    /// Callers must pass the *effective* color mode (the requested mode
    /// downsampled to one the terminal can actually render). See
    /// ``ASCIIColorMode/effective(for:)``.
    func foregroundColorCode(for pixel: RGBA, mode: ASCIIColorMode) -> String {
        Self.escape(for: cellColor(for: pixel, mode: mode), background: false)
    }

    /// Returns the ANSI background color escape code for a pixel.
    func backgroundColorCode(for pixel: RGBA, mode: ASCIIColorMode) -> String {
        Self.escape(for: cellColor(for: pixel, mode: mode), background: true)
    }

    /// The escape for `color` as a string — the spelling ``ANSIRowBuilder``
    /// writes as bytes, for the callers that want a `String`. Not on the
    /// converters' path any more; they write bytes.
    static func escape(for color: Color?, background: Bool) -> String {
        guard let color else { return "" }
        var builder = ANSIRowBuilder(capacity: 24)
        builder.setColors(foreground: background ? nil : color, background: background ? color : nil)
        // The builder closes with a reset; the string form never carried one.
        let closed = builder.finish()
        return String(closed.dropLast(ANSIEscape.reset.count))
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
