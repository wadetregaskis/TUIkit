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
/// Both label paths use this: the procedural string path and the
/// `@ViewBuilder` path draw the same caps around different middles, and the
/// rule for what colour they take — dim to the button's own face, bright to the
/// full accent — belongs in one place.
struct ButtonCapCycle {
    /// The shared focus-emphasis cycle behind every breathing indicator, so the
    /// caps keep step with list cursors and menu rows and honour
    /// `.selectionIndicatorStyle`.
    private let cycle: SelectionEmphasisCycle

    /// The button's own face: what an unfocused cap shows, and the recessive
    /// end of the breath.
    private let background: Color

    /// The full accent: the loud end of the breath.
    ///
    /// The cap is a half-block GLYPH, not a fill behind text, so it has no
    /// readability ceiling and can go all the way — which is also the widest
    /// ramp the terminal's palette can give it. It used to stop at 45% accent,
    /// which on a 256-colour terminal quantised to two or three indices,
    /// several of them off-hue greys.
    private let accent: Color

    /// Builds the cycle for a button on `background` in a palette whose accent
    /// is `accent`.
    ///
    /// - Parameter isFocused: Pass the *effective* state — a disabled button is
    ///   never indicating, however the focus system has it recorded.
    @MainActor
    init(isFocused: Bool, background: Color, accent: Color, context: RenderContext) {
        cycle = context.environment.selectionEmphasis.cycle(isFocused)
        self.background = background
        self.accent = accent
    }

    /// Whether the caps actually move. A still cap needs no run — the ordinary
    /// render already drew it, and replaying it would emit bytes for no change.
    var isAnimating: Bool { cycle.isAnimating }

    /// The colour to draw right now. A cap is a fill, so it recedes to the
    /// button's own face when unfocused rather than sitting at the accent.
    @MainActor
    var colorNow: Color {
        cycle.isFocused ? cycle.colorNow(dim: background, bright: accent) : background
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
        return [
            run(TerminalSymbols.openCap, offsetX: 0),
            run(TerminalSymbols.closeCap, offsetX: width - 1),
        ].compactMap { $0 }
    }

    @MainActor
    private func run(_ cap: Character, offsetX: Int) -> AnimatedCellRun? {
        cycle.run(
            String(cap), dim: background, bright: accent, offsetX: offsetX, offsetY: 0)
    }
}
