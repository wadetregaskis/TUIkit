//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color+ColorSpaces.swift
//
//  Created by LAYERED.work
//  License: MIT

// Color-space conversions: constructors that build an RGB ``Color`` from HSL /
// HSB / CMYK components, and the matching inverses that decompose an RGB triple
// back into each model.
//
// Terminals are an RGB (additive) medium, so every model ultimately resolves to
// `.rgb`. HSL and HSB are alternative *coordinates* on the same RGB gamut and
// round-trip exactly (modulo 8-bit rounding). CMYK is a subtractive print model
// included for parity with desktop colour pickers; the naive device conversion
// used here is fully reversible for in-gamut values but does not model ink or a
// colour profile — it is a convenience for viewing/entering values, not a
// print-accurate transform.

extension Color {

    // MARK: - HSL

    /// Creates a color from HSL values.
    ///
    /// - Parameters:
    ///   - hue: The hue component (0-360).
    ///   - saturation: The saturation component (0-100).
    ///   - lightness: The lightness component (0-100).
    /// - Returns: The corresponding RGB color.
    public static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> Self {
        let normalizedHue = hue / 360.0
        let normalizedSaturation = saturation / 100.0
        let normalizedLightness = lightness / 100.0

        if normalizedSaturation <= 0 {
            // Achromatic (gray)
            let gray = clampedByte(normalizedLightness * 255)
            return .rgb(gray, gray, gray)
        }

        let chromaFactor =
            normalizedLightness < 0.5
            ? normalizedLightness * (1 + normalizedSaturation)
            : normalizedLightness + normalizedSaturation - normalizedLightness * normalizedSaturation
        let luminanceFactor = 2 * normalizedLightness - chromaFactor

        func hueToRGB(_ luminance: Double, _ chroma: Double, _ hueComponent: Double) -> Double {
            var adjustedHue = hueComponent
            if adjustedHue < 0 { adjustedHue += 1 }
            if adjustedHue > 1 { adjustedHue -= 1 }
            if adjustedHue < 1 / 6 { return luminance + (chroma - luminance) * 6 * adjustedHue }
            if adjustedHue < 1 / 2 { return chroma }
            if adjustedHue < 2 / 3 { return luminance + (chroma - luminance) * (2 / 3 - adjustedHue) * 6 }
            return luminance
        }

        let red = clampedByte(hueToRGB(luminanceFactor, chromaFactor, normalizedHue + 1 / 3) * 255)
        let green = clampedByte(hueToRGB(luminanceFactor, chromaFactor, normalizedHue) * 255)
        let blue = clampedByte(hueToRGB(luminanceFactor, chromaFactor, normalizedHue - 1 / 3) * 255)

        return .rgb(red, green, blue)
    }

    /// Converts RGB components to HSL (hue 0–360, saturation 0–100, lightness 0–100).
    ///
    /// - Parameters:
    ///   - red: Red component (0–255).
    ///   - green: Green component (0–255).
    ///   - blue: Blue component (0–255).
    /// - Returns: A tuple of (hue, saturation, lightness) in their standard ranges.
    public static func rgbToHSL(red: UInt8, green: UInt8, blue: UInt8) -> (hue: Double, saturation: Double, lightness: Double) {
        let normalizedRed = Double(red) / 255.0
        let normalizedGreen = Double(green) / 255.0
        let normalizedBlue = Double(blue) / 255.0

        let maxComponent = max(normalizedRed, normalizedGreen, normalizedBlue)
        let minComponent = min(normalizedRed, normalizedGreen, normalizedBlue)
        let delta = maxComponent - minComponent

        let lightness = (maxComponent + minComponent) / 2.0

        guard delta > 0 else {
            // Achromatic (gray)
            return (hue: 0, saturation: 0, lightness: lightness * 100)
        }

        let saturation: Double
        if lightness < 0.5 {
            saturation = delta / (maxComponent + minComponent)
        } else {
            saturation = delta / (2.0 - maxComponent - minComponent)
        }

        let hue: Double
        switch maxComponent {
        case normalizedRed:
            let segment = (normalizedGreen - normalizedBlue) / delta
            hue = 60 * (segment < 0 ? segment + 6 : segment)
        case normalizedGreen:
            hue = 60 * ((normalizedBlue - normalizedRed) / delta + 2)
        default:
            hue = 60 * ((normalizedRed - normalizedGreen) / delta + 4)
        }

        return (hue: hue, saturation: saturation * 100, lightness: lightness * 100)
    }

    // MARK: - HSB / HSV

    /// Creates a color from HSB (a.k.a. HSV) values.
    ///
    /// HSB shares HSL's hue but differs in the second axis: HSB's *brightness*
    /// runs a fully-saturated hue (at brightness 100) to black (at 0), whereas
    /// HSL's *lightness* runs it to white at 100 and is mid-tone at 50. It is the
    /// model behind a hue/value rectangle picker.
    ///
    /// - Parameters:
    ///   - hue: The hue component (0-360).
    ///   - saturation: The saturation component (0-100).
    ///   - brightness: The brightness/value component (0-100).
    /// - Returns: The corresponding RGB color.
    public static func hsb(_ hue: Double, _ saturation: Double, _ brightness: Double) -> Self {
        let s = saturation / 100.0
        let v = brightness / 100.0

        if s <= 0 {
            // Achromatic (gray): brightness alone sets the level.
            let gray = clampedByte(v * 255)
            return .rgb(gray, gray, gray)
        }

        // A non-finite hue would trap the `Int(...)` below — fold it to 0.
        var sector = (hue.isFinite ? hue : 0).truncatingRemainder(dividingBy: 360)
        if sector < 0 { sector += 360 }
        sector /= 60  // 0..<6

        let index = Int(sector.rounded(.down))
        let fraction = sector - Double(index)
        let p = v * (1 - s)
        let q = v * (1 - s * fraction)
        let t = v * (1 - s * (1 - fraction))

        let red: Double
        let green: Double
        let blue: Double
        switch index % 6 {
        case 0: (red, green, blue) = (v, t, p)
        case 1: (red, green, blue) = (q, v, p)
        case 2: (red, green, blue) = (p, v, t)
        case 3: (red, green, blue) = (p, q, v)
        case 4: (red, green, blue) = (t, p, v)
        default: (red, green, blue) = (v, p, q)
        }

        return .rgb(clampedByte(red * 255), clampedByte(green * 255), clampedByte(blue * 255))
    }

    /// Converts RGB components to HSB / HSV (hue 0–360, saturation 0–100,
    /// brightness 0–100).
    ///
    /// - Parameters:
    ///   - red: Red component (0–255).
    ///   - green: Green component (0–255).
    ///   - blue: Blue component (0–255).
    /// - Returns: A tuple of (hue, saturation, brightness) in their standard ranges.
    public static func rgbToHSB(red: UInt8, green: UInt8, blue: UInt8) -> (hue: Double, saturation: Double, brightness: Double) {
        let normalizedRed = Double(red) / 255.0
        let normalizedGreen = Double(green) / 255.0
        let normalizedBlue = Double(blue) / 255.0

        let maxComponent = max(normalizedRed, normalizedGreen, normalizedBlue)
        let minComponent = min(normalizedRed, normalizedGreen, normalizedBlue)
        let delta = maxComponent - minComponent

        let brightness = maxComponent
        let saturation = maxComponent <= 0 ? 0 : delta / maxComponent

        guard delta > 0 else {
            // Achromatic (gray)
            return (hue: 0, saturation: 0, brightness: brightness * 100)
        }

        let hue: Double
        switch maxComponent {
        case normalizedRed:
            let segment = (normalizedGreen - normalizedBlue) / delta
            hue = 60 * (segment < 0 ? segment + 6 : segment)
        case normalizedGreen:
            hue = 60 * ((normalizedBlue - normalizedRed) / delta + 2)
        default:
            hue = 60 * ((normalizedRed - normalizedGreen) / delta + 4)
        }

        return (hue: hue, saturation: saturation * 100, brightness: brightness * 100)
    }

    // MARK: - CMYK

    /// Creates a color from CMYK values via the naive device conversion.
    ///
    /// CMYK is a subtractive (print) model; this is the standard reversible
    /// device transform, not a colour-managed one — included so a picker can
    /// show and accept CMYK numbers. Round-trips exactly with ``rgbToCMYK(red:green:blue:)``
    /// for in-gamut values.
    ///
    /// - Parameters:
    ///   - cyan: The cyan component (0-100).
    ///   - magenta: The magenta component (0-100).
    ///   - yellow: The yellow component (0-100).
    ///   - black: The key/black component (0-100).
    /// - Returns: The corresponding RGB color.
    public static func cmyk(_ cyan: Double, _ magenta: Double, _ yellow: Double, _ black: Double) -> Self {
        let c = cyan / 100.0
        let m = magenta / 100.0
        let y = yellow / 100.0
        let k = black / 100.0

        let red = 255.0 * (1 - c) * (1 - k)
        let green = 255.0 * (1 - m) * (1 - k)
        let blue = 255.0 * (1 - y) * (1 - k)

        return .rgb(clampedByte(red), clampedByte(green), clampedByte(blue))
    }

    /// Converts RGB components to CMYK (each component 0–100) via the naive
    /// device conversion.
    ///
    /// - Parameters:
    ///   - red: Red component (0–255).
    ///   - green: Green component (0–255).
    ///   - blue: Blue component (0–255).
    /// - Returns: A tuple of (cyan, magenta, yellow, black) percentages.
    public static func rgbToCMYK(red: UInt8, green: UInt8, blue: UInt8) -> (cyan: Double, magenta: Double, yellow: Double, black: Double) {
        let normalizedRed = Double(red) / 255.0
        let normalizedGreen = Double(green) / 255.0
        let normalizedBlue = Double(blue) / 255.0

        let key = 1 - max(normalizedRed, normalizedGreen, normalizedBlue)
        guard key < 1 else {
            // Pure black: cyan/magenta/yellow are undefined, report all-key.
            return (cyan: 0, magenta: 0, yellow: 0, black: 100)
        }

        let cyan = (1 - normalizedRed - key) / (1 - key)
        let magenta = (1 - normalizedGreen - key) / (1 - key)
        let yellow = (1 - normalizedBlue - key) / (1 - key)

        return (cyan: cyan * 100, magenta: magenta * 100, yellow: yellow * 100, black: key * 100)
    }
}

// MARK: - Private Helpers

/// Rounds and clamps a 0–255-scaled channel value into a `UInt8`, guarding
/// against out-of-range user input (e.g. a hand-entered HSL/HSB/CMYK value) that
/// would otherwise trap the `UInt8` conversion. Rounding (not truncation) keeps
/// the RGB↔HSB and RGB↔CMYK round-trips exact.
///
/// A non-finite input (NaN or ±∞, e.g. from a degenerate conversion) is treated
/// as 0 — `UInt8(.nan)` and `UInt8(.infinity)` both trap, so they must never
/// reach the conversion.
private func clampedByte(_ value: Double) -> UInt8 {
    guard value.isFinite else { return 0 }
    return UInt8(max(0, min(255, value.rounded())))
}
