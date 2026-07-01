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

        // Render every option's label once; reuse for sizing and drawing.
        let renderedLabels: [String] = entries.map { entry in
            entry.label.renderToBuffer(context: context).lines.first ?? ""
        }
        let maxLabelWidth = renderedLabels.map(\.strippedLength).max() ?? 0

        // Inner width = label + selection marker + a space + 1 char padding
        // on each side. When the option list overflows, the drop-down shows a
        // scrollbar in its rightmost interior column; reserve one more column so
        // there's a blank gap between the option text and the bar (rather than the
        // text running flush against it) without truncating any label. The
        // overflow test mirrors the windowing in `renderOpenMenu`.
        let maxVisibleForWidth = min(entries.count, max(4, context.environment.overlayContentHeight - 2))
        let wantsScrollbar = entries.count > maxVisibleForWidth
        let desiredInner = maxLabelWidth + 4 + (wantsScrollbar ? 1 : 0)
        let innerWidth = max(6, min(desiredInner, max(6, context.availableWidth - 2)))

        let isOpen = handler.isOpen && !entries.isEmpty
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
            max(0, handler.highlightedIndex), entries.count - 1)
        attachOpenPopup(
            to: &buffer,
            context: context,
            handler: handler,
            persistedFocusID: persistedFocusID,
            innerWidth: innerWidth,
            renderedLabels: renderedLabels,
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
        let itemValues = entries.map { AnyHashable($0.tag) }

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

    /// Builds the open drop-down popup, wires its per-row mouse
    /// handlers, and attaches it as an overlay layer anchored
    /// one row below the collapsed control. The in-flow control
    /// stays a single line so opening the picker never disturbs
    /// the layout of sibling views and the list draws on top of
    /// whatever sits beneath it.
    private func attachOpenPopup(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        handler: _PickerMenuHandler,
        persistedFocusID: String,
        innerWidth: Int,
        renderedLabels: [String],
        palette: any Palette
    ) {
        // Window the options against the visible screen, scrolling (with a
        // scrollbar) when they don't all fit. Use the published overlay content
        // height — the area above the status bar / below the header that the
        // compositor clamps overlays to — not `availableHeight` (a Picker inside a
        // ScrollView is offered a huge measure budget) nor `terminalHeight` (that
        // includes the status bar + header, so the drop-down would be sized too
        // tall and have its bottom border + last rows shaved off against the status
        // bar). Subtract 2 for the drop-down's own top/bottom border; keep a floor.
        let maxVisible = min(entries.count, max(4, context.environment.overlayContentHeight - 2))
        let wantsBar = entries.count > maxVisible

        handler.menuScroll.extent = entries.count
        handler.menuScroll.viewportHeight = maxVisible
        // Follow the highlight only when keyboard navigation moved it; wheel/bar
        // scrolling (which doesn't set the flag) then moves the window freely.
        if handler.scrollFollowPending {
            ensureHighlightedVisible(handler: handler, maxVisible: maxVisible)
            handler.scrollFollowPending = false
        }
        handler.menuScroll.clampScrollOffset()
        let scrollOffset = handler.menuScroll.scrollOffset
        let visibleRange = scrollOffset..<min(entries.count, scrollOffset + maxVisible)

        let barCells: [String]? =
            wantsBar
            ? ScrollbarRenderer.verticalScrollbar(
                height: maxVisible, extent: entries.count, viewport: maxVisible,
                offset: scrollOffset, arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                colors: ScrollbarColors(
                    thumb: palette.foregroundSecondary, track: palette.foregroundQuaternary,
                    arrow: palette.foregroundTertiary))
            : nil

        let popup = popupLines(
            innerWidth: innerWidth,
            renderedLabels: renderedLabels,
            highlightedIndex: handler.highlightedIndex,
            visibleRange: visibleRange,
            barCells: barCells,
            context: context,
            palette: palette
        )
        var popupBuffer = FrameBuffer(lines: popup)
        attachPopupRowHandlers(
            to: &popupBuffer,
            context: context,
            handler: handler,
            persistedFocusID: persistedFocusID,
            innerWidth: innerWidth,
            visibleRange: visibleRange,
            wantsBar: wantsBar,
            maxVisible: maxVisible
        )
        if wantsBar {
            ScrollbarRenderer.driveAutoRepeat(
                state: handler.menuScroll,
                token: "picker-menu-scrollbar-\(context.identity.path)", context: context)
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

    /// Adjusts the menu's scroll offset so the highlighted option is within the
    /// visible window (called only when keyboard navigation moved the highlight).
    private func ensureHighlightedVisible(handler: _PickerMenuHandler, maxVisible: Int) {
        let highlighted = handler.highlightedIndex
        var offset = handler.menuScroll.scrollOffset
        if highlighted < offset {
            offset = highlighted
        } else if highlighted >= offset + maxVisible {
            offset = highlighted - maxVisible + 1
        }
        handler.menuScroll.scrollOffset = offset
    }

    /// Emits the popup's hit-test regions: a wheel/click-catcher over the whole
    /// drop-down, the scrollbar (when shown), and one region per *visible* option
    /// row. Order matters under the dispatcher's reverse-iteration: the wheel
    /// catcher goes in first (lowest priority — it only catches the fall-through
    /// wheel and stray clicks), then the bar, then the rows (highest priority for
    /// their cells). Rows start at y=1 (after the top border).
    private func attachPopupRowHandlers(
        to popupBuffer: inout FrameBuffer,
        context: RenderContext,
        handler: _PickerMenuHandler,
        persistedFocusID: String,
        innerWidth: Int,
        visibleRange: Range<Int>,
        wantsBar: Bool,
        maxVisible: Int
    ) {
        // Combine own + cascaded disabled (renderToBuffer's shadowing local does
        // not reach this helper).
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        let captureSelection = selection
        let contentInner = wantsBar ? max(1, innerWidth - 1) : innerWidth

        // Wheel anywhere over the popup scrolls the window freely (it does not set
        // the follow flag, so the highlight may scroll out of view — like a desktop
        // drop-down). Left clicks on chrome/empty area are consumed so they don't
        // fall through to whatever sits behind the open menu.
        let menuScroll = handler.menuScroll
        let wheelID = mouseDispatcher.register { event in
            if menuScroll.handleWheelEvent(event) { return true }
            return event.button == .left
        }
        popupBuffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: innerWidth + 2, height: maxVisible + 2,
                handlerID: wheelID))

        // The scrollbar column (rightmost interior column over the option rows).
        if wantsBar {
            let barHandler = ScrollbarRenderer.verticalMouseHandler(
                for: menuScroll, length: maxVisible,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                behavior: context.environment.scrollbarClickBehavior)
            let barID = mouseDispatcher.register(barHandler)
            popupBuffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: innerWidth, offsetY: 1, width: 1, height: maxVisible,
                    handlerID: barID))
        }

        for (local, index) in visibleRange.enumerated() {
            let entry = entries[index]
            let mouseHandlerID = mouseDispatcher.register { event in
                switch event.phase {
                case .entered:
                    // Hover follows the cursor across the popup (desktop drop-down
                    // model): whichever row is under the cursor becomes highlighted.
                    handler.highlightedIndex = index
                    return true
                case .exited:
                    // Leave the highlight where it is when the cursor leaves.
                    return true
                case .pressed where event.button == .left:
                    return true
                case .released where event.button == .left:
                    focusManager?.focus(id: persistedFocusID)
                    captureSelection.wrappedValue = entry.tag
                    handler.highlightedIndex = index
                    handler.isOpen = false
                    return true
                default:
                    return false
                }
            }
            popupBuffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 1,
                    offsetY: 1 + local,
                    width: contentInner,
                    height: 1,
                    handlerID: mouseHandlerID
                )
            )
        }
    }

    // MARK: Collapsed Control

    /// Draws the single-line collapsed control: `▐ Selection      ▾ ▌`.
    private func collapsedLine(
        innerWidth: Int,
        renderedLabels: [String],
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
            selectedText = renderedLabels[index].stripped
        } else {
            selectedText = ""
        }

        let caret = isOpen ? PickerMenuConstants.openCaret : PickerMenuConstants.closedCaret

        // Content layout: leading space + text + caret + trailing space.
        let textWidth = max(0, innerWidth - 3)
        let fittedText = fit(selectedText, to: textWidth)
        let content = " " + fittedText + caret + " "

        // Same hover treatment as Button: bump the background
        // tint while the cursor is hovering and the control
        // isn't focused. Caps and label colour are unchanged.
        let buttonBgOpacity = isHovered
            ? ViewConstants.hoverBackground
            : ViewConstants.focusBorderDim
        let buttonBg = palette.accent.opacity(buttonBgOpacity)

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
        visibleRange: Range<Int>,
        barCells: [String]?,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        let borderStyle = context.environment.appearance.borderStyle
        // While the drop-down is open the picker holds keyboard focus, so we
        // pulse the highlighted row's background between a dim and a bright
        // accent — the same affordance ``List`` uses for its focused row —
        // to make it visually obvious that arrow keys and Enter are driving
        // the drop-down rather than whatever sits behind it.
        let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
        let brightAccent = palette.accent.opacity(ViewConstants.focusPulseMax)
        let indicator = SelectionIndicator.resolve(isFocused: true, context: context)
        let highlightBg = indicator.color(dim: dimAccent, bright: brightAccent)
        // The border colour echoes the highlight pulse at lower intensity so
        // the drop-down's frame reads as part of the same active control,
        // not as a static element with a moving inside.
        let borderColor = indicator.color(
            dim: palette.accent.opacity(ViewConstants.focusBorderDim), bright: palette.accent)

        var lines: [String] = [
            BorderRenderer.standardTopBorder(
                style: borderStyle,
                innerWidth: innerWidth,
                color: borderColor
            )
        ]

        // When a scrollbar is shown it takes the rightmost interior column, so the
        // option content fits the remaining width and each row is composed manually
        // (border + content + bar cell + border) — mirroring `contentLine`.
        let verticalBorder = ANSIRenderer.colorize(String(borderStyle.vertical), foreground: borderColor)
        let contentInner = barCells == nil ? innerWidth : max(1, innerWidth - 1)

        for (local, index) in visibleRange.enumerated() {
            let entry = entries[index]
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

            if let barCells {
                let fitted = fit(rowContent, to: contentInner)
                let styled = fitted.withPersistentBackground(isHighlighted ? highlightBg : nil)
                let cell = local < barCells.count ? barCells[local] : " "
                lines.append(verticalBorder + styled + ANSIRenderer.reset + cell + verticalBorder)
            } else {
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
