//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// Where the active label rests: readable on the chip, and quiet. Black or white
    /// for the surface (`contrastingForeground`) — never a palette slot, so it has no
    /// alpha of its own, which is what decides how ``labelBright`` treats one.
    let labelDim: Color

    /// The loud end of the breath: the accent, SPENT against the chip's surface and
    /// then floored so it stays readable there (a mid-tone accent on a mid-tone
    /// surface is the case that fails).
    ///
    /// Spent because the other end cannot carry: a breath between an opaque end and
    /// a translucent one has an alpha that moves with its phase, and the run the strip
    /// leaves behind is replayed under ONE claim per cell (§29). Exact for a faded tint
    /// on an opaque surface; under a faded SURFACE an approximation, since what the cell
    /// shows is that surface composited over whatever is behind it.
    ///
    /// Spent THEN floored: the floor reads RGB, not alpha, so a floor passed before
    /// the spend is no floor after it.
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
            .spendingAlpha(over: surface)
            .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: surface)
        // Every frame is a lerp or a swap of these two, so agreeing here is agreeing
        // everywhere — and it is what the claim both strips derive from `labelNow`
        // silently depends on.
        assert(
            labelDim.alpha == labelBright.alpha,
            "a tab chip's breath ends disagree about alpha: \(labelDim.alpha) vs \(labelBright.alpha)")
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
