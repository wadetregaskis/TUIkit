//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ActiveChipCycle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The active tab chip's background, as a whole cycle. When the strip is
/// focused it breathes toward the accent so the active tab is easy to find
/// on a busy screen; otherwise it's the quiet shared surface.
///
/// A cycle rather than "this tick's colour" because that is what lets the
/// strip hand those cells to the run loop as an ``AnimatedCellRun``. Asking
/// for the live phase instead is a volatile read: it keeps the timer running
/// and re-renders the whole page, several times a second, to recolour one
/// chip. Building the cycle reads no clock at all.
struct ActiveChipCycle {
    let cycle: SelectionEmphasisCycle

    /// The quiet shared surface — where an unfocused chip sits, and the
    /// recessive end of the breath.
    let surface: Color

    /// The loud end: the accent, at the weight a *fill* behind text can
    /// carry without hurting the label's contrast.
    let accentTint: Color

    @MainActor
    init(surface: Color, palette: any Palette, isFocused: Bool, context: RenderContext) {
        cycle = context.environment.selectionEmphasis.cycle(isFocused)
        self.surface = surface
        accentTint = palette.accent.opacity(
            ViewConstants.focusedChipBackground, over: surface)
    }

    /// The background to fill the active chip with right now. A fill
    /// recedes to its own surface when unfocused (a still cycle would
    /// otherwise sit at the accent).
    @MainActor
    var now: Color {
        cycle.isFocused ? cycle.colorNow(dim: surface, bright: accentTint) : surface
    }

    /// The chip's run, drawn by `draw` at each colour of the cycle — nil
    /// when the chip is not breathing.
    @MainActor
    func run(offsetX: Int, offsetY: Int, draw: (Color) -> String) -> AnimatedCellRun? {
        cycle.run(
            dim: surface, bright: accentTint, offsetX: offsetX, offsetY: offsetY, draw: draw)
    }
}
