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

    /// Volatile: reading it keeps the row out of any render memo, so the
    /// highlight pulses instead of freezing on its first frame.
    @Environment(\.pulsePhase) private var pulsePhase

    /// The width the highlight bar should span, injected by the menu once it
    /// knows it. See ``EnvironmentValues/menuRowWidth``.
    @Environment(\.menuRowWidth) private var menuRowWidth

    var body: some View {
        // The bar spans the menu's interior — but ONLY once the menu has
        // measured itself. Filling with `.frame(maxWidth: .infinity)` instead
        // would make every row measure as flexible, the stack would measure at
        // whatever it was offered, and the menu would go back to spanning the
        // screen (the same trap `Divider` sprang). A fixed width measures as
        // itself, and it is absent during the sizing pass, so the rows hug
        // while the menu is being measured and fill once it is being drawn.
        row.frame(width: menuRowWidth, alignment: .leading)
            .background(background)
    }

    private var row: some View {
        label.foregroundStyle(foreground)
    }

    @ViewBuilder
    private var label: some View {
        if let labelView = configuration.labelView {
            labelView
        } else {
            Text(" \(configuration.label)")
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

    /// The focused bar, pulsing between the same two endpoints the `Picker`
    /// drop-down uses, so both menus breathe together.
    private var highlight: Color {
        Color.lerp(
            palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background),
            palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background),
            phase: pulsePhase)
    }
}

// MARK: - Environment

private struct MenuRowWidthKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The width a menu row's highlight bar should span, or `nil` while the menu
    /// is still measuring itself (rows hug then, so the measure yields the
    /// menu's natural width rather than whatever it was offered).
    ///
    /// Set by ``ContextMenuModifier`` between its measure and its render.
    var menuRowWidth: Int? {
        get { self[MenuRowWidthKey.self] }
        set { self[MenuRowWidthKey.self] = newValue }
    }
}
