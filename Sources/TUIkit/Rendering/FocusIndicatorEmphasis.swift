//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusIndicatorEmphasis.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The breathing ● an active focus section shows in its border — every frame of
/// it, not just the one on screen now.
///
/// A section decides *whether* the indicator is showing; the border that draws
/// the box is the only thing that knows *where* it lands. Passing a plain
/// `Color` between them was enough to draw it and not enough to animate it: the
/// colour had to be resolved from the live clock as the section rendered, which
/// marks the whole frame as having consulted that clock, so every tick of the
/// pulse re-rendered the entire page to repaint one cell. Carrying the cycle
/// instead lets the border hand the run loop an ``AnimatedCellRun`` and let it
/// advance the ● alone.
///
/// The two endpoints are decided here, once, because both producers — a
/// ``FocusSectionModifier`` and a ``NavigationSplitView`` column — want the same
/// ●, and a second copy of the arithmetic is a second thing to drift.
struct FocusIndicatorEmphasis {
    /// Every frame of the pulse.
    let cycle: SelectionEmphasisCycle

    /// The recessive end — the accent dimmed towards the page, never the
    /// border's own colour (see ``ViewConstants/focusBorderDim``).
    let dim: Color

    /// The visible end.
    let bright: Color

    /// The indicator for a section that is active right now, or `nil` when it
    /// is not — which is also the value that means "draw no ●".
    @MainActor
    static func activeSection(_ isActive: Bool, in environment: EnvironmentValues) -> Self? {
        guard isActive else { return nil }
        let accent = environment.palette.accent
        return Self(
            cycle: environment.selectionEmphasis.cycle(true),
            dim: accent.opacity(ViewConstants.focusBorderDim, over: environment.palette.background),
            bright: accent)
    }

    /// The colour to draw the ● in this frame.
    @MainActor
    var colorNow: Color { cycle.colorNow(dim: dim, bright: bright) }

    /// The run that breathes the ● at `(offsetX, offsetY)`, or `nil` when the
    /// indicator style does not animate (a still ● was already drawn, and a run
    /// would rewrite it every tick to no visible effect).
    @MainActor
    func run(offsetX: Int, offsetY: Int) -> AnimatedCellRun? {
        cycle.run(
            String(BorderRenderer.focusIndicator), dim: dim, bright: bright,
            offsetX: offsetX, offsetY: offsetY)
    }
}
