//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBar.swift
//
//  A status bar that displays keyboard shortcuts and context-sensitive actions.
//  Always rendered at the bottom of the terminal, never dimmed by overlays.
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - StatusBar View

/// A status bar that displays at the bottom of the terminal.
///
/// The status bar shows keyboard shortcuts and their descriptions.
/// It's rendered separately from the main view tree and is never
/// affected by overlays or dimming.
///
/// # Layout
///
/// The status bar consists of two containers:
/// - **User Container** (left): User-defined items, sorted by order
/// - **System Container** (right): System items (quit, help, theme), fixed order
///
/// ```
/// ┌────────────────────────────────────────┬───────────────────────────────┐
/// │ s save   x action   ↑↓ nav             │ q quit   ? help   t theme    │
/// └────────────────────────────────────────┴───────────────────────────────┘
/// ```
///
/// # Usage
///
/// To set status bar items, use the environment:
///
/// ```swift
/// // In renderToBuffer(context:):
/// let statusBar = context.environment.statusBar
/// statusBar.setItems([
///     StatusBarItem(shortcut: "s", label: "save"),
///     StatusBarItem(shortcut: "↑↓", label: "nav"),
/// ])
/// ```
public struct StatusBar: View {
    /// User items (left container).
    public let userItems: [any StatusBarItemProtocol]

    /// System items (right container).
    public let systemItems: [any StatusBarItemProtocol]

    /// The visual style.
    public let style: ChromeStyle

    /// The horizontal alignment of user items within the left container.
    public let alignment: StatusBarAlignment

    /// The highlight color for shortcut keys.
    public let highlightColor: Color

    /// The label color.
    public let labelColor: Color?

    /// This frame's tooltip, already wrapped to the bar's content width.
    ///
    /// Passed in rather than read from the environment so `height` — which the
    /// run loop reads before it renders anything — and the render agree by
    /// construction. See `StatusBarState.tooltipLines`.
    public var tooltipLines: [String] = []

    /// Creates a status bar with separate user and system items.
    ///
    /// - Parameters:
    ///   - userItems: User-defined items (left container).
    ///   - systemItems: System items (right container).
    ///   - style: The visual style (default: `.bordered`).
    ///   - alignment: The alignment of user items (default: `.leading`).
    ///   - highlightColor: The color for shortcut keys (default: `.cyan`).
    ///   - labelColor: The color for labels (default: nil, terminal default).
    ///   - tooltipLines: This frame's tooltip, already wrapped to the bar's
    ///     content width (default: none).
    public init(
        userItems: [any StatusBarItemProtocol] = [],
        systemItems: [any StatusBarItemProtocol] = [],
        style: ChromeStyle = .bordered,
        alignment: StatusBarAlignment = .leading,
        highlightColor: Color = .cyan,
        labelColor: Color? = nil,
        tooltipLines: [String] = []
    ) {
        self.userItems = userItems
        self.systemItems = systemItems
        self.style = style
        self.alignment = alignment
        self.tooltipLines = tooltipLines
        self.highlightColor = highlightColor
        self.labelColor = labelColor
    }

    /// Creates a status bar with all items combined (legacy compatibility).
    ///
    /// - Parameters:
    ///   - items: All items to display (will be treated as user items).
    ///   - style: The visual style (default: `.bordered`).
    ///   - alignment: The horizontal alignment (default: `.justified`).
    ///   - highlightColor: The color for shortcut keys (default: `.cyan`).
    ///   - labelColor: The color for labels (default: nil, terminal default).
    public init(
        items: [any StatusBarItemProtocol],
        style: ChromeStyle = .bordered,
        alignment: StatusBarAlignment = .justified,
        highlightColor: Color = .cyan,
        labelColor: Color? = nil
    ) {
        self.userItems = items
        self.systemItems = []
        self.style = style
        self.alignment = alignment
        self.highlightColor = highlightColor
        self.labelColor = labelColor
    }

    /// Creates a status bar using a builder.
    ///
    /// - Parameters:
    ///   - style: The visual style.
    ///   - alignment: The horizontal alignment.
    ///   - highlightColor: The color for shortcut keys.
    ///   - labelColor: The color for labels.
    ///   - builder: A closure that returns items.
    public init(
        style: ChromeStyle = .bordered,
        alignment: StatusBarAlignment = .justified,
        highlightColor: Color = .cyan,
        labelColor: Color? = nil,
        @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
    ) {
        self.userItems = builder()
        self.systemItems = []
        self.style = style
        self.alignment = alignment
        self.highlightColor = highlightColor
        self.labelColor = labelColor
    }

    /// All items combined (sorted user items, then filtered system items).
    ///
    /// User items are sorted by their `order` property.
    /// System items maintain their fixed order (quit, help, theme).
    /// User items override system items with the same shortcut.
    /// Use this for event handling to check all items.
    public var allItems: [any StatusBarItemProtocol] {
        let userShortcuts = Set(userItems.map { $0.shortcut })
        let filteredSystemItems = systemItems.filter { !userShortcuts.contains($0.shortcut) }
        return userItems.sorted { $0.order < $1.order } + filteredSystemItems
    }

    /// Whether the status bar has any items to display.
    public var hasItems: Bool {
        !userItems.isEmpty || !systemItems.isEmpty
    }

    public var body: some View {
        _StatusBarCore(
            userItems: userItems,
            systemItems: systemItems,
            style: style,
            alignment: alignment,
            highlightColor: highlightColor,
            labelColor: labelColor,
            tooltipLines: tooltipLines
        )
    }
}

// MARK: - StatusBar Core (Private Renderable)

/// Private rendering core for ``StatusBar``.
///
/// Handles all procedural ANSI rendering and buffer assembly.
/// Public ``StatusBar`` delegates to this via its `body`.
///
/// `highlightColor` and `labelColor` are resolved against the environment's
/// palette once, at the top of `renderToBuffer`, and only the resolved colours go
/// on to the emitter and the claims. Either may be a palette role, and a role
/// that reached `ANSIRenderer` unresolved stopped the process: the emitter does
/// not resolve, and a bar built outside the run loop had nothing else to do it.
private struct _StatusBarCore: View, Renderable {
    let userItems: [any StatusBarItemProtocol]
    let systemItems: [any StatusBarItemProtocol]
    let style: ChromeStyle
    let alignment: StatusBarAlignment
    let highlightColor: Color
    let labelColor: Color?
    let tooltipLines: [String]

    var body: Never {
        fatalError("_StatusBarCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Filter out items hidden from the status bar — they
        // still participate in keyboard dispatch via StatusBar-
        // State, but they don't contribute a visible row here.
        let visibleUserItems = userItems.filter(\.displayInStatusBar)
        let visibleSystemItems = systemItems.filter(\.displayInStatusBar)

        // Get shortcuts used by user items (for deduplication)
        let userShortcuts = Set(visibleUserItems.map { $0.shortcut })

        // Filter out system items that are overridden by user items
        let filteredSystemItems = visibleSystemItems.filter { !userShortcuts.contains($0.shortcut) }

        // Pull the transient escape-label override (set by an open Picker
        // drop-down, an inline editor, etc.) so the escape entry shows
        // "close menu" or similar while the underlying handler is unchanged.
        let escapeOverride = context.environment.statusBar?.escapeLabelOverride

        // Combine: sorted user items, then the system items in THEIR order —
        // which is what puts the two contextual keys next to the page's own
        // items rather than after the app-wide ones. (Quit / appearance / theme
        // are already in ascending order, so this changes nothing for them.)
        let sortedUserItems = visibleUserItems.sorted { $0.order < $1.order }
        let combinedItems = sortedUserItems + filteredSystemItems.sorted { $0.order < $1.order }

        guard !combinedItems.isEmpty || !tooltipLines.isEmpty else {
            return FrameBuffer()
        }

        // Build item strings and capture their visible widths
        // so the layout pass can also report each item's column
        // range in the rendered line — used below to emit mouse
        // hit-test regions for clickable items. The hovered item
        // (set by the dispatcher's .entered / .exited events
        // below) gets a bumped tint so the user has visual
        // confirmation that an item is clickable.
        let hoveredID = context.environment.statusBar?.hoveredItemID
        let activationOverride = context.environment.statusBar?.activationLabelOverride
        let colours = resolvedColours(in: context.environment.palette)
        let layouts = combinedItems.map { item -> ItemLayout in
            let display = renderItemString(
                item: item,
                colours: colours,
                escapeOverride: escapeOverride,
                activationOverride: activationOverride,
                isHovered: item.id == hoveredID && itemIsClickable(item)
            )
            return ItemLayout(
                item: item,
                display: display,
                visibleWidth: display.strippedLength
            )
        }

        var buffer: FrameBuffer
        let itemColumnOffset: Int
        let itemRowOffset: Int

        switch style {
        case .compact:
            let tips = tooltipContent(
                width: style.barContentWidth(context.availableWidth), context: context)
            let result = renderCompact(layouts: layouts, width: context.availableWidth)
            buffer = tips.isEmpty
                ? result.buffer
                : FrameBuffer(lines: tips + (combinedItems.isEmpty ? [] : result.buffer.lines))
            itemColumnOffset = 0
            itemRowOffset = tips.count
            // The placed columns on `result.placedColumns` are
            // already absolute on a single-row compact bar.
            return finished(
                buffer: buffer,
                layouts: layouts,
                columns: result.placedColumns,
                columnOffset: itemColumnOffset,
                rowOffset: itemRowOffset,
                colours: colours,
                context: context
            )

        case .rule:
            // A rule ABOVE the items, mirroring the app header's rule below
            // its content — the two are meant to read as one frame around the
            // page, so both come from `ChromeStyle.ruleRow`.
            let tips = tooltipContent(
                width: style.barContentWidth(context.availableWidth), context: context)
            let result = alignContent(layouts: layouts, width: context.availableWidth)
            buffer = FrameBuffer(
                lines: [ChromeStyle.ruleRow(width: context.availableWidth, context: context)]
                    + tips + (combinedItems.isEmpty ? [] : [result.line]))
            // The rule is line 0 here, above the items — the mirror of the
            // header's, which sits below its content.
            if let claim = ChromeStyle.ruleClaim(
                width: context.availableWidth, offsetY: 0, context: context)
            {
                buffer.opacityRegions.append(claim)
            }
            itemColumnOffset = 0
            itemRowOffset = 1 + tips.count
            return finished(
                buffer: buffer,
                layouts: layouts,
                columns: result.placedColumns,
                columnOffset: itemColumnOffset,
                rowOffset: itemRowOffset,
                colours: colours,
                context: context
            )

        case .bordered:
            let tips = tooltipContent(
                width: style.barContentWidth(context.availableWidth), context: context)
            let result = renderBordered(
                layouts: layouts,
                width: context.availableWidth,
                context: context,
                tooltipRows: tips,
                drawsItemRow: !combinedItems.isEmpty
            )
            buffer = result.buffer
            // The bordered renderer reports columns relative to
            // the inner content; offset by the border + the
            // single-space content padding it added on the left.
            itemColumnOffset = 1 + 1
            itemRowOffset = 1 + tips.count
            return finished(
                buffer: buffer,
                layouts: layouts,
                columns: result.placedColumns,
                columnOffset: itemColumnOffset,
                rowOffset: itemRowOffset,
                colours: colours,
                context: context
            )
        }
    }

    /// The tooltip's rows, styled and padded to the bar's content width.
    ///
    /// Padded rather than left ragged because a `FrameBuffer`'s lines are
    /// compared as strings by the frame diff, and a short row would let whatever
    /// the previous frame drew show through to its right.
    private func tooltipContent(width: Int, context: RenderContext) -> [String] {
        guard !tooltipLines.isEmpty else { return [] }
        // Opaque in the bytes. The slot's own alpha is claimed over these rows by
        // `finished(buffer:…)`, the one place that knows where they sit.
        let colour = context.environment.palette.foregroundSecondary.opaqueSpelling
        return tooltipLines.map {
            ANSIRenderer.colorize($0.padToVisibleWidth(width), foreground: colour)
        }
    }

    /// Per-item layout snapshot — display string + its visible
    /// width — passed through the alignment pipeline so the
    /// pipeline can produce a parallel array of column offsets.
    private struct ItemLayout {
        let item: any StatusBarItemProtocol
        let display: String
        let visibleWidth: Int
    }

    /// A laid-out line with the columns at which each input
    /// item's display string was placed.
    private struct LaidOutLine {
        let line: String
        let placedColumns: [Int]
    }

    /// A laid-out buffer with the same column metadata as
    /// ``LaidOutLine``, used by the bordered style which wraps
    /// the line in a 3-row frame.
    private struct LaidOutBuffer {
        let buffer: FrameBuffer
        let placedColumns: [Int]
    }

    /// The bar's two configurable colours, resolved against one palette.
    ///
    /// A type of its own so the emitter and the claims can only be handed colours
    /// that have been through ``resolvedColours(in:)``, never the stored ones.
    private struct ItemColours {
        /// The shortcut keys' colour, concrete, carrying the alpha it was given.
        let highlight: Color
        /// The labels' colour, concrete, or `nil` for no stated colour.
        let label: Color?
    }

    /// `highlightColor` and `labelColor`, resolved against `palette`.
    ///
    /// Resolving keeps each colour's alpha (a role's own, composed with the call
    /// site's), which is what the claims read.
    private func resolvedColours(in palette: any Palette) -> ItemColours {
        ItemColours(
            highlight: highlightColor.resolve(with: palette),
            label: labelColor?.resolve(with: palette))
    }

    /// Whether `shortcut` is the Return key, however the app spelled it.
    static func isReturnShortcut(_ shortcut: String) -> Bool {
        shortcut == Shortcut.enter || shortcut == Shortcut.returnKey || shortcut == "enter"
            || shortcut == "return"
    }

    /// Renders a single item's `shortcut + " " + label` in `colours` and with the
    /// escape-label override. When `isHovered` is true, the whole item is
    /// underlined so the user has a clear visual confirmation that they're over a
    /// clickable target.
    private func renderItemString(
        item: any StatusBarItemProtocol,
        colours: ItemColours,
        escapeOverride: String?,
        activationOverride: String?,
        isHovered: Bool
    ) -> String {
        let shortcutStyled = ANSIRenderer.render(
            item.shortcut,
            with: {
                var textStyle = TextStyle()
                textStyle.foregroundColor = colours.highlight.opaqueSpelling
                textStyle.isBold = true
                textStyle.isUnderlined = isHovered
                return textStyle
            }()
        )

        // Apply the modal escape-label override only to items bound to
        // the escape key, and the focused control's Return verb only to items
        // bound to Return; everything else keeps its declared label.
        let effectiveLabel: String
        if item.shortcut == Shortcut.escape, let override = escapeOverride {
            effectiveLabel = override
        } else if Self.isReturnShortcut(item.shortcut), let override = activationOverride {
            effectiveLabel = override
        } else {
            effectiveLabel = item.label
        }

        let labelStyled: String
        if let color = colours.label {
            labelStyled = ANSIRenderer.render(
                " " + effectiveLabel,
                with: {
                    var textStyle = TextStyle()
                    textStyle.foregroundColor = color.opaqueSpelling
                    textStyle.isUnderlined = isHovered
                    return textStyle
                }()
            )
        } else if isHovered {
            // Plain label with hover — emit an underlined run
            // so the visual cue is consistent with the styled-
            // colour branch above.
            labelStyled = ANSIRenderer.render(
                " " + effectiveLabel,
                with: {
                    var textStyle = TextStyle()
                    textStyle.isUnderlined = true
                    return textStyle
                }()
            )
        } else {
            labelStyled = " " + effectiveLabel
        }

        return shortcutStyled + labelStyled
    }

    /// Emits a 1-row hit-test region for each item with an
    /// action, sized to the item's visible width and offset by
    /// the surrounding chrome. Returns `buffer` unchanged when
    /// the mouse dispatcher isn't available (measure pass etc.)
    /// or when none of the items are clickable.
    /// Everything a laid-out bar owes its items, in one call: the claims for their
    /// two configurable colours and for the tooltip row above them, then the hit
    /// regions that make them clickable.
    ///
    /// One function because all three styles want both, with the same arguments —
    /// they differ only in the offsets — and because a style added later must not be
    /// able to remember one and forget the other. That is what happened to the
    /// header's side payloads twice (see `AppHeader`).
    private func finished(
        buffer: FrameBuffer,
        layouts: [ItemLayout],
        columns: [Int],
        columnOffset: Int,
        rowOffset: Int,
        colours: ItemColours,
        context: RenderContext
    ) -> FrameBuffer {
        var claimed = applyOpacityClaims(
            buffer: buffer, layouts: layouts, columns: columns,
            columnOffset: columnOffset, rowOffset: rowOffset, colours: colours)
        // The tooltip's rows, when the palette slot they paint is faded. They sit
        // directly above the items and are inset exactly as the items are — flush
        // for `.compact` and `.rule`, past the wall and a space of padding for
        // `.bordered` — and padded to `barContentWidth`, so the items' own offsets
        // place them in every style. Here and not in each arm for the reason this
        // function exists. Asked of the lines first: a frame with no tooltip, which
        // is nearly every frame, does not read the palette.
        if !tooltipLines.isEmpty,
            let claim = OpacityRegion.claim(
                offsetX: columnOffset, offsetY: rowOffset - tooltipLines.count,
                width: style.barContentWidth(context.availableWidth),
                height: tooltipLines.count,
                ink: context.environment.palette.foregroundSecondary)
        {
            claimed.opacityRegions.append(claim)
        }
        return applyHitTestRegions(
            buffer: claimed, layouts: layouts, columns: columns, columnOffset: columnOffset,
            rowOffset: rowOffset, context: context)
    }

    /// The claims a bar's items owe when either configurable colour is faded.
    ///
    /// ``StatusBarState/highlightColor`` and ``StatusBarState/labelColor`` are
    /// public `var`s an app sets, and each paints a DIFFERENT run of every item:
    /// the shortcut and the label. So one claim over the row would fade one of them
    /// at the other's alpha, and the two runs are claimed separately — per item,
    /// because the items are spread across the row by the alignment.
    ///
    /// `columns` is the same per-item placement ``applyHitTestRegions`` uses, for
    /// the same reason: only the alignment knows where an item ended up, and a claim
    /// computed from the item widths alone would be wrong under `.justified`.
    ///
    /// The alphas are read from the RESOLVED colours, the same ones the bytes were
    /// spelled from, so a palette role is claimed at its alpha in this palette.
    ///
    /// - Parameters:
    ///   - buffer: The bar's buffer.
    ///   - layouts: The items, in the order they were placed.
    ///   - columns: Where each item's display string starts, in the LINE.
    ///   - columnOffset: What the line itself is inset by (a wall, for a bordered
    ///     bar).
    ///   - rowOffset: Which row of the buffer the items are on.
    ///   - colours: The two colours the items were drawn in, resolved.
    /// - Returns: The buffer, with the claims appended.
    private func applyOpacityClaims(
        buffer: FrameBuffer,
        layouts: [ItemLayout],
        columns: [Int],
        columnOffset: Int,
        rowOffset: Int,
        colours: ItemColours
    ) -> FrameBuffer {
        // Asked of the two colours before anything is walked: an app that has not
        // faded either — which is every app until one does — pays one comparison.
        guard !colours.highlight.isOpaque || colours.label?.isOpaque == false else {
            return buffer
        }
        var result = buffer
        for (layout, columnInLine) in zip(layouts, columns) {
            let start = columnOffset + columnInLine
            // The shortcut, then the label — which carries the separating space, so
            // the two runs together are exactly `visibleWidth` and neither the gap
            // nor the last cell belongs to nobody.
            let shortcutWidth = layout.item.shortcut.strippedLength
            if let claim = OpacityRegion.claim(
                offsetX: start, offsetY: rowOffset, width: shortcutWidth, height: 1,
                ink: colours.highlight)
            {
                result.opacityRegions.append(claim)
            }
            if let claim = OpacityRegion.claim(
                offsetX: start + shortcutWidth, offsetY: rowOffset,
                width: layout.visibleWidth - shortcutWidth, height: 1, ink: colours.label)
            {
                result.opacityRegions.append(claim)
            }
        }
        return result
    }

    private func applyHitTestRegions(
        buffer: FrameBuffer,
        layouts: [ItemLayout],
        columns: [Int],
        columnOffset: Int,
        rowOffset: Int,
        context: RenderContext
    ) -> FrameBuffer {
        guard !context.isMeasuring,
              let dispatcher = context.environment.mouseEventDispatcher,
              layouts.contains(where: { itemIsClickable($0.item) })
        else {
            return buffer
        }
        // Per-frame motion request — the dispatcher only emits
        // .entered / .exited transitions when motion tracking is
        // active.
        dispatcher.requestFeature(.motion)
        guard let statusBarState = context.environment.statusBar else { return buffer }
        let captureSynthesizeKey = context.environment.synthesizeKeyEvent

        var result = buffer
        for (layout, columnInLine) in zip(layouts, columns) {
            guard itemIsClickable(layout.item) else { continue }
            let captureItem = layout.item
            let captureItemID = layout.item.id
            let handlerID = dispatcher.register { event in
                switch event.phase {
                case .entered:
                    statusBarState.hoveredItemID = captureItemID
                    return true
                case .exited:
                    // Only clear if we're the currently-hovered
                    // item — another item's .entered may have
                    // already overwritten the id by the time we
                    // see our own .exited (the dispatcher fires
                    // exit on the old region before enter on the
                    // new, but a re-entry to the same item in a
                    // single frame could race).
                    if statusBarState.hoveredItemID == captureItemID {
                        statusBarState.hoveredItemID = nil
                    }
                    return true
                case .pressed where event.button == .left:
                    return true
                case .released where event.button == .left:
                    // Two click models, picked at runtime per
                    // item: items with an inline action invoke
                    // it directly; items that only have a
                    // triggerKey (system "back" / "quit" /
                    // "show", page-level ESC label entries)
                    // synthesise the corresponding key event
                    // and dispatch it through the same key
                    // chain that responds to a physical
                    // keypress. The mouse path therefore
                    // mirrors the keyboard path exactly — a
                    // click on "back" runs whatever the ESC
                    // handler runs, including page pops the
                    // page system installs.
                    if let concrete = captureItem as? StatusBarItem,
                       concrete.hasAction
                    {
                        captureItem.execute()
                    } else if let triggerKey = captureItem.triggerKey {
                        captureSynthesizeKey?(KeyEvent(key: triggerKey))
                    } else {
                        captureItem.execute()
                    }
                    return true
                default:
                    return false
                }
            }
            result.hitTestRegions.append(
                HitTestRegion(
                    offsetX: columnOffset + columnInLine,
                    offsetY: rowOffset,
                    width: layout.visibleWidth,
                    height: 1,
                    handlerID: handlerID
                )
            )
        }
        return result
    }

    /// Whether an item can respond to a mouse click — either
    /// because it has an explicit action closure, or because
    /// it has a triggerKey that the keyboard handler chain
    /// already responds to. The latter covers system items
    /// like "Back" (esc), "Quit" (q), "Show" (enter), and the
    /// page-level "back" item that pages register as a label
    /// for the global ESC handler: each has a triggerKey but
    /// no inline action, and the mouse handler dispatches the
    /// key event through ``keyEventDispatcher`` so a click is
    /// equivalent to pressing the key.
    private func itemIsClickable(_ item: any StatusBarItemProtocol) -> Bool {
        if let concrete = item as? StatusBarItem {
            return concrete.hasAction || concrete.triggerKey != nil
        }
        return item.triggerKey != nil
    }

    /// Aligns content within the given width based on alignment
    /// setting. Returns the rendered line and the column at
    /// which each input item was placed.
    private func alignContent(layouts: [ItemLayout], width: Int) -> LaidOutLine {
        let separator = "  "  // Two spaces between items for non-justified
        let strings = layouts.map(\.display)
        let widths = layouts.map(\.visibleWidth)

        switch alignment {
        case .leading:
            let content = " " + strings.joined(separator: separator)
            var columns: [Int] = []
            var running = 1  // leading space
            for itemWidth in widths {
                columns.append(running)
                running += itemWidth + separator.count
            }
            return LaidOutLine(
                line: content.padToVisibleWidth(width),
                placedColumns: columns
            )

        case .trailing:
            let content = strings.joined(separator: separator) + " "
            let contentWidth = content.strippedLength
            let padding = max(0, width - contentWidth)
            var columns: [Int] = []
            var running = padding
            for itemWidth in widths {
                columns.append(running)
                running += itemWidth + separator.count
            }
            return LaidOutLine(
                line: String(repeating: " ", count: padding) + content,
                placedColumns: columns
            )

        case .center:
            let content = strings.joined(separator: separator)
            let contentWidth = content.strippedLength
            let totalPadding = max(0, width - contentWidth)
            let leftPadding = totalPadding / 2
            let rightPadding = totalPadding - leftPadding
            var columns: [Int] = []
            var running = leftPadding
            for itemWidth in widths {
                columns.append(running)
                running += itemWidth + separator.count
            }
            let line = String(repeating: " ", count: leftPadding)
                + content
                + String(repeating: " ", count: rightPadding)
            return LaidOutLine(line: line, placedColumns: columns)

        case .justified:
            return justifyContent(layouts: layouts, width: width)
        }
    }

    /// Distributes items evenly across the width (justified alignment).
    /// Returns the rendered line and the column at which each
    /// input item was placed.
    private func justifyContent(layouts: [ItemLayout], width: Int) -> LaidOutLine {
        guard !layouts.isEmpty else {
            return LaidOutLine(
                line: String(repeating: " ", count: width),
                placedColumns: []
            )
        }

        guard layouts.count > 1 else {
            // Single item: center it
            let only = layouts[0]
            let contentWidth = only.visibleWidth
            let totalPadding = max(0, width - contentWidth)
            let leftPadding = totalPadding / 2
            let rightPadding = totalPadding - leftPadding
            let line = String(repeating: " ", count: leftPadding)
                + only.display
                + String(repeating: " ", count: rightPadding)
            return LaidOutLine(line: line, placedColumns: [leftPadding])
        }

        // Calculate total content width (without gaps)
        let totalContentWidth = layouts.reduce(0) { $0 + $1.visibleWidth }

        // For n items, we have n+1 gaps (left edge, between each item, right edge)
        let gapCount = layouts.count + 1
        let availableForGaps = max(0, width - totalContentWidth)
        let gapWidth = availableForGaps / gapCount
        let extraSpace = availableForGaps % gapCount

        // Build justified string with equal gaps, recording each
        // item's starting column as we go.
        var line = ""
        var columns: [Int] = []
        var cursor = 0

        // Left edge gap (gets extra space if available)
        let leftGapExtra = extraSpace > 0 ? 1 : 0
        let leftGap = gapWidth + leftGapExtra
        line += String(repeating: " ", count: leftGap)
        cursor += leftGap

        for (index, layout) in layouts.enumerated() {
            columns.append(cursor)
            line += layout.display
            cursor += layout.visibleWidth

            if index < layouts.count - 1 {
                // Gap between items.
                // Distribute extra space to middle gaps (after left edge took one if available).
                let gapIndex = index + 1  // 0 = left edge, 1..n-1 = between items, n = right edge
                let extra = gapIndex < extraSpace ? 1 : 0
                let gap = gapWidth + extra
                line += String(repeating: " ", count: gap)
                cursor += gap
            }
        }

        // Right edge gap
        let rightGapIndex = layouts.count
        let rightGapExtra = rightGapIndex < extraSpace ? 1 : 0
        line += String(repeating: " ", count: gapWidth + rightGapExtra)

        // Ensure the result fills the width exactly
        return LaidOutLine(
            line: line.padToVisibleWidth(width),
            placedColumns: columns
        )
    }

    /// Renders the compact style (single line with alignment).
    private func renderCompact(layouts: [ItemLayout], width: Int) -> LaidOutBuffer {
        let result = alignContent(layouts: layouts, width: width)
        return LaidOutBuffer(
            buffer: FrameBuffer(lines: [result.line]),
            placedColumns: result.placedColumns
        )
    }

    /// Renders the bordered style using the current appearance's
    /// border style. Reports each item's column relative to the
    /// *inner* content area; the caller offsets by the border
    /// and padding when emitting hit-test regions.
    private func renderBordered(
        layouts: [ItemLayout],
        width: Int,
        context: RenderContext,
        tooltipRows: [String] = [],
        drawsItemRow: Bool = true
    ) -> LaidOutBuffer {
        let contentPadding = 2  // 1 char padding left + right
        let innerWidth = width - BorderRenderer.borderWidthOverhead
        // The same figure `ChromeStyle.barContentWidth` gives the tooltip
        // wrapper, so the rows this boxes are the width it boxes them at.
        let contentWidth = innerWidth - contentPadding
        let aligned = alignContent(layouts: layouts, width: contentWidth)
        let content = " " + aligned.line + " "

        let border = context.environment.appearance.borderStyle
        let borderColor = context.environment.palette.border
        func contentLine(_ text: String) -> String {
            BorderRenderer.standardContentLine(
                content: " " + text + " ", innerWidth: innerWidth, style: border,
                color: borderColor)
        }

        var buffer = FrameBuffer(
            lines: [
                BorderRenderer.standardTopBorder(
                    style: border, innerWidth: innerWidth, color: borderColor)
            ]
                + tooltipRows.map(contentLine)
                + (drawsItemRow
                    ? [
                        BorderRenderer.standardContentLine(
                            content: content, innerWidth: innerWidth, style: border,
                            color: borderColor)
                    ] : [])
                + [
                    BorderRenderer.standardBottomBorder(
                        style: border, innerWidth: innerWidth, color: borderColor)
                ])
        // The chrome's own cells, when the theme's `border` is faded. The items
        // between the walls are coloured by their own styling, which makes its own
        // claims and travels in `aligned.line`.
        buffer.opacityRegions = BorderRenderer.opacityClaims(
            outerWidth: innerWidth + BorderRenderer.borderWidthOverhead,
            height: buffer.lines.count, style: border, color: borderColor)
        return LaidOutBuffer(buffer: buffer, placedColumns: aligned.placedColumns)
    }
}

// MARK: - Status Bar Height Helper

extension StatusBar {
    /// The height of the status bar in lines: its one row of items, any tooltip
    /// rows above them, plus whatever chrome the style draws around it.
    public var height: Int {
        style.barHeight(contentRows: (hasItems ? 1 : 0) + tooltipLines.count)
    }
}
