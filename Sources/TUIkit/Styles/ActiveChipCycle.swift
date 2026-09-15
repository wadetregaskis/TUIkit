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

    /// Where the active label rests: readable on the chip, and quiet. The palette's
    /// readable ink for the surface (`ContrastingLabel.on`), spent over it, so it is
    /// opaque even under a palette whose foreground is translucent. That is what
    /// decides how ``labelBright`` treats the accent's alpha.
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
    ///
    /// It also stands off ``labelDim`` by the chrome pulse floor, measured as drawn.
    /// Nothing else keeps the two ends apart, and an accent the cube draws like the
    /// resting label is a label that does not breathe. White's accent is white, as
    /// the black-or-white resting label on its dark chip was; a phosphor palette's
    /// accent is a lighter foreground. This end moves, not the resting one,
    /// because the resting end is what an unfocused strip shows, and it is floored
    /// against the chip again afterwards.
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
        var bright = palette.accent.resolve(with: palette)
            .spendingAlpha(over: surface)
            .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: surface)
        // The loud end moves, never the resting one: that is what an unfocused strip
        // shows. Re-floored against the chip after, because standing off the resting
        // label can walk it toward the surface. Both floors carry alpha, so the two
        // ends still agree about it.
        if ChromeTrack.renderedRatio(bright, restingLabel) < ViewConstants.chromePulseFloor {
            bright = bright
                .ensuringRenderedContrast(atLeast: ViewConstants.chromePulseFloor, against: restingLabel)
                .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: surface)
        }
        labelBright = bright
        // Every frame is a lerp or a swap of these two, so agreeing here is agreeing
        // everywhere — and it is what the claim both strips derive from `labelNow`
        // silently depends on.
        assert(
            labelDim.alpha == labelBright.alpha,
            "a tab chip's breath ends disagree about alpha: \(labelDim.alpha) vs \(labelBright.alpha)")
    }

    /// The two ends the focused label breathes between: ``labelDim`` and
    /// ``labelBright``, or the bright end twice where either has no RGB
    /// (`Color.breathEnds(dim:bright:)`), where the breath would blink between them.
    /// Kept apart from `labelDim`, which is also where an unfocused label rests.
    private var breath: (dim: Color, bright: Color) {
        Color.breathEnds(dim: labelDim, bright: labelBright)
    }

    /// Whether the active chip is breathing — the strip holds the focus, the
    /// style animates, and the two ends differ. A hover must not fight that.
    var isBreathing: Bool { cycle.isFocused && cycle.isAnimating(dim: breath.dim, bright: breath.bright) }

    /// The active label's colour right now — breathing while the strip holds
    /// the focus, resting otherwise.
    ///
    /// The breath is in the TEXT rather than in the fill: a pulsing background
    /// behind a whole tab is a large area of moving colour, which reads as the
    /// tab flashing rather than as "the keyboard is here", and it drags the
    /// label's contrast up and down with it.
    @MainActor
    var labelNow: Color {
        guard cycle.isFocused else { return labelDim }
        let ends = breath
        return cycle.colorNow(dim: ends.dim, bright: ends.bright)
    }

    /// The chip's run, drawn by `draw` at each label colour of the cycle — nil
    /// when the chip is not breathing.
    @MainActor
    func run(offsetX: Int, offsetY: Int, draw: (Color) -> String) -> AnimatedCellRun? {
        let ends = breath
        return cycle.run(
            dim: ends.dim, bright: ends.bright, offsetX: offsetX, offsetY: offsetY, draw: draw)
    }
}
