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

    /// Reverse video (SGR 7) over the palette's own ink and page, both stated beside
    /// the 7 — the highlight a terminal paints whatever colours it keeps, for a row
    /// whose fill cannot be measured (``HighlightFill``).
    case reversed(ink: Color, field: Color)

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
    ///
    /// Where the accent or the page has no RGB the pair cannot be mixed, and the row
    /// reverses the palette's pair instead of holding a colour nobody can check
    /// (``Palette/emphasisFill(over:)``).
    ///
    /// Where the view does not appear active (``EnvironmentValues/appearsActive`` —
    /// the terminal window has lost focus), the row is still the cursor, and says so,
    /// still: it takes the tint a selected row shows while its control does not hold
    /// the keys. The focus is parked, not gone. The rule is
    /// `Palette.highlightedRowFill(appearsActive:)`'s, shared with a menu's and a
    /// drop-down's highlighted row.
    @MainActor
    static func focusedSelection(in context: RenderContext, palette: any Palette) -> Self {
        breathing(
            palette.highlightedRowFill(appearsActive: context.environment.appearsActive),
            in: context)
    }

    /// The highlight a row merely UNDER the cursor shows — the cursor row of a focused
    /// list or table, on a row the selection does not include: the focus wash,
    /// breathing (``Palette/focusWashPulse()``), or a reversal where that wash cannot
    /// be measured.
    ///
    /// It breathes for the reason the selected cursor row does: motion says the keys
    /// go here, now, and a list that has them says so wherever its cursor is. Where the
    /// view does not appear active it holds still at the bottom of that breath, the
    /// plain wash, the look it has always had — `Palette.focusWashEmphasis(appearsActive:)`
    /// is the rule, and says why a translucent wash is held spent over the page.
    ///
    /// Under ``View/rowSelectionIndicator(_:)`` `.hidden` too, where no ● says whether
    /// the cursor row is selected. Motion is what says where the keys go, so it cannot
    /// also be what says "selected": this row used to hold the plain wash still there,
    /// which made the one list on the page that had been told not to mark its
    /// selection the one whose cursor did not move. The focus indicator always visibly
    /// breathes, selected or not; which of the two a cursor row is, the breaths say
    /// themselves — a selected cursor row's peaks clearly brighter than an unselected
    /// one's (``Palette/accentFillPulse(over:)``).
    ///
    /// Here rather than at the two call sites for the reason ``focusedSelection(in:palette:)``
    /// is: the twins ask one question in one place.
    @MainActor
    static func focused(in context: RenderContext, palette: any Palette) -> Self {
        breathing(
            palette.focusWashEmphasis(appearsActive: context.environment.appearsActive),
            in: context)
    }

    /// `highlight` as a cursor row draws it: a breath on the shared focus-emphasis
    /// cycle, and anything else still.
    @MainActor
    private static func breathing(_ highlight: HighlightFill, in context: RenderContext) -> Self {
        guard case .pulse(let dim, let bright) = highlight else { return still(highlight) }
        return .pulsing(context.environment.selectionEmphasis.cycle(true), dim: dim, bright: bright)
    }

    /// The fill of a highlight that only ever TINTS — a selected row that is not the
    /// cursor, an alternating row — and nothing where that tint cannot be measured.
    ///
    /// Such a row repeats what the ● beside it and the cursor row already say. Reversed
    /// it would read as a second cursor, so where its tint has no RGB it is left
    /// unfilled — which is what a `Table` has always drawn for a selected row it does
    /// not have the cursor on.
    static func tint(_ highlight: HighlightFill) -> Self {
        guard case .fill(let color) = highlight else { return .none }
        return .fixed(color)
    }

    /// `highlight` as a background that does not animate.
    ///
    /// A breath is not one: a site that can show one asks ``breathing(_:in:)``, and
    /// here the bright end stands in, which is the colour such a cycle holds anyway
    /// wherever it cannot be measured (§79).
    private static func still(_ highlight: HighlightFill) -> Self {
        switch highlight {
        case .fill(let color): return .fixed(color)
        case .pulse(_, let bright): return .fixed(bright)
        case .reversed(let ink, let field): return .reversed(ink: ink, field: field)
        }
    }

    /// The colour to draw with in the frame being rendered now, or `nil` where the row
    /// fills with no colour of its own — no background at all, and a reversal, which
    /// paints with the pair already in force.
    @MainActor
    var colorNow: Color? {
        switch self {
        case .none, .reversed: return nil
        case .fixed(let color): return color
        case .pulsing(let cycle, let dim, let bright):
            return cycle.colorNow(dim: dim, bright: bright)
        }
    }

    /// `line` — a row's finished line, already padded to its width — drawn over this
    /// background as the frame being rendered now shows it.
    ///
    /// A fill is left in force at the end of the line, as
    /// ``String/withPersistentBackground(_:)`` leaves it; a reversal closes itself with
    /// a reset. Both re-state themselves after every reset inside the line, because a
    /// row is a reset per styled run followed by plain padding. For the reversal that is
    /// the whole point: the 7 exchanges the colours IN FORCE, so without the palette's
    /// ink and field restated beside it the padding would fill with the terminal's own
    /// foreground (`ANSIRenderer.applyPersistentReverse(_:ink:field:)`).
    ///
    /// Opaque spellings, as every row paint uses: a translucent fill's alpha is claimed
    /// (``claimableFill``) and resolved against what is behind the row, and the emitter
    /// is never handed a colour that still states one.
    @MainActor
    func painting(_ line: String) -> String {
        guard case .reversed(let ink, let field) = self else {
            return line.withPersistentBackground(claimableFill?.opaqueSpelling ?? colorNow)
        }
        return ANSIRenderer.applyPersistentReverse(
            line, ink: ink.opaqueSpelling, field: field.opaqueSpelling)
    }

    /// A row's still lines, from a renderer that draws them over a colour.
    ///
    /// ``painting(_:)`` for a caller whose lines are BUILT with their background rather
    /// than painted after the fact — a `List` row draws its badge and its gutter into
    /// them. A reversal renders them over no colour and reverses each; every other
    /// background hands the renderer the colour of the frame being rendered now.
    ///
    /// - Parameter render: Draws the row's lines over the colour it is given.
    @MainActor
    func stillLines(_ render: (Color?) -> [String]) -> [String] {
        guard case .reversed = self else {
            return render(claimableFill?.opaqueSpelling ?? colorNow)
        }
        return render(nil).map { painting($0) }
    }

    /// Every colour of the pulse, in cycle order — or `nil` when this background
    /// does not animate (a still picture earns no runs: the ordinary render
    /// already drew it, and replaying it would emit bytes per tick to no
    /// visible effect). A pulse between two equal ends is still too, whatever its
    /// cycle: `accentFillPulse` returns one where the accent or the page has no RGB.
    @MainActor
    var pulseColors: [Color]? {
        guard case .pulsing(let cycle, let dim, let bright) = self,
            cycle.isAnimating(dim: dim, bright: bright)
        else { return nil }
        return cycle.colors(dim: dim, bright: bright)
    }

    /// The frame duration and clock ``pulseColors`` step on, or `nil` exactly when
    /// that is `nil`: what a run built from those colours is built with.
    var pulseTiming: IndicatorCycleTiming? {
        guard case .pulsing(let cycle, let dim, let bright) = self,
            cycle.isAnimating(dim: dim, bright: bright)
        else { return nil }
        return cycle.timing
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
/// background, which breathes while the control has the keys; a row merely
/// under the cursor has not been chosen, and says so with no glyph, and with the
/// neutral focus wash behind it rather than the accent, breathing whether or not
/// the control draws a mark at all (``RowBackground/focused(in:palette:)``).
/// So a control with no selection at all draws no glyph on any row, which is
/// what a plain `List` looked like before this existed and still looks like now.
struct RowSelectionIndicator: Equatable {
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
        // The cursor row of a focused control — in a window that has lost the
        // terminal's focus too. Its background quietens there to the tint an
        // unfocused selection shows (``RowBackground/focusedSelection(in:palette:)``);
        // the mark staying at full strength is what still tells it from one.
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
