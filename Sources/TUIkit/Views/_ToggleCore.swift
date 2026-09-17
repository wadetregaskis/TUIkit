//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _ToggleCore.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Internal Core View

/// StateStorage property indices for ``_ToggleCore``. Lifted
/// out of the generic struct because Swift does not allow
/// static stored properties in generic types.
private enum ToggleStateIndex {
    // Negative: the label renders at the core's own identity, and 0...
    // belongs to a composite label's own @State. See
    // `StateStorage.StateKey`'s reserved-range table.
    static let focusID = -50
    static let isHovered = -51
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

    /// The controls this toggle governs — see ``View/toggleContent(_:)``.
    let content: (@MainActor () -> AnyView)?

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

    /// One coloured piece of an indicator: the cells, the ink, and the field
    /// beneath them when the style paints one.
    ///
    /// An indicator is two or three differently-coloured runs on one row, and
    /// before this the strings were built by concatenating `colorize` calls while
    /// nothing said where each run STARTED. That is fine for bytes and useless for
    /// an ``OpacityRegion``, which needs a column. Describing the runs once and
    /// deriving both from it is what keeps a claim on the cells it is a claim
    /// about — a `⬛︎` is two cells wide and a `[` is one, so a hardcoded offset is
    /// wrong under two `ToggleCharacterSet`s out of three.
    private struct IndicatorRun {
        let text: String
        let ink: Color
        var field: Color?
    }

    /// One run's bytes, stating its colours' opaque spelling — an SGR emitter has
    /// no backdrop to composite against, so the alpha travels as a claim instead.
    private static func painted(_ run: IndicatorRun) -> String {
        ANSIRenderer.colorize(
            run.text, foreground: run.ink.opaqueSpelling,
            background: run.field?.opaqueSpelling)
    }

    /// The claims a visited sequence of runs owes, in the columns they landed in.
    ///
    /// Takes a VISITOR rather than an array, and that is measured rather than
    /// stylistic. Describing an indicator as `[IndicatorRun]` cost `framedcolumns`
    /// — the Toggle-heavy stress scenario — **+2.2%**, because the description is
    /// rebuilt for every phase of a focus pulse, of every toggle, every frame, and
    /// each rebuild is a heap allocation. Visiting allocates nothing, and the bytes
    /// and the claims still read one description so their widths cannot drift.
    private static func claims(
        visiting runs: ((IndicatorRun) -> Void) -> Void
    ) -> [OpacityRegion] {
        // A first pass over the COLOURS alone, before any width is measured.
        // `strippedLength` is a grapheme walk, and an indicator drawn in opaque
        // colours — every indicator in nearly every app — would otherwise pay one
        // per run per frame to discover it owes nothing.
        //
        // Measured as NOTHING: `framedcolumns` (24 toggles) went +0.6% → +0.5%,
        // which is inside its own noise. Kept anyway, and this is the reason rather
        // than an imagined saving — an indicator's runs are one to three ASCII or
        // single-glyph strings, so each scan takes the byte fast path, and the count
        // scales with the number of controls on the page rather than with anything
        // this scenario varies. It is strictly less work and cannot diverge from the
        // second pass, since both walk the same visitor.
        var isTranslucent = false
        runs { isTranslucent = isTranslucent || !$0.ink.isOpaque || $0.field?.isOpaque == false }
        guard isTranslucent else { return [] }

        var column = 0
        var claims: [OpacityRegion] = []
        runs { run in
            let width = run.text.strippedLength
            defer { column += width }
            if let claim = OpacityRegion.claim(
                offsetX: column, width: width, height: 1, ink: run.ink, field: run.field)
            {
                claims.append(claim)
            }
        }
        return claims
    }

    /// The styled checkbox indicator (■/□ by default, `[x]`/`[ ]` under
    /// `.toggleCharacterSet(.ascii)`) for the toggle's current state, themed for
    /// focus / disabled, and floored against the hover face when it has one.
    private func styledToggleIndicator(
        isOnValue: Bool, isDisabled: Bool, isFocused: Bool, isHovered: Bool,
        context: RenderContext
    ) -> (text: String, animation: AnimatedCellRun?, claims: [OpacityRegion]) {
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

        // One function DESCRIBES the indicator at a given bracket colour; the bytes
        // and the claims are both derived from it, so the animation's frames are
        // the same cells the render draws and a claim is on the cells it names.
        func runs(_ bracketColor: Color, _ visit: (IndicatorRun) -> Void) {
            guard !style.openBracket.isEmpty else {
                // Self-contained glyph (unicode squares): its *shape* shows on/off, so
                // its colour is free to show state — accent when checked, plus the
                // focus / hover / disabled tints the brackets would otherwise carry.
                let markColor =
                    (isOnValue && !isDisabled && !isFocused)
                    ? (isHovered ? palette.hoveredForeground(palette.accent) : palette.accent)
                    : bracketColor
                visit(IndicatorRun(text: mark, ink: markColor))
                return
            }
            // Two-tone bracketed (ASCII): the brackets show focus while the
            // inner mark shows on/off (accent when checked, dimmed when
            // disabled; the OFF mark is a space, so its colour is moot).
            visit(IndicatorRun(text: style.openBracket, ink: bracketColor))
            visit(
                IndicatorRun(
                    text: mark,
                    ink: indicatorMarkColor(
                        isOnValue: isOnValue, isDisabled: isDisabled, isHovered: isHovered,
                        context: context)))
            visit(IndicatorRun(text: style.closeBracket, ink: bracketColor))
        }
        func draw(_ bracketColor: Color) -> String {
            var painted = ""
            runs(bracketColor) { painted += Self.painted($0) }
            return painted
        }
        let animation = brackets.run(draw: draw)
        // Claimed while it pulses too: the only colour that moves is the brackets',
        // between two spent ends, so the claim taken now is every frame's (§57).
        return (
            draw(brackets.now), animation,
            brackets.claims { colour in Self.claims(visiting: { runs(colour, $0) }) })
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
        // Both ends from `accentPulse()` — see §21. A `dim` from there beside a
        // bright of `palette.accent` had the two disagreeing about a translucent
        // accent, the dim end spending its alpha and the bright end carrying it.
        let pulse = palette.accentPulse()
        return IndicatorCycle(
            isFocused: isFocused && !isDisabled,
            dim: pulse.dim,
            bright: pulse.bright,
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

        /// The claims this indicator owes: the drawn frame's, which every frame of its
        /// run shares. The only colour that moves is this cycle's, and both of its ends
        /// spend their alpha (`accentPulse` for the brackets, `SwitchTrackBreath` for a
        /// coloured track), so a moving cell owes nothing in any frame
        /// and a still one — the mark, the knob — owes the same in all. Asserted,
        /// because a breath whose ends disagree is silent otherwise (§44).
        @MainActor
        func claims(at claimsAt: (Color) -> [OpacityRegion]) -> [OpacityRegion] {
            if cycle.isAnimating {
                // Every frame's claims, built for the assertion — as the scrollbar's and
                // the scroll indicator's are.
                assertFramesOweOneClaim(
                    cycle.colors(dim: dim, bright: bright).map(claimsAt), "a toggle's indicator")
            }
            return claimsAt(now)
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
    /// - **off**: the palette's tertiary tone, separated from the page and the accent;
    /// - **disabled**: the off track faded halfway toward the page.
    ///
    /// The off track is `SwitchTrackBreath.offTrack(in:)`: a palette rung, so it
    /// follows the theme, moved until it stands off both the page the knob is drawn
    /// in and the accent the same track turns when on. Disabled is that track faded
    /// toward the page, so it is always quieter than off and the two never look
    /// alike. The knob is the background colour so it contrasts the track on light
    /// and dark terminals alike.
    private func styledSwitchIndicator(
        isOnValue: Bool, isDisabled: Bool, isFocused: Bool, isHovered: Bool,
        context: RenderContext
    ) -> (text: String, animation: AnimatedCellRun?, claims: [OpacityRegion]) {
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
            let knobColour = indicatorMarkColor(
                isOnValue: isOnValue, isDisabled: isDisabled, isHovered: isHovered,
                context: context)
            let knob = IndicatorRun(text: SwitchIndicatorGlyphs.asciiKnob, ink: knobColour)
            // The blank half of the track is a space in the knob's own colour: no
            // ink lands on it, so a claim over it changes nothing, and describing it
            // as a run is what keeps the closing bracket's COLUMN right.
            let gap = IndicatorRun(text: " ", ink: knobColour)
            func runs(_ bracketColor: Color, _ visit: (IndicatorRun) -> Void) {
                visit(IndicatorRun(text: style.openBracket, ink: bracketColor))
                visit(isOnValue ? gap : knob)
                visit(isOnValue ? knob : gap)
                visit(IndicatorRun(text: style.closeBracket, ink: bracketColor))
            }
            func draw(_ bracketColor: Color) -> String {
                var painted = ""
                runs(bracketColor) { painted += Self.painted($0) }
                return painted
            }
            let animation = brackets.run(draw: draw)
            // Claimed while it pulses, as the checkbox is: only the brackets move.
            return (
                draw(brackets.now), animation,
                brackets.claims { colour in Self.claims(visiting: { runs(colour, $0) }) })
        }

        let knob = SwitchIndicatorGlyphs.knob(for: style)

        var trackColor: Color
        let knobColor: Color
        if isDisabled {
            // The off track faded halfway toward the page background — reads as
            // greyed-out / inactive on dark AND light palettes (a fade toward
            // black turned the disabled track *more* prominent than "off" on
            // light backgrounds), while staying distinct from the off track.
            trackColor = SwitchTrackBreath.offTrack(in: palette).opacity(
                ViewConstants.disabledForeground, over: palette.background)
            knobColor = palette.background
        } else if isOnValue {
            trackColor = palette.accent
            knobColor = palette.background
        } else {
            // Off: the palette's tertiary tone, separated from the accent (and the
            // page), so a switch that's off never reads as a dimmer "on".
            trackColor = SwitchTrackBreath.offTrack(in: palette)
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
        // accent for on, the off track lifted toward the foreground for off —
        // so the breathing never misreads as a state change, and the knob's
        // half-block margin keeps it visible at the dim end of the pulse.
        // Both ends spend their alpha over the page — see `SwitchTrackBreath`.
        let ends = SwitchTrackBreath.ends(track: trackColor, isOn: isOnValue, palette: palette)
        let track = IndicatorCycle(
            isFocused: isFocused && !isDisabled,
            dim: ends.dim,
            bright: ends.bright,
            resting: trackColor,
            context: context)

        // Off: knob then a blank cell; on: a blank cell then knob.
        let cells = isOnValue ? " " + knob : knob + " "
        func runs(_ background: Color, _ visit: (IndicatorRun) -> Void) {
            visit(IndicatorRun(text: cells, ink: knobColor, field: background))
        }
        func draw(_ background: Color) -> String {
            var painted = ""
            runs(background) { painted += Self.painted($0) }
            return painted
        }
        let animation = track.run(draw: draw)
        // Claimed while it breathes, as the bracketed indicators are: both of the
        // track's ends spend, so the claim taken now is every frame's (§58).
        return (
            draw(track.now), animation,
            track.claims { colour in Self.claims(visiting: { runs(colour, $0) }) })
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
    ) -> (buffer: FrameBuffer, clickWidth: Int, clickHeight: Int, indent: Int) {
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
        // The indicator opens the first row, so its claims need no shifting either.
        // Every indicator claims while it pulses too: its claims hold for every frame
        // (`IndicatorCycle.claims(at:)`).
        buffer.opacityRegions += styledIndicator.claims
        return (
            buffer, composed.titleWidth, composed.titleRows,
            Self.labelIndent(forIndicator: styledIndicator.text))
    }

    /// The column the label starts in: the indicator's own width plus the space
    /// after it.
    ///
    /// One function, because three things line up on it — a multi-view label's
    /// subtitle, the controls `toggleContent(_:)` carries, and nothing else may
    /// guess it. The indicator is a `ToggleCharacterSet` resolved against the
    /// terminal at render time, so its width is `■` = 1, `⬛︎` = 2, `[x]` = 3,
    /// and a hardcoded indent is wrong on two terminals out of three.
    static func labelIndent(forIndicator indicator: String) -> Int {
        FrameBuffer(lines: [indicator]).width + 1
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
            subtitleContext.environment.foregroundStyle = .color(palette.foregroundSecondary)
        }
        let indent = Self.labelIndent(forIndicator: indicator)
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
        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. Space still
        // flips it.
        let isFocused = context.indicatesFocus(
            FocusRegistration.isFocused(context: context, focusID: persistedFocusID))
        FocusRegistration.publishActivationLabel(
            LocalizationService.shared.string(for: LocalizationKey.StatusBar.toggle),
            context: context, isFocused: isFocused)
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
        /// The column ``View/toggleContent(_:)``'s controls start in.
        let contentIndent: Int
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
                labelContext.environment.foregroundStyle = .color(
                    palette.foregroundTertiary.opacity(
                        ViewConstants.disabledForeground, over: palette.background))
            } else if isHovered {
                // The whole row answers the pointer, not just the indicator: the
                // whole row is what the click hits. Whatever colour is in force
                // is what gets lifted — the app's own included, since the lift
                // keeps its hue and a colour nobody lifts is a colour that never
                // answers. Same rule as a plain `Button`'s label.
                let base =
                    labelContext.environment.foregroundStyle?.representative
                    ?? labelContext.environment.styleCascade
                        .resolve(for: [.all, .text, .control(.toggle)]).foreground
                    ?? palette.foreground
                labelContext.environment.foregroundStyle = .color(
                    palette.hoveredForeground(base))
            }

            let built = builtInStyleBuffer(
                isSwitch: toggleStyle is SwitchToggleStyle, isOnValue: isOnValue, isDisabled: isDisabled, isFocused: isFocused,
                isHovered: isHovered, labelContext: labelContext, palette: palette,
                context: context)
            buffer = built.buffer
            clickWidth = built.clickWidth
            clickHeight = built.clickHeight
            contentIndent = built.indent
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
            // A custom style draws its own indicator — there is nothing here to
            // measure, so content under it is not indented under one.
            contentIndent = 0
        }

        // What the toggle governs, under it and indented to its label. Drawn
        // whether the toggle is on or off — so the rows below do not move as it
        // is flipped — but live only while it is on, which is also what keeps
        // it out of the focus ring when it does not apply. Its own identity, a
        // step off the core's, because indices 0... at the core's identity
        // belong to a composite LABEL's `@State`.
        if let content {
            let governed = content()
                .padding(.leading, contentIndent)
                .disabled(isDisabled || !isOnValue)
            buffer.appendVertically(
                TUIkitView.renderToBuffer(
                    governed,
                    context: context.withChildIdentity(erasedType: AnyView.self, index: 0)))
        }

        registerPointer(
            on: &buffer, focusID: persistedFocusID, hoverBox: hoverBox,
            clickWidth: clickWidth, clickHeight: clickHeight, isDisabled: isDisabled,
            context: context)

        return buffer
    }

    /// Hit-test region: a left-button release anywhere on the toggle row flips
    /// its value, mirroring how Space / Enter activate it. The same region
    /// drives the hover state machine — .entered / .exited (synthesised by the
    /// dispatcher) flip the hover StateBox.
    ///
    /// The region covers the indicator-and-title row ONLY. Neither a
    /// multi-view label's subtitle nor the controls ``View/toggleContent(_:)``
    /// carries is a click target: clicking a slider under a toggle must move
    /// the slider, not flip the switch out from under it.
    private func registerPointer(
        on buffer: inout FrameBuffer, focusID persistedFocusID: String,
        hoverBox: StateBox<Bool>, clickWidth: Int, clickHeight: Int, isDisabled: Bool,
        context: RenderContext
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        mouseDispatcher.requestFeature(.motion)
        let focusManager = context.environment.focusManager
        let captureFocusID = persistedFocusID
        let toggleBinding = isOn
        let handlerID = mouseDispatcher.register(in: context, hoverBox: hoverBox) { event in
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
}
