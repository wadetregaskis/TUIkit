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
