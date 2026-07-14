//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Menu.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A menu item representing a single selectable option.
public struct MenuItem: Identifiable {
    /// The unique identifier.
    public let id: String

    /// The display label.
    public let label: String

    /// An optional keyboard shortcut (e.g., "1", "a", "q").
    public let shortcut: Character?

    /// Whether this item is a separator rule rather than a selectable option.
    /// See ``divider``.
    public let isDivider: Bool

    /// Creates a menu item.
    ///
    /// - Parameters:
    ///   - id: The unique identifier (defaults to label).
    ///   - label: The display label.
    ///   - shortcut: An optional keyboard shortcut character.
    public init(id: String? = nil, label: String, shortcut: Character? = nil) {
        self.id = id ?? label
        self.label = label
        self.shortcut = shortcut
        self.isDivider = false
    }

    /// A separator rule between groups of items.
    ///
    /// Dividers are purely visual: keyboard navigation skips over them and
    /// clicks on them do nothing.
    ///
    /// - Note: Every divider shares one `id` ("\u{2500}divider\u{2500}"), so
    ///   give dividers explicit identity (`MenuItem(id:label:)` is not it —
    ///   use position) if you diff a menu's items by `id` yourself.
    public static var divider: Self {
        Self(divider: ())
    }

    /// Backs ``divider`` (the public init always creates selectable items).
    private init(divider: Void) {
        self.id = "\u{2500}divider\u{2500}"
        self.label = ""
        self.shortcut = nil
        self.isDivider = true
    }
}

/// A vertical menu displaying a list of selectable items.
///
/// `Menu` renders items as a vertical list with optional shortcuts.
/// The currently selected item is highlighted.
///
/// # Basic Example (Static)
///
/// ```swift
/// Menu(
///     title: "Main Menu",
///     items: [
///         MenuItem(label: "Text Styles", shortcut: "1"),
///         MenuItem(label: "Colors", shortcut: "2"),
///         MenuItem(label: "Quit", shortcut: "q")
///     ],
///     selectedIndex: 0
/// )
/// ```
///
/// # Interactive Example (with Binding)
///
/// ```swift
/// struct ContentView: View {
///     @State var selection = 0
///
///     var body: some View {
///         Menu(
///             title: "Main Menu",
///             items: menuItems,
///             selection: $selection,
///             onSelect: { index in
///                 handleSelection(index)
///             }
///         )
///     }
/// }
/// ```
public struct Menu: View {
    /// The menu title (optional).
    let title: String?

    /// The menu items.
    let items: [MenuItem]

    /// The currently selected item index.
    var selectedIndex: Int

    /// Binding to the selection (for interactive menus).
    private let selectionBinding: Binding<Int>?

    /// Callback when an item is selected (Enter or shortcut).
    private let onSelect: ((Int) -> Void)?

    /// The style for unselected items.
    let itemColor: Color?

    /// The style for the selected item.
    let selectedColor: Color?

    /// The indicator for the selected item.
    let selectionIndicator: String

    /// The border style (nil for no border).
    let borderStyle: BorderStyle?

    /// The border color.
    let borderColor: Color?

    /// Creates a static menu (non-interactive).
    ///
    /// - Parameters:
    ///   - title: The menu title (optional).
    ///   - items: The menu items.
    ///   - selectedIndex: The currently selected item index (default: 0).
    ///   - itemColor: The color for unselected items (default: theme foreground).
    ///   - selectedColor: The color for the selected item (default: theme accent).
    ///   - selectionIndicator: The indicator shown before selected item (default: "▶ ").
    ///   - borderStyle: The border style (default: appearance borderStyle, nil for no border).
    ///   - borderColor: The border color (default: theme border).
    public init(
        title: String? = nil,
        items: [MenuItem],
        selectedIndex: Int = 0,
        itemColor: Color? = nil,
        selectedColor: Color? = nil,
        selectionIndicator: String = "▶ ",
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil
    ) {
        self.title = title
        self.items = items
        self.selectedIndex = max(0, min(selectedIndex, items.count - 1))
        self.selectionBinding = nil
        self.onSelect = nil
        self.itemColor = itemColor
        self.selectedColor = selectedColor
        self.selectionIndicator = selectionIndicator
        self.borderStyle = borderStyle
        self.borderColor = borderColor
    }

    /// Creates an interactive menu with selection binding.
    ///
    /// - Parameters:
    ///   - title: The menu title (optional).
    ///   - items: The menu items.
    ///   - selection: Binding to the selected index.
    ///   - onSelect: Callback when item is activated (Enter or shortcut).
    ///   - itemColor: The color for unselected items (default: theme foreground).
    ///   - selectedColor: The color for the selected item (default: theme accent).
    ///   - selectionIndicator: The indicator shown before selected item (default: "▶ ").
    ///   - borderStyle: The border style (default: appearance borderStyle, nil for no border).
    ///   - borderColor: The border color (default: theme border).
    public init(
        title: String? = nil,
        items: [MenuItem],
        selection: Binding<Int>,
        onSelect: ((Int) -> Void)? = nil,
        itemColor: Color? = nil,
        selectedColor: Color? = nil,
        selectionIndicator: String = "▶ ",
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil
    ) {
        self.title = title
        self.items = items
        self.selectedIndex = max(0, min(selection.wrappedValue, items.count - 1))
        self.selectionBinding = selection
        self.onSelect = onSelect
        self.itemColor = itemColor
        self.selectedColor = selectedColor
        self.selectionIndicator = selectionIndicator
        self.borderStyle = borderStyle
        self.borderColor = borderColor
    }

    public var body: some View {
        _MenuCore(
            title: title,
            items: items,
            selectedIndex: selectedIndex,
            selectionBinding: selectionBinding,
            onSelect: onSelect,
            itemColor: itemColor,
            selectedColor: selectedColor,
            selectionIndicator: selectionIndicator,
            borderStyle: borderStyle,
            borderColor: borderColor
        )
    }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of Menu.
private struct _MenuCore: View, Renderable, Layoutable {
    let title: String?
    let items: [MenuItem]
    let selectedIndex: Int
    let selectionBinding: Binding<Int>?
    let onSelect: ((Int) -> Void)?
    let itemColor: Color?
    let selectedColor: Color?
    let selectionIndicator: String
    let borderStyle: BorderStyle?
    let borderColor: Color?

    var body: Never {
        fatalError("_MenuCore renders via Renderable")
    }

    /// A menu sizes to its widest item / title (it does not fill), so a single
    /// render is its exact, fixed measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette

        // Register key handlers if this is an interactive menu
        if let binding = selectionBinding {
            registerKeyHandlers(binding: binding, context: context)
        }

        // The selection-indicator column: the indicator on the selected row,
        // same-width spaces on every other row, so labels stay aligned. An
        // empty indicator collapses the column entirely.
        let indicatorWidth = selectionIndicator.strippedLength

        // Calculate the content width for full-width selection bar
        let contentWidth = indicatorWidth + maxItemWidth + 2  // +2 for padding

        let currentSelection = selectionBinding?.wrappedValue ?? selectedIndex

        // The title block (title + divider) is fixed at the top and never
        // scrolls. A blank/whitespace title is treated as no title.
        var titleLines: [String] = []
        if let menuTitle = title, !menuTitle.allSatisfy(\.isWhitespace) {
            var titleStyle = TextStyle()
            titleStyle.isBold = true
            titleStyle.foregroundColor = selectedColor?.resolve(with: palette) ?? palette.accent
            titleLines.append(" " + ANSIRenderer.render(menuTitle, with: titleStyle))
            titleLines.append("")  // divider placeholder
        }

        // One styled row per menu item (a `.divider` becomes a blank placeholder
        // the border turns into a rule); `item` is the item index, `nil` for a
        // divider, so a click / the window can map a row back to its item.
        var itemRows: [(item: Int?, line: String)] = []
        for (index, item) in items.enumerated() {
            if item.isDivider {
                itemRows.append((nil, ""))
                continue
            }
            let isSelected = index == currentSelection
            let labelText = item.shortcut.map { "[\($0)] \(item.label)" } ?? "    \(item.label)"
            let marker = isSelected ? selectionIndicator : String(repeating: " ", count: indicatorWidth)
            let fullText = " " + marker + labelText
            let padding = max(0, contentWidth - fullText.strippedLength)
            let paddedText = fullText + String(repeating: " ", count: padding)

            var style = TextStyle()
            if isSelected {
                style.isBold = true
                style.foregroundColor = selectedColor?.resolve(with: palette) ?? palette.accent
            } else {
                style.foregroundColor = itemColor?.resolve(with: palette) ?? palette.foreground
            }
            itemRows.append((index, ANSIRenderer.render(paddedText, with: style)))
        }

        // Window the item rows to the available height, keeping the selected row
        // visible. A menu taller than its viewport shows ▲/▼ overflow markers and
        // scrolls as the selection moves — so every item is reachable on a short
        // terminal. The border eats 2 rows and the title block eats its own.
        let itemBudget = max(1, context.availableHeight - 2 - titleLines.count)
        let window = Self.windowedRows(itemRows, budget: itemBudget, selection: currentSelection)

        // Assemble the content lines plus a parallel item-index map (for clicks):
        // title lines, an optional ▲, the visible item rows, an optional ▼.
        var lines: [String] = []
        var lineItemIndex: [Int?] = []
        var dividerLineIndices: Set<Int> = []
        for (offset, tline) in titleLines.enumerated() {
            if offset == 1 { dividerLineIndices.insert(lines.count) }  // title divider
            lines.append(tline)
            lineItemIndex.append(nil)
        }
        if window.hasAbove {
            lines.append(Self.overflowMarker("▲", width: contentWidth, palette: palette))
            lineItemIndex.append(nil)
        }
        for row in window.rows {
            if row.item == nil { dividerLineIndices.insert(lines.count) }
            lines.append(row.line)
            lineItemIndex.append(row.item)
        }
        if window.hasBelow {
            lines.append(Self.overflowMarker("▼", width: contentWidth, palette: palette))
            lineItemIndex.append(nil)
        }

        var contentBuffer = FrameBuffer(lines: lines)
        let effectiveBorderStyle = borderStyle ?? context.environment.appearance.borderStyle
        contentBuffer = applyBorder(
            to: contentBuffer,
            style: effectiveBorderStyle,
            color: borderColor,
            dividerLineIndices: dividerLineIndices,
            palette: palette
        )

        registerMouseHandlers(on: &contentBuffer, context: context, lineItemIndex: lineItemIndex)

        return contentBuffer
    }

    /// A centred ▲ / ▼ overflow marker line (tertiary colour), padded to the
    /// menu's content width so it aligns with the item rows.
    private static func overflowMarker(_ glyph: String, width: Int, palette: any Palette)
        -> String
    {
        let leftPad = max(0, (width - 1) / 2)
        let rightPad = max(0, width - 1 - leftPad)
        var style = TextStyle()
        style.foregroundColor = palette.foregroundTertiary
        return ANSIRenderer.render(
            String(repeating: " ", count: leftPad) + glyph + String(repeating: " ", count: rightPad),
            with: style)
    }

    /// The slice of `rows` to show for a `budget`-row viewport, keeping the
    /// `selection` row visible. Returns the full list (no markers) when it fits;
    /// otherwise a window centred on the selection with `hasAbove`/`hasBelow`
    /// flags for the ▲/▼ markers (each marker consumes one budget row).
    private static func windowedRows(
        _ rows: [(item: Int?, line: String)], budget: Int, selection: Int
    ) -> (rows: ArraySlice<(item: Int?, line: String)>, hasAbove: Bool, hasBelow: Bool) {
        guard rows.count > budget else { return (rows[...], false, false) }
        let selRow = rows.firstIndex { $0.item == selection } ?? 0
        func clampStart(_ visible: Int) -> Int {
            max(0, min(selRow - visible / 2, rows.count - visible))
        }
        // First pass with the full budget tells us which edges overflow; the
        // second reclaims the rows the markers that WILL show would occupy.
        var start = clampStart(budget)
        var hasAbove = start > 0
        var hasBelow = start + budget < rows.count
        let visible = max(1, budget - (hasAbove ? 1 : 0) - (hasBelow ? 1 : 0))
        start = clampStart(visible)
        hasAbove = start > 0
        hasBelow = start + visible < rows.count
        return (rows[start..<start + visible], hasAbove, hasBelow)
    }

    /// Mouse: scroll-wheel anywhere on the menu changes selection (which
    /// re-windows a tall menu to follow it); a left-click on an item row selects
    /// it. `lineItemIndex` maps each content line (title / ▲ / item / ▼) back to
    /// its item index, so windowing and dividers can't misroute a click.
    private func registerMouseHandlers(
        on contentBuffer: inout FrameBuffer, context: RenderContext, lineItemIndex: [Int?]
    ) {
        guard !context.isMeasuring,
            let binding = selectionBinding,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let menuItems = items
        let selectCallback = onSelect
        // The border adds a top row, so content line `n` sits at buffer y `n+1`.
        func itemAt(_ y: Int) -> Int? {
            let line = y - 1
            guard line >= 0, line < lineItemIndex.count else { return nil }
            return lineItemIndex[line]
        }
        let mouseHandlerID = mouseDispatcher.register { event in
            switch event.button {
            case .scrollUp:
                binding.wrappedValue = Self.nextSelectableIndex(
                    from: binding.wrappedValue, by: -1, in: menuItems)
                return true
            case .scrollDown:
                binding.wrappedValue = Self.nextSelectableIndex(
                    from: binding.wrappedValue, by: 1, in: menuItems)
                return true
            case .left where event.phase == .released:
                if let itemIndex = itemAt(event.y) {
                    binding.wrappedValue = itemIndex
                    selectCallback?(itemIndex)
                    return true
                }
                return false
            case .left where event.phase == .pressed:
                // Claim presses on item rows so the matching release routes back
                // here for the activation above. (Marker / divider rows are inert.)
                return itemAt(event.y) != nil
            default:
                return false
            }
        }
        contentBuffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: contentBuffer.width,
                height: contentBuffer.height,
                handlerID: mouseHandlerID
            )
        )
    }

    /// Registers key handlers for menu navigation.
    private func registerKeyHandlers(binding: Binding<Int>, context: RenderContext) {
        let menuItems = items
        let selectCallback = onSelect

        context.environment.keyEventDispatcher!.addHandler { event in
            switch event.key {
            case .up:
                // Move selection up, wrapping and skipping dividers
                binding.wrappedValue = Self.nextSelectableIndex(
                    from: binding.wrappedValue, by: -1, in: menuItems)
                return true

            case .down:
                // Move selection down, wrapping and skipping dividers
                binding.wrappedValue = Self.nextSelectableIndex(
                    from: binding.wrappedValue, by: 1, in: menuItems)
                return true

            case .enter:
                // Select current item
                selectCallback?(binding.wrappedValue)
                return true

            case .character(let character):
                // Check for shortcut
                for (index, item) in menuItems.enumerated() {
                    if let shortcut = item.shortcut,
                        shortcut.lowercased() == character.lowercased()
                    {
                        binding.wrappedValue = index
                        selectCallback?(index)
                        return true
                    }
                }
                return false

            default:
                return false
            }
        }
    }

    /// The next selectable index from `current`, stepping by `delta` with
    /// wrap-around and skipping dividers. Returns `current` unchanged when
    /// the menu has no selectable items.
    private static func nextSelectableIndex(
        from current: Int, by delta: Int, in items: [MenuItem]
    ) -> Int {
        guard items.contains(where: { !$0.isDivider }) else { return current }
        var index = current
        repeat {
            index = (index + delta + items.count) % items.count
        } while items[index].isDivider
        return index
    }

    /// The maximum width of menu items (for sizing).
    private var maxItemWidth: Int {
        items.map { item -> Int in
            let shortcutPart = 4  // "[x] " or "    " — always 4 characters wide
            return shortcutPart + item.label.strippedLength
        }.max() ?? 0
    }

    /// Applies a border to the buffer.
    ///
    /// - Parameters:
    ///   - buffer: The content buffer to wrap with border.
    ///   - style: The border style to use.
    ///   - color: The border color (optional).
    ///   - dividerLineIndices: Line indices rendered as horizontal dividers with T-junctions.
    private func applyBorder(
        to buffer: FrameBuffer,
        style: BorderStyle,
        color: Color?,
        dividerLineIndices: Set<Int> = [],
        palette: any Palette
    ) -> FrameBuffer {
        guard !buffer.isEmpty else { return buffer }

        let innerWidth = buffer.width
        let borderForeground = color?.resolve(with: palette) ?? palette.border
        var result: [String] = []

        result.append(BorderRenderer.standardTopBorder(style: style, innerWidth: innerWidth, color: borderForeground))

        for (index, line) in buffer.lines.enumerated() {
            if dividerLineIndices.contains(index) {
                result.append(BorderRenderer.standardDivider(style: style, innerWidth: innerWidth, color: borderForeground))
            } else {
                result.append(
                    BorderRenderer.standardContentLine(
                        content: line,
                        innerWidth: innerWidth,
                        style: style,
                        color: borderForeground
                    )
                )
            }
        }

        result.append(BorderRenderer.standardBottomBorder(style: style, innerWidth: innerWidth, color: borderForeground))

        // The border adds a top row and a leading column, so content
        // shifted right by 1 and down by 1. Carry overlays and hit-
        // test regions by the same amount — bare FrameBuffer(lines:)
        // would drop them, breaking clicks on menu items inside the
        // bordered menu.
        return buffer.replacingLines(result, overlayShiftX: 1, overlayShiftY: 1)
    }
}

// MARK: - AnyView Helper
