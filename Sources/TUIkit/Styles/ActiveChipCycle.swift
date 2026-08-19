//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ActiveChipCycle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The active tab chip's LABEL colour, as a whole cycle. When the strip is
/// focused the label breathes toward the accent so the active tab is easy to
/// find on a busy screen; otherwise it rests at a quiet, readable tone. The
/// chip's fill does not move.
///
/// A cycle rather than "this tick's colour" because that is what lets the
/// strip hand those cells to the run loop as an ``AnimatedCellRun``. Asking
/// for the live phase instead is a volatile read: it keeps the timer running
/// and re-renders the whole page, several times a second, to recolour one
/// chip. Building the cycle reads no clock at all.
struct ActiveChipCycle {
    let cycle: SelectionEmphasisCycle

    /// The chip's own surface — steady, focused or not. A tab is a place, not a
    /// state, and its fill says which place; the focus says so in the label.
    let surface: Color

    /// Where the active label rests: readable on the chip, and quiet.
    let labelDim: Color

    /// The loud end of the breath: the accent, floored so it stays readable on
    /// the chip it is drawn on (a mid-tone accent on a mid-tone surface is the
    /// case that fails).
    let labelBright: Color

    /// - Parameter restingLabel: where the active label sits when the strip
    ///   does not hold the focus — the dim end of the breath.
    @MainActor
    init(
        surface: Color, restingLabel: Color, palette: any Palette, isFocused: Bool,
        context: RenderContext
    ) {
        cycle = context.environment.selectionEmphasis.cycle(isFocused)
        self.surface = surface
        labelDim = restingLabel
        labelBright = palette.accent.resolve(with: palette)
            .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: surface)
    }

    /// Whether the active chip is breathing — the strip holds the focus, and
    /// the style animates. A hover must not fight that.
    var isBreathing: Bool { cycle.isFocused && cycle.isAnimating }

    /// The active label's colour right now — breathing while the strip holds
    /// the focus, resting otherwise.
    ///
    /// The breath is in the TEXT rather than in the fill: a pulsing background
    /// behind a whole tab is a large area of moving colour, which reads as the
    /// tab flashing rather than as "the keyboard is here", and it drags the
    /// label's contrast up and down with it.
    @MainActor
    var labelNow: Color {
        cycle.isFocused ? cycle.colorNow(dim: labelDim, bright: labelBright) : labelDim
    }

    /// The chip's run, drawn by `draw` at each label colour of the cycle — nil
    /// when the chip is not breathing.
    @MainActor
    func run(offsetX: Int, offsetY: Int, draw: (Color) -> String) -> AnimatedCellRun? {
        cycle.run(
            dim: labelDim, bright: labelBright, offsetX: offsetX, offsetY: offsetY, draw: draw)
    }
}
