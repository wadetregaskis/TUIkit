//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DropdownOptionMenu.swift
//
//  The layer above ``DropdownMenu``'s rows: a menu of OPTIONS.
//
//  A drop-down's renderer thinks in rows and row indices. Every control that
//  opens one thinks in options and option ordinals — dividers are not things
//  you can pick, so they cannot be things you can be ON. Both the `Picker`'s
//  drop-down and a text field's suggestions menu used to bridge those two
//  worlds themselves, with the same marker column, the same `label + 4` width
//  arithmetic and the same ordinal↔row dictionaries written out twice.
//
//  This is that bridge, once.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension DropdownMenu {
    /// One entry a control offers in its drop-down.
    ///
    /// The layer above ``Row``: an option here is a bare label and a "this is
    /// the current value" flag, and the selection marker, the row padding, the
    /// width arithmetic and the ordinal↔row mapping are all worked out from
    /// that — once, in ``attach(_:to:context:onHover:onActivate:onDismiss:)``,
    /// instead of hand-rolled identically by every control with a drop-down.
    enum Entry {
        /// A pickable option. `label` is its already-rendered line (a caller
        /// renders its labels itself, because only it knows what a label IS);
        /// `isSelected` earns the ✓ marker.
        case option(label: String, isSelected: Bool)

        /// A rule between groups of options.
        case divider
    }

    /// Everything a control passes to
    /// ``attach(_:to:context:onHover:onActivate:onDismiss:)``.
    ///
    /// Both callbacks speak OPTION ORDINALS — the index of the option among
    /// the options, dividers not counted — because that is what a control's
    /// own state is indexed by. The row indices the renderer works in never
    /// escape this file.
    struct OptionMenu {
        /// The menu's entries, in display order.
        let entries: [Entry]

        /// The highlighted option's ordinal, or `nil` for none.
        let highlightedOption: Int?

        /// The caller-owned scroll state for the window.
        let scroll: ScrollAxis

        /// Whether to scroll the window to keep the highlight visible — set
        /// after keyboard navigation moved it. See
        /// ``Configuration/followHighlight``.
        let followHighlight: Bool

        /// A stable identity for the scrollbar's held-button auto-repeat.
        let autoRepeatToken: String

        /// Whether the menu answers the pointer at all. A disabled control
        /// should never have an open menu in the first place; this is the belt
        /// to that pair of braces.
        var isEnabled = true
    }

    /// The interior width (between the borders) a menu of these entries wants.
    ///
    /// Label + the marker column + a space + one column of padding on each
    /// side, plus one more when the scrollbar takes the rightmost interior
    /// column, so the option text does not run flush against the bar. Capped by
    /// the screen: a drop-down is an overlay and may grow WIDER than its
    /// control to fit its options, anchored at the control's left edge — the
    /// overlay compositor nudges it left only when the screen's right edge
    /// forces it.
    ///
    /// Exposed because a `Picker`'s collapsed control is drawn to the same
    /// width as the menu it opens.
    static func innerWidth(for entries: [Entry], context: RenderContext) -> Int {
        let maxLabelWidth =
            entries.compactMap { entry -> Int? in
                guard case .option(let label, _) = entry else { return nil }
                return label.strippedLength
            }.max() ?? 0
        let wantsBar = wantsScrollbar(rowCount: entries.count, context: context)
        let desired = maxLabelWidth + 4 + (wantsBar ? 1 : 0)
        let cap = max(context.availableWidth, context.environment.terminalWidth)
        return max(6, min(desired, max(6, cap - 2)))
    }

    /// Renders `menu` as the open drop-down and attaches it to `buffer` as an
    /// overlay one row beneath the control.
    ///
    /// The in-flow control stays whatever height it was, so opening a menu
    /// never disturbs the layout of sibling views and the list draws on top of
    /// whatever sits beneath it.
    ///
    /// - Parameters:
    ///   - menu: The entries, the highlight, and the scroll state.
    ///   - buffer: The control's own buffer; the overlay is appended to it.
    ///   - context: The current render context.
    ///   - onHover: Called with an option's ordinal when the cursor enters it.
    ///   - onActivate: Called with an option's ordinal when it is clicked.
    ///   - onDismiss: Called on a click OUTSIDE the menu.
    @MainActor
    static func attach(
        _ menu: OptionMenu,
        to buffer: inout FrameBuffer,
        context: RenderContext,
        onHover: @escaping (Int) -> Void,
        onActivate: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let accent = context.environment.palette.accent
        var rows: [Row] = []
        var ordinalByRow: [Int: Int] = [:]
        var rowByOrdinal: [Int] = []
        for entry in menu.entries {
            switch entry {
            case .divider:
                rows.append(.divider)
            case .option(let label, let isSelected):
                // The marker column keeps every label on one left edge whether
                // or not its row is the selected one.
                let marker =
                    isSelected
                    ? ANSIRenderer.colorize(selectedMarker, foreground: accent) : " "
                ordinalByRow[rows.count] = rowByOrdinal.count
                rowByOrdinal.append(rows.count)
                rows.append(.option(" " + marker + " " + label))
            }
        }
        let highlightedRow = menu.highlightedOption.flatMap {
            rowByOrdinal.indices.contains($0) ? rowByOrdinal[$0] : nil
        }

        var popup = popup(
            Configuration(
                rows: rows,
                highlightedRow: highlightedRow,
                innerWidth: innerWidth(for: menu.entries, context: context),
                scroll: menu.scroll,
                followHighlight: menu.followHighlight,
                autoRepeatToken: menu.autoRepeatToken),
            context: context,
            onHover: { row in ordinalByRow[row].map(onHover) },
            onActivate: { row in ordinalByRow[row].map(onActivate) },
            onDismiss: onDismiss)
        if !menu.isEnabled { popup.hitTestRegions.removeAll() }

        buffer.overlays.append(
            OverlayLayer(
                offsetX: 0, offsetY: 1, content: popup, level: .popover, anchorHeight: 1))
    }
}
