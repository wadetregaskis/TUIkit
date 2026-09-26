//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuItemButtonStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Menu Item Style

/// Renders a `Button` as a **menu row** rather than as a button.
///
/// A `.contextMenu`'s items are `Button`s — that is SwiftUI's API and TUIkit
/// matches it — but they must not *look* like buttons: a pop-up menu's rows are
/// a plain label with a full-width highlight bar under the cursor, exactly like
/// the `Picker` drop-down's rows. (The drop-down itself can't be reused: it is a
/// procedural renderer over plain strings, not views, so nothing there takes a
/// `Button`.) This style is the view-composed counterpart, sharing the
/// drop-down's palette and pulse endpoints so the two menus read as one idiom.
///
/// Applied by ``ContextMenuModifier`` to the whole item stack, so every item
/// picks it up without the caller styling anything.
///
/// `Equatable` because it is injected into the environment around every menu
/// column, inline and pop-up alike: the render cache refuses to memoize
/// anything below a value it cannot compare, so while this style could not be
/// compared, no subtree inside a menu could be stored or served however
/// comparable everything else in force was. It holds nothing, so every instance
/// styles a row identically — see ``MenuStyle``.
struct _MenuItemButtonStyle: ButtonStyle, Equatable {
    func makeBody(configuration: Configuration) -> some View {
        _MenuItemRowBar(configuration: configuration)
    }
}

// MARK: - The breathing bar

/// Draws the focused row's highlight, and hands the run loop the whole breath
/// as finished lines rather than reading the clock (see ``AnimatedCellRun``).
///
/// This is where the row's *bar* lives, not in ``_MenuItemRow`` itself, for one
/// reason: painted here it is one persistent background over the finished line,
/// so the cycle is 16 recolourings of a line that was rendered once. Painted
/// inside the row it would be part of the row's own styling, and every step
/// would mean rendering the row again.
///
/// Why it matters: 32 rows resolving the live emphasis held the Example's main
/// menu at **35.5% of a core while idle** at 604 bytes/s — the fewest bytes and
/// the most CPU of any screen, i.e. an entire view walk ~30×/s to recolour one
/// row.
private struct _MenuItemRowBar: View, Renderable, Layoutable {
    let configuration: ButtonStyleConfiguration

    var body: Never {
        fatalError("_MenuItemRowBar renders via Renderable")
    }

    /// The row without the bar — what is measured, and what each step of the
    /// cycle is painted over.
    ///
    /// The three environment values the row draws itself from are read HERE and
    /// handed over as stored properties, rather than declared as `@Environment`
    /// on the row. This view is `Renderable`, so it has the render context that
    /// a `ButtonStyle`'s body does not — and the row sits directly inside it
    /// with no modifier between, so the values are the same ones it would have
    /// resolved for itself. What it saves is the resolution: three
    /// `EnvironmentBox` allocations, a reflective walk over the row's fields
    /// that hands each back as `Any`, and three existential casts, per row, on
    /// every measure and every render.
    /// On the `menus` stress scenario `resolveEnvironmentProperties`'s inner
    /// loop was **5.9% of the frame** and `Environment.wrappedValue` another
    /// **5.0%**, and every reflecting view on that path was this row.
    private func row(in context: RenderContext) -> _MenuItemRow {
        _MenuItemRow(
            configuration: configuration,
            palette: context.environment.palette,
            menuRowWidth: context.environment.menuRowWidth,
            menuRowInset: context.environment.menuRowInset)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(row(in: context), proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let row = row(in: context)
        var buffer = TUIkit.renderToBuffer(row, context: context)
        guard configuration.isFocused else { return buffer }

        let palette = context.environment.palette
        // `emphasisFill()`, not a hand-rolled pair: this bar is a FILL that a
        // label is drawn on, and that is exactly the distinction the two pulse
        // functions carry (`accentPulse` reaches the accent, a fill's bright end
        // stops at `focusPulseMax` so the content stays readable). Spelled out here,
        // the two ends also disagreed about a translucent accent — the dim end spent
        // its alpha and the bright end was written from `palette.accent` again. See
        // `Documentation/Opacity as composition.md` §21. And where the accent or the
        // page has no RGB there is nothing between them to breathe (§75), so the bar
        // reverses the palette's own pair rather than hold a colour nobody can check
        // the label against (§88) — the same answer `RowBackground` gives a cursor row.
        // And where the window has lost the terminal's focus, the bar stays, still,
        // in the tint a `List` gives a selection it does not hold the keys for: the
        // row is still the one the keys will reach when it comes back, and hiding it
        // read as the focus having been lost. That rule is the palette's, asked by
        // every highlighted row, so a menu's row and a list's cursor row agree.
        let emphasis = palette.highlightedRowFill(appearsActive: context.environment.appearsActive)

        // Squared off first: the bar spans the row, and a short line would
        // otherwise be painted only as far as it happens to reach, leaving the
        // highlight ragged on a multi-line label.
        let width = buffer.lines.map(\.strippedLength).max() ?? 0
        let plain = buffer.lines.map { $0.padToVisibleWidth(width) }

        // Each step is self-contained — its own background in front and a reset
        // behind — because a frame the loop splices in cannot lean on an escape
        // that happens to sit earlier in the line.
        func painted(_ line: String, _ color: Color) -> String {
            ANSIRenderer.applyPersistentBackground(line, color: color) + ANSIRenderer.reset
        }

        switch emphasis {
        case .reversed(let ink, let field):
            // Steady: a reversal has no phase to advance, so the row is drawn once and
            // leaves no run — and with no run there is no clock for the loop to wake
            // for. No cycle is built either, which is work avoided rather than a rule:
            // building one is sixteen frames and a pulse ramp for a picture that cannot
            // change, and it is NOT itself a clock read (`IndicatorCycleTiming.step(on:)`
            // does not mark the frame, unlike `CursorTimer.pulsePhase(for:)`).
            // The pair is restated after every reset inside the line, because a row is a
            // reset per styled run followed by plain padding, and a bare 7 exchanges the
            // colours IN FORCE, which after a reset are the terminal's own.
            func reversed(_ line: String) -> String {
                ANSIRenderer.applyPersistentReverse(
                    line, ink: ink.opaqueSpelling, field: field.opaqueSpelling)
            }
            buffer.lines = plain.map(reversed)
            // The label's own runs sit on the bar wherever their frames leave a
            // cell bare, so their grounds take the same paint as the lines do
            // (`AnimatedCellRun.ground`) — here, and in the two cases below.
            buffer.paintRunGrounds { _, ground in reversed(ground) }
            // And the bar is behind every fade inside the label: spent against it,
            // over the lines just reversed, and nothing restates the reversal after.
            // Carried up, a label faded below one half met the reversal's field as
            // its own and lost it to the page — a hole in the bar
            // (`Opacity as composition.md` §86.1).
            buffer = buffer.resolvingOpacity(onReversal: ink.opaqueSpelling, palette: palette)
        case .fill(let color):
            buffer.lines = plain.map { painted($0, color) }
            buffer.paintRunGrounds { _, ground in painted(ground, color) }
        case .pulse(let dim, let bright):
            let cycle = context.environment.selectionEmphasis.cycle(true)
            let now = cycle.colorNow(dim: dim, bright: bright)
            buffer.lines = plain.map { painted($0, now) }
            // For a bar that holds still, whose label keeps its runs. A breathing one
            // drops them below and leaves only its own, which ARE the bar.
            buffer.paintRunGrounds { _, ground in painted(ground, now) }
            // A still cycle (`.selectionIndicatorStyle(.none)`, or a blink at rest)
            // was already drawn above; replaying it would emit bytes per tick to
            // change nothing. Nor do two equal ends breathe (an accent the page's
            // own colour, a fully transparent one), however many frames the cycle
            // has — the question the List's cursor row asks, and asked here the
            // same way: asked only of `isAnimating`, such a bar dropped the label's
            // runs and then drew none of its own, so the spinner moved by a full
            // render at every step. Measuring passes leave no runs at all.
            guard cycle.isAnimating(dim: dim, bright: bright), !context.isMeasuring else { break }
            // The bar's runs repaint the WHOLE row every tick, over the label as it
            // was drawn, so a run the label left — a spinner beside its text — is a
            // second animation claiming cells the bar's already claims, and the
            // wider one wins: the spinner held the glyph it was rendered with. So
            // the label's runs are dropped for as long as the bar breathes, and the
            // row takes over what they did, as a `List`'s breathing cursor row does:
            // what they said about alpha stays behind, after the label's own regions
            // (§69.4), and the render they would have caused at their next step is
            // asked for on their behalf.
            let dropped = buffer.animatedCells.filter(\.isAnimating)
            buffer.opacityRegions += dropped.flatMap(\.alphaLeftBehind)
            context.requestWake(
                token: "menu-row-dropped-run-\(context.identity.path)",
                forNextStepOf: dropped.map { ($0.clock, $0.frameTicks) })
            buffer.animatedCells = plain.indices.compactMap { index in
                cycle.run(dim: dim, bright: bright, offsetX: 0, offsetY: index) {
                    painted(plain[index], $0)
                }
            }
        }
        return buffer
    }
}

// MARK: - Row

/// One menu row. A separate view because `ButtonStyle.makeBody` composes views
/// and has no render context — but ``_MenuItemRowBar``, which builds this, is
/// `Renderable` and does, so the values arrive as stored properties instead of
/// being resolved here. (The gradient editor's `_StopChipStyle` is the same
/// shape and still reads the environment, because nothing between it and the
/// style has a context.)
private struct _MenuItemRow: View {
    let configuration: ButtonStyleConfiguration

    /// The palette in force where the row sits.
    ///
    /// Passed in by ``_MenuItemRowBar`` rather than declared `@Environment`
    /// here — see the note on its `row(in:)`. The doc comment above still holds
    /// for a style's *body*: this row is one level below that, inside a
    /// `Renderable` that has the context.
    let palette: any Palette

    /// The width the highlight bar should span, injected by the menu once it
    /// knows it. See ``EnvironmentValues/menuRowWidth``.
    let menuRowWidth: Int?
    let menuRowInset: Int

    @ViewBuilder
    var body: some View {
        // Inside the background, so the highlight covers the breathing room
        // rather than leaving gutters the eye reads as part of the bar and the
        // pointer cannot hit. An INLINE menu leaves this 0 and takes its
        // margin from the column's own padding, which is outside the row.
        let content = columns.padding(.horizontal, menuRowInset)
        // The focused row draws no background of its own: ``_MenuItemRowBar``
        // paints its bar over the finished line, and a background here would
        // sit *inside* that paint — the inner code wins for the cells it
        // covers — leaving the bar showing only in the gaps.
        if let background {
            content.background(background)
        } else {
            content
        }
    }

    private var columns: some View {
        // The bar spans the menu's interior — but ONLY once the menu has
        // measured itself. Filling with `.frame(maxWidth: .infinity)` instead
        // would make every row measure as flexible, the stack would measure at
        // whatever it was offered, and the menu would go back to spanning the
        // screen (the same trap `Divider` sprang). A fixed width measures as
        // itself, and it is absent during the sizing pass, so the rows hug
        // while the menu is being measured and fill once it is being drawn.
        HStack(spacing: 0) {
            row.frame(width: labelWidth, alignment: .leading)
            if !hint.isEmpty {
                // The gap before the hint is the frame's, not a leading space
                // in the string: the frame is what right-aligns the hint into
                // a column of its own, and it keeps the gap out of the string
                // the row would otherwise have to measure and draw identically.
                Text(hint)
                    .foregroundStyle(hintForeground)
                    .frame(width: hintWidth, alignment: .trailing)
            }
        }
    }

    private var row: some View {
        label.foregroundStyle(foreground)
    }

    /// The button's key equivalent, printed at the trailing edge the way a
    /// menu item's key equivalent is on every desktop platform.
    private var hint: String {
        configuration.keyboardShortcut?.displayString ?? ""
    }

    /// The label's share of the row: everything the hint doesn't take. The
    /// hints line up in a column because every row is the same total width and
    /// each pads its own label to leave room for its own hint. `nil` while the
    /// menu is still measuring, so the label hugs and the natural width comes
    /// out as label + gap + hint.
    private var labelWidth: Int? {
        guard let menuRowWidth else { return nil }
        return max(1, menuRowWidth - hintWidth - 2 * menuRowInset)
    }

    /// The hint's column, gap included. Known without ``menuRowWidth``, so the
    /// measuring pass reserves exactly what the render draws.
    private var hintWidth: Int {
        hint.isEmpty ? 0 : hint.strippedLength + 1
    }

    /// The hint is secondary information — dimmed, except on the highlight bar
    /// where it comes up to full strength alongside the label.
    private var hintForeground: Color {
        guard configuration.isEnabled, !configuration.isFocused else { return foreground }
        return palette.foregroundSecondary
    }

    /// The row's label — the string one, or the caller's `@ViewBuilder` one.
    ///
    /// No leading space of its own: the menu's border and its one cell of
    /// padding already inset every row, and a `@ViewBuilder` label would not
    /// get the extra space anyway, so adding it here would only make the two
    /// kinds of row disagree. (It used to be written `Text(" \(label)")`, which
    /// drew nothing at all until `Text` stopped swallowing leading spaces.)
    @ViewBuilder
    private var label: some View {
        if let labelView = configuration.labelView {
            labelView
        } else {
            Text(configuration.label)
        }
    }

    /// The row's text colour. A destructive role keeps its error tint whatever
    /// the row's state — matching SwiftUI, where the role overrides the style.
    ///
    /// The focused row keeps the ordinary foreground rather than picking a
    /// colour against the bar. Two reasons, and the first is the real one: the
    /// bar MOVES, so a colour chosen against it moves too, and text that
    /// changes colour mid-breath reads as a glitch. (It could also flip from
    /// the light end of the palette to the dark one partway through a cycle.)
    /// And the pair is already measured — `PaletteContrastAuditTests` holds
    /// `foreground` over both pulse endpoints, for every shipped palette,
    /// which is exactly what bounds ``ViewConstants/focusPulseMax``. It is
    /// what the `Picker` drop-down and `List`'s focused row do as well.
    private var foreground: Color {
        if !configuration.isEnabled {
            return palette.foreground.opacity(ViewConstants.disabledForeground, over: palette.background)
        }
        let ink = configuration.role == .destructive ? palette.error : palette.foreground
        // Under the pointer the row's wash is an accent tint, which is the page where it
        // cannot be measured, so the label lifts instead (Opacity as composition §82).
        // Not on the keyboard cursor's row, whose bar is drawn over it.
        guard configuration.isHovered, !configuration.isFocused else { return ink }
        return palette.hoveredLabel(ink)
    }

    /// The row's own background: a quiet tint under the pointer, the page
    /// colour otherwise — and *nothing* under the keyboard cursor, whose
    /// breathing bar ``_MenuItemRowBar`` paints over the finished line.
    private var background: Color? {
        if configuration.isFocused { return nil }
        guard configuration.isHovered else { return palette.background }
        // A tint of the accent over the page — and where either has no RGB there is
        // nothing between them, so every share of the blend is one end or the other
        // (Opacity as composition §75). Below half that end is the page, which says
        // nothing at all; the label's ink lifts instead (§82, `hoveredLabel` above).
        // Asked of the colours rather than left to `hoverBackground` happening to sit
        // below half: raised above it, the same blend would be a solid accent under a
        // label nobody can check for contrast.
        let wash = palette.accent.opacity(ViewConstants.hoverBackground, over: palette.background)
        guard case .fill(let tint) = palette.highlightFill(wash, tint: palette.accent) else {
            return palette.background
        }
        return tint
    }
}

// MARK: - Environment

private struct MenuRowInsetKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct MenuRowWidthKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The width a menu row's highlight bar should span, or `nil` while the menu
    /// is still measuring itself (rows hug then, so the measure yields the
    /// menu's natural width rather than whatever it was offered).
    ///
    /// Set by ``ContextMenuModifier`` between its measure and its render.
    /// How many cells of breathing room a menu row keeps INSIDE its highlight.
    ///
    /// A pop-up sets 1: its rows are placed straight into the drop-down's
    /// interior, so the margin has to be part of the row or the highlight bar
    /// runs edge to edge. An inline menu leaves it 0 — its column is padded as
    /// a whole, outside the rows.
    var menuRowInset: Int {
        get { self[MenuRowInsetKey.self] }
        set { self[MenuRowInsetKey.self] = newValue }
    }

    var menuRowWidth: Int? {
        get { self[MenuRowWidthKey.self] }
        set { self[MenuRowWidthKey.self] = newValue }
    }
}
