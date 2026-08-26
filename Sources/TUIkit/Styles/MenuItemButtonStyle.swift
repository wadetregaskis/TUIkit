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
struct _MenuItemButtonStyle: ButtonStyle {
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
    private var row: _MenuItemRow {
        _MenuItemRow(configuration: configuration)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(row, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(row, context: context)
        guard configuration.isFocused else { return buffer }

        let palette = context.environment.palette
        let cycle = context.environment.selectionEmphasis.cycle(true)
        let dim = palette.accentPulse().dim
        let bright = palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background)

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

        let now = cycle.colorNow(dim: dim, bright: bright)
        buffer.lines = plain.map { painted($0, now) }

        // A still cycle (`.selectionIndicatorStyle(.none)`, or a blink at rest)
        // was already drawn above; replaying it would emit bytes per tick to
        // change nothing. Measuring passes leave no runs at all.
        guard cycle.isAnimating, !context.isMeasuring else { return buffer }
        buffer.animatedCells += plain.indices.compactMap { index in
            cycle.run(dim: dim, bright: bright, offsetX: 0, offsetY: index) {
                painted(plain[index], $0)
            }
        }
        return buffer
    }
}

// MARK: - Row

/// One menu row. A separate view because `ButtonStyle.makeBody` composes views
/// and has no render context: the palette has to come from the environment (the
/// same shape as the gradient editor's `_StopChipStyle`).
private struct _MenuItemRow: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.palette) private var palette

    /// The width the highlight bar should span, injected by the menu once it
    /// knows it. See ``EnvironmentValues/menuRowWidth``.
    @Environment(\.menuRowWidth) private var menuRowWidth
    @Environment(\.menuRowInset) private var menuRowInset

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
        if configuration.role == .destructive { return palette.error }
        return palette.foreground
    }

    /// The row's own background: a quiet tint under the pointer, the page
    /// colour otherwise — and *nothing* under the keyboard cursor, whose
    /// breathing bar ``_MenuItemRowBar`` paints over the finished line.
    private var background: Color? {
        if configuration.isFocused { return nil }
        if configuration.isHovered {
            return palette.accent.opacity(ViewConstants.hoverBackground, over: palette.background)
        }
        return palette.background
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
