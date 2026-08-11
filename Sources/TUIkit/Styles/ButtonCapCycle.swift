//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    /// The cap colour at each tick of a full cycle. A single entry means the
    /// caps do not animate: unfocused, disabled, or `.selectionIndicatorStyle`
    /// set to `.none`.
    let colors: [Color]

    /// Where the clock is now — the index to draw immediately.
    let step: Int

    /// Builds the cycle for a button on `background` in a palette whose accent
    /// is `accent`.
    ///
    /// - Parameter isFocused: Pass the *effective* state — a disabled button is
    ///   never indicating, however the focus system has it recorded.
    @MainActor
    init(isFocused: Bool, background: Color, accent: Color, context: RenderContext) {
        let cycle = context.environment.selectionEmphasis.cycle(isFocused)
        // The cap is a half-block GLYPH, not a fill behind text, so it has no
        // readability ceiling: it breathes all the way to the full accent,
        // which is also the widest ramp the terminal's palette can give it. It
        // used to stop at 45% accent, which on a 256-colour terminal quantised
        // to two or three indices, several of them off-hue greys.
        //
        // Through the shared clock, so the caps keep step with list cursors and
        // menu rows and honour `.selectionIndicatorStyle`.
        colors = isFocused ? cycle.colors(dim: background, bright: accent) : [background]
        step = cycle.step
    }

    /// Whether the caps actually move. A still cap needs no run — the ordinary
    /// render already drew it, and replaying it would emit bytes for no change.
    var isAnimating: Bool { colors.count > 1 }

    /// The colour to draw right now.
    var colorNow: Color { colors[step % colors.count] }

    /// The runs for a single-row button `width` cells wide: one cap at each end.
    ///
    /// Two runs rather than one because the label between them is not part of
    /// the animation and must not be repainted on a clock.
    ///
    /// Returns nothing for a still cap, or for a button too narrow to have two
    /// distinct ends — at that width the caller's own clamping has already
    /// begun eating the chrome, and a run must never outlive the cells it
    /// describes.
    func runs(width: Int) -> [AnimatedCellRun] {
        guard isAnimating, width >= 2 else { return [] }
        return [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1,
                frames: frames(TerminalSymbols.openCap), clock: .cursor),
            AnimatedCellRun(
                offsetX: width - 1, offsetY: 0, width: 1,
                frames: frames(TerminalSymbols.closeCap), clock: .cursor),
        ]
    }

    /// One finished, styled string per step — the form ``AnimatedCellRun``
    /// wants, so the loop's per-tick work is an array index.
    private func frames(_ cap: Character) -> [String] {
        colors.map { ANSIRenderer.colorize(String(cap), foreground: $0) }
    }
}
