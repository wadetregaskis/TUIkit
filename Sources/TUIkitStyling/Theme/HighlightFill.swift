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

    /// A breath with one end in reverse video, the other a fill (`nil` is the reversed
    /// end): a 16-colour list or table row whose terminal has too few colours to tell
    /// every row's state apart (``RowFills``). The reversal is `ink` and `field`
    /// exchanged, with every colour of the row's own content dropped. A list's or
    /// table's cursor row, a menu's bar and a drop-down's highlighted row ask for one;
    /// any other site (a date field's component, a split view's divider) holds the
    /// fill end still (``stillFill``).
    case reversingPulse(dim: Color?, bright: Color?, ink: Color, field: Color)

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

    /// This highlight for a site that cannot draw a reversing breath: its fill end,
    /// held still. Every other highlight is returned as it is.
    package var stillFill: Self {
        guard case .reversingPulse(let dim, let bright, let ink, let field) = self else { return self }
        return (bright ?? dim).map(Self.fill) ?? .reversed(ink: ink, field: field)
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
    /// ground has no RGB, and on a terminal that draws no colour at all (`.noColor`),
    /// where a fill is nothing and the row would not say where the cursor is.
    ///
    /// Such a breath is two equal ends held at the bright one (§79), which for an opaque
    /// accent is a solid half-strength accent under content nobody can check for
    /// contrast, and for a translucent one is the ground itself. Reversed, the row says
    /// where the cursor is in whatever colours the terminal paints.
    ///
    /// - Parameter surface: What the fill sits on, when that is not the page.
    package func emphasisFill(over surface: Color? = nil) -> HighlightFill {
        let ground = surface ?? background
        // Without colour a fill draws nothing at all; reverse video is an attribute,
        // which such a terminal still draws.
        guard accent.rgbComponents != nil, ground.rgbComponents != nil, ColorDepth.current > .noColor else {
            return .reversed(ink: foreground, field: ground)
        }
        let (dim, bright) = accentFillPulse(over: surface)
        return .pulse(dim: dim, bright: bright)
    }

    /// The still wash of a row merely under the cursor — the cursor row of a focused
    /// list or table, on a row the selection does not include, wherever it does not
    /// breathe (``focusWashEmphasis(appearsActive:)``): ``focusBackground``, or
    /// reverse video where that wash cannot be measured or no colour is drawn.
    ///
    /// The default wash is the tertiary tier at 30% over the page, and a share below
    /// half of a colour the terminal decides is the page itself (Opacity as
    /// composition §75): it measures, and shows nothing. So where the palette has not
    /// stated a wash of its own, the tier it is built from is asked as well.
    package func focusWashFill() -> HighlightFill {
        // Without colour a fill draws nothing at all (see `emphasisFill(over:)`).
        guard ColorDepth.current > .noColor else { return .reversed(ink: foreground, field: background) }
        // A shipped palette's cursor row rests on the F dim end chosen for it
        // (see `RowFills`), not on its `focusBackground`.
        if let fills = rowFills() { return .fill(fills.focusDim) }
        let fill = focusBackground
        let tint = fill == derivedFocusBackground() ? foregroundTertiary : nil
        return highlightFill(fill, tint: tint)
    }

    /// The still tint a selected row shows while the list it is in does not hold the
    /// keys: the palette's S (``RowFills``) — chosen at coding time for a shipped
    /// palette, else by the row-fill rule — and where the palette's colours cannot be
    /// measured, the accent at ``ViewConstants/selectedBackground`` over the page, or
    /// reverse video where that tint cannot be measured either.
    ///
    /// The quiet counterpart of ``emphasisFill(over:)``: the same accent, about half
    /// the strength of its peak, and still. `PaletteContrastAuditTests` measures the
    /// row's text against it as `foreground/selectedRowFill`, which is where the name
    /// comes from — not to be confused with a text input's selection, which is the
    /// accent at ``ViewConstants/selectionIndicator``.
    ///
    /// Over the page only: every row that shows it sits on the page. A caller that must
    /// not draw a second cursor where the tint cannot be measured asks
    /// `RowBackground.tint(_:)` for it, which leaves such a row unfilled rather than
    /// reversed.
    package func selectedRowFill() -> HighlightFill {
        if let fills = rowFills() { return .fill(fills.selection) }
        return highlightFill(accent.opacity(ViewConstants.selectedBackground, over: background), tint: accent)
    }

    /// What a highlighted row paints — a focused list's or table's cursor row on a
    /// selected row, a menu's, a drop-down's or a field's suggestions' highlighted
    /// row: ``emphasisFill(over:)``, and where the row's view does not appear active
    /// (its window has lost the terminal's focus), ``selectedRowFill()`` in place of
    /// the breath.
    ///
    /// The row is still the one the keys will reach when the window comes back, so it
    /// stays drawn; it stops breathing, because motion says the keys go here NOW; and
    /// it takes the look a `List` gives a selection it does not hold the keys for,
    /// which is what makes it read as "here, but not now". One rule, asked here by
    /// every such row, so the three that draw one cannot disagree about it.
    ///
    /// Only a breath is swapped. A reversal — where the accent or the page has no RGB
    /// — is already still, and the tint it would become is exactly the one that
    /// cannot be measured there.
    ///
    /// - Parameters:
    ///   - appearsActive: Whether the row's view appears active
    ///     (`EnvironmentValues.appearsActive`).
    ///   - reversing: Whether the site can draw a breath with one end in reverse
    ///     video (``HighlightFill/reversingPulse(dim:bright:ink:field:)``) — a list's
    ///     or table's cursor row, a menu's bar, a drop-down's highlighted row.
    ///     Elsewhere such a breath's fill end is held still.
    package func highlightedRowFill(appearsActive: Bool, reversing: Bool = false) -> HighlightFill {
        let breath = reversing ? reversingBreath(\.reversedEmphasisEnd, \.emphasisDim, \.emphasisBright) : nil
        return (breath ?? emphasisFill()).stilled(to: selectedRowFill(), unless: appearsActive)
    }

    /// The breath at `end` of this palette's row fills, where one of its ends is
    /// reverse video (16 colours only), else `nil`.
    private func reversingBreath(
        _ end: KeyPath<RowFills, RowFills.BreathEnd?>, _ dim: KeyPath<RowFills, Color>,
        _ bright: KeyPath<RowFills, Color>
    ) -> HighlightFill? {
        guard let fills = rowFills(), let reversed = fills[keyPath: end] else { return nil }
        return .reversingPulse(
            dim: reversed == .dim ? nil : fills[keyPath: dim], bright: reversed == .top ? nil : fills[keyPath: bright],
            ink: foreground, field: background)
    }

    /// What the cursor row of a list or table paints on a row the selection does not
    /// include: the focus wash breathing (``focusWashPulse()``), and where the row's
    /// view does not appear active, the bottom of that breath, still — the plain wash.
    ///
    /// The neutral counterpart of ``highlightedRowFill(appearsActive:)``, under the
    /// same rule: motion says the keys go HERE, now, so a list that has them breathes
    /// its cursor row whether or not that row is selected, and one whose window has
    /// lost the terminal's focus holds it still in the look it always had. A list
    /// drawn with `.rowSelectionIndicator(.hidden)` asks this too: the focus indicator
    /// always visibly breathes, with or without a ● beside it
    /// (`RowBackground.focused(in:palette:)`).
    ///
    /// Where the wash cannot be measured it is reversed, still, as it always was.
    ///
    /// Held at the breath's own bottom rather than at ``focusWashFill()``. For an
    /// opaque wash — every shipped palette's — the two are one colour. A translucent
    /// one (the Example's faded palette) the breath spends over the page at both ends,
    /// and `focusWashFill()` carries: its alpha is claimed and resolved against what
    /// is actually behind the row. Over a view drawn behind the list — a panel in a
    /// `ZStack` — the row then changed colour as the window lost the terminal's focus
    /// instead of stopping, from the wash over the page to the wash over the panel. Spent
    /// over the page awake and held, as a selected row's breath and its held tint
    /// (``selectedRowFill()``) both are, it stops where it was. The limit is the
    /// accent's too: on a surface other than the page, a translucent wash shows the
    /// page's composite rather than that surface's.
    ///
    /// - Parameter appearsActive: Whether the row's view appears active
    ///   (`EnvironmentValues.appearsActive`).
    package func focusWashEmphasis(appearsActive: Bool) -> HighlightFill {
        let still = focusWashFill()
        guard case .fill(let rest) = still else { return still }
        // A 16-colour breath with an end in reverse video: rows draw it.
        if let breath = reversingBreath(\.reversedFocusEnd, \.focusDim, \.focusBright) {
            return breath.stilled(to: .fill(rest), unless: appearsActive)
        }
        let (dim, bright) = focusWashPulse()
        return HighlightFill.pulse(dim: dim, bright: bright).stilled(to: .fill(dim), unless: appearsActive)
    }
}

extension HighlightFill {
    /// This highlight, or `still` in place of a breath where the row's view does not
    /// appear active: the one rule every cursor-like row follows
    /// (``Palette/highlightedRowFill(appearsActive:)``,
    /// ``Palette/focusWashEmphasis(appearsActive:)``). A fill or a reversal is already
    /// still and is returned as it is.
    fileprivate func stilled(
        to still: @autoclosure () -> HighlightFill, unless appearsActive: Bool
    ) -> HighlightFill {
        switch self {
        case .pulse, .reversingPulse: return appearsActive ? self : still()
        case .fill, .reversed: return self
        }
    }
}
