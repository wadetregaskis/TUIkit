//  🖥️ TUIKit — Terminal UI Kit for Swift
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
        _MenuItemRow(configuration: configuration)
    }
}

// MARK: - Row

/// One menu row. A separate view because `ButtonStyle.makeBody` composes views
/// and has no render context: the palette and the pulse phase have to come from
/// the environment (the same shape as the gradient editor's `_StopChipStyle`).
private struct _MenuItemRow: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.palette) private var palette

    /// The shared focus-emphasis clock — the same one the `Picker` drop-down,
    /// `List` rows and every other focused control resolve through, so a menu
    /// row breathes in step with them and honours `.selectionIndicatorStyle`.
    /// Reading it while focused is also volatile, which keeps the row out of any
    /// render memo so the highlight animates instead of freezing on frame one.
    @Environment(\.selectionEmphasis) private var emphasis

    /// The width the highlight bar should span, injected by the menu once it
    /// knows it. See ``EnvironmentValues/menuRowWidth``.
    @Environment(\.menuRowWidth) private var menuRowWidth
    @Environment(\.menuRowInset) private var menuRowInset

    var body: some View {
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
        // Inside the background, so the highlight covers the breathing room
        // rather than leaving gutters the eye reads as part of the bar and the
        // pointer cannot hit. An INLINE menu leaves this 0 and takes its
        // margin from the column's own padding, which is outside the row.
        .padding(.horizontal, menuRowInset)
        .background(background)
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
    /// where it has to share the label's readable-against-accent colour.
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
    private var foreground: Color {
        if !configuration.isEnabled {
            return palette.foreground.opacity(ViewConstants.disabledForeground, over: palette.background)
        }
        if configuration.role == .destructive { return palette.error }
        // On the highlight bar, pick whichever of the palette's text colours
        // actually reads against it.
        return configuration.isFocused ? palette.readableText(on: highlight) : palette.foreground
    }

    /// The row's background: the pulsing accent bar under the keyboard cursor, a
    /// quieter tint under the pointer, nothing otherwise.
    private var background: Color {
        if configuration.isFocused { return highlight }
        if configuration.isHovered {
            return palette.accent.opacity(ViewConstants.hoverBackground, over: palette.background)
        }
        return palette.background
    }

    /// The focused bar, between the same two endpoints the `Picker` drop-down
    /// uses — and now on the same clock as well. It used to read `pulsePhase`
    /// directly, which is a different timer: 2.0 s per cycle against the
    /// selection clock's 0.8 s, so a menu row visibly lagged every other
    /// highlight on screen, and `.selectionIndicatorStyle(.none/.blink)` did
    /// not reach it at all.
    private var highlight: Color {
        emphasis(configuration.isFocused).color(
            dim: palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background),
            bright: palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background))
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
