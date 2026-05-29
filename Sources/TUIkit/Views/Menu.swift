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
private struct _MenuCore: View, Renderable {
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

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette

        // Register key handlers if this is an interactive menu
        if let binding = selectionBinding {
            registerKeyHandlers(binding: binding, context: context)
        }

        var lines: [String] = []

        // Calculate the content width for full-width selection bar
        let contentWidth = maxItemWidth + 2  // +2 for padding

        // Track the divider line index (for T-junction rendering)
        var dividerLineIndex: Int?

        // Title if present
        if let menuTitle = title {
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
            dividerLineIndex = lines.count
            lines.append("")  // Placeholder for divider
        }

        // Menu items
        let currentSelection = selectionBinding?.wrappedValue ?? selectedIndex

        for (index, item) in items.enumerated() {
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
            dividerLineIndex: dividerLineIndex,
            palette: palette
        )

        // Mouse: scroll-wheel anywhere on the menu changes selection;
        // a left-click on an item row selects it. Item rows live inside
        // the border (top border + title/divider if present), so we
        // translate the buffer-relative y back to an item index before
        // forwarding the event.
        if !context.isMeasuring,
            let binding = selectionBinding,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            let menuItems = items
            let selectCallback = onSelect
            let itemsStartRow = 1 + (title != nil ? 2 : 0)  // top border + (title + divider)
            let mouseHandlerID = mouseDispatcher.register { event in
                switch event.button {
                case .scrollUp:
                    let current = binding.wrappedValue
                    binding.wrappedValue = current > 0 ? current - 1 : menuItems.count - 1
                    return true
                case .scrollDown:
                    let current = binding.wrappedValue
                    binding.wrappedValue = current < menuItems.count - 1 ? current + 1 : 0
                    return true
                case .left where event.phase == .released:
                    let itemIndex = event.y - itemsStartRow
                    if itemIndex >= 0 && itemIndex < menuItems.count {
                        binding.wrappedValue = itemIndex
                        selectCallback?(itemIndex)
                        return true
                    }
                    return false
                case .left where event.phase == .pressed:
                    // Claim presses inside item rows so the matching
                    // release routes back here for the activation above.
                    let itemIndex = event.y - itemsStartRow
                    return itemIndex >= 0 && itemIndex < menuItems.count
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

        return contentBuffer
    }

    /// Registers key handlers for menu navigation.
    private func registerKeyHandlers(binding: Binding<Int>, context: RenderContext) {
        let itemCount = items.count
        let menuItems = items
        let selectCallback = onSelect

        context.environment.keyEventDispatcher!.addHandler { event in
            switch event.key {
            case .up:
                // Move selection up
                let current = binding.wrappedValue
                if current > 0 {
                    binding.wrappedValue = current - 1
                } else {
                    binding.wrappedValue = itemCount - 1  // Wrap to bottom
                }
                return true

            case .down:
                // Move selection down
                let current = binding.wrappedValue
                if current < itemCount - 1 {
                    binding.wrappedValue = current + 1
                } else {
                    binding.wrappedValue = 0  // Wrap to top
                }
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
    ///   - dividerLineIndex: If set, renders a horizontal divider with T-junctions at this line index.
    private func applyBorder(
        to buffer: FrameBuffer,
        style: BorderStyle,
        color: Color?,
        dividerLineIndex: Int? = nil,
        palette: any Palette
    ) -> FrameBuffer {
        guard !buffer.isEmpty else { return buffer }

        let innerWidth = buffer.width
        let borderForeground = color?.resolve(with: palette) ?? palette.border
        var result: [String] = []

        result.append(BorderRenderer.standardTopBorder(style: style, innerWidth: innerWidth, color: borderForeground))

        for (index, line) in buffer.lines.enumerated() {
            if let dividerIndex = dividerLineIndex, index == dividerIndex {
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
