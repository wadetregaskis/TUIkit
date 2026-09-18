//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationCrumbButtonStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Crumb Style

/// Renders a ``NavigationStack`` breadcrumb as a **word in a trail** rather
/// than as a button: no focus-indicator column, no chrome — the crumb's own
/// text carries every state it has.
///
/// The built-in `.plain` style would prefix each crumb with its 2-cell pulsing
/// bullet, and in a trail that lands the bullet hard against the preceding `›`
/// (`Albums  ›●  Track`) — two marks a cell apart, one of them chrome for the
/// crumb *after* it. Reserving those cells is also what forced the trail's
/// double spacing: the separators and the current screen had to be padded to
/// match, or the row read as unevenly spaced.
///
/// So focus is the text itself breathing between ``Palette/foregroundSecondary``
/// and the accent, hover is a single lift of the resting colour, and the trail
/// spaces itself with the single blanks in ``NavigationCrumbs/lead``.
///
/// Under a translucent palette or tint, a crumb at rest claims its colour's alpha
/// over its own cells, and a focused one breathes between ends SPENT against the
/// surface it sits on, so every frame is opaque (`Opacity as composition.md`, §47).
///
/// `Equatable` for the reason given under ``ButtonStyle``: every crumb of a
/// navigation bar is styled through the environment, and the bar is on screen
/// for as long as the screen is. It holds nothing — all of a crumb's state
/// reaches `_NavigationCrumbLabel` through the configuration — so every
/// instance styles a crumb identically.
struct _NavigationCrumbButtonStyle: ButtonStyle, Equatable {
    func makeBody(configuration: Configuration) -> some View {
        _NavigationCrumbLabel(configuration: configuration)
    }
}

// MARK: - The breathing crumb

/// One crumb, drawn from a whole emphasis cycle so the run loop can breathe it
/// without a view involved (see ``AnimatedCellRun``): a navigation bar is on
/// screen for as long as the screen is, and re-rendering it 20×/s to recolour
/// one word is what an animated run exists to avoid.
private struct _NavigationCrumbLabel: View, Renderable, Layoutable {
    let configuration: ButtonStyleConfiguration

    var body: Never {
        fatalError("_NavigationCrumbLabel renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(width: fitted(to: proposal.width).strippedLength, height: 1)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let label = fitted(to: context.availableWidth)
        let isFocused = configuration.isFocused && configuration.isEnabled

        var style = TextStyle()
        style.isBold = isFocused
        // Focus and hover are the same claim on the same cells, so they cannot
        // both draw: focus is the more emphatic of the two, and a pointer
        // resting on the crumb it already focused should not freeze the breath.
        let hovered = configuration.isHovered && !isFocused

        // A disabled crumb spends its alpha against the page, as every disabled
        // control does (§31.3): opaque, so it claims nothing below.
        let resting: Color =
            configuration.isEnabled
            ? palette.foregroundSecondary
            : palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)

        // Still: nothing replays these cells, so the colour CARRIES its alpha — the
        // bytes state its opaque spelling and the alpha travels as a claim over
        // exactly the crumb's cells, the pairing a plain button's label makes. The
        // pointer's lift carries too (§28.1), so it is claimed the same way.
        guard isFocused else {
            let color = hovered ? palette.hoveredForeground(resting) : resting
            var still = style
            still.foregroundColor = color
            var buffer = FrameBuffer(lines: [ANSIRenderer.render(label, with: still.opaqueColours)])
            buffer.opacityRegions.appendCoalescing(
                OpacityRegion.claim(width: label.strippedLength, height: 1, ink: color))
            return buffer
        }

        // Breathing: a run replays its frames under ONE claim per cell (§29.2), so
        // both ends SPEND their alpha against the ground the crumb is drawn on, and
        // every frame is opaque and owes nothing. They were a resting rung and the
        // accent — two slots with alphas of their own, so a faded tint alone put 255
        // at one end and 128 at the other, and a faded palette put a translucent
        // colour into every frame. `spendingAlpha` on each end, not
        // `BorderRenderer.breathEnds(from:on:)`: that breathes one colour against a
        // dimmed copy of itself, and would lose the accent. A still focus
        // (`.selectionIndicatorStyle(.none)`) is drawn spent too, as the plain
        // button's ● is (§30.3), so focus shows one bright colour either way. Held at
        // the accent where either end has no RGB, where the breath would blink (§79.1).
        let surface = context.environment.enclosingSurface
        return BreathingLabel.draw(
            label, style: style,
            ends: Color.breathEnds(
                dim: resting.spendingAlpha(over: surface), bright: palette.accent.spendingAlpha(over: surface)),
            cycle: context.environment.selectionEmphasis.cycle(true),
            indicating: true, isMeasuring: context.isMeasuring)
    }

    /// The crumb's text, clipped to what it was offered.
    ///
    /// ``NavigationCrumbs/trail(titles:fittingWidth:)`` has already decided the
    /// trail fits, so this only bites when the bar is drawn narrower than it
    /// measured — but a crumb that overruns would push the rest of the trail
    /// off the row rather than being cut itself.
    private func fitted(to width: Int?) -> String {
        guard let width, width >= 0 else { return configuration.label }
        return configuration.label.strippedLength <= width
            ? configuration.label
            : configuration.label.truncatedToWidth(width)
    }
}
