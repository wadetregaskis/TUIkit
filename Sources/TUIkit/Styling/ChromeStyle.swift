//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ChromeStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Chrome style

/// How the app's framing bars — the app header and the status bar — separate
/// themselves from the page between them.
///
/// One type for both, because the two are read together: a boxed footer under a
/// ruled header looks like a mistake even though each is defensible alone. Set
/// them at once with ``Scene/chromeStyle(_:)``, or independently with
/// ``Scene/chromeStyle(appHeader:statusBar:)`` when the mismatch is the point.
///
/// Every style draws with the current ``Appearance``'s border glyphs and the
/// palette's `border` colour, so a custom border restyles the chrome in step
/// with the rest of the app.
///
/// TUI-specific: SwiftUI has no app header or status bar.
public enum ChromeStyle: String, Sendable, Hashable, CaseIterable, Codable {
    /// Content, plus a full-width rule on the side facing the page — under the
    /// header, over the status bar.
    ///
    /// The lightest thing that still reads as a boundary. The two bars mirror
    /// each other, which is what makes a header and a footer look like a pair.
    ///
    /// ```
    /// My App                                    v1.0
    /// ────────────────────────────────────────────────
    ///  … the page …
    /// ────────────────────────────────────────────────
    ///   ↑↓ nav          ↵ select          q quit
    /// ```
    case rule

    /// Content inside a full box, like a container view.
    ///
    /// The default: two extra rows per bar and a wall down each side, so the
    /// chrome reads as a panel of its own rather than as a margin.
    ///
    /// ```
    /// ╭──────────────────────────────────────────────╮
    /// │  ↑↓ nav          ↵ select          q quit    │
    /// ╰──────────────────────────────────────────────╯
    /// ```
    case bordered

    /// Content alone — no rule, no box.
    ///
    /// The fewest rows a bar can occupy, for apps that would rather spend the
    /// height on the page. The bars are still distinguishable by their
    /// background colour (`appHeaderBackground` / `statusBarBackground`).
    case compact
}

extension ChromeStyle {
    /// How many rows this style adds around the bar's own content.
    ///
    /// The single place the arithmetic lives: heights are computed before the
    /// bars render (the layout has to reserve their space first), so a style
    /// that added a row here and forgot to draw it there would overlap the
    /// page — or leave a gap.
    var chromeRows: Int {
        switch self {
        case .rule: return 1
        case .bordered: return 2
        case .compact: return 0
        }
    }

    /// The bar's total height for `contentRows` rows of content.
    func barHeight(contentRows: Int) -> Int {
        contentRows + chromeRows
    }

    /// How many columns the style's own drawing takes away from the bar's
    /// content — a wall down each side of a box, nothing for the rest.
    ///
    /// Wanted in two places that must agree: the modifier lays the header
    /// content out at `width - contentWidthInset`, and the renderer pads each
    /// of those lines to the same figure before boxing them. Laying out at the
    /// full width and boxing afterwards is what silently ate the last two cells
    /// of every header ("TUIkit v0.6" for "TUIkit v0.6.0").
    var contentWidthInset: Int {
        self == .bordered ? BorderRenderer.borderWidthOverhead : 0
    }
}

// MARK: - Shared drawing

extension ChromeStyle {
    /// A full-width rule in the current appearance's horizontal border glyph and
    /// the palette's border colour.
    ///
    /// Shared so the header's rule and the status bar's are the same rule: they
    /// are meant to read as two edges of one frame, and drawing them from two
    /// places is how they drift.
    @MainActor
    static func ruleRow(width: Int, context: RenderContext) -> String {
        let glyph = context.environment.appearance.borderStyle.horizontal
        return ANSIRenderer.colorize(
            String(repeating: glyph, count: max(0, width)),
            foreground: context.environment.palette.border)
    }
}
