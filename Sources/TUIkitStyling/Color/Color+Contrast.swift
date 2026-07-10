//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color+Contrast.swift
//
//  WCAG contrast measurement and a hue-preserving readability floor.
//  Palette derivations use these to guarantee that every colour pair an app
//  actually draws stays readable, while keeping each palette's signature
//  hues — the fix for derived colours that landed unreadably close to their
//  background on mid-tone or saturated profiles (Silver Aerogel's grey,
//  Man Page's pale yellow, Ocean's blue).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Color {

    // MARK: - Measurement

    /// The WCAG 2.x relative luminance of this colour (0...1), or `nil` for
    /// colours without concrete RGB components (e.g. unresolved semantics).
    public var relativeLuminance: Double? {
        guard let (red, green, blue) = rgbComponents else { return nil }
        func channel(_ value: UInt8) -> Double {
            let c = Double(value) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// The WCAG contrast ratio between this colour and `other` (1...21), or
    /// `0` when either colour has no concrete RGB components.
    public func contrastRatio(against other: Color) -> Double {
        guard
            let mine = relativeLuminance,
            let theirs = other.relativeLuminance
        else { return 0 }
        let lighter = max(mine, theirs)
        let darker = min(mine, theirs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Readability floor

    /// Returns this colour adjusted — hue and saturation preserved, lightness
    /// moved as little as possible — so its contrast against `background`
    /// reaches at least `minimum`.
    ///
    /// Already-readable colours return unchanged, so applying the floor to a
    /// whole palette only touches the offenders. When both lighter and darker
    /// variants can satisfy the minimum, the nearer one wins (least change to
    /// the palette's feel). If no lightness of this hue can reach the minimum
    /// (extreme minimums against mid-tone backgrounds), the closer of black /
    /// white is returned. Colours without RGB components return unchanged.
    public func ensuringContrast(atLeast minimum: Double, against background: Color) -> Color {
        guard contrastRatio(against: background) < minimum else { return self }
        guard let (red, green, blue) = rgbComponents else { return self }
        let (hue, saturation, lightness) = Self.rgbToHSL(red: red, green: green, blue: blue)

        // Walk lightness outward in 1% steps and note the first satisfying
        // value in each direction.
        func firstSatisfying(step: Double) -> Double? {
            var candidate = lightness + step
            while candidate >= 0, candidate <= 100 {
                if Self.hsl(hue, saturation, candidate).contrastRatio(against: background)
                    >= minimum {
                    return candidate
                }
                candidate += step
            }
            return nil
        }

        let up = firstSatisfying(step: 1)
        let down = firstSatisfying(step: -1)
        switch (up, down) {
        case (let brighter?, let darker?):
            let nearest =
                abs(brighter - lightness) <= abs(darker - lightness) ? brighter : darker
            return Self.hsl(hue, saturation, nearest)
        case (let brighter?, nil):
            return Self.hsl(hue, saturation, brighter)
        case (nil, let darker?):
            return Self.hsl(hue, saturation, darker)
        case (nil, nil):
            let white = Self.rgb(255, 255, 255)
            let black = Self.rgb(0, 0, 0)
            return white.contrastRatio(against: background) >= black.contrastRatio(against: background)
                ? white : black
        }
    }
}
