//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBar.swift
//
//  Created by LAYERED.work
//  License: MIT  Always rendered at the bottom of the terminal, never dimmed by overlays.
//

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
    public let style: StatusBarStyle

    /// The horizontal alignment of user items within the left container.
    public let alignment: StatusBarAlignment

    /// The highlight color for shortcut keys.
    public let highlightColor: Color

    /// The label color.
    public let labelColor: Color?

    /// Creates a status bar with separate user and system items.
    ///
    /// - Parameters:
    ///   - userItems: User-defined items (left container).
    ///   - systemItems: System items (right container).
    ///   - style: The visual style (default: `.compact`).
    ///   - alignment: The alignment of user items (default: `.leading`).
    ///   - highlightColor: The color for shortcut keys (default: `.cyan`).
    ///   - labelColor: The color for labels (default: nil, terminal default).
    public init(
        userItems: [any StatusBarItemProtocol] = [],
        systemItems: [any StatusBarItemProtocol] = [],
        style: StatusBarStyle = .compact,
        alignment: StatusBarAlignment = .leading,
        highlightColor: Color = .cyan,
        labelColor: Color? = nil
    ) {
        self.userItems = userItems
        self.systemItems = systemItems
        self.style = style
        self.alignment = alignment
        self.highlightColor = highlightColor
        self.labelColor = labelColor
    }

    /// Creates a status bar with all items combined (legacy compatibility).
    ///
    /// - Parameters:
    ///   - items: All items to display (will be treated as user items).
    ///   - style: The visual style (default: `.compact`).
    ///   - alignment: The horizontal alignment (default: `.justified`).
    ///   - highlightColor: The color for shortcut keys (default: `.cyan`).
    ///   - labelColor: The color for labels (default: nil, terminal default).
    public init(
        items: [any StatusBarItemProtocol],
        style: StatusBarStyle = .compact,
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
        style: StatusBarStyle = .compact,
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
            labelColor: labelColor
        )
    }
}

// MARK: - StatusBar Core (Private Renderable)

/// Private rendering core for ``StatusBar``.
///
/// Handles all procedural ANSI rendering and buffer assembly.
/// Public ``StatusBar`` delegates to this via its `body`.
private struct _StatusBarCore: View, Renderable {
    let userItems: [any StatusBarItemProtocol]
    let systemItems: [any StatusBarItemProtocol]
    let style: StatusBarStyle
    let alignment: StatusBarAlignment
    let highlightColor: Color
    let labelColor: Color?

    var body: Never {
        fatalError("_StatusBarCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Get shortcuts used by user items (for deduplication)
        let userShortcuts = Set(userItems.map { $0.shortcut })

        // Filter out system items that are overridden by user items
        let filteredSystemItems = systemItems.filter { !userShortcuts.contains($0.shortcut) }

        // Combine: sorted user items + filtered system items (fixed order)
        let sortedUserItems = userItems.sorted { $0.order < $1.order }
        let combinedItems = sortedUserItems + filteredSystemItems

        guard !combinedItems.isEmpty else {
            return FrameBuffer()
        }

        // Pull the transient escape-label override (set by an open Picker
        // drop-down, an inline editor, etc.) so the escape entry shows
        // "close menu" or similar while the underlying handler is unchanged.
        let escapeOverride = context.environment.statusBar.escapeLabelOverride

        // Build item strings and capture their visible widths
        // so the layout pass can also report each item's column
        // range in the rendered line — used below to emit mouse
        // hit-test regions for clickable items.
        let layouts = combinedItems.map { item -> ItemLayout in
            let display = renderItemString(
                item: item,
                escapeOverride: escapeOverride
            )
            return ItemLayout(
                item: item,
                display: display,
                visibleWidth: display.strippedLength
            )
        }

        let buffer: FrameBuffer
        let itemColumnOffset: Int
        let itemRowOffset: Int

        switch style {
        case .compact:
            let result = renderCompact(layouts: layouts, width: context.availableWidth)
            buffer = result.buffer
            itemColumnOffset = 0
            itemRowOffset = 0
            // The placed columns on `result.placedColumns` are
            // already absolute on a single-row compact bar.
            return applyHitTestRegions(
                buffer: buffer,
                layouts: layouts,
                columns: result.placedColumns,
                columnOffset: itemColumnOffset,
                rowOffset: itemRowOffset,
                context: context
            )

        case .bordered:
            let result = renderBordered(
                layouts: layouts,
                width: context.availableWidth,
                context: context
            )
            buffer = result.buffer
            // The bordered renderer reports columns relative to
            // the inner content; offset by the border + the
            // single-space content padding it added on the left.
            itemColumnOffset = 1 + 1
            itemRowOffset = 1
            return applyHitTestRegions(
                buffer: buffer,
                layouts: layouts,
                columns: result.placedColumns,
                columnOffset: itemColumnOffset,
                rowOffset: itemRowOffset,
                context: context
            )
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

    /// Renders a single item's `shortcut + " " + label` with the
    /// configured highlight / label colors and the escape-label
    /// override.
    private func renderItemString(
        item: any StatusBarItemProtocol,
        escapeOverride: String?
    ) -> String {
        let shortcutStyled = ANSIRenderer.render(
            item.shortcut,
            with: {
                var textStyle = TextStyle()
                textStyle.foregroundColor = highlightColor
                textStyle.isBold = true
                return textStyle
            }()
        )

        // Apply the modal escape-label override only to items bound to
        // the escape key; everything else keeps its declared label.
        let effectiveLabel: String
        if item.shortcut == Shortcut.escape, let override = escapeOverride {
            effectiveLabel = override
        } else {
            effectiveLabel = item.label
        }

        let labelStyled: String
        if let color = labelColor {
            labelStyled = ANSIRenderer.render(
                " " + effectiveLabel,
                with: {
                    var textStyle = TextStyle()
                    textStyle.foregroundColor = color
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
              layouts.contains(where: { itemHasAction($0.item) })
        else {
            return buffer
        }

        var result = buffer
        for (layout, columnInLine) in zip(layouts, columns) {
            guard itemHasAction(layout.item) else { continue }
            let captureItem = layout.item
            let handlerID = dispatcher.register { event in
                guard event.button == .left else { return false }
                switch event.phase {
                case .pressed:
                    return true
                case .released:
                    captureItem.execute()
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

    /// Whether an item has a meaningful action to invoke. For
    /// concrete StatusBarItems we can read hasAction directly;
    /// for other conformers we assume any non-informational item
    /// (i.e. one with a triggerKey) is clickable.
    private func itemHasAction(_ item: any StatusBarItemProtocol) -> Bool {
        if let concrete = item as? StatusBarItem { return concrete.hasAction }
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
        context: RenderContext
    ) -> LaidOutBuffer {
        let contentPadding = 2  // 1 char padding left + right
        let innerWidth = width - BorderRenderer.borderWidthOverhead
        let contentWidth = innerWidth - contentPadding
        let aligned = alignContent(layouts: layouts, width: contentWidth)
        let content = " " + aligned.line + " "

        let border = context.environment.appearance.borderStyle
        let borderColor = context.environment.palette.border

        let buffer = FrameBuffer(lines: [
            BorderRenderer.standardTopBorder(style: border, innerWidth: innerWidth, color: borderColor),
            BorderRenderer.standardContentLine(content: content, innerWidth: innerWidth, style: border, color: borderColor),
            BorderRenderer.standardBottomBorder(style: border, innerWidth: innerWidth, color: borderColor),
        ])
        return LaidOutBuffer(buffer: buffer, placedColumns: aligned.placedColumns)
    }
}

// MARK: - Status Bar Height Helper

extension StatusBar {
    /// The height of the status bar in lines.
    public var height: Int {
        switch style {
        case .compact:
            return 1
        case .bordered:
            return 3
        }
    }
}
