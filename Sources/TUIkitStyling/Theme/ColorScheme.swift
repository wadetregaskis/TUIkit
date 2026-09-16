//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorScheme.swift
//
//  Whether an app is drawn on a light page or a dark one.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Color Scheme

/// Whether the surroundings are light or dark.
///
/// Read it from the environment to choose between two things an app draws:
///
/// ```swift
/// @Environment(\.colorScheme) private var colorScheme
///
/// var body: some View {
///     Text(colorScheme == .dark ? "🌙" : "☀️")
/// }
/// ```
///
/// It is a READ, and what it answers is the ``Palette``'s: the page the palette
/// paints where that can be measured, what the terminal said about its own
/// colours where the palette leaves the page to the terminal, and ``light``
/// where nothing said anything. A view pins it for its subtree by writing it
/// (`.environment(\.colorScheme, .dark)`), and a whole appearance is a palette —
/// `.palette(_:)` — as `Documentation/SwiftUI-compatibility.md` §2.5 records.
public enum ColorScheme: CaseIterable, Hashable, Sendable {
    /// Dark content on a light page.
    case light

    /// Light content on a dark page.
    case dark
}

extension ColorScheme {
    /// The scheme a page of `background` reads as, or `nil` where that colour has
    /// no RGB to measure — ``Color/default``, a slot the terminal has not
    /// reported, an unresolved semantic colour.
    ///
    /// **Which ink reads better on it**, rather than a lightness threshold: that
    /// is the question a scheme is asked in order to answer, and WCAG's own
    /// contrast ratio already states it. The crossover — where white ink starts
    /// reading better than black — is the ratio's equal point, a relative
    /// luminance of about 0.179, which falls between grey 117 (dark) and grey 118
    /// (light). `ColorSchemeTests` pins that pair.
    package init?(background: Color) {
        guard background.rgbComponents != nil else { return nil }
        let white = Color.white.contrastRatio(against: background)
        let black = Color.black.contrastRatio(against: background)
        self = white > black ? .dark : .light
    }
}
