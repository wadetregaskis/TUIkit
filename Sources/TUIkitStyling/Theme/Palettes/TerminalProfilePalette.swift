//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalProfilePalette.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Terminal Profile Palette

/// A palette recreating one of the built-in **macOS Terminal.app** profiles
/// (Basic, Grass, Homebrew, Man Page, Novel, Ocean, Pro, Red Sands, Silver
/// Aerogel, Solid Colors).
///
/// The defining colours — background, text, bold text, cursor and selection —
/// are the exact sRGB values shipped in
/// `Terminal.app/Contents/Resources/Initial Settings/*.terminal` (decoded from
/// their archived `NSColor` blobs). The Terminal profiles do **not** override
/// the 16 ANSI colours, so each profile's character lives entirely in those
/// five colours; TUIkit's remaining semantic roles are derived from them:
///
/// - `foregroundSecondary/Tertiary/Quaternary` ladder the text colour toward
///   the background.
/// - `accent` is the bold-text colour when it is colourful (Grass amber,
///   Homebrew green, Red Sands gold, Novel brick…), else the most distinct of
///   the cursor / selection / bold candidates — so neutral profiles (Pro,
///   Solid Colors) get a clean monochrome accent.
/// - `focusBackground` is the profile's selection colour (the same role: the
///   background of a highlighted region).
/// - `success / warning / error / info` are readable green / amber / red / blue
///   tuned to the background's lightness (Terminal uses its default ANSI set
///   for all profiles, so these are intentionally profile-independent in hue).
public struct TerminalProfilePalette: Palette {

    // MARK: - Profile

    /// The built-in macOS Terminal.app profiles.
    public enum Profile: String, CaseIterable, Sendable {
        case basic
        case grass
        case homebrew
        case manPage
        case novel
        case ocean
        case pro
        case redSands
        case silverAerogel
        case solidColors

        /// The profile's name as shown in Terminal.app.
        public var displayName: String {
            switch self {
            case .basic: return "Basic"
            case .grass: return "Grass"
            case .homebrew: return "Homebrew"
            case .manPage: return "Man Page"
            case .novel: return "Novel"
            case .ocean: return "Ocean"
            case .pro: return "Pro"
            case .redSands: return "Red Sands"
            case .silverAerogel: return "Silver Aerogel"
            case .solidColors: return "Solid Colors"
            }
        }
    }

    public let id: String
    public let name: String

    public let background: Color
    public let statusBarBackground: Color
    public let appHeaderBackground: Color
    public let overlayBackground: Color

    public let foreground: Color
    public let foregroundSecondary: Color
    public let foregroundTertiary: Color
    public let foregroundQuaternary: Color

    public let accent: Color
    public let success: Color
    public let warning: Color
    public let error: Color
    public let info: Color

    public let border: Color
    public let focusBackground: Color
    public let cursorColor: Color

    /// Creates a palette recreating the given Terminal.app profile.
    public init(_ profile: Profile) {
        let spec = Self.spec(for: profile)
        self.init(
            id: "terminal.\(profile.rawValue)",
            name: profile.displayName,
            background: spec.background,
            foreground: spec.foreground,
            bold: spec.bold,
            cursor: spec.cursor,
            selection: spec.selection)
    }

    /// Derives the full semantic palette from a profile's five defining colours.
    /// `cursor` and `selection` are optional because some profiles inherit
    /// Terminal's defaults rather than overriding them.
    private init(
        id: String,
        name: String,
        background: Color,
        foreground: Color,
        bold: Color,
        cursor: Color?,
        selection: Color?
    ) {
        self.id = id
        self.name = name

        let darkBackground = Self.isDark(background)

        self.background = background
        self.statusBarBackground =
            darkBackground ? background.lighter(by: 0.10) : background.darker(by: 0.06)
        self.appHeaderBackground =
            darkBackground ? background.lighter(by: 0.16) : background.darker(by: 0.10)
        self.overlayBackground = background

        self.foreground = foreground
        self.foregroundSecondary = Color.lerp(foreground, background, phase: 0.25)
        self.foregroundTertiary = Color.lerp(foreground, background, phase: 0.45)
        self.foregroundQuaternary = Color.lerp(foreground, background, phase: 0.62)

        let accent = Self.deriveAccent(
            background: background, foreground: foreground,
            candidates: [bold, cursor, selection].compactMap { $0 })
        self.accent = accent

        self.border = Color.lerp(foreground, background, phase: 0.6)
        // The profile's selection colour is the same role as a focused row's
        // background; when a profile doesn't define one, tint the background
        // gently toward the accent so the highlight still reads.
        self.focusBackground = selection ?? Color.lerp(accent, background, phase: 0.78)
        self.cursorColor = cursor ?? foreground

        // Status colours: readable green / amber / red / blue, brighter on a
        // dark background and deeper on a light one. Profile-independent in hue
        // (Terminal uses its default ANSI palette for every profile).
        self.success = Color.hsl(135, darkBackground ? 55 : 50, darkBackground ? 62 : 38)
        self.warning = Color.hsl(40, darkBackground ? 80 : 72, darkBackground ? 62 : 42)
        self.error = Color.hsl(6, darkBackground ? 70 : 62, darkBackground ? 64 : 46)
        self.info = Color.hsl(208, darkBackground ? 70 : 60, darkBackground ? 68 : 48)
    }
}

// MARK: - Profile Specifications

extension TerminalProfilePalette {

    /// The five defining colours of each profile, as exact sRGB values decoded
    /// from the shipped `.terminal` files. `cursor`/`selection` are `nil` where
    /// the profile inherits Terminal's default rather than overriding it.
    private struct Spec {
        let background: Color
        let foreground: Color
        let bold: Color
        let cursor: Color?
        let selection: Color?
    }

    private static func spec(for profile: Profile) -> Spec {
        switch profile {
        case .basic:
            // Basic ships no colour overrides; these are Terminal's defaults.
            return Spec(
                background: .rgb(255, 255, 255), foreground: .rgb(0, 0, 0),
                bold: .rgb(0, 0, 0), cursor: .rgb(146, 146, 146), selection: .rgb(164, 205, 255))
        case .grass:
            return Spec(
                background: .rgb(19, 119, 61), foreground: .rgb(255, 240, 165),
                bold: .rgb(255, 176, 59), cursor: .rgb(142, 40, 0), selection: .rgb(182, 73, 38))
        case .homebrew:
            return Spec(
                background: .rgb(0, 0, 0), foreground: .rgb(40, 254, 20),
                bold: .rgb(0, 249, 0), cursor: .rgb(56, 254, 39), selection: .rgb(12, 46, 238))
        case .manPage:
            return Spec(
                background: .rgb(254, 244, 156), foreground: .rgb(0, 0, 0),
                bold: .rgb(0, 0, 0), cursor: nil, selection: .rgb(191, 184, 117))
        case .novel:
            return Spec(
                background: .rgb(223, 219, 195), foreground: .rgb(77, 47, 45),
                bold: .rgb(147, 58, 33), cursor: .rgb(58, 35, 34), selection: .rgb(135, 133, 99))
        case .ocean:
            return Spec(
                background: .rgb(43, 102, 201), foreground: .rgb(255, 255, 255),
                bold: .rgb(255, 255, 255), cursor: nil, selection: .rgb(41, 134, 255))
        case .pro:
            return Spec(
                background: .rgb(0, 0, 0), foreground: .rgb(244, 244, 244),
                bold: .rgb(255, 255, 255), cursor: .rgb(96, 96, 96), selection: .rgb(82, 82, 82))
        case .redSands:
            return Spec(
                background: .rgb(142, 53, 39), foreground: .rgb(215, 201, 167),
                bold: .rgb(230, 199, 43), cursor: .rgb(255, 255, 255), selection: .rgb(61, 25, 22))
        case .silverAerogel:
            return Spec(
                background: .rgb(146, 146, 146), foreground: .rgb(0, 0, 0),
                bold: .rgb(255, 255, 255), cursor: .rgb(224, 224, 224), selection: .rgb(120, 122, 156))
        case .solidColors:
            return Spec(
                background: .rgb(255, 255, 255), foreground: .rgb(0, 0, 0),
                bold: .rgb(0, 0, 0), cursor: .rgb(203, 203, 203), selection: nil)
        }
    }
}

// MARK: - Derivation Helpers

extension TerminalProfilePalette {

    /// Whether a colour reads as "dark" by perceived luminance (Rec. 601 luma).
    private static func isDark(_ color: Color) -> Bool {
        guard let (red, green, blue) = color.rgbComponents else { return true }
        let luma = 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
        return luma < 128
    }

    /// Euclidean distance between two colours in RGB (0 if either is unresolved).
    private static func distance(_ lhs: Color, _ rhs: Color) -> Double {
        guard let a = lhs.rgbComponents, let b = rhs.rgbComponents else { return 0 }
        let dr = Double(a.red) - Double(b.red)
        let dg = Double(a.green) - Double(b.green)
        let db = Double(a.blue) - Double(b.blue)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// Picks the accent colour: the first *colourful* candidate clearly distinct
    /// from the background (so a profile's signature emphasis colour wins), or —
    /// for monochrome profiles with no colourful candidate — the candidate most
    /// distinct from the background, falling back to the foreground.
    private static func deriveAccent(
        background: Color,
        foreground: Color,
        candidates: [Color]
    ) -> Color {
        for candidate in candidates {
            guard let (red, green, blue) = candidate.rgbComponents else { continue }
            let saturation = Color.rgbToHSB(red: red, green: green, blue: blue).saturation
            if saturation >= 18 && distance(candidate, background) > 25 {
                return candidate
            }
        }
        return candidates.max(by: { distance($0, background) < distance($1, background) })
            ?? foreground
    }
}

// MARK: - Convenience

extension TerminalProfilePalette {
    /// Every Terminal.app profile palette, in Terminal's listing order.
    public static let all: [TerminalProfilePalette] = Profile.allCases.map(TerminalProfilePalette.init)
}
