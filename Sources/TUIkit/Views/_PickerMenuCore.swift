//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _PickerMenuCore.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Picker Menu Constants

/// Layout and glyph constants for the menu-style picker.
///
/// Held at file scope rather than nested in the generic ``_PickerMenuCore``
/// because Swift does not allow static stored properties inside a generic
/// type.
private enum PickerMenuConstants {
    /// `StateStorage` property index for the persisted handler.
    static let handlerStateIndex = 0

    /// `StateStorage` property index for the persisted focus identifier.
    static let focusIDStateIndex = 1

    /// The caret shown when the drop-down is closed (▾).
    static let closedCaret = "\u{25BE}"

    /// The caret shown when the drop-down is open (▴).
    static let openCaret = "\u{25B4}"

    /// The marker drawn beside the currently selected option (✓).
    static let selectedMarker = "\u{2713}"
}

// MARK: - Picker Menu Core

/// The rendering core for a ``Picker`` using the menu style.
///
/// Draws a collapsed single-line control showing the current selection and
/// a caret. When activated the bordered drop-down list of options is emitted
/// as a free-floating ``OverlayLayer`` anchored directly below the control,
/// so opening the picker never disturbs the layout of sibling views — the
/// terminal equivalent of a pop-up menu.
///
/// - Important: Framework infrastructure. ``Picker`` returns this from its
///   `body` for the menu style; it is never used directly.
struct _PickerMenuCore<SelectionValue: Hashable>: View, Renderable {
    /// The resolved options.
    let entries: [_PickerEntry<SelectionValue>]

    /// A binding to the selected value.
    let selection: Binding<SelectionValue>

    /// The explicit focus identifier, or `nil` to auto-generate one.
    let focusID: String?

    /// Whether the picker is disabled.
    let isDisabled: Bool

    var body: Never {
        fatalError("_PickerMenuCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "picker",
            propertyIndex: PickerMenuConstants.focusIDStateIndex
        )

        // Type-erase the selection so the (non-generic) handler can drive it.
        let erasedSelection = Binding<AnyHashable>(
            get: { AnyHashable(selection.wrappedValue) },
            set: { newValue in
                if let typed = newValue.base as? SelectionValue {
                    selection.wrappedValue = typed
                }
            }
        )
        let itemValues = entries.map { AnyHashable($0.tag) }

        // Fetch or create the persistent handler (holds open/closed state).
        let handlerKey = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: PickerMenuConstants.handlerStateIndex
        )
        let handlerBox: StateBox<_PickerMenuHandler> = stateStorage.storage(
            for: handlerKey,
            default: _PickerMenuHandler(
                focusID: persistedFocusID,
                selection: erasedSelection,
                itemValues: itemValues,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value
        handler.selection = erasedSelection
        handler.itemValues = itemValues
        handler.canBeFocused = !isDisabled
        if isDisabled {
            handler.isOpen = false
        }

        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        // Render every option's label once; reuse for sizing and drawing.
        let renderedLabels: [String] = entries.map { entry in
            entry.label.renderToBuffer(context: context).lines.first ?? ""
        }
        let maxLabelWidth = renderedLabels.map(\.strippedLength).max() ?? 0

        // Inner width = label + selection marker + a space + 1 char padding
        // on each side. Clamp to the space actually available.
        let desiredInner = maxLabelWidth + 4
        let innerWidth = max(6, min(desiredInner, max(6, context.availableWidth - 2)))

        let isOpen = handler.isOpen && !entries.isEmpty
        let collapsed = collapsedLine(
            innerWidth: innerWidth,
            renderedLabels: renderedLabels,
            isOpen: isOpen,
            isFocused: isFocused,
            context: context,
            palette: palette
        )

        guard isOpen else {
            return FrameBuffer(lines: [collapsed])
        }

        handler.highlightedIndex = min(
            max(0, handler.highlightedIndex),
            entries.count - 1
        )
        let popup = popupLines(
            innerWidth: innerWidth,
            renderedLabels: renderedLabels,
            highlightedIndex: handler.highlightedIndex,
            context: context,
            palette: palette
        )

        // The drop-down floats as an overlay layer anchored one row below the
        // collapsed control. The in-flow control stays a single line, so
        // opening the picker never disturbs the layout of sibling views and
        // the list draws on top of whatever sits beneath it.
        var buffer = FrameBuffer(lines: [collapsed])
        buffer.overlays = [
            OverlayLayer(
                offsetX: 0,
                offsetY: 1,
                content: FrameBuffer(lines: popup),
                level: .popover,
                anchorHeight: 1
            )
        ]
        return buffer
    }

    // MARK: Collapsed Control

    /// Draws the single-line collapsed control: `▐ Selection      ▾ ▌`.
    private func collapsedLine(
        innerWidth: Int,
        renderedLabels: [String],
        isOpen: Bool,
        isFocused: Bool,
        context: RenderContext,
        palette: any Palette
    ) -> String {
        // The text of the currently selected option, if any.
        let selectedText: String
        if let index = entries.firstIndex(where: { $0.tag == selection.wrappedValue }) {
            selectedText = renderedLabels[index].stripped
        } else {
            selectedText = ""
        }

        let caret = isOpen ? PickerMenuConstants.openCaret : PickerMenuConstants.closedCaret

        // Content layout: leading space + text + caret + trailing space.
        let textWidth = max(0, innerWidth - 3)
        let fittedText = fit(selectedText, to: textWidth)
        let content = " " + fittedText + caret + " "

        let buttonBg = palette.accent.opacity(ViewConstants.focusBorderDim)

        let labelFg: Color
        if isDisabled {
            labelFg = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
        } else if isFocused {
            labelFg = palette.accent
        } else {
            labelFg = palette.foregroundSecondary
        }

        let capColor: Color
        if isDisabled {
            capColor = buttonBg
        } else if isFocused {
            capColor = Color.lerp(
                buttonBg,
                palette.accent.opacity(ViewConstants.buttonCapPulseBright),
                phase: context.environment.pulsePhase
            )
        } else {
            capColor = buttonBg
        }

        let openCap = ANSIRenderer.colorize(
            String(TerminalSymbols.openCap),
            foreground: capColor
        )
        let closeCap = ANSIRenderer.colorize(
            String(TerminalSymbols.closeCap),
            foreground: capColor
        )
        let styledContent = ANSIRenderer.colorize(
            content,
            foreground: labelFg,
            background: buttonBg,
            bold: isFocused && !isDisabled
        )
        return openCap + styledContent + closeCap
    }

    // MARK: Drop-down Popup

    /// Draws the bordered drop-down list shown below the collapsed control.
    private func popupLines(
        innerWidth: Int,
        renderedLabels: [String],
        highlightedIndex: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        let borderStyle = context.environment.appearance.borderStyle
        let borderColor = palette.accent
        let highlightBg = palette.accent.opacity(ViewConstants.selectedBackground)

        var lines: [String] = [
            BorderRenderer.standardTopBorder(
                style: borderStyle,
                innerWidth: innerWidth,
                color: borderColor
            )
        ]

        for (index, entry) in entries.enumerated() {
            let isSelected = entry.tag == selection.wrappedValue
            let isHighlighted = index == highlightedIndex

            let marker =
                isSelected
                ? ANSIRenderer.colorize(
                    PickerMenuConstants.selectedMarker,
                    foreground: palette.accent
                )
                : " "
            let rowContent = " " + marker + " " + renderedLabels[index]

            lines.append(
                BorderRenderer.standardContentLine(
                    content: rowContent,
                    innerWidth: innerWidth,
                    style: borderStyle,
                    color: borderColor,
                    backgroundColor: isHighlighted ? highlightBg : nil
                )
            )
        }

        lines.append(
            BorderRenderer.standardBottomBorder(
                style: borderStyle,
                innerWidth: innerWidth,
                color: borderColor
            )
        )
        return lines
    }

    /// Truncates or pads a plain string to exactly `width` visible columns.
    private func fit(_ text: String, to width: Int) -> String {
        text.strippedLength > width
            ? text.ansiAwarePrefix(visibleCount: width)
            : text.padToVisibleWidth(width)
    }
}

// MARK: - Picker Menu Handler

/// The focus and keyboard handler for a menu-style ``Picker``.
///
/// Persisted across renders via `StateStorage` so the open/closed state and
/// the highlighted option survive re-rendering. While closed, Enter, Space,
/// or Down opens the drop-down; while open, the arrow keys move the
/// highlight, Enter or Space commits it, and Escape closes without changing
/// the selection.
final class _PickerMenuHandler: Focusable {
    let focusID: String
    var selection: Binding<AnyHashable>
    var itemValues: [AnyHashable]
    var canBeFocused: Bool

    /// Whether the drop-down list is currently expanded.
    var isOpen: Bool = false

    /// The option index highlighted while the drop-down is open.
    var highlightedIndex: Int = 0

    init(
        focusID: String,
        selection: Binding<AnyHashable>,
        itemValues: [AnyHashable],
        canBeFocused: Bool
    ) {
        self.focusID = focusID
        self.selection = selection
        self.itemValues = itemValues
        self.canBeFocused = canBeFocused
        if let index = itemValues.firstIndex(of: selection.wrappedValue) {
            self.highlightedIndex = index
        }
    }

    func onFocusLost() {
        // Closing on focus loss keeps the drop-down from lingering over
        // unrelated content once the user tabs away.
        isOpen = false
        if let index = itemValues.firstIndex(of: selection.wrappedValue) {
            highlightedIndex = index
        }
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard !itemValues.isEmpty else { return false }
        highlightedIndex = min(max(0, highlightedIndex), itemValues.count - 1)

        if isOpen {
            switch event.key {
            case .up:
                highlightedIndex =
                    highlightedIndex > 0 ? highlightedIndex - 1 : itemValues.count - 1
                return true
            case .down:
                highlightedIndex =
                    highlightedIndex < itemValues.count - 1 ? highlightedIndex + 1 : 0
                return true
            case .enter, .space:
                selection.wrappedValue = itemValues[highlightedIndex]
                isOpen = false
                return true
            case .escape:
                isOpen = false
                return true
            case .tab:
                // Close, but let the focus system move on to the next view.
                isOpen = false
                return false
            default:
                // While open the picker is modal: swallow everything else.
                return true
            }
        } else {
            switch event.key {
            case .enter, .space, .down:
                highlightedIndex = itemValues.firstIndex(of: selection.wrappedValue) ?? 0
                isOpen = true
                return true
            default:
                // Closed: let Tab and arrows drive focus navigation.
                return false
            }
        }
    }
}
