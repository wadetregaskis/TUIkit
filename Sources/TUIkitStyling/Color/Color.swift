//  🖥️ TUIkit — Terminal UI Kit for Swift
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
import Foundation  // `String(format:)` / `trimmingCharacters` — stated, not borrowed from a sibling file (SE-0444)

public struct Color: Sendable, Hashable {
    /// The internal color value.
    public let value: ColorValue

    /// Internal enum for different color types.
    public enum ColorValue: Sendable, Hashable {
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

    // MARK: - SwiftUI's Named Colors

    // The eight names SwiftUI has that the ANSI vocabulary above does not.
    //
    // The VALUES are Apple's system palette, sampled from AppKit in the light
    // (aqua) appearance rather than guessed — `NSColor.systemOrange` and friends
    // converted to sRGB. SwiftUI resolves these dynamically per appearance; a
    // terminal has no such notion, so one appearance had to be chosen and light
    // is the one a default terminal theme matches.
    //
    // - Important: These are deliberately NOT the CSS colours of the same name.
    //   `Color.orange` is Apple's `#FF9500`; CSS "orange" is `#FFA500`, and the
    //   colour picker's Named-colours tab (``SwatchPalettes``) lists the CSS
    //   value under that name. Both are correct for what they are: the picker
    //   browses the web vocabulary, this matches the SwiftUI source you are
    //   porting. Do not reconcile them.
    //
    // `.red`, `.green`, `.blue` and `.yellow` are NOT re-pointed at their system
    // values. In a terminal those names mean the ANSI slots, which the user's
    // theme defines — taking that away to gain a nominal match with Apple's
    // `#FF3B30` would break every themed app on screen.

    /// Grey (Apple's system grey, `#8E8E93`).
    public static let gray = Self.hex(0x8E_8E_93)

    /// Orange (Apple's system orange, `#FF9500`).
    public static let orange = Self.hex(0xFF_95_00)

    /// Pink (Apple's system pink, `#FF2D55`).
    public static let pink = Self.hex(0xFF_2D_55)

    /// Purple (Apple's system purple, `#AF52DE`).
    public static let purple = Self.hex(0xAF_52_DE)

    /// Brown (Apple's system brown, `#A2845E`).
    public static let brown = Self.hex(0xA2_84_5E)

    /// Mint (Apple's system mint, `#00C7BE`).
    public static let mint = Self.hex(0x00_C7_BE)

    /// Teal (Apple's system teal, `#59ADC4`).
    public static let teal = Self.hex(0x59_AD_C4)

    /// Indigo (Apple's system indigo, `#5856D6`).
    public static let indigo = Self.hex(0x58_56_D6)

    // MARK: - Semantic Colors

    /// These are the SwiftUI-shaped spellings of the palette roles below, and
    /// they mean exactly those roles — they are not fixed colours that happen
    /// to be named after them.
    ///
    /// They used to be: `primary` was `Color.blue` and `accent` was
    /// `Color.cyan`. That was wrong twice over. It disagreed with SwiftUI,
    /// where `.primary` is the colour a label defaults to rather than a hue;
    /// and, more fundamentally, **a fixed ANSI name is not a colour anyone can
    /// predict** — `SGR 34` selects slot 4 of the user's scheme, which they are
    /// free to make orange. A colour the framework chooses on the user's behalf
    /// has to be either a palette role, which the app's theme defines, or
    /// ``default``, which is explicitly the user's own. See "What an ANSI
    /// colour actually paints" in `Documentation/Terminal-compatibility.md`.
    ///
    /// Being semantic, they resolve at render time and return `nil` from
    /// ``rgbComponents`` until they do — see ``resolve(with:)``.

    /// The colour text defaults to — SwiftUI's `.primary`, and the palette's
    /// ``SemanticColor/foreground``.
    public static let primary = Self.palette.foreground

    /// A lower-emphasis label colour — SwiftUI's `.secondary`, and the
    /// palette's ``SemanticColor/foregroundSecondary``.
    public static let secondary = Self.palette.foregroundSecondary

    /// The app's accent — SwiftUI's `.accentColor`, and the palette's
    /// ``SemanticColor/accent``.
    ///
    /// Spelled as SwiftUI spells it. It was `Color.accent`, which was a second
    /// name for a thing `Color.palette.accent` already said, and named the
    /// FIXED cyan rather than the themed role — so ported SwiftUI code that
    /// wrote `.accentColor` did not compile, and code that wrote `.accent` got
    /// the un-themed one.
    public static let accentColor = Self.palette.accent

    /// Warning color — the palette's ``SemanticColor/warning``.
    public static let warning = Self.palette.warning

    /// Error color — the palette's ``SemanticColor/error``.
    public static let error = Self.palette.error

    /// Success color — the palette's ``SemanticColor/success``.
    public static let success = Self.palette.success

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
    /// Non-semantic colors are returned unchanged. Semantic colors are mapped to
    /// the corresponding palette property — *transitively*, because a palette
    /// slot may itself hold a semantic reference (a palette editor can set
    /// `accent` to `.semantic(.success)`, so resolving `.accent` yields another
    /// semantic colour that must be resolved in turn).
    ///
    /// The result is **always concrete**. A reference cycle (e.g. a slot set to
    /// its own role, `accent` → `.semantic(.accent)`) is broken after a bounded
    /// number of hops and falls back to a neutral RGB, so resolution can neither
    /// loop forever nor return a `.semantic` colour to the renderer — which
    /// `ANSIRenderer` traps on. (Without this, clicking a role in a colour
    /// picker's semantic tab while editing that same role crashed the app.)
    ///
    /// - Parameter palette: The palette to resolve against.
    /// - Returns: A concrete (non-semantic) color.
    public func resolve(with palette: any Palette) -> Color {
        var resolved = self
        // 16 > the number of palette roles, so any acyclic reference chain
        // resolves fully within the cap; only a cycle reaches it.
        for _ in 0..<16 {
            guard case .semantic(let token) = resolved.value else { return resolved }
            resolved = token.resolve(with: palette)
        }
        if case .semantic = resolved.value { return .rgb(128, 128, 128) }
        return resolved
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
    /// Exactly ``opacity(_:over:)`` with a black surface, and rounds the same
    /// way ``lerp(_:_:phase:)`` does — a test pins the two together, because a
    /// shorthand that disagrees with the thing it is short for is worse than no
    /// shorthand.
    ///
    /// - Parameter opacity: The opacity (0–1; clamped, and a NaN reads as 0).
    /// - Returns: A color simulating the given opacity, or self if semantic.
    public func opacity(_ opacity: Double) -> Self {
        guard let (red, green, blue) = rgbComponents else {
            return self
        }

        // Clamped, because a caller is allowed to hand this a number out of
        // range and `UInt8(_: Double)` traps on one. `min`/`max` in this order
        // also fold a NaN to 0, which is the only answer available.
        let opacity = min(1, max(0, opacity))
        func scaled(_ channel: UInt8) -> UInt8 {
            UInt8(min(255, max(0, (Double(channel) * opacity).rounded())))
        }

        return .rgb(scaled(red), scaled(green), scaled(blue))
    }

    /// Returns the color composited at `opacity` over `surface` — true alpha
    /// blending, unlike ``opacity(_:)`` which can only mix toward black.
    ///
    /// Over a black surface the two coincide exactly, which is how the
    /// mix-toward-black shorthand survived on dark palettes; over light
    /// surfaces it turns every "dim" into a near-black smudge (the
    /// dark-on-dark controls seen under light palettes), so palette-aware
    /// rendering should pass the surface the colour actually draws on.
    ///
    /// - Parameters:
    ///   - opacity: The opacity (0–1).
    ///   - surface: The colour beneath, typically the palette background the
    ///     view draws over.
    /// - Returns: The blended color, or `self` if either side is semantic.
    public func opacity(_ opacity: Double, over surface: Color) -> Self {
        Self.lerp(self, surface, phase: 1 - opacity)
    }

    /// This colour mixed with another — SwiftUI's spelling of ``lerp(_:_:phase:)``.
    ///
    /// ```swift
    /// let halfway = Color.red.mix(with: .blue, by: 0.5)
    /// ```
    ///
    /// Exactly a two-stop gradient evaluated at `fraction`:
    /// `Gradient(colors: [self, rhs]).color(at: fraction)` is the same colour,
    /// because both are this one interpolation.
    ///
    /// ## The default is `.perceptual`, and a gradient's is not
    ///
    /// That asymmetry is SwiftUI's, kept rather than tidied: a bare
    /// ``Gradient`` interpolates in ``Gradient/ColorSpace/device`` and this
    /// mixes in ``Gradient/ColorSpace/perceptual``. So
    /// `Color.red.mix(with: .blue, by: 0.5)` and
    /// `Gradient(colors: [.red, .blue]).color(at: 0.5)` are NOT the same
    /// colour unless you say so — the first comes out of OKLab, the second out
    /// of encoded sRGB. Pass `in: .device`, or build the gradient with
    /// `colorSpace: .perceptual`, and they agree again.
    ///
    /// - Parameters:
    ///   - rhs: The colour to mix towards.
    ///   - fraction: How far towards `rhs` (0–1; clamped).
    ///   - colorSpace: Which space to mix in.
    /// - Returns: The mixture, or `self` if either side is semantic.
    public func mix(
        with rhs: Color, by fraction: Double,
        in colorSpace: Gradient.ColorSpace = .perceptual
    ) -> Self {
        Self.interpolate(self, rhs, phase: fraction, in: colorSpace)
    }

    /// Two colours blended in a named space — the whole of what
    /// ``Gradient/ColorSpace`` decides.
    ///
    /// `.device` is ``lerp(_:_:phase:)`` exactly, so nothing that does not ask
    /// for a space changes by a byte. `.perceptual` goes through OKLab, where a
    /// straight line between two colours looks like one: the midpoint of red
    /// and blue stops being darker than either end, and blue to yellow stops
    /// passing through grey.
    ///
    /// - Parameters:
    ///   - from: The colour at `0`.
    ///   - to: The colour at `1`.
    ///   - phase: How far between them (0–1; clamped).
    ///   - space: Which space to blend in.
    /// - Returns: The blend, or `from` if either side is semantic.
    package static func interpolate(
        _ from: Color, _ to: Color, phase: Double, in space: Gradient.ColorSpace
    ) -> Color {
        guard space.isPerceptual else { return lerp(from, to, phase: phase) }
        guard let fromRGB = from.rgbComponents, let toRGB = to.rgbComponents else { return from }
        let clamped = min(1, max(0, phase))
        let start = oklab(red: fromRGB.red, green: fromRGB.green, blue: fromRGB.blue)
        let end = oklab(red: toRGB.red, green: toRGB.green, blue: toRGB.blue)
        let blended = fromOKLab(
            l: start.l + (end.l - start.l) * clamped,
            a: start.a + (end.a - start.a) * clamped,
            b: start.b + (end.b - start.b) * clamped)
        return .rgb(blended.red, blended.green, blended.blue)
    }

    /// Linearly interpolates between two colors.
    ///
    /// Both colors are converted to RGB before interpolation. If either
    /// color is semantic (unresolved), the `from` color is returned unchanged.
    ///
    /// Used by the breathing focus indicator to smoothly fade between
    /// a dimmed and a full-brightness accent color.
    ///
    /// ## Rounding
    ///
    /// To nearest, because that is the answer with the smallest average error —
    /// truncating biases every channel of every blend down by half a unit, and
    /// a "dim" derived by blending toward the background is therefore always a
    /// shade darker than it was asked to be. It also agreed with nothing else:
    /// `encodedChannel`, which is where the perceptual path and the
    /// linear-light compositing path both come out, has always rounded. Two
    /// answers to the same question was the only reason for the difference.
    ///
    /// - Parameters:
    ///   - from: The start color (returned when `phase` is 0).
    ///   - to: The end color (returned when `phase` is 1).
    ///   - phase: The interpolation factor (0–1, clamped; a `phase` of NaN
    ///     reads as 0).
    /// - Returns: The interpolated RGB color.
    public static func lerp(_ from: Color, _ to: Color, phase: Double) -> Color {
        guard let fromRGB = from.rgbComponents,
            let toRGB = to.rgbComponents
        else {
            return from
        }

        let clamped = min(1, max(0, phase))
        func blend(_ start: UInt8, _ end: UInt8) -> UInt8 {
            let value = Double(start) + (Double(end) - Double(start)) * clamped
            // Clamped as well as rounded: the arithmetic cannot leave 0…255 for
            // a `clamped` in 0…1, but `UInt8(_: Double)` traps if it ever did,
            // and a trap is not an acceptable answer to a rounding question.
            return UInt8(min(255, max(0, value.rounded())))
        }

        return .rgb(
            blend(fromRGB.red, toRGB.red),
            blend(fromRGB.green, toRGB.green),
            blend(fromRGB.blue, toRGB.blue))
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
    package static func palette256ToRGB(_ index: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8) {
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
