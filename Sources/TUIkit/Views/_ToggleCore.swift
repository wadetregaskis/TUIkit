//  TUIKit - Terminal UI Kit for Swift
//  _ToggleCore.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Internal Core View

/// StateStorage property indices for ``_ToggleCore``. Lifted
/// out of the generic struct because Swift does not allow
/// static stored properties in generic types.
private enum ToggleStateIndex {
    static let focusID = 0
    static let isHovered = 1
}

/// The switch style's knob glyphs, selected by the ambient ``ToggleCharacterSet``'s
/// glyph repertoire (lifted out of the generic core for testability).
enum SwitchIndicatorGlyphs {
    /// Under ``ToggleCharacterSet/emoji``, the knob is the emoji-repertoire large
    /// square in text presentation — ONE glyph spanning two cells, which
    /// Terminal.app draws seamlessly where it shows visible seams between
    /// adjacent FULL BLOCK cells. Every other style gets ▐▌ (right + left
    /// half blocks): a one-cell-wide knob centred across its two cells, with
    /// half a cell of TRACK showing on either side. The visible track margin
    /// is what makes the knob read at all — the knob is drawn in the page
    /// background colour, so an edge-to-edge ██ knob melts into the page
    /// beside the switch and the whole control collapses to a bare colour
    /// chip (found evaluating iTerm2, where `automatic` falls back to this
    /// repertoire; the emoji square gets the same effect for free from its
    /// glyph's intrinsic inset). Both knobs are two cells, so the 3-cell
    /// track geometry never changes; the half blocks are plain Block
    /// Elements — SGR-tintable, no variation selector to mis-measure
    /// (issue #9).
    static func knob(for style: ToggleCharacterSet) -> String {
        style == .emoji ? "\u{2B1B}\u{FE0E}" : "\u{2590}\u{258C}"  // ⬛︎ : ▐▌
    }

    /// The sliding knob of the bracketed (ASCII) switch: `[o ]` / `[ o]`.
    /// A plain letter, so the style stays honest for terminals/fonts where
    /// the block glyphs are the reason `.ascii` was chosen.
    static let asciiKnob = "o"
}

/// Internal view that handles the actual rendering of Toggle.
struct _ToggleCore<Label: View>: View, Renderable, Layoutable {
    let isOn: Binding<Bool>
    let label: Label
    let focusID: String?
    let isDisabled: Bool

    var body: Never {
        fatalError("_ToggleCore renders via Renderable")
    }

    /// Size from one render (the label is flattened into the `<mark> label` row, so
    /// its width can't be derived structurally), with flexibility taken from the
    /// label: the toggle fills its width iff its label does. The single-render
    /// fallback would size it the same, but always reports fixed — this adds the
    /// structural label probe so a flexible label still makes the toggle flexible.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        let labelFlexible = measureChild(label, proposal: proposal, context: context).isWidthFlexible
        return ViewSize(width: size.width, height: size.height, isWidthFlexible: labelFlexible)
    }

    private typealias StateIndex = ToggleStateIndex

    /// The styled checkbox indicator (■/□ by default, `[x]`/`[ ]` under
    /// `.toggleCharacterSet(.ascii)`) for the toggle's current state, themed for
    /// focus / disabled, and floored against the hover face when it has one.
    private func styledToggleIndicator(
        isOnValue: Bool, isDisabled: Bool, isFocused: Bool, isHovered: Bool,
        context: RenderContext
    ) -> (text: String, animation: AnimatedCellRun?) {
        let palette = context.environment.palette
        let brackets = bracketCycle(
            isDisabled: isDisabled, isFocused: isFocused, isHovered: isHovered, context: context)

        // The checkbox glyphs come from the configurable ``ToggleCharacterSet`` (■/□
        // by default, `[x]`/`[ ]` under `.toggleCharacterSet(.ascii)`).
        // `effectiveToggleCharacterSet`, NOT `toggleCharacterSet`: `.automatic` is a marker
        // that must be resolved against this frame's terminal here, at the point
        // of drawing — that is what lets it follow a tmux client change.
        let style = context.environment.effectiveToggleCharacterSet
        let mark = isOnValue ? style.onMark : style.offMark

        // One function draws the indicator at a given bracket colour, so the
        // animation's frames are the same cells the render draws.
        func draw(_ bracketColor: Color) -> String {
            if style.openBracket.isEmpty {
                // Self-contained glyph (unicode squares): its *shape* shows on/off, so
                // its colour is free to show state — accent when checked, plus the
                // focus / hover / disabled tints the brackets would otherwise carry.
                let markColor =
                    (isOnValue && !isDisabled && !isFocused)
                    ? (isHovered ? palette.hoveredForeground(palette.accent) : palette.accent)
                    : bracketColor
                return ANSIRenderer.colorize(mark, foreground: markColor)
            }
            // Two-tone bracketed (ASCII): the brackets show focus while the
            // inner mark shows on/off (accent when checked, dimmed when
            // disabled; the OFF mark is a space, so its colour is moot).
            return ANSIRenderer.colorize(style.openBracket, foreground: bracketColor)
                + ANSIRenderer.colorize(
                    mark,
                    foreground: indicatorMarkColor(
                        isOnValue: isOnValue, isDisabled: isDisabled, isHovered: isHovered,
                        context: context))
                + ANSIRenderer.colorize(style.closeBracket, foreground: bracketColor)
        }
        return (draw(brackets.now), brackets.run(draw: draw))
    }

    /// Bracket color for the two-tone bracketed indicators (checkbox `[x]` and
    /// switch `[o ]`): pulsing accent when focused, the normal foreground when
    /// simply unfocused, and dimmed only when actually disabled.
    /// (An unfocused-but-enabled control must stay readable — dimming it
    /// to the disabled style made the brackets almost invisible against
    /// the terminal background.)
    ///
    /// Hover LIFTS the resting colour (``Palette/hoveredForeground(_:)``)
    /// rather than tinting it. It once swapped the brackets to
    /// ``Palette/hoveredControlFace`` — a *fill* colour used as a foreground —
    /// so the pointer made the indicator fade toward the page, which reads as
    /// "disabled"; and it briefly painted the row's face instead, which a
    /// toggle has no business doing, since it draws over its parent's
    /// background rather than owning one.
    private func bracketCycle(
        isDisabled: Bool, isFocused: Bool, isHovered: Bool, context: RenderContext
    ) -> IndicatorCycle {
        let palette = context.environment.palette
        let resting: Color
        if isDisabled {
            resting = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        } else if isHovered {
            resting = palette.hoveredForeground(palette.foreground)
        } else {
            resting = palette.foreground
        }
        return IndicatorCycle(
            isFocused: isFocused && !isDisabled,
            dim: palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background),
            bright: palette.accent,
            resting: resting,
            context: context)
    }

    /// One animated colour of an indicator, taken as a whole cycle.
    ///
    /// A cycle rather than "this tick's colour" because that is what lets the
    /// toggle hand those cells to the run loop as an ``AnimatedCellRun``. Asking
    /// for the live phase instead is a volatile read: it keeps the clock running
    /// and re-renders the whole page, several times a second, to recolour two
    /// cells. Building the cycle reads no clock at all.
    private struct IndicatorCycle {
        let cycle: SelectionEmphasisCycle

        /// What the indicator shows when it is NOT focused — disabled, hovered,
        /// or simply at rest. Held separately because a still cycle sits at
        /// `bright`: right for a selection mark, wrong for chrome that recedes.
        let resting: Color

        let dim: Color
        let bright: Color

        @MainActor
        init(isFocused: Bool, dim: Color, bright: Color, resting: Color, context: RenderContext) {
            cycle = context.environment.selectionEmphasis.cycle(isFocused)
            self.dim = dim
            self.bright = bright
            self.resting = resting
        }

        /// The colour to draw right now.
        @MainActor
        var now: Color { cycle.isFocused ? cycle.colorNow(dim: dim, bright: bright) : resting }

        /// The indicator's run — it opens the toggle's row, so its offset is the
        /// buffer's origin. Nil when the indicator is not breathing.
        @MainActor
        func run(draw: (Color) -> String) -> AnimatedCellRun? {
            cycle.run(dim: dim, bright: bright, offsetX: 0, offsetY: 0, draw: draw)
        }
    }

    /// Mark color for the two-tone bracketed indicators: accent when on, plain
    /// foreground when off, dimmed when disabled — the state channel the
    /// brackets (focus channel) don't carry.
    private func indicatorMarkColor(
        isOnValue: Bool, isDisabled: Bool, isHovered: Bool, context: RenderContext
    ) -> Color {
        let palette = context.environment.palette
        if isDisabled {
            return palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        }
        let base = isOnValue ? palette.accent : palette.foreground
        return isHovered ? palette.hoveredForeground(base) : base
    }

    /// A switch track: a two-cell knob (██, or ⬛︎ under the `.emoji` checkbox
    /// style) on the side the switch points to — left for off, right for on —
    /// over a coloured track so it reads as a two-position switch rather than
    /// a checkbox, mirroring a macOS switch.
    ///
    /// The track colour carries the state, distinctly in all three states:
    /// - **on**: the accent (highlight) colour, like macOS's blue;
    /// - **off**: a solid neutral grey;
    /// - **disabled**: a *dimmed* version of the off grey, with a dimmed knob.
    ///
    /// The off grey is a fixed neutral (`.brightBlack`), not a palette shade, so it
    /// reads as grey under every theme — including accent-tinted ones whose neutral
    /// foregrounds are themselves tinted. Disabled is that grey dimmed via `opacity`
    /// (which darkens toward black), so it is always darker than the off grey and
    /// the two never look alike. The knob is the background colour so it contrasts
    /// the track on light and dark terminals alike (dimmed to match when disabled).
    private func styledSwitchIndicator(
        isOnValue: Bool, isDisabled: Bool, isFocused: Bool, isHovered: Bool,
        context: RenderContext
    ) -> (text: String, animation: AnimatedCellRun?) {
        let palette = context.environment.palette
        // The knob follows the checkbox style's glyph repertoire (see
        // ``SwitchIndicatorGlyphs/knob(for:)``): the seamless two-cell emoji
        // square under `.emoji`, two half blocks otherwise — and under a
        // bracketed style (`.ascii`), a bracketed track with a sliding `o`.
        // Resolved, not raw: the comparisons below are against concrete styles,
        // which an unresolved `.automatic` marker could never equal.
        let style = context.environment.effectiveToggleCharacterSet

        if !style.openBracket.isEmpty {
            // Bracketed (ASCII) switch: `[o ]` off, `[ o]` on — the knob slides
            // like the coloured-track switch, inside the same bracket chrome as
            // the `[x]` checkbox. Two-tone like the checkbox: brackets carry
            // focus / disabled, the knob carries state (accent when on,
            // foreground when off). No background colours at all, keeping the
            // style honest for terminals/fonts where the block glyphs are the
            // reason `.ascii` was chosen.
            let brackets = bracketCycle(
                isDisabled: isDisabled, isFocused: isFocused, isHovered: isHovered,
                context: context)
            let knob = ANSIRenderer.colorize(
                SwitchIndicatorGlyphs.asciiKnob,
                foreground: indicatorMarkColor(
                    isOnValue: isOnValue, isDisabled: isDisabled, isHovered: isHovered,
                    context: context))
            let track = isOnValue ? " " + knob : knob + " "
            func draw(_ bracketColor: Color) -> String {
                ANSIRenderer.colorize(style.openBracket, foreground: bracketColor)
                    + track
                    + ANSIRenderer.colorize(style.closeBracket, foreground: bracketColor)
            }
            return (draw(brackets.now), brackets.run(draw: draw))
        }

        let knob = SwitchIndicatorGlyphs.knob(for: style)

        var trackColor: Color
        let knobColor: Color
        if isDisabled {
            // The off grey faded halfway toward the page background — reads as
            // greyed-out / inactive on dark AND light palettes (a fade toward
            // black turned the disabled track *more* prominent than "off" on
            // light backgrounds), while staying distinct from the solid grey.
            trackColor = Color.brightBlack.opacity(
                ViewConstants.disabledForeground, over: palette.background)
            knobColor = palette.background
        } else if isOnValue {
            trackColor = palette.accent
            knobColor = palette.background
        } else {
            // Off: a neutral dark grey like macOS — independent of the accent, so a
            // switch that's off never reads as a dimmer "on".
            trackColor = .brightBlack
            knobColor = palette.background
        }
        // The track IS this style's foreground — it is the coloured thing the
        // eye reads — so the pointer lifts it, exactly as it lifts the brackets
        // of the styles that have them.
        if isHovered {
            trackColor = palette.hoveredForeground(trackColor)
        }

        // Focused: the TRACK breathes — the coloured-track styles have no
        // bracket chrome to pulse, so the switch's own background carries the
        // focus animation (same SelectionIndicator convention as the
        // bracketed styles). The endpoints stay within the state's own hue —
        // accent for on, neutral grey lifted toward the foreground for off —
        // so the breathing never misreads as a state change, and the knob's
        // half-block margin keeps it visible at the dim end of the pulse.
        let track = IndicatorCycle(
            isFocused: isFocused && !isDisabled,
            dim: trackColor.opacity(ViewConstants.focusPulseMin, over: palette.background),
            bright: isOnValue
                ? palette.accent
                : Color.lerp(.brightBlack, palette.foreground, phase: 0.45),
            resting: trackColor,
            context: context)

        // Off: knob then a blank cell; on: a blank cell then knob.
        let cells = isOnValue ? " " + knob : knob + " "
        func draw(_ background: Color) -> String {
            ANSIRenderer.colorize(cells, foreground: knobColor, background: background)
        }
        return (draw(track.now), track.run(draw: draw))
    }

    /// The buffer for one of the built-in toggle styles: the indicator, the
    /// label composed beside it, and the indicator's animation run.
    ///
    /// The switch style renders a two-position track (knob left = off, right =
    /// on) on a distinct background, so it reads as a switch rather than a
    /// checkbox; the others use the checkbox glyph.
    private func builtInStyleBuffer(
        isSwitch: Bool, isOnValue: Bool, isDisabled: Bool, isFocused: Bool, isHovered: Bool,
        labelContext: RenderContext, palette: any Palette, context: RenderContext
    ) -> (buffer: FrameBuffer, clickWidth: Int, clickHeight: Int) {
        let styledIndicator =
            isSwitch
            ? styledSwitchIndicator(
                isOnValue: isOnValue, isDisabled: isDisabled,
                isFocused: isFocused, isHovered: isHovered, context: context)
            : styledToggleIndicator(
                isOnValue: isOnValue, isDisabled: isDisabled,
                isFocused: isFocused, isHovered: isHovered, context: context)

        let composed = composeLabelBuffer(
            indicator: styledIndicator.text, labelContext: labelContext,
            isDisabled: isDisabled, palette: palette)
        var buffer = composed.buffer
        // The indicator opens the toggle's first row, so its run needs no
        // shifting. Handing it to the run loop is what lets the focus indicator
        // breathe without re-rendering the page around it.
        if !context.isMeasuring, let animation = styledIndicator.animation {
            buffer.animatedCells = [animation]
        }
        return (buffer, composed.titleWidth, composed.titleRows)
    }

    /// Composes a built-in toggle's buffer from its indicator and label.
    ///
    /// A single-view label is flattened onto the indicator line, as before. A
    /// label closure holding two or more views is the SwiftUI "title +
    /// explanatory text" form: the first view becomes the clickable title on the
    /// indicator line, and the rest become an explanatory subtitle on the line(s)
    /// below — indented to the title column and drawn in the secondary colour, the
    /// macOS checkbox-with-help-text convention. The subtitle is not a click
    /// target.
    ///
    /// - Returns: the composed buffer, plus the width and row count of the
    ///   clickable title (the indicator line) for the hit-test region.
    private func composeLabelBuffer(
        indicator: String, labelContext: RenderContext, isDisabled: Bool, palette: any Palette
    ) -> (buffer: FrameBuffer, titleWidth: Int, titleRows: Int) {
        // `.labelsHidden()` leaves the indicator alone — the box IS the
        // control — and takes the separating space with the words, so the
        // toggle is one glyph wide rather than a glyph and a gap. Every part
        // goes, subtitle included: an explanatory line under a label that is
        // not there explains nothing.
        guard !labelContext.environment.controlLabelsAreHidden else {
            let buffer = FrameBuffer(lines: [indicator])
            return (buffer, buffer.width, buffer.height)
        }
        let parts = resolveChildViews(from: label, context: labelContext)

        // Single-view label: flatten the whole label next to the indicator.
        guard parts.count >= 2 else {
            let labelText = TUIkit.renderToBuffer(label, context: labelContext)
                .lines.joined(separator: " ")
            let buffer = FrameBuffer(lines: [indicator + " " + labelText])
            return (buffer, buffer.width, buffer.height)
        }

        // Title = the first label view, flattened onto the indicator line.
        let titleText = renderLabelPart(parts[0], maxWidth: nil, context: labelContext)
            .lines.joined(separator: " ")
        let titleLine = indicator + " " + titleText
        let titleWidth = FrameBuffer(lines: [titleLine]).width

        // Subtitle = the remaining label views: secondary, and indented to the
        // title column (past "<indicator> ") so it left-aligns to the label, not
        // the box. A disabled toggle keeps the inherited dimmed colour.
        var subtitleContext = labelContext
        subtitleContext.environment.controlKind = nil
        if !isDisabled {
            subtitleContext.environment.foregroundStyle = palette.foregroundSecondary
        }
        let indicatorWidth = FrameBuffer(lines: [indicator]).width
        let indent = indicatorWidth + 1
        let indentString = String(repeating: " ", count: indent)
        // Wrap the subtitle to the width left after the indent. The enclosing
        // stack hands the toggle the same `availableWidth` in both the measure
        // pass (it proposes `.unspecified`, which falls back to `availableWidth`)
        // and the render pass (it renders children at `availableWidth`), so
        // wrapping to this width is layout-consistent — exactly as a wrapping
        // `Text` is.
        let subtitleWidth = max(1, labelContext.availableWidth - indent)

        var lines = [titleLine]
        for index in 1..<parts.count {
            for line in renderLabelPart(parts[index], maxWidth: subtitleWidth, context: subtitleContext).lines {
                lines.append(indentString + line)
            }
        }
        return (FrameBuffer(lines: lines), titleWidth, 1)
    }

    /// Renders a single label part, wrapped to `maxWidth` when given (the
    /// subtitle), or at its natural size when `maxWidth` is nil (the title).
    private func renderLabelPart(_ part: ChildView, maxWidth: Int?, context: RenderContext) -> FrameBuffer {
        let size = part.measure(proposal: ProposedSize(width: maxWidth, height: nil), context: context)
        return part.render(width: maxWidth ?? size.width, height: size.height, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.stateStorage!

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "toggle",
            propertyIndex: StateIndex.focusID
        )
        let binding = isOn
        let handler = ActionHandler(
            focusID: persistedFocusID,
            action: { binding.wrappedValue.toggle() },
            canBeFocused: !isDisabled
        )
        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        FocusRegistration.publishActivationLabel("toggle", context: context, isFocused: isFocused)
        let isOnValue = isOn.wrappedValue

        // Hover state — flipped by the dispatcher on .entered / .exited events
        // synthesised from motion. Not suppressed by focus: the two say
        // different things (where the keyboard is, where the mouse is) and the
        // toggle answers them in different ink — the brackets pulse for focus,
        // the label and the mark lift for the pointer. Suppressed when
        // disabled, which has nothing to answer with.
        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && hoverBox.value

        // The built-in styles render procedurally (focus glow + `ToggleCharacterSet`
        // glyphs); a custom `ToggleStyle` renders through its `makeBody`. Either
        // way the interaction wiring below (focus, mouse) is the core's job.
        var buffer: FrameBuffer
        // Extent of the *clickable* part of the toggle (the indicator + title
        // row). An explanatory subtitle below the title is not a click target,
        // so the hit region must not extend over it.
        let clickWidth: Int
        let clickHeight: Int
        let toggleStyle = context.environment.toggleStyle
        if toggleStyle is DefaultToggleStyle || toggleStyle is CheckboxToggleStyle
            || toggleStyle is SwitchToggleStyle {
            // Render the label, keeping its colour styling. Stripping the ANSI
            // here left the label with no foreground colour at all, so it drew
            // in the terminal's default — unreadable against the themed
            // background. A disabled toggle dims its label; otherwise the label
            // inherits the normal foreground colour.
            var labelContext = context
            // Tag the label subtree so its Text resolves `.control(.toggle)` style
            // entries (e.g. `.toggleTextStyle { … }`).
            labelContext.environment.controlKind = .toggle
            if isDisabled {
                labelContext.environment.foregroundStyle =
                    palette.foregroundTertiary.opacity(
                        ViewConstants.disabledForeground, over: palette.background)
            } else if isHovered {
                // The whole row answers the pointer, not just the indicator: the
                // whole row is what the click hits. Whatever colour is in force
                // is what gets lifted — the app's own included, since the lift
                // keeps its hue and a colour nobody lifts is a colour that never
                // answers. Same rule as a plain `Button`'s label.
                let base =
                    labelContext.environment.foregroundStyle
                    ?? labelContext.environment.styleCascade
                        .resolve(for: [.all, .text, .control(.toggle)]).foreground
                    ?? palette.foreground
                labelContext.environment.foregroundStyle =
                    palette.hoveredForeground(base)
            }

            let built = builtInStyleBuffer(
                isSwitch: toggleStyle is SwitchToggleStyle, isOnValue: isOnValue, isDisabled: isDisabled, isFocused: isFocused,
                isHovered: isHovered, labelContext: labelContext, palette: palette,
                context: context)
            buffer = built.buffer
            clickWidth = built.clickWidth
            clickHeight = built.clickHeight
        } else {
            let configuration = ToggleStyleConfiguration(
                label: AnyView(label),
                isOn: isOn,
                isFocused: isFocused && !isDisabled,
                isHovered: isHovered,
                isEnabled: !isDisabled)
            buffer = toggleStyle.makeBuffer(configuration: configuration, context: context)
            clickWidth = buffer.width
            clickHeight = buffer.height
        }

        // Hit-test region: a left-button release anywhere on the
        // toggle row flips its value, mirroring how Space / Enter
        // activate it. The same region drives the hover state
        // machine — .entered / .exited (synthesised by the
        // dispatcher) flip the hover StateBox.
        if !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            mouseDispatcher.requestFeature(.motion)
            let focusManager = context.environment.focusManager
            let captureFocusID = persistedFocusID
            let toggleBinding = isOn
            let captureHoverBox = hoverBox
            let handlerID = mouseDispatcher.register(hoverBox: captureHoverBox) { event in
                switch event.phase {
                case .pressed where event.button == .left:
                    return true
                case .released where event.button == .left:
                    focusManager?.focus(id: captureFocusID)
                    toggleBinding.wrappedValue.toggle()
                    return true
                default:
                    return false
                }
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0,
                    offsetY: 0,
                    width: clickWidth,
                    height: clickHeight,
                    handlerID: handlerID,
                    focusID: persistedFocusID
                )
            )
        }

        return buffer
    }
}
