//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DropdownMenuRenderer.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Drop-down Menu

/// The shared pop-up list machinery behind every drop-down menu in TUIkit —
/// the menu-style ``Picker``'s option list and a ``TextField``'s input
/// suggestions (``View/textInputSuggestions(_:)``).
///
/// Renders a bordered, vertically-windowed list of rows (options and
/// dividers) with the standard active-control affordances — a pulsing accent
/// highlight and border, plus a scrollbar when the rows overflow the overlay
/// budget — and wires the popup's mouse behaviour: hover moves the highlight
/// (the desktop drop-down model), a click activates a row, the wheel scrolls
/// the window freely, and left-clicks on chrome or empty area are consumed so
/// they never fall through to whatever sits behind the open menu.
///
/// The caller owns the control-specific state (highlight ordinal, open flag,
/// a ``ScrollAxis`` for the window) and attaches the returned buffer as an
/// ``OverlayLayer`` anchored beneath its collapsed control.
@MainActor
enum DropdownMenu {
    /// The caret marking a control whose drop-down is closed (▾).
    static let closedCaret = "\u{25BE}"

    /// The caret marking a control whose drop-down is open (▴).
    static let openCaret = "\u{25B4}"

    /// The marker drawn beside a menu's current value (✓).
    static let selectedMarker = "\u{2713}"

    /// One row of a drop-down menu.
    enum Row {
        /// A selectable option. The string is the row's interior text,
        /// already carrying its leading marker/padding; the renderer fits it
        /// to the menu width and applies the highlight background.
        case option(String)

        /// A horizontal rule between option groups. Never highlighted,
        /// hovered, or clickable.
        case divider
    }

    /// The number of rows the popup can show at once: every row when they fit
    /// the overlay content area (minus the popup's own top/bottom border),
    /// floored at 4 so a cramped terminal still shows a usable window.
    static func maxVisibleRows(rowCount: Int, context: RenderContext) -> Int {
        min(rowCount, max(4, context.environment.overlayContentHeight - 2))
    }

    /// Whether the popup overflows its window and therefore shows a scrollbar
    /// in its rightmost interior column.
    static func wantsScrollbar(rowCount: Int, context: RenderContext) -> Bool {
        rowCount > maxVisibleRows(rowCount: rowCount, context: context)
    }

    /// Collapses runs of adjacent dividers and drops leading/trailing ones,
    /// so conditional groups (e.g. a "recents" section that is sometimes
    /// empty) never leave a stray rule at the menu's edge.
    static func normalizedEntries<Entry>(
        _ entries: [Entry], isDivider: (Entry) -> Bool
    ) -> [Entry] {
        var result: [Entry] = []
        for entry in entries {
            if isDivider(entry) {
                guard let last = result.last, !isDivider(last) else { continue }
            }
            result.append(entry)
        }
        while let last = result.last, isDivider(last) {
            result.removeLast()
        }
        return result
    }

    /// Everything a control passes to ``popup(_:context:onHover:onActivate:)``.
    struct Configuration {
        /// The menu rows, options and dividers, in display order.
        let rows: [Row]

        /// The highlighted row index, or `nil` for none. Divider rows are
        /// never highlighted; the caller maps its option-ordinal highlight to
        /// a row index.
        let highlightedRow: Int?

        /// The popup's interior width (between the borders).
        let innerWidth: Int

        /// The caller-owned scroll state for the window; its extent and
        /// viewport are synced by the renderer.
        let scroll: ScrollAxis

        /// When `true`, the window scrolls (if needed) to keep
        /// `highlightedRow` visible — set after keyboard navigation moved the
        /// highlight. Wheel/scrollbar movement passes `false` so the window
        /// moves freely, as in a desktop drop-down.
        let followHighlight: Bool

        /// A stable identity for the scrollbar's held-button auto-repeat
        /// (unique per control).
        let autoRepeatToken: String
    }

    /// Renders the bordered popup — windowed against the overlay budget, with
    /// a scrollbar when the rows overflow — and wires its mouse handlers.
    ///
    /// - Parameters:
    ///   - config: The rows, highlight, width, and scroll state.
    ///   - context: The current render context.
    ///   - onHover: Called with the row index when the cursor enters an
    ///     option row.
    ///   - onActivate: Called with the row index when an option row is
    ///     clicked.
    ///   - onDismiss: Called when the user clicks OUTSIDE the popup — close
    ///     the menu (the click itself is consumed, macOS-style).
    /// - Returns: The popup buffer, ready to attach as an ``OverlayLayer``.
    static func popup(
        _ config: Configuration,
        context: RenderContext,
        onHover: @escaping (Int) -> Void,
        onActivate: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) -> FrameBuffer {
        let rows = config.rows
        let scroll = config.scroll
        let maxVisible = maxVisibleRows(rowCount: rows.count, context: context)
        let wantsBar = rows.count > maxVisible

        scroll.extent = rows.count
        scroll.viewportHeight = maxVisible
        scroll.wheelEdgeHold.delayNanos =
            context.environment.scrollChainingDelay.wheelDelayNanos
        if config.followHighlight, let highlightedRow = config.highlightedRow {
            var offset = scroll.scrollOffset
            if highlightedRow < offset {
                offset = highlightedRow
            } else if highlightedRow >= offset + maxVisible {
                offset = highlightedRow - maxVisible + 1
            }
            scroll.scrollOffset = offset
        }
        scroll.clampScrollOffset()
        let scrollOffset = scroll.scrollOffset
        let visibleRange = scrollOffset..<min(rows.count, scrollOffset + maxVisible)

        let palette = context.environment.palette
        let barCells: [String]? =
            wantsBar
            ? ScrollbarRenderer.verticalScrollbar(
                height: maxVisible, extent: rows.count, viewport: maxVisible,
                offset: scrollOffset, arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                colors: ScrollbarColors(
                    thumb: palette.foregroundSecondary, track: palette.foregroundQuaternary,
                    arrow: palette.foregroundTertiary))
            : nil

        var buffer = FrameBuffer(
            lines: lines(
                rows: rows,
                highlightedRow: config.highlightedRow,
                visibleRange: visibleRange,
                innerWidth: config.innerWidth,
                barCells: barCells,
                context: context))
        attachMouseHandlers(
            to: &buffer,
            config: config,
            visibleRange: visibleRange,
            wantsBar: wantsBar,
            maxVisible: maxVisible,
            context: context,
            onHover: onHover,
            onActivate: onActivate)
        if wantsBar {
            ScrollbarRenderer.driveAutoRepeat(
                state: scroll, token: config.autoRepeatToken, context: context)
        }

        // macOS behaviour: a click OUTSIDE an open menu closes it, and does
        // nothing else — the closing click is consumed. The popup carries a
        // screen-covering backdrop region: inserted FIRST, so every region
        // of the popup itself (rows, scrollbar) wins over it, while overlay
        // regions composite after the page's, so it still beats everything
        // underneath. The generous bounds cover any screen wherever the
        // popup is anchored (region containment is pure arithmetic; nothing
        // clips it to the buffer). Wheel events fall through — the page can
        // still scroll behind an open menu.
        if !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher {
            let dismissID = dispatcher.register { event in
                switch event.phase {
                case .pressed where !event.button.isWheel:
                    onDismiss()
                    return true
                case .released:
                    return true  // the consumed press's matching release
                default:
                    return false
                }
            }
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: -4096, offsetY: -4096, width: 8192, height: 8192,
                    handlerID: dismissID),
                at: 0)
        }
        return buffer
    }

    // MARK: - Line drawing

    /// Draws the bordered popup lines for the visible window.
    private static func lines(
        rows: [Row],
        highlightedRow: Int?,
        visibleRange: Range<Int>,
        innerWidth: Int,
        barCells: [String]?,
        context: RenderContext
    ) -> [String] {
        let palette = context.environment.palette
        let borderStyle = context.environment.appearance.borderStyle
        // While the popup is open its control holds keyboard focus, so the
        // highlighted row's background pulses between a dim and a bright
        // accent — the same affordance ``List`` uses for its focused row —
        // to make it visually obvious that the arrow keys and Enter are
        // driving the menu rather than whatever sits behind it.
        let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background)
        let brightAccent = palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background)
        let indicator = SelectionIndicator.resolve(isFocused: true, context: context)
        let highlightBg = indicator.color(dim: dimAccent, bright: brightAccent)
        // The border echoes the highlight pulse at lower intensity so the
        // popup's frame reads as part of the same active control.
        let borderColor = indicator.color(
            dim: palette.accent.opacity(ViewConstants.focusBorderDim, over: palette.background),
            bright: palette.accent)

        var lines: [String] = [
            BorderRenderer.standardTopBorder(
                style: borderStyle, innerWidth: innerWidth, color: borderColor)
        ]

        // When a scrollbar is shown it takes the rightmost interior column, so
        // content fits the remaining width and each row is composed manually
        // (border + content + bar cell + border).
        let verticalBorder = ANSIRenderer.colorize(
            String(borderStyle.vertical), foreground: borderColor)
        let contentInner = barCells == nil ? innerWidth : max(1, innerWidth - 1)

        for (local, index) in visibleRange.enumerated() {
            switch rows[index] {
            case .divider:
                // An inset rule (no T-junctions): it spans the content area
                // but not the scrollbar column, macOS-menu-separator style.
                let rule = ANSIRenderer.colorize(
                    String(repeating: borderStyle.horizontal, count: contentInner),
                    foreground: borderColor)
                if let barCells {
                    let cell = local < barCells.count ? barCells[local] : " "
                    lines.append(verticalBorder + rule + cell + verticalBorder)
                } else {
                    lines.append(verticalBorder + rule + verticalBorder)
                }
            case .option(let content):
                let isHighlighted = index == highlightedRow
                if let barCells {
                    let fitted = fit(content, to: contentInner)
                    let styled = fitted.withPersistentBackground(
                        isHighlighted ? highlightBg : nil)
                    let cell = local < barCells.count ? barCells[local] : " "
                    lines.append(
                        verticalBorder + styled + ANSIRenderer.reset + cell + verticalBorder)
                } else {
                    lines.append(
                        BorderRenderer.standardContentLine(
                            content: content,
                            innerWidth: innerWidth,
                            style: borderStyle,
                            color: borderColor,
                            backgroundColor: isHighlighted ? highlightBg : nil))
                }
            }
        }

        lines.append(
            BorderRenderer.standardBottomBorder(
                style: borderStyle, innerWidth: innerWidth, color: borderColor))
        return lines
    }

    // MARK: - Mouse wiring

    /// Emits the popup's hit-test regions: a wheel/click-catcher over the
    /// whole popup, the scrollbar (when shown), and one region per *visible*
    /// option row. Order matters under the dispatcher's reverse-iteration:
    /// the wheel catcher goes in first (lowest priority — it only catches the
    /// fall-through wheel and stray clicks), then the bar, then the rows
    /// (highest priority for their cells). Rows start at y=1 (after the top
    /// border). Divider rows get no region — clicks on them land in the
    /// catcher and are consumed.
    private static func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        config: Configuration,
        visibleRange: Range<Int>,
        wantsBar: Bool,
        maxVisible: Int,
        context: RenderContext,
        onHover: @escaping (Int) -> Void,
        onActivate: @escaping (Int) -> Void
    ) {
        guard !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        // Hover-follows-cursor needs motion reports (the collapsed control
        // usually requested them already; this is idempotent).
        mouseDispatcher.requestFeature(.motion)
        let rows = config.rows
        let scroll = config.scroll
        let innerWidth = config.innerWidth
        let contentInner = wantsBar ? max(1, innerWidth - 1) : innerWidth

        // Wheel anywhere over the popup scrolls the window freely (it does
        // not follow the highlight — like a desktop drop-down). Left clicks
        // on chrome/empty area are consumed so they don't fall through.
        let wheelID = mouseDispatcher.register { event in
            if scroll.handleWheelEvent(event) { return true }
            return event.button == .left
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: innerWidth + 2, height: maxVisible + 2,
                handlerID: wheelID))

        // The scrollbar column (rightmost interior column over the rows).
        if wantsBar {
            let barHandler = ScrollbarRenderer.verticalMouseHandler(
                for: scroll, length: maxVisible,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                behavior: context.environment.scrollbarClickBehavior)
            let barID = mouseDispatcher.register(barHandler)
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: innerWidth, offsetY: 1, width: 1, height: maxVisible,
                    handlerID: barID))
        }

        for (local, index) in visibleRange.enumerated() {
            guard case .option = rows[index] else { continue }
            let mouseHandlerID = mouseDispatcher.register { event in
                switch event.phase {
                case .entered:
                    // Hover follows the cursor across the popup: whichever
                    // option row is under the cursor becomes highlighted.
                    onHover(index)
                    return true
                case .exited:
                    // Leave the highlight where it is when the cursor leaves.
                    return true
                case .pressed where event.button == .left:
                    return true
                case .released where event.button == .left:
                    onActivate(index)
                    return true
                default:
                    return false
                }
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 1,
                    offsetY: 1 + local,
                    width: contentInner,
                    height: 1,
                    handlerID: mouseHandlerID))
        }
    }

    /// Truncates or pads a plain string to exactly `width` visible columns.
    static func fit(_ text: String, to width: Int) -> String {
        text.strippedLength > width
            ? text.ansiAwarePrefix(visibleCount: width)
            : text.padToVisibleWidth(width)
    }
}
