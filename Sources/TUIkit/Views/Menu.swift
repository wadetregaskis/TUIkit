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

        var lines: [String] = []

        // Calculate the content width for full-width selection bar
        let contentWidth = maxItemWidth + 2  // +2 for padding

        // Track divider line indices (for T-junction rendering): the rule
        // under the title, plus any `.divider` items.
        var dividerLineIndices: Set<Int> = []

        // Title if present (a blank/whitespace title is treated as no title —
        // otherwise it would reserve an empty title row plus a divider).
        if let menuTitle = title, !menuTitle.allSatisfy(\.isWhitespace) {
            let titleStyled = ANSIRenderer.render(
                menuTitle,
                with: {
                    var style = TextStyle()
                    style.isBold = true
                    style.foregroundColor = selectedColor?.resolve(with: palette) ?? palette.accent
                    return style
                }()
            )
            lines.append(" " + titleStyled)

            // Mark divider position - actual divider will be rendered by applyBorder
            dividerLineIndices.insert(lines.count)
            lines.append("")  // Placeholder for divider
        }

        // Menu items
        let currentSelection = selectionBinding?.wrappedValue ?? selectedIndex

        for (index, item) in items.enumerated() {
            if item.isDivider {
                // A separator rule between item groups — rendered by
                // applyBorder with T-junctions, skipped by navigation.
                dividerLineIndices.insert(lines.count)
                lines.append("")  // Placeholder for divider
                continue
            }
            let isSelected = index == currentSelection

            // Build the label with optional shortcut
            let labelText: String
            if let shortcut = item.shortcut {
                labelText = "[\(shortcut)] \(item.label)"
            } else {
                labelText = "    \(item.label)"
            }

            // Build the full text with padding
            let fullText = " " + labelText

            // Pad to full width for selection bar
            let visibleLength = fullText.strippedLength
            let padding = max(0, contentWidth - visibleLength)
            let paddedText = fullText + String(repeating: " ", count: padding)

            // Apply styling
            var style = TextStyle()
            if isSelected {
                // Selected: bold text with dimmed background, highlighted foreground
                style.isBold = true
                style.foregroundColor = selectedColor?.resolve(with: palette) ?? palette.accent
                // Selected items have no special background — bold + accent is enough
            } else {
                // Use palette foreground color if no custom itemColor is set
                style.foregroundColor = itemColor?.resolve(with: palette) ?? palette.foreground
            }

            let styledLine = ANSIRenderer.render(paddedText, with: style)
            lines.append(styledLine)
        }

        // Create content buffer
        var contentBuffer = FrameBuffer(lines: lines)

        // Apply border — use explicit style, or fall back to appearance default
        let effectiveBorderStyle = borderStyle ?? context.environment.appearance.borderStyle

        contentBuffer = applyBorder(
            to: contentBuffer,
            style: effectiveBorderStyle,
            color: borderColor,
            dividerLineIndices: dividerLineIndices,
            palette: palette
        )

        registerMouseHandlers(on: &contentBuffer, context: context)

        return contentBuffer
    }

    /// Mouse: scroll-wheel anywhere on the menu changes selection; a
    /// left-click on an item row selects it. Item rows live inside the border
    /// (top border + title/divider if present), so the buffer-relative y is
    /// translated back to an item index before forwarding the event.
    private func registerMouseHandlers(
        on contentBuffer: inout FrameBuffer, context: RenderContext
    ) {
        guard !context.isMeasuring,
            let binding = selectionBinding,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let menuItems = items
        let selectCallback = onSelect
        let itemsStartRow = 1 + (title != nil ? 2 : 0)  // top border + (title + divider)
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
                let itemIndex = event.y - itemsStartRow
                if itemIndex >= 0 && itemIndex < menuItems.count,
                    !menuItems[itemIndex].isDivider
                {
                    binding.wrappedValue = itemIndex
                    selectCallback?(itemIndex)
                    return true
                }
                return false
            case .left where event.phase == .pressed:
                // Claim presses inside item rows so the matching
                // release routes back here for the activation above.
                // (Divider rows are inert, so their presses fall through.)
                let itemIndex = event.y - itemsStartRow
                return itemIndex >= 0 && itemIndex < menuItems.count
                    && !menuItems[itemIndex].isDivider
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
