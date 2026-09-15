//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HighlightFill.swift
//
//  What a highlight drawn behind content paints, where the colours it is built from
//  may be the terminal's own.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What a highlight drawn behind content paints: a fill, a breath between two fills,
/// or reverse video over a stated pair.
///
/// A highlight is a tint — the accent, or a text tier, blended into the page. Where
/// that tint or the ground has no RGB (``Color/default``, or a colour of the terminal's
/// own that it has not reported), the blend has no RGB between its ends: every share of
/// it is one end or the other (`Documentation/Opacity as composition.md` §75). Below
/// half that is the ground, which says nothing at all; at half or more it is a solid
/// colour whose contrast with the content on top of it nobody can check. Reverse video
/// is the one highlight a terminal paints legibly whatever colours it keeps, so that is
/// what such a site draws instead.
package enum HighlightFill: Equatable, Sendable {
    /// One colour, every frame.
    case fill(Color)

    /// A breath between two fills, for a site that can animate one.
    case pulse(dim: Color, bright: Color)

    /// Reverse video (SGR 7) over `ink` on `field`, both of which are STATED beside the
    /// 7. A bare 7 exchanges the colours in force, and after a reset those are the
    /// terminal's own pair rather than the palette's
    /// (`Documentation/Terminal-compatibility.md`, "Reverse video (SGR 7)").
    case reversed(ink: Color, field: Color)

    /// Whether this is a reversal — for a site that already knows the pair it would
    /// paint and only needs telling whether to state it beside an SGR 7.
    ///
    /// A text input's selection and its block caret are both of those: each reverses
    /// the CELL, whose ink and field it holds already, and what it asks the palette is
    /// only whether the tint it would otherwise have drawn can be measured.
    package var isReversed: Bool {
        if case .reversed = self { return true }
        return false
    }
}

extension Palette {
    /// A still highlight: `fill`, or reverse video where it cannot be measured.
    ///
    /// - Parameters:
    ///   - fill: The colour the site would draw.
    ///   - surface: What the highlight sits on, when that is not the page.
    ///   - tint: The colour `fill` is a share of, where it is one. A share below half of
    ///     a colour the terminal decides is the ground itself, which measures perfectly
    ///     well and shows nothing, so the fill alone cannot say whether the highlight is
    ///     visible.
    /// - Returns: `.fill(fill)` where the fill, the tint and the ground all have RGB;
    ///   otherwise `.reversed`, over this palette's ``Palette/foreground`` on the ground.
    package func highlightFill(
        _ fill: Color, over surface: Color? = nil, tint: Color? = nil
    ) -> HighlightFill {
        let ground = surface ?? background
        guard fill.rgbComponents != nil, ground.rgbComponents != nil,
            tint.map({ $0.rgbComponents != nil }) ?? true
        else { return .reversed(ink: foreground, field: ground) }
        return .fill(fill)
    }

    /// The emphasis a focused, selected row shows: the accent's fill breath
    /// (``Palette/accentFillPulse(over:)``), or reverse video where the accent or the
    /// ground has no RGB.
    ///
    /// Such a breath is two equal ends held at the bright one (§79), which for an opaque
    /// accent is a solid half-strength accent under content nobody can check for
    /// contrast, and for a translucent one is the ground itself. Reversed, the row says
    /// where the cursor is in whatever colours the terminal paints.
    ///
    /// - Parameter surface: What the fill sits on, when that is not the page.
    package func emphasisFill(over surface: Color? = nil) -> HighlightFill {
        let ground = surface ?? background
        guard accent.rgbComponents != nil, ground.rgbComponents != nil else {
            return .reversed(ink: foreground, field: ground)
        }
        let (dim, bright) = accentFillPulse(over: surface)
        return .pulse(dim: dim, bright: bright)
    }
}
