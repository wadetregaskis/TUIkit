//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A color for use in TUIkit views.
///
/// `Color` represents standard ANSI colors as well as
/// extended 256-color palette and True Color (24-bit RGB).
///
/// # Standard Colors
///
/// ```swift
/// Text("Red").foregroundStyle(.red)
/// Text("Green").foregroundStyle(.green)
/// Text("Blue").foregroundStyle(.blue)
/// ```
///
/// # RGB Colors
///
/// ```swift
/// Text("Custom").foregroundStyle(.rgb(255, 128, 0))
/// ```
public struct Color: Sendable, Equatable {
    /// The internal color value.
    public let value: ColorValue

    /// Internal enum for different color types.
    public enum ColorValue: Sendable, Equatable {
        case standard(ANSIColor)
        case bright(ANSIColor)
        case palette256(UInt8)
        case rgb(red: UInt8, green: UInt8, blue: UInt8)
        case semantic(SemanticColor)
    }

    // MARK: - Standard ANSI Colors

    /// Black (ANSI 30/40)
    public static let black = Self(value: .standard(.black))

    /// Red (ANSI 31/41)
    public static let red = Self(value: .standard(.red))

    /// Green (ANSI 32/42)
    public static let green = Self(value: .standard(.green))

    /// Yellow (ANSI 33/43)
    public static let yellow = Self(value: .standard(.yellow))

    /// Blue (ANSI 34/44)
    public static let blue = Self(value: .standard(.blue))

    /// Magenta (ANSI 35/45)
    public static let magenta = Self(value: .standard(.magenta))

    /// Cyan (ANSI 36/46)
    public static let cyan = Self(value: .standard(.cyan))

    /// White (ANSI 37/47)
    public static let white = Self(value: .standard(.white))

    /// Default color (terminal default)
    public static let `default` = Self(value: .standard(.`default`))

    // MARK: - Bright ANSI Colors

    /// Bright black (gray)
    public static let brightBlack = Self(value: .bright(.black))

    /// Bright red
    public static let brightRed = Self(value: .bright(.red))

    /// Bright green
    public static let brightGreen = Self(value: .bright(.green))

    /// Bright yellow
    public static let brightYellow = Self(value: .bright(.yellow))

    /// Bright blue
    public static let brightBlue = Self(value: .bright(.blue))

    /// Bright magenta
    public static let brightMagenta = Self(value: .bright(.magenta))

    /// Bright cyan
    public static let brightCyan = Self(value: .bright(.cyan))

    /// Bright white
    public static let brightWhite = Self(value: .bright(.white))

    // MARK: - Semantic Colors

    /// Primary color (default: blue)
    public static let primary = Self.blue

    /// Secondary color (default: gray)
    public static let secondary = Self.brightBlack

    /// Accent color (default: cyan)
    public static let accent = Self.cyan

    /// Warning color
    public static let warning = Self.yellow

    /// Error color
    public static let error = Self.red

    /// Success color
    public static let success = Self.green

    // MARK: - Palette-Aware Semantic Colors

    /// Namespace for palette-aware semantic colors.
    ///
    /// These colors are resolved at render time against the current ``Palette``
    /// via ``resolve(with:)``. Use them in view `body` properties where no
    /// ``RenderContext`` is available:
    ///
    /// ```swift
    /// Text("Hello").foregroundStyle(.palette.accent)
    /// ```
    public enum Semantic {
        // Background colors
        public static let background = Color(value: .semantic(.background))
        public static let statusBarBackground = Color(value: .semantic(.statusBarBackground))
        public static let appHeaderBackground = Color(value: .semantic(.appHeaderBackground))
        public static let overlayBackground = Color(value: .semantic(.overlayBackground))

        // Foreground colors
        public static let foreground = Color(value: .semantic(.foreground))
        public static let foregroundSecondary = Color(value: .semantic(.foregroundSecondary))
        public static let foregroundTertiary = Color(value: .semantic(.foregroundTertiary))
        public static let foregroundQuaternary = Color(value: .semantic(.foregroundQuaternary))

        // Accent colors
        public static let accent = Color(value: .semantic(.accent))

        // Status colors
        public static let success = Color(value: .semantic(.success))
        public static let warning = Color(value: .semantic(.warning))
        public static let error = Color(value: .semantic(.error))
        public static let info = Color(value: .semantic(.info))

        // UI element colors
        public static let border = Color(value: .semantic(.border))
    }

    /// Access palette-aware semantic colors.
    ///
    /// Colors returned by this namespace are not resolved until render time,
    /// when the current ``Palette`` is available via ``RenderContext``.
    ///
    /// ```swift
    /// Text("Hello").foregroundStyle(.palette.accent)
    /// ```
    public static var palette: Semantic.Type { Semantic.self }

    /// The RGB components of this color.
    ///
    /// Converts any color type to its RGB representation:
    /// - `.rgb` — returned directly
    /// - `.standard` / `.bright` — mapped to xterm standard RGB values
    /// - `.palette256` — mapped to xterm 256-color palette RGB values
    /// - `.semantic` — returns nil (must be resolved first via ``resolve(with:)``)
    public var rgbComponents: (red: UInt8, green: UInt8, blue: UInt8)? {
        switch value {
        case .rgb(let red, let green, let blue):
            return (red, green, blue)
        case .standard(let ansi):
            return ansi.rgbValues
        case .bright(let ansi):
            return ansi.brightRGBValues
        case .palette256(let index):
            return Self.palette256ToRGB(index)
        case .semantic:
            return nil
        }
    }
}

// MARK: - Public API

extension Color {
    /// Resolves this color against a palette.
    ///
    /// Non-semantic colors are returned unchanged. Semantic colors
    /// are mapped to the corresponding palette property.
    ///
    /// - Parameter palette: The palette to resolve against.
    /// - Returns: A concrete (non-semantic) color.
    public func resolve(with palette: any Palette) -> Color {
        guard case .semantic(let token) = value else { return self }
        return token.resolve(with: palette)
    }

    /// Creates a color from the 256-color palette.
    ///
    /// - Parameter index: The palette index (0-255).
    /// - Returns: The corresponding color.
    public static func palette(_ index: UInt8) -> Self {
        Self(value: .palette256(index))
    }

    /// Creates a True Color RGB color.
    ///
    /// - Parameters:
    ///   - red: The red component (0-255).
    ///   - green: The green component (0-255).
    ///   - blue: The blue component (0-255).
    /// - Returns: The RGB color.
    public static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Self {
        Self(value: .rgb(red: red, green: green, blue: blue))
    }

    /// Creates a color from a hex value.
    ///
    /// - Parameter hex: The hex value (e.g., 0xFF5500).
    /// - Returns: The corresponding RGB color.
    public static func hex(_ hex: UInt32) -> Self {
        let red = UInt8((hex >> 16) & 0xFF)
        let green = UInt8((hex >> 8) & 0xFF)
        let blue = UInt8(hex & 0xFF)
        return .rgb(red, green, blue)
    }

    /// Creates a color from a hex string.
    ///
    /// Supports formats: "#RGB", "#RRGGBB", "RGB", "RRGGBB"
    ///
    /// - Parameter hex: The hex string (e.g., "#FF5500", "F50", "#abc").
    /// - Returns: The corresponding RGB color, or nil if invalid.
    public static func hex(_ hex: String) -> Self? {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove # prefix if present
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        // Handle shorthand format (RGB -> RRGGBB)
        if hexString.count == 3 {
            let chars = Array(hexString)
            hexString = String([chars[0], chars[0], chars[1], chars[1], chars[2], chars[2]])
        }

        // Must be 6 characters now
        guard hexString.count == 6 else { return nil }

        // Parse hex value
        guard let hexValue = UInt32(hexString, radix: 16) else { return nil }

        return .hex(hexValue)
    }

    /// Returns a lighter version of this color.
    ///
    /// The percentage is relative to the remaining lightness headroom.
    /// For example, a color with HSL lightness 60 lightened by 0.5 (50%)
    /// moves halfway toward 100: `60 + (100 − 60) × 0.5 = 80`.
    ///
    /// - Parameter percentage: The fraction to lighten (0–1, default 0.2 = 20%).
    /// - Returns: A lighter color with preserved hue and saturation.
    public func lighter(by percentage: Double = 0.2) -> Self {
        adjusted(by: percentage)
    }

    /// Returns a darker version of this color.
    ///
    /// The percentage is relative to the current lightness.
    /// For example, a color with HSL lightness 60 darkened by 0.5 (50%)
    /// moves halfway toward 0: `60 × (1 − 0.5) = 30`.
    ///
    /// - Parameter percentage: The fraction to darken (0–1, default 0.2 = 20%).
    /// - Returns: A darker color with preserved hue and saturation.
    public func darker(by percentage: Double = 0.2) -> Self {
        adjusted(by: -percentage)
    }

    /// Returns a color with adjusted opacity (simulated via color mixing).
    ///
    /// Since terminals don't support true transparency, this mixes
    /// the color with black to simulate opacity. Works with all color types
    /// by converting to RGB first.
    ///
    /// - Parameter opacity: The opacity (0-1).
    /// - Returns: A color simulating the given opacity, or self if semantic.
    public func opacity(_ opacity: Double) -> Self {
        guard let (red, green, blue) = rgbComponents else {
            return self
        }

        let newRed = UInt8(Double(red) * opacity)
        let newGreen = UInt8(Double(green) * opacity)
        let newBlue = UInt8(Double(blue) * opacity)

        return .rgb(newRed, newGreen, newBlue)
    }

    /// Linearly interpolates between two colors.
    ///
    /// Both colors are converted to RGB before interpolation. If either
    /// color is semantic (unresolved), the `from` color is returned unchanged.
    ///
    /// Used by the breathing focus indicator to smoothly fade between
    /// a dimmed and a full-brightness accent color.
    ///
    /// - Parameters:
    ///   - from: The start color (returned when `phase` is 0).
    ///   - to: The end color (returned when `phase` is 1).
    ///   - phase: The interpolation factor (0–1, clamped).
    /// - Returns: The interpolated RGB color.
    public static func lerp(_ from: Color, _ to: Color, phase: Double) -> Color {
        guard let fromRGB = from.rgbComponents,
            let toRGB = to.rgbComponents
        else {
            return from
        }

        let clamped = min(1, max(0, phase))
        let red = UInt8(Double(fromRGB.red) + (Double(toRGB.red) - Double(fromRGB.red)) * clamped)
        let green = UInt8(
            Double(fromRGB.green) + (Double(toRGB.green) - Double(fromRGB.green)) * clamped
        )
        let blue = UInt8(
            Double(fromRGB.blue) + (Double(toRGB.blue) - Double(fromRGB.blue)) * clamped
        )

        return .rgb(red, green, blue)
    }
}

// MARK: - Internal Helpers

extension Color {
    /// Converts a 256-color palette index to RGB values.
    ///
    /// - Indices 0–7: standard ANSI colors
    /// - Indices 8–15: bright ANSI colors
    /// - Indices 16–231: 6×6×6 color cube
    /// - Indices 232–255: grayscale ramp
    static func palette256ToRGB(_ index: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8) {
        switch index {
        case 0...7:
            guard let ansi = ANSIColor(rawValue: index) else { return (0, 0, 0) }
            return ansi.rgbValues
        case 8...15:
            guard let ansi = ANSIColor(rawValue: index - 8) else { return (0, 0, 0) }
            return ansi.brightRGBValues
        case 16...231:
            // 6×6×6 color cube: index = 16 + 36*r + 6*g + b (each 0–5)
            let cubeIndex = index - 16
            let cubeRed = cubeIndex / 36
            let cubeGreen = (cubeIndex % 36) / 6
            let cubeBlue = cubeIndex % 6
            let channelMap: [UInt8] = [0, 95, 135, 175, 215, 255]
            return (channelMap[Int(cubeRed)], channelMap[Int(cubeGreen)], channelMap[Int(cubeBlue)])
        default:
            // Grayscale ramp: 232–255 → 8, 18, 28, ..., 238
            let gray = UInt8(8 + Int(index - 232) * 10)
            return (gray, gray, gray)
        }
    }
}

// MARK: - Private Helpers

extension Color {
    /// Adjusts a color's lightness by a relative percentage in HSL space.
    ///
    /// Positive values lighten (move toward 100), negative values darken
    /// (move toward 0). The adjustment is **relative** to the current position:
    ///
    /// - Lighten: `newLightness = lightness + (100 − lightness) × percentage`
    /// - Darken:  `newLightness = lightness × (1 − |percentage|)`
    ///
    /// This means 0.5 always moves halfway to the target extreme, regardless
    /// of the starting lightness. Hue and saturation are preserved.
    ///
    /// - Parameter percentage: The relative adjustment (−1 to 1).
    /// - Returns: The adjusted color as HSL, or self if semantic (unresolved).
    fileprivate func adjusted(by percentage: Double) -> Self {
        guard let (red, green, blue) = rgbComponents else {
            return self
        }

        let (hue, saturation, lightness) = Self.rgbToHSL(red: red, green: green, blue: blue)
        let clamped = min(1.0, max(-1.0, percentage))

        let newLightness: Double
        if clamped >= 0 {
            // Lighten: move toward 100
            newLightness = lightness + (100.0 - lightness) * clamped
        } else {
            // Darken: move toward 0
            newLightness = lightness * (1.0 + clamped)
        }

        return .hsl(hue, saturation, min(100, max(0, newLightness)))
    }
}
