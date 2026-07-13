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

    /// `StateStorage` property index for the persisted hover state.
    static let isHoveredStateIndex = 2
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
struct _PickerMenuCore<SelectionValue: Hashable>: View, Renderable, Layoutable {
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

    /// The picker's option menu sizes to its widest option (it does not fill), so
    /// a single render is its exact, fixed measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "picker",
            propertyIndex: PickerMenuConstants.focusIDStateIndex
        )
        let handler = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context
        )
        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(
            context: context, focusID: persistedFocusID)

        let hoverBox = resolveHoverBox(
            stateStorage: stateStorage, context: context)
        let isHovered = !isDisabled && !isFocused && hoverBox.value

        // Render every option's label once (dividers have none); reuse for
        // sizing and drawing. Row indices match `entries` throughout — the
        // drop-down highlight is tracked as an option ordinal on the handler
        // and mapped to a row via `optionRowIndices`. Labels render at the
        // SCREEN width, not the control's: the drop-down is an overlay that
        // may grow wider than its control, so a narrow picker must not
        // wrap/truncate its option labels.
        let labelContext = context.withAvailableWidth(
            max(context.availableWidth, context.environment.terminalWidth))
        let renderedLabels: [String?] = entries.map { entry in
            entry.label.map { $0.renderToBuffer(context: labelContext).lines.first ?? "" }
        }
        let optionRowIndices = entries.indices.filter { entries[$0].tag != nil }
        let maxLabelWidth = renderedLabels.compactMap { $0?.strippedLength }.max() ?? 0

        // Inner width = label + selection marker + a space + 1 char padding
        // on each side. When the option list overflows, the drop-down shows a
        // scrollbar in its rightmost interior column; reserve one more column so
        // there's a blank gap between the option text and the bar (rather than the
        // text running flush against it) without truncating any label. The
        // overflow test mirrors the drop-down's windowing.
        let wantsScrollbar = DropdownMenu.wantsScrollbar(
            rowCount: entries.count, context: context)
        let desiredInner = maxLabelWidth + 4 + (wantsScrollbar ? 1 : 0)
        // The drop-down is an overlay: it may grow WIDER than its control to
        // fit its options, up to the screen. It anchors at the control's left
        // edge (preferring to grow rightward); the overlay compositor nudges
        // it left only when the screen's right edge forces it.
        let widthCap = max(context.availableWidth, context.environment.terminalWidth)
        let innerWidth = max(6, min(desiredInner, max(6, widthCap - 2)))

        let isOpen = handler.isOpen && !optionRowIndices.isEmpty
        publishOpenEscapeLabel(context: context, isOpen: isOpen)

        let collapsed = collapsedLine(
            innerWidth: innerWidth,
            renderedLabels: renderedLabels,
            isOpen: isOpen,
            isFocused: isFocused,
            isHovered: isHovered,
            context: context,
            palette: palette
        )
        var buffer = FrameBuffer(lines: [collapsed])

        attachCollapsedMouseHandlers(
            to: &buffer,
            context: context,
            handler: handler,
            hoverBox: hoverBox,
            persistedFocusID: persistedFocusID,
            collapsedWidth: collapsed.strippedLength
        )

        guard isOpen else { return buffer }
        handler.highlightedIndex = min(
            max(0, handler.highlightedIndex), optionRowIndices.count - 1)
        attachOpenPopup(
            to: &buffer,
            context: context,
            handler: handler,
            persistedFocusID: persistedFocusID,
            innerWidth: innerWidth,
            renderedLabels: renderedLabels,
            optionRowIndices: optionRowIndices,
            palette: palette
        )
        return buffer
    }

    // MARK: - Render-time state resolution

    /// Type-erases the selection binding so the non-generic
    /// handler can drive it, then fetches (or creates) the
    /// persistent handler from StateStorage and syncs the
    /// per-frame bindings on it.
    private func resolveHandler(
        persistedFocusID: String,
        stateStorage: StateStorage,
        context: RenderContext
    ) -> _PickerMenuHandler {
        // Combine own + cascaded disabled (renderToBuffer's shadowing local does
        // not reach this helper).
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let erasedSelection = Binding<AnyHashable>(
            get: { AnyHashable(selection.wrappedValue) },
            set: { newValue in
                if let typed = newValue.base as? SelectionValue {
                    selection.wrappedValue = typed
                }
            }
        )
        // Options only — dividers are not navigable, so the handler's
        // highlight moves over the option ordinals.
        let itemValues = entries.compactMap { $0.tag.map { AnyHashable($0) } }

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
        if isDisabled { handler.isOpen = false }
        return handler
    }

    /// Fetches the hover StateBox.
    private func resolveHoverBox(
        stateStorage: StateStorage,
        context: RenderContext
    ) -> StateBox<Bool> {
        let key = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: PickerMenuConstants.isHoveredStateIndex
        )
        return stateStorage.storage(for: key, default: false)
    }

    /// While the drop-down is open the picker's own handler
    /// consumes ESC to close it, so any page-level ESC handler
    /// stays inactive. Posting the ESC label override here makes
    /// that discoverable in the status bar without changing
    /// which handler fires.
    private func publishOpenEscapeLabel(
        context: RenderContext, isOpen: Bool
    ) {
        guard isOpen, !context.isMeasuring else { return }
        context.environment.statusBar.escapeLabelOverride = "close drop-down menu"
    }

    // MARK: - Mouse handler wiring

    /// Registers the collapsed control's mouse handler and emits
    /// its hit-test region. A click on the collapsed control
    /// toggles the drop-down and grants focus; hover transitions
    /// drive the visual affordance.
    private func attachCollapsedMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        handler: _PickerMenuHandler,
        hoverBox: StateBox<Bool>,
        persistedFocusID: String,
        collapsedWidth: Int
    ) {
        // Combine own + cascaded disabled (renderToBuffer's shadowing local does
        // not reach this helper).
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        mouseDispatcher.requestFeature(.motion)
        let focusManager = context.environment.focusManager
        let mouseHandlerID = mouseDispatcher.register { event in
            switch event.phase {
            case .entered:
                hoverBox.value = true
                return true
            case .exited:
                hoverBox.value = false
                return true
            case .pressed where event.button == .left:
                return true
            case .released where event.button == .left:
                // Capture the open/close intent BEFORE focusing. Focusing the
                // (already-focused) picker fires its own `onFocusLost`, which
                // sets `isOpen = false`; reading `isOpen` *after* that and
                // toggling it would flip false→true and reopen a drop-down the
                // user clicked the control to close. Setting the intended state
                // explicitly after the focus call is immune to that.
                let shouldOpen = !handler.isOpen
                focusManager?.focus(id: persistedFocusID)
                handler.isOpen = shouldOpen
                if handler.isOpen {
                    handler.highlightedIndex =
                        handler.itemValues.firstIndex(
                            of: handler.selection.wrappedValue) ?? 0
                }
                return true
            default: return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: collapsedWidth,
                height: 1,
                handlerID: mouseHandlerID,
                focusID: persistedFocusID
            )
        )
    }

    /// Builds the open drop-down popup via the shared ``DropdownMenu``
    /// machinery and attaches it as an overlay layer anchored one row below
    /// the collapsed control. The in-flow control stays a single line so
    /// opening the picker never disturbs the layout of sibling views and the
    /// list draws on top of whatever sits beneath it.
    private func attachOpenPopup(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        handler: _PickerMenuHandler,
        persistedFocusID: String,
        innerWidth: Int,
        renderedLabels: [String?],
        optionRowIndices: [Int],
        palette: any Palette
    ) {
        // Combine own + cascaded disabled (renderToBuffer's shadowing local does
        // not reach this helper).
        let isDisabled = self.isDisabled || !context.environment.isEnabled

        // Row content: ` ✓ label` for the selected option, ` · label` rows
        // otherwise (the marker column keeps labels aligned); dividers pass
        // through as rules.
        let rows: [DropdownMenu.Row] = entries.indices.map { index in
            switch entries[index] {
            case .divider:
                return .divider
            case .option(let tag, _):
                let marker =
                    tag == selection.wrappedValue
                    ? ANSIRenderer.colorize(
                        DropdownMenu.selectedMarker,
                        foreground: palette.accent
                    )
                    : " "
                return .option(" " + marker + " " + (renderedLabels[index] ?? ""))
            }
        }

        // The handler's highlight is an option ordinal; the drop-down wants a
        // row index (and reports row indices back from hover/click).
        let ordinalByRow = Dictionary(
            uniqueKeysWithValues: optionRowIndices.enumerated().map { ($1, $0) })
        let highlightedRow =
            optionRowIndices.indices.contains(handler.highlightedIndex)
            ? optionRowIndices[handler.highlightedIndex] : nil

        // Follow the highlight only when keyboard navigation moved it; wheel/bar
        // scrolling (which doesn't set the flag) then moves the window freely.
        let followHighlight = handler.scrollFollowPending
        handler.scrollFollowPending = false

        let focusManager = context.environment.focusManager
        let captureSelection = selection
        let captureEntries = entries
        var popupBuffer = DropdownMenu.popup(
            DropdownMenu.Configuration(
                rows: rows,
                highlightedRow: highlightedRow,
                innerWidth: innerWidth,
                scroll: handler.menuScroll,
                followHighlight: followHighlight,
                autoRepeatToken: "picker-menu-scrollbar-\(context.identity.path)"),
            context: context,
            onHover: { row in
                guard let ordinal = ordinalByRow[row] else { return }
                handler.highlightedIndex = ordinal
            },
            onActivate: { row in
                guard let ordinal = ordinalByRow[row],
                    let tag = captureEntries[row].tag
                else { return }
                focusManager?.focus(id: persistedFocusID)
                captureSelection.wrappedValue = tag
                handler.highlightedIndex = ordinal
                handler.isOpen = false
            },
            onDismiss: { handler.isOpen = false }
        )
        // A disabled picker never opens (the handler closes it), but belt and
        // braces: drop the popup's interactivity if we got here disabled.
        if isDisabled {
            popupBuffer.hitTestRegions.removeAll()
        }
        buffer.overlays = [
            OverlayLayer(
                offsetX: 0,
                offsetY: 1,
                content: popupBuffer,
                level: .popover,
                anchorHeight: 1
            )
        ]
    }

    // MARK: Collapsed Control

    /// Draws the single-line collapsed control: `▐ Selection      ▾ ▌`.
    private func collapsedLine(
        innerWidth: Int,
        renderedLabels: [String?],
        isOpen: Bool,
        isFocused: Bool,
        isHovered: Bool,
        context: RenderContext,
        palette: any Palette
    ) -> String {
        // Combine own + cascaded disabled (renderToBuffer's shadowing local does
        // not reach this helper).
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        // The text of the currently selected option, if any.
        let selectedText: String
        if let index = entries.firstIndex(where: { $0.tag == selection.wrappedValue }) {
            selectedText = renderedLabels[index]?.stripped ?? ""
        } else {
            selectedText = ""
        }

        let caret = isOpen ? DropdownMenu.openCaret : DropdownMenu.closedCaret

        // Content layout: leading space + text + caret + trailing space.
        let textWidth = max(0, innerWidth - 3)
        let fittedText = DropdownMenu.fit(selectedText, to: textWidth)
        let content = " " + fittedText + caret + " "

        // Same hover treatment as Button: bump the background
        // tint while the cursor is hovering and the control
        // isn't focused. Caps and label colour are unchanged.
        let buttonBgOpacity = isHovered
            ? ViewConstants.hoverBackground
            : ViewConstants.focusBorderDim
        let buttonBg = palette.accent.opacity(buttonBgOpacity, over: palette.background)

        // The label colours are floored (hue-preserving) against the face
        // they sit on, like Button labels — see ButtonStyle.makeStandardBody.
        let labelFg: Color
        if isDisabled {
            labelFg = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        } else if isFocused {
            labelFg = palette.accent.ensuringContrast(atLeast: 3.0, against: buttonBg)
        } else {
            labelFg = palette.foregroundSecondary.ensuringContrast(atLeast: 3.0, against: buttonBg)
        }

        let capColor: Color
        if isDisabled {
            capColor = buttonBg
        } else if isFocused {
            capColor = Color.lerp(
                buttonBg,
                palette.accent.opacity(ViewConstants.buttonCapPulseBright, over: palette.background),
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

    /// The drop-down's vertical scroll, when the option list is taller than the
    /// menu can show. `extent` = option count, `viewportHeight` = visible rows,
    /// `scrollOffset` = first visible option. Drives the menu's scrollbar (the
    /// shared ``ScrollbarRenderer`` machinery) and its wheel.
    let menuScroll = ScrollAxis()

    /// Set when keyboard navigation (or opening) moves the highlight, so the next
    /// render scrolls the window to keep the highlight visible. Wheel/bar scrolling
    /// leaves it `false` so those move the window freely (the highlight may leave
    /// the viewport, as in a desktop drop-down).
    var scrollFollowPending = true

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
                scrollFollowPending = true
                return true
            case .down:
                highlightedIndex =
                    highlightedIndex < itemValues.count - 1 ? highlightedIndex + 1 : 0
                scrollFollowPending = true
                return true
            case .home:
                highlightedIndex = 0
                scrollFollowPending = true
                return true
            case .end:
                highlightedIndex = itemValues.count - 1
                scrollFollowPending = true
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
            case .enter, .space:
                // Only Enter/Space (or a click) open the drop-down — matching
                // SwiftUI. Arrow keys must fall through to focus navigation.
                highlightedIndex = itemValues.firstIndex(of: selection.wrappedValue) ?? 0
                isOpen = true
                scrollFollowPending = true
                return true
            default:
                // Closed: let Tab and the arrow keys drive focus navigation.
                return false
            }
        }
    }
}
