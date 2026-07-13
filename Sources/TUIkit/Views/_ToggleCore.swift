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

/// The switch style's knob glyphs, selected by the ambient ``CheckboxStyle``'s
/// glyph repertoire (lifted out of the generic core for testability).
enum SwitchIndicatorGlyphs {
    /// Under ``CheckboxStyle/emoji``, the knob is the emoji-repertoire large
    /// square in text presentation — ONE glyph spanning two cells, which
    /// Terminal.app draws seamlessly where it shows visible seams between
    /// adjacent FULL BLOCK cells. Every other style gets the two FULL BLOCKs:
    /// universally one cell each, SGR-tintable, and with no variation
    /// selector for a terminal to mis-measure (issue #9). Both knobs are two
    /// cells, so the 3-cell track geometry never changes.
    static func knob(for style: CheckboxStyle) -> String {
        style == .emoji ? "\u{2B1B}\u{FE0E}" : "\u{2588}\u{2588}"  // ⬛︎ : ██
    }
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
    /// `.checkboxStyle(.ascii)`) for the toggle's current state, themed for
    /// focus / hover / disabled.
    private func styledToggleIndicator(
        isOnValue: Bool, isDisabled: Bool, isFocused: Bool, isHovered: Bool, context: RenderContext
    ) -> String {
        let palette = context.environment.palette

        // Bracket color: pulsing accent when focused, the normal foreground
        // when simply unfocused, and dimmed only when actually disabled.
        // (An unfocused-but-enabled control must stay readable — dimming it
        // to the disabled style made the brackets almost invisible against
        // the terminal background.)
        let bracketColor: Color
        if isDisabled {
            bracketColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        } else if isFocused {
            let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background)
            bracketColor = SelectionIndicator.resolve(isFocused: true, context: context)
                .color(dim: dimAccent, bright: palette.accent)
        } else if isHovered {
            // Hover bumps the brackets to a partial accent tint
            // so the affordance reads without the focused pulse.
            bracketColor = palette.accent.opacity(ViewConstants.hoverBackground, over: palette.background)
        } else {
            bracketColor = palette.foreground
        }

        // The checkbox glyphs come from the configurable ``CheckboxStyle`` (■/□
        // by default, `[x]`/`[ ]` under `.checkboxStyle(.ascii)`).
        let style = context.environment.checkboxStyle
        let mark = isOnValue ? style.onMark : style.offMark

        if style.openBracket.isEmpty {
            // Self-contained glyph (unicode squares): its *shape* shows on/off, so its
            // colour is free to show state — accent when checked, plus the
            // focus / hover / disabled tints the brackets would otherwise carry.
            let markColor = (isOnValue && !isDisabled && !isFocused) ? palette.accent : bracketColor
            return ANSIRenderer.colorize(mark, foreground: markColor)
        }
        // Two-tone bracketed (ASCII): the brackets show focus while the
        // inner mark shows on/off (accent when checked, dimmed when
        // disabled; the OFF mark is a space, so its colour is moot).
        let contentColor: Color
        if isDisabled {
            contentColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        } else if isOnValue {
            contentColor = palette.accent
        } else {
            contentColor = palette.foreground
        }
        return ANSIRenderer.colorize(style.openBracket, foreground: bracketColor)
            + ANSIRenderer.colorize(mark, foreground: contentColor)
            + ANSIRenderer.colorize(style.closeBracket, foreground: bracketColor)
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
        isOnValue: Bool, isDisabled: Bool, context: RenderContext
    ) -> String {
        let palette = context.environment.palette
        // The knob follows the checkbox style's glyph repertoire (see
        // ``SwitchIndicatorGlyphs/knob(for:)``): the seamless two-cell emoji
        // square under `.emoji`, two FULL BLOCKs otherwise.
        let knob = SwitchIndicatorGlyphs.knob(for: context.environment.checkboxStyle)

        let trackColor: Color
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

        // Off: knob then a blank cell; on: a blank cell then knob.
        let cells = isOnValue ? " " + knob : knob + " "
        return ANSIRenderer.colorize(cells, foreground: knobColor, background: trackColor)
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
        let stateStorage = context.environment.stateStorage!

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
        let isOnValue = isOn.wrappedValue

        // Hover state — flipped by the dispatcher on .entered /
        // .exited events synthesised from motion. Suppressed
        // when focused (focus is the more emphatic affordance)
        // and when disabled.
        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && !isFocused && hoverBox.value

        // The built-in styles render procedurally (focus glow + `CheckboxStyle`
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
            }

            // The switch style renders a two-position track (knob left = off,
            // right = on) on a distinct background, so it reads as a switch rather
            // than a checkbox; the others use the checkbox glyph.
            let styledIndicator =
                toggleStyle is SwitchToggleStyle
                ? styledSwitchIndicator(
                    isOnValue: isOnValue, isDisabled: isDisabled, context: context)
                : styledToggleIndicator(
                    isOnValue: isOnValue, isDisabled: isDisabled,
                    isFocused: isFocused, isHovered: isHovered, context: context)

            let composed = composeLabelBuffer(
                indicator: styledIndicator, labelContext: labelContext,
                isDisabled: isDisabled, palette: palette)
            buffer = composed.buffer
            clickWidth = composed.titleWidth
            clickHeight = composed.titleRows
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
            let handlerID = mouseDispatcher.register { event in
                switch event.phase {
                case .entered:
                    captureHoverBox.value = true
                    return true
                case .exited:
                    captureHoverBox.value = false
                    return true
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
