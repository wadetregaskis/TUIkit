//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonCapCycle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The breathing of a standard button's `▐ … ▌` end caps, as a whole cycle.
///
/// A focused button's caps are the only thing on it that moves while it sits
/// still. Re-deriving this tick's colour and re-rendering the screen to place
/// two cells — twenty times a second, forever — is what made an idle page cost
/// a third of a core (see `Documentation/Performance-profile-2026-08.md`). So
/// the cycle is built once at render time and handed to the run loop as
/// ``AnimatedCellRun``s, which advance those cells with no view involved.
///
/// Both label paths use this, and so does a menu picker's collapsed control:
/// the procedural string path and the `@ViewBuilder` path draw the same caps
/// around different middles, and the rule for what colour they take — dim to
/// the button's own face, bright to the full accent — belongs in one place.
///
/// On a face the terminal decides, the rule is different (Opacity as
/// composition, §78). When the face, or the accent it is tinted with, has no
/// RGB, the face is the page itself, and the foreground slot spells an
/// unreported page as its own default, 39: a cap drawn in that face is a
/// half-block in the terminal's foreground, by accident, and a breath from it
/// is the same accident for half its frames. So there the caps rest in the
/// palette's tertiary tier and, focused, hold the accent, still.
struct ButtonCapCycle {
    /// The shared focus-emphasis cycle behind every breathing indicator, so the
    /// caps keep step with list cursors and menu rows and honour
    /// `.selectionIndicatorStyle`.
    private let cycle: SelectionEmphasisCycle

    /// What an unfocused cap shows: the button's own face, which is also the
    /// recessive end of the breath, or the tertiary tier on a face the terminal
    /// decides. Always opaque — the face is a composite over the page, or an
    /// opaque accent kept at its own spelling (`Palette.hoveredControlFace`,
    /// §49), and the tier is spent against it — which is what lets the caps go
    /// to the emitter with no claim.
    private let resting: Color

    /// The cap colour at each point of the cycle, from the face to the full
    /// accent; on a face the terminal decides, the accent alone.
    ///
    /// The bright end is the full accent because the cap is a half-block GLYPH,
    /// not a fill behind text, so it has no readability ceiling and can go all
    /// the way — which is also the widest ramp the terminal's palette can give
    /// it. It used to stop at 45% accent, which on a 256-colour terminal
    /// quantised to two or three indices, several of them off-hue greys.
    ///
    /// Built once, here, because BOTH readers want the same breath: the colour
    /// to draw now, and the frames of the two runs. Asking for it twice would
    /// build the pulse ramp twice for a fade that is identical either way.
    private let breath: [Color]

    /// Builds the cycle for a button on `background` in `palette`.
    ///
    /// - Parameters:
    ///   - isFocused: Pass the *effective* state — a disabled button is never
    ///     indicating, however the focus system has it recorded.
    ///   - background: The face the caps belong to, resting or hovered.
    ///   - palette: Where the accent, and on a face the terminal decides the
    ///     tertiary tier, come from.
    @MainActor
    init(isFocused: Bool, background: Color, palette: any Palette, context: RenderContext) {
        let cycle = context.environment.selectionEmphasis.cycle(isFocused)
        self.cycle = cycle
        // Checked, because the caps are drawn with no claim on the strength of it.
        // A face that stopped being opaque would put its alpha into the emitter on
        // the string path and be claimed at ink 0 on the view path — loud in one
        // place and silent in the other (§49).
        assert(background.isOpaque, "a button's face must be opaque; its alpha is \(background.alpha)")
        // The accent SPENDS a translucent tint's alpha against the button's own
        // face, which is the dim end of this breath and so the ground both ends
        // have to agree about. Passed raw it carried the alpha while `background`
        // — a composite through `restingControlFace` — did not, so the two caps
        // of a focused button under `.tint(.red.opacity(0.5))` breathed between
        // one opaque colour and one translucent one, with an alpha that differed
        // per phase and no static claim that could describe it. §29.
        let accent = palette.accent.spendingAlpha(over: background)
        // Both, not only the face. An accent with no RGB tints an RGB page to the
        // page itself (a 20% share snaps to the heavier end, rule 9), so that face
        // measures, yet nothing between it and the accent does: the breath would be
        // the page for half its frames and the accent for the rest.
        guard background.resolve(with: palette).rgbComponents != nil,
            palette.accent.resolve(with: palette).rgbComponents != nil
        else {
            // Not left to the face: the tier is a colour the palette states for
            // recessive ink, where the face here is the page, which the foreground
            // slot can only spell as 39. Spent against the face like the accent,
            // so an opaque tier comes back as itself.
            resting = palette.foregroundTertiary.resolve(with: palette).spendingAlpha(over: background)
            // Still: its dim end would be the face, the accident this avoids.
            breath = [accent]
            return
        }
        resting = background
        breath = cycle.colors(dim: background, bright: accent)
    }

    /// Whether the caps actually move. A still cap needs no run — the ordinary
    /// render already drew it, and replaying it would emit bytes for no change.
    /// Nor does a breath of one colour, which is what a face the terminal decides
    /// gets.
    var isAnimating: Bool { cycle.isAnimating && breath.count > 1 }

    /// The colour to draw right now. A cap is a fill, so it recedes to the
    /// button's own face when unfocused rather than sitting at the accent.
    var colorNow: Color {
        // `breath` is the cycle's own frames coloured, so indexing it by `step`
        // is what `cycle.colorNow(dim:bright:)` would return — without building
        // a second ramp to get there.
        cycle.isFocused ? breath[cycle.step % breath.count] : resting
    }

    /// The runs for a single-row button `width` cells wide: one cap at each end.
    ///
    /// Two runs rather than one because the label between them is not part of
    /// the animation and must not be repainted on a clock.
    ///
    /// Returns nothing for a still cap, or for a button too narrow to have two
    /// distinct ends — at that width the caller's own clamping has already
    /// begun eating the chrome, and a run must never outlive the cells it
    /// describes.
    @MainActor
    func runs(width: Int) -> [AnimatedCellRun] {
        guard isAnimating, width >= 2 else { return [] }
        // ONE breath spent on both caps. Asking `cycle.run(dim:bright:…)` twice
        // would build the same pulse ramp twice — the two caps are the same
        // colours at opposite ends of the same row, never two animations.
        return [
            run(TerminalSymbols.openCap, colors: breath, offsetX: 0),
            run(TerminalSymbols.closeCap, colors: breath, offsetX: width - 1),
        ].compactMap { $0 }
    }

    @MainActor
    private func run(_ cap: Character, colors: [Color], offsetX: Int) -> AnimatedCellRun? {
        cycle.run(colors: colors, offsetX: offsetX, offsetY: 0) {
            ANSIRenderer.colorize(String(cap), foreground: $0)
        }
    }
}
