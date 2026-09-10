//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusIndicatorColor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension AnimatedColor {
    /// The breathing ● an ACTIVE focus section shows in its border, or `nil`
    /// when the section is not active — which is also the value that means
    /// "draw no ●".
    ///
    /// A section decides *whether* the indicator is showing; the border that
    /// draws the box is the only thing that knows *where* it lands. Passing a
    /// plain `Color` between them was enough to draw it and not enough to
    /// animate it: the colour had to be resolved from the live clock as the
    /// section rendered, which marks the whole frame as having consulted that
    /// clock, so every tick of the pulse re-rendered the entire page to repaint
    /// one cell.
    ///
    /// The two endpoints are decided here, once, because both producers — a
    /// ``FocusSectionModifier`` and a ``NavigationSplitView`` column — want the
    /// same ●, and a second copy of the arithmetic is a second thing to drift.
    @MainActor
    static func activeSection(_ isActive: Bool, in environment: EnvironmentValues) -> Self? {
        guard isActive else { return nil }
        // Over the surface the section's border is drawn on, not the page:
        // inside a tab the page blend put the trough at the tab body's own
        // luminance (Homebrew: 1.009:1), the defect the button breath had.
        //
        // Through `Color.breathEnds`, so BOTH ends spend a translucent tint's
        // alpha against that surface. The bright end used to be a bare `accent`
        // and carried it while the dim end consumed it — §29.
        let ends = environment.palette.accent.breathEnds(
            dimmedTo: ViewConstants.focusBorderDim, over: environment.enclosingSurface)
        return environment.selectionEmphasis.animatedColor(
            true, dim: ends.dim, bright: ends.bright)
    }

    /// The ● drawn in this colour — the one description of that glyph, shared
    /// by the border that draws it and the run that replays it.
    func focusIndicatorGlyph(_ colour: Color) -> String {
        String(BorderRenderer.focusIndicator).styled(foreground: colour)
    }

    /// The run that breathes the ● at `(offsetX, offsetY)`, or `nil` when the
    /// indicator style does not animate (a still ● was already drawn, and a run
    /// would rewrite it on every tick to no visible effect).
    @MainActor
    func focusIndicatorRun(offsetX: Int, offsetY: Int) -> AnimatedCellRun? {
        run(offsetX: offsetX, offsetY: offsetY) { focusIndicatorGlyph($0) }
    }
}
