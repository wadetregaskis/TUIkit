//  🖥️ TUIKit — Terminal UI Kit for Swift
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
struct _NavigationCrumbButtonStyle: ButtonStyle {
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

        let resting: Color =
            configuration.isEnabled
            ? palette.foregroundSecondary
            : palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        let bright = palette.accent

        func drawn(_ color: Color) -> String {
            var styled = style
            styled.foregroundColor = color
            return ANSIRenderer.render(label, with: styled)
        }

        guard isFocused else {
            return FrameBuffer(
                lines: [drawn(hovered ? palette.hoveredForeground(resting) : resting)])
        }

        let cycle = context.environment.selectionEmphasis.cycle(true)
        var buffer = FrameBuffer(lines: [drawn(cycle.colorNow(dim: resting, bright: bright))])
        // A still cycle (`.selectionIndicatorStyle(.none)`) is already drawn —
        // at `bright`, which is how focus still reads with the animation off.
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells += [
            cycle.run(dim: resting, bright: bright, offsetX: 0, offsetY: 0, draw: drawn)
        ].compactMap { $0 }
        return buffer
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
