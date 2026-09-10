//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowBackground.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// What a selectable row draws behind itself — a flat colour, or the whole
/// breath of one.
///
/// The cursor row of a focused list or table pulses its background. Resolving
/// that to a single `Color` as the row renders is a read of the live animation
/// clock, which makes the frame unreplayable: the run loop then has no way to
/// advance the pulse except by walking and re-rendering the entire view tree,
/// ten to twenty times a second, to recolour one row. Carrying the *cycle*
/// instead lets the row be drawn once and handed to the loop as
/// ``AnimatedCellRun``s. See ``SelectionEmphasisCycle``.
///
/// Shared by `_ListCore` and `Table` deliberately. They are twins — the same
/// rules about focus, selection and the unfocused-selection visibility, written
/// out twice — and the two have drifted apart before. One description of what a
/// row's background can be is one fewer thing to drift.
enum RowBackground {
    /// No background at all.
    case none

    /// One colour, every frame.
    case fixed(Color)

    /// A breathing colour: the whole cycle and the two ends it runs between.
    case pulsing(SelectionEmphasisCycle, dim: Color, bright: Color)

    /// `.fixed`, or `.none` for no colour — for the callers whose other branches
    /// produce an optional.
    init(_ color: Color?) {
        self = color.map(Self.fixed) ?? .none
    }

    /// The pulse a focused, selected row shows, between the shared min/max ends.
    ///
    /// The one definition of that colour pair: a list and a table showing
    /// visibly different pulses for the same state is exactly the kind of drift
    /// this type exists to prevent.
    @MainActor
    static func focusedSelection(in context: RenderContext, palette: any Palette) -> Self {
        let (dim, bright) = palette.accentFillPulse()
        return .pulsing(context.environment.selectionEmphasis.cycle(true), dim: dim, bright: bright)
    }

    /// The colour to draw with in the frame being rendered now.
    @MainActor
    var colorNow: Color? {
        switch self {
        case .none: return nil
        case .fixed(let color): return color
        case .pulsing(let cycle, let dim, let bright):
            return cycle.colorNow(dim: dim, bright: bright)
        }
    }

    /// Every colour of the pulse, in cycle order — or `nil` when this background
    /// does not animate (a still picture earns no runs: the ordinary render
    /// already drew it, and replaying it would emit bytes per tick to no
    /// visible effect).
    @MainActor
    var pulseColors: [Color]? {
        guard case .pulsing(let cycle, let dim, let bright) = self, cycle.isAnimating else {
            return nil
        }
        return cycle.colors(dim: dim, bright: bright)
    }

    /// Which colour of ``pulseColors`` the frame being rendered now shows.
    @MainActor
    var stepNow: Int {
        guard case .pulsing(let cycle, _, _) = self, !cycle.frames.isEmpty else { return 0 }
        return cycle.step % cycle.frames.count
    }

    /// The fill a claim would be about, or `nil` where there is nothing to claim.
    ///
    /// A PULSING background earns none and needs none: `accentFillPulse` returns both
    /// ends through ``Color/opacity(_:over:)``, which consumes a translucent tint's
    /// alpha and stamps the result opaque (§21, §29). Every frame of the breath
    /// therefore states a concrete colour and no alpha is left over — which is also
    /// why the pulse can be a run at all, since a run's frames must all answer to one
    /// static region.
    @MainActor
    var claimableFill: Color? {
        guard case .fixed(let color) = self else { return nil }
        return color
    }
}

// MARK: - What a selectable row's line owes

/// The claims one line of a selectable row owes for the translucent colours it
/// painted.
///
/// Here beside ``RowBackground`` and ``RowSelectionIndicator`` for exactly the reason
/// those are: a `List` and a `Table` run the same rules about focus, selection and
/// visibility, they have drifted apart before, and "which cells of a row owe a blend"
/// is one more rule that must not be written out twice.
enum SelectableRowClaims {
    /// - Parameters:
    ///   - line: Which of the row's lines this is, in the row's own coordinates.
    ///   - width: The row's full width — what a background fill covers.
    ///   - cells: The columns the row's TEXT occupies, which start past the mark and
    ///     its gap. Empty where the caller draws no text of its own (a `List` row's
    ///     content is a child buffer that claims for itself).
    ///   - ink: The colour every cell of that text was drawn in.
    ///   - mark: The colour the selection ● was drawn in, or `nil` on a continuation
    ///     line and wherever no mark is drawn.
    ///   - fill: The row's background, or `nil` for a row that paints none and for a
    ///     PULSING one (see ``RowBackground/claimableFill``).
    /// - Returns: Between zero and three regions, in the row's own coordinates.
    ///
    /// Three rectangles rather than one, and they must not be merged. The mark and the
    /// text are different colours: a merged INK rectangle would resolve the ● at the
    /// text's alpha, which is §23.2's mistake in a different shape. The fill is a
    /// different CHANNEL, so its rectangle overlaps both and that is correct — an
    /// ink-only region carries `fieldOpacity: 1` and a field-only one carries
    /// `inkOpacity: 1`, and the resolver multiplies across every region covering a
    /// cell (§27). This is `.foregroundStyle(…).background(…)` in row form.
    ///
    /// The gap cell between the mark and the text is deliberately covered by the FILL
    /// claim only. It is a bare space with no ink of its own, and an ink claim on such
    /// a cell lets what is behind it through where the row drew a pad.
    static func claims(
        line: Int, width: Int, cells: Range<Int>, ink: Color?, mark: Color?, fill: Color?
    ) -> [OpacityRegion] {
        // Asked first, so an opaque row — every row of nearly every table — pays three
        // alpha compares and allocates nothing.
        guard ink?.isOpaque == false || mark?.isOpaque == false || fill?.isOpaque == false
        else { return [] }
        var claims: [OpacityRegion] = []
        if let mark, let claim = OpacityRegion.claim(
            offsetX: 0, offsetY: line, width: 1, height: 1, ink: mark)
        {
            claims.append(claim)
        }
        if let claim = OpacityRegion.claim(
            offsetX: cells.lowerBound, offsetY: line, width: cells.count, height: 1, ink: ink)
        {
            claims.append(claim)
        }
        if let claim = OpacityRegion.claim(
            offsetX: 0, offsetY: line, width: width, height: 1, field: fill)
        {
            claims.append(claim)
        }
        return claims
    }
}

// MARK: - Selection Indicator

/// The glyph a selectable row shows in its indicator gutter, and its colour.
///
/// Here, beside ``RowBackground``, for exactly the reason that type gives: the
/// two views are twins running the same rules about focus, selection and the
/// unfocused-selection visibility, and this is a place they HAD already
/// drifted. `Table` drew a bullet in its gutter; `_ListCore` reserved a gutter
/// of identical purpose on every row and never drew anything in it. Same state,
/// same palette, same pulse — one showed the mark and the other did not.
///
/// **It marks SELECTION, not focus.** Which row the cursor is on is said by the
/// background, which breathes; a row merely under the cursor has not been
/// chosen, and says so with a still highlight and no glyph. So a control with
/// no selection at all draws no glyph on any row, which is what a plain `List`
/// looked like before this existed and still looks like now.
struct RowSelectionIndicator {
    /// Exactly one cell wide, always — the gutter is reserved whether or not
    /// there is anything to put in it, so a blank is a space rather than an
    /// empty string. A row whose glyph changed width would move its content.
    let glyph: String

    /// The colour to draw ``glyph`` in. Meaningless for a blank, and set to the
    /// same tertiary the `Table` has always used there rather than to `nil`, so
    /// callers need no optional they would only ever pass through.
    let color: Color

    /// Whether anything is actually drawn — for a caller that can skip work
    /// when the answer is a space.
    var isBlank: Bool { glyph == " " }

    /// Whether a control should set cells aside for the mark at all.
    ///
    /// A control with no selection binding has nothing to mark, and one told
    /// ``View/rowSelectionIndicator(_:)`` `.hidden` has been told not to mark
    /// it. Either way ``forRow(isFocused:isSelected:context:palette:)`` answers
    /// a blank for every row for the control's whole life, so cells kept for it
    /// are an indent nobody asked for — which is what a `Table` with no
    /// selection was: three cells of air before every value, two of them
    /// unreachable.
    ///
    /// Only ``forRow(isFocused:isSelected:context:palette:)``'s *structural*
    /// conditions are here. The per-row ones are not: whether THIS row is
    /// selected, and whether an unfocused selection is shown, both change as
    /// the app runs, and a column that appeared when you clicked a row would
    /// shift every value in the table sideways.
    ///
    /// `Table` reserves two cells — the glyph and the gap to the first column —
    /// and gives both back here. `_ListCore` reserves none: it draws its mark
    /// in the one pad cell its rows already had, so it has nothing to hand
    /// back, and asks this only so the two twins keep answering one question in
    /// one place.
    ///
    /// - Parameters:
    ///   - hasSelection: Whether the control has a selection binding at all.
    ///   - environment: For ``EnvironmentValues/rowSelectionIndicator``.
    static func isReserved(hasSelection: Bool, environment: EnvironmentValues) -> Bool {
        hasSelection && environment.rowSelectionIndicator != .hidden
    }

    /// The indicator for a row in the state given.
    ///
    /// - Parameters:
    ///   - isFocused: Whether this is the cursor row AND the control has focus.
    ///   - isSelected: Whether the row is in the selection.
    ///   - context: For ``EnvironmentValues/unfocusedSelectionVisibility``.
    ///   - palette: The colours to draw from.
    @MainActor
    static func forRow(
        isFocused: Bool, isSelected: Bool, context: RenderContext, palette: any Palette
    ) -> Self {
        let blank = Self(glyph: " ", color: palette.foregroundTertiary)
        guard isSelected else { return blank }
        // The caller asked for the highlight alone. Checked before anything
        // else, because it is a statement about this control rather than about
        // this row's state.
        guard context.environment.rowSelectionIndicator != .hidden else { return blank }
        if isFocused { return Self(glyph: "●", color: palette.accent) }
        // Selected while the control itself does not have focus. `.hidden`
        // collapses the row's whole visual state into an unselected one — the
        // background does the same — so the mark goes with it.
        guard context.environment.unfocusedSelectionVisibility != .hidden else { return blank }
        return Self(
            glyph: "●",
            color: palette.accent.opacity(ViewConstants.selectionIndicator, over: palette.background)
        )
    }
}
