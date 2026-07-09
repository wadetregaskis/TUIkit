//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RadioButton.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Radio Button Orientation

/// Defines the layout direction of a radio button group.
public enum RadioButtonOrientation: Sendable {
    /// Items stacked vertically (default).
    case vertical

    /// Items arranged horizontally.
    case horizontal
}

// MARK: - Radio Button Item

/// A single option in a radio button group.
///
/// Contains a value (for selection binding) and a label view.
public struct RadioButtonItem<Value: Hashable> {
    /// The value associated with this option.
    let value: Value

    /// The label view builder.
    let labelBuilder: @MainActor () -> AnyView

    /// Creates a radio button item with a view label.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - label: A view builder closure that returns the label.
    @MainActor
    public init<Label: View>(
        _ value: Value,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.value = value
        self.labelBuilder = { AnyView(label()) }
    }

    /// Creates a radio button item with a string label.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - label: The label text.
    @MainActor
    public init(
        _ value: Value,
        _ label: String
    ) {
        self.value = value
        self.labelBuilder = { AnyView(Text(label)) }
    }
}

// MARK: - Radio Button Group Builder

/// A result builder that constructs arrays of radio button items for use in ``RadioButtonGroup``.
///
/// `RadioButtonGroupBuilder` enables the declarative syntax for defining multiple
/// options within a ``RadioButtonGroup``. You don't use this type directly; instead,
/// the `@RadioButtonGroupBuilder` attribute is applied to the trailing closure of
/// ``RadioButtonGroup/init(selection:orientation:isDisabled:builder:)``.
///
/// ## Overview
///
/// When you write:
///
/// ```swift
/// RadioButtonGroup(selection: $choice) {
///     RadioButtonItem(.option1, "First Option")
///     RadioButtonItem(.option2, "Second Option")
///     RadioButtonItem(.option3, "Third Option")
/// }
/// ```
///
/// The `@RadioButtonGroupBuilder` attribute transforms this closure into an array
/// of ``RadioButtonItem`` instances that the group can render and manage.
///
/// ## Supported Control Flow
///
/// The builder supports:
/// - Multiple item expressions
/// - `if`/`else` conditionals
/// - `if let` optional binding
/// - `for`...`in` loops
@resultBuilder
public enum RadioButtonGroupBuilder<Value: Hashable> {
    public static func buildBlock(_ items: RadioButtonItem<Value>...) -> [RadioButtonItem<Value>] {
        Array(items)
    }

    public static func buildOptional(_ items: [RadioButtonItem<Value>]?) -> [RadioButtonItem<Value>] {
        items ?? []
    }

    public static func buildEither(first items: [RadioButtonItem<Value>]) -> [RadioButtonItem<Value>] {
        items
    }

    public static func buildEither(second items: [RadioButtonItem<Value>]) -> [RadioButtonItem<Value>] {
        items
    }

    public static func buildArray(_ itemGroups: [[RadioButtonItem<Value>]]) -> [RadioButtonItem<Value>] {
        itemGroups.flatMap { $0 }
    }
}

// MARK: - Radio Button Group

/// An interactive radio button group for single-selection from multiple options.
///
/// Radio buttons can be arranged vertically or horizontally. Each option is focusable
/// and supports keyboard navigation with arrow keys. Selection can be changed with Enter or Space.
///
/// ## Rendering
///
/// Vertical layout:
/// ```
/// ◯ Option 1
/// ● Option 2  (selected)
/// ◯ Option 3
/// ```
///
/// Horizontal layout:
/// ```
/// ◯ Option 1  ● Option 2  ◯ Option 3
/// ```
///
/// # Basic Example
///
/// ```swift
/// @State var selection: String = "option1"
///
/// RadioButtonGroup(selection: $selection) {
///     RadioButtonItem("option1") { Text("First Choice") }
///     RadioButtonItem("option2") { Text("Second Choice") }
///     RadioButtonItem("option3") { Text("Third Choice") }
/// }
/// ```
public struct RadioButtonGroup<Value: Hashable>: View {
    /// The binding to the selected value.
    let selection: Binding<Value>

    /// The items in the group.
    let items: [RadioButtonItem<Value>]

    /// The layout orientation.
    let orientation: RadioButtonOrientation

    /// The unique focus identifier for the group.
    /// Auto-generated if not provided, but must be stable across renders.
    var focusID: String?

    /// Whether the group is disabled.
    var isDisabled: Bool

    /// Creates a radio button group with items and a selection binding.
    ///
    /// - Parameters:
    ///   - selection: A binding to the selected value.
    ///   - orientation: The layout orientation (default: `.vertical`).
    ///   - isDisabled: Whether the group is disabled (default: false).
    ///   - builder: A builder closure that returns radio button items.
    public init(
        selection: Binding<Value>,
        orientation: RadioButtonOrientation = .vertical,
        isDisabled: Bool = false,
        @RadioButtonGroupBuilder<Value> builder: () -> [RadioButtonItem<Value>]
    ) {
        self.selection = selection
        self.items = builder()
        self.orientation = orientation
        self.focusID = nil
        self.isDisabled = isDisabled
    }

    /// Creates a radio button group from a pre-built array of items.
    ///
    /// Framework-internal: used by ``Picker`` to build a group from options
    /// it has already extracted, bypassing the result builder (which only
    /// accepts statically-listed items).
    init(
        selection: Binding<Value>,
        orientation: RadioButtonOrientation = .vertical,
        isDisabled: Bool = false,
        items: [RadioButtonItem<Value>]
    ) {
        self.selection = selection
        self.items = items
        self.orientation = orientation
        self.focusID = nil
        self.isDisabled = isDisabled
    }

    public var body: some View {
        _RadioButtonGroupCore(
            selection: selection,
            items: items,
            orientation: orientation,
            focusID: focusID,
            isDisabled: isDisabled
        )
    }
}

// MARK: - Internal Core View

/// StateStorage property indices for ``_RadioButtonGroupCore``.
/// Lifted out of the generic struct because Swift does not
/// allow static stored properties in generic types.
private enum RadioButtonGroupStateIndex {
    static let handler = 0
    static let focusID = 1
    /// The index of the currently hovered item, or `-1` for
    /// none. A single shared StateBox covers the whole group
    /// because at most one item can be hovered at a time.
    static let hoveredIndex = 2
}

/// Internal view that handles the actual rendering of RadioButtonGroup.
private struct _RadioButtonGroupCore<Value: Hashable>: View, Renderable, Layoutable {
    let selection: Binding<Value>
    let items: [RadioButtonItem<Value>]
    let orientation: RadioButtonOrientation
    let focusID: String?
    let isDisabled: Bool

    private typealias StateIndex = RadioButtonGroupStateIndex

    var body: Never {
        fatalError("_RadioButtonGroupCore renders via Renderable")
    }

    /// A radio group is fixed: its options lay out at their natural size (it does
    /// not fill), so a single render is its exact, fixed measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!

        // Create type-erased selection binding and item values
        let erasedSelection = Binding<AnyHashable>(
            get: { AnyHashable(selection.wrappedValue) },
            set: { newValue in
                if let typedValue = newValue.base as? Value {
                    selection.wrappedValue = typedValue
                }
            }
        )
        let itemValues = items.map { AnyHashable($0.value) }

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "radio-group",
            propertyIndex: StateIndex.focusID
        )

        // Get or create persistent handler from state storage.
        // The handler maintains focusedIndex across renders, enabling Tab navigation.
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<RadioButtonGroupHandler> = stateStorage.storage(
            for: handlerKey,
            default: RadioButtonGroupHandler(
                focusID: persistedFocusID,
                selection: erasedSelection,
                itemValues: itemValues,
                orientation: orientation,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value

        // Keep handler in sync with current values (in case items changed)
        handler.selection = erasedSelection
        handler.itemValues = itemValues
        handler.canBeFocused = !isDisabled
        handler.wrapsAtEdge = context.environment.radioButtonGroupWrapsAtEdge

        FocusRegistration.register(context: context, handler: handler)
        let groupHasFocus = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        // Hover state for the group — at most one item is
        // hovered at a time, so a single StateBox<Int> holds
        // its index (or `-1` for none). The per-item mouse
        // handlers flip it on .entered / .exited; the
        // renderer reads it per row below. Disabled groups
        // never show hover (mouse handlers below skip
        // registration entirely).
        let hoveredIndexKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.hoveredIndex)
        let hoveredIndexBox: StateBox<Int> = stateStorage.storage(
            for: hoveredIndexKey, default: -1)
        let hoveredIndex = isDisabled ? -1 : hoveredIndexBox.value

        // Render items based on orientation
        let lines: [String]
        let itemRegions: [(x: Int, y: Int, width: Int)]
        switch orientation {
        case .vertical:
            (lines, itemRegions) = renderVerticalWithRegions(
                context: context, handler: handler, groupHasFocus: groupHasFocus,
                hoveredIndex: hoveredIndex, palette: palette)
        case .horizontal:
            (lines, itemRegions) = renderHorizontalWithRegions(
                context: context, handler: handler, groupHasFocus: groupHasFocus,
                hoveredIndex: hoveredIndex, palette: palette)
        }

        var buffer = FrameBuffer(lines: lines)

        // Mouse: a left-button release on an item row selects that item
        // and grants the group focus. Each item gets its own hit-test
        // region so the dispatcher can identify which item was clicked.
        // The same per-item region drives the hover state — .entered
        // / .exited synthesised by the dispatcher flip the shared
        // hoveredIndexBox to that item's index (or back to -1).
        if !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            // Ask the dispatcher to enable motion reporting this
            // frame so the hover state machine sees .moved
            // events.
            mouseDispatcher.requestFeature(.motion)

            let focusManager = context.environment.focusManager
            let captureFocusID = persistedFocusID
            let captureItems = items
            let captureSelection = selection
            let captureHoveredIndexBox = hoveredIndexBox
            // Tag only the currently-focused item's region with
            // the group's focus ID so ScrollView's snap-to-focus
            // anchors on the right radio button — not whichever
            // one happens to come first. Arrow-key navigation
            // changes handler.focusedIndex; the next render
            // moves the tag to the new item, and the snap
            // follows. Items that aren't currently focused get
            // a nil focusID — the surrounding ScrollView's
            // hit-test region falls through cleanly because
            // mismatched IDs are skipped.
            for (index, region) in itemRegions.enumerated() {
                let mouseHandlerID = mouseDispatcher.register { event in
                    switch event.phase {
                    case .entered:
                        captureHoveredIndexBox.value = index
                        return true
                    case .exited:
                        // Only clear if this is the index we
                        // claimed — protects against a fast
                        // cursor movement where .entered on the
                        // next item arrives before .exited on
                        // the previous item.
                        if captureHoveredIndexBox.value == index {
                            captureHoveredIndexBox.value = -1
                        }
                        return true
                    case .pressed where event.button == .left:
                        return true
                    case .released where event.button == .left:
                        focusManager?.focus(id: captureFocusID)
                        handler.focusedIndex = index
                        captureSelection.wrappedValue = captureItems[index].value
                        return true
                    default:
                        return false
                    }
                }
                buffer.hitTestRegions.append(
                    HitTestRegion(
                        offsetX: region.x,
                        offsetY: region.y,
                        width: region.width,
                        height: 1,
                        handlerID: mouseHandlerID,
                        focusID: index == handler.focusedIndex ? captureFocusID : nil
                    )
                )
            }
        }

        return buffer
    }

    private func renderVerticalWithRegions(
        context: RenderContext,
        handler: RadioButtonGroupHandler,
        groupHasFocus: Bool,
        hoveredIndex: Int,
        palette: Palette
    ) -> (lines: [String], regions: [(x: Int, y: Int, width: Int)]) {
        var lines: [String] = []
        var regions: [(x: Int, y: Int, width: Int)] = []
        for (index, item) in items.enumerated() {
            let isFocused = handler.focusedIndex == index && groupHasFocus
            let line = renderRadioButton(
                index: index,
                item: item,
                isFocused: isFocused,
                groupHasFocus: groupHasFocus,
                isSelected: selection.wrappedValue == item.value,
                isHovered: hoveredIndex == index && !isFocused,
                context: context,
                palette: palette
            )
            lines.append(line)
            // One full-width row per item.
            regions.append((x: 0, y: index, width: line.strippedLength))
        }
        return (lines, regions)
    }

    private func renderHorizontalWithRegions(
        context: RenderContext,
        handler: RadioButtonGroupHandler,
        groupHasFocus: Bool,
        hoveredIndex: Int,
        palette: Palette
    ) -> (lines: [String], regions: [(x: Int, y: Int, width: Int)]) {
        let itemStrings = items.enumerated().map { index, item -> String in
            let isFocused = handler.focusedIndex == index && groupHasFocus
            return renderRadioButton(
                index: index,
                item: item,
                isFocused: isFocused,
                groupHasFocus: groupHasFocus,
                isSelected: selection.wrappedValue == item.value,
                isHovered: hoveredIndex == index && !isFocused,
                context: context,
                palette: palette
            )
        }

        let spacingWidth = 2
        var regions: [(x: Int, y: Int, width: Int)] = []
        var xCursor = 0
        for (i, text) in itemStrings.enumerated() {
            let w = text.strippedLength
            regions.append((x: xCursor, y: 0, width: w))
            xCursor += w
            if i < itemStrings.count - 1 {
                xCursor += spacingWidth
            }
        }

        let spacing = String(repeating: " ", count: spacingWidth)
        return ([itemStrings.joined(separator: spacing)], regions)
    }

    private func renderRadioButton(
        index: Int,
        item: RadioButtonItem<Value>,
        isFocused: Bool,
        groupHasFocus: Bool,
        isSelected: Bool,
        isHovered: Bool,
        context: RenderContext,
        palette: Palette
    ) -> String {
        // Combine own + cascaded disabled (renderToBuffer's shadowing local does
        // not reach this helper).
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        // Radio indicator: ● if selected OR focused; otherwise ◯ when enabled, or
        // ◌ (dotted circle) when disabled — a disabled, unselected option reads
        // as "not pickable". (A disabled control never holds focus, so a disabled
        // item is ● only when it is the current selection.)
        let indicator: String
        if isSelected || isFocused {
            indicator = TerminalSymbols.radioSelected
        } else if isDisabled {
            indicator = TerminalSymbols.radioDisabledUnselected
        } else {
            indicator = TerminalSymbols.radioUnselected
        }

        // Determine indicator color based on state. Priority
        // order: disabled > focused > selected > hovered >
        // default. Hover thus only changes the look of an
        // unselected, unfocused item — focus and selection are
        // both more emphatic affordances and shouldn't
        // compete.
        let indicatorColor: Color
        if isDisabled {
            indicatorColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
        } else if isFocused {
            // Focused: pulsing accent (whether selected or not)
            let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
            indicatorColor = SelectionIndicator.resolve(isFocused: true, context: context)
                .color(dim: dimAccent, bright: palette.accent)
        } else if isSelected {
            // Selected but not focused: solid accent
            indicatorColor = palette.accent
        } else if isHovered {
            // Hovered (and neither focused nor selected):
            // dim accent — reads as "you can pick me" without
            // mimicking the focused or selected look.
            indicatorColor = palette.accent.opacity(ViewConstants.focusBorderDim)
        } else {
            // Unselected, unfocused, unhovered: dimmed.
            indicatorColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
        }

        let styledIndicator = ANSIRenderer.colorize(indicator, foreground: indicatorColor)

        // Render label, tagged so its Text resolves `.control(.radioButton)`
        // style entries — but only when not already inside another control (e.g.
        // a Picker's radio-group style, which keeps its `.picker` identity).
        var labelContext = context
        if labelContext.environment.controlKind == nil {
            labelContext.environment.controlKind = .radioButton
        }
        let labelView = item.labelBuilder()
        let labelBuffer = labelView.renderToBuffer(context: labelContext)
        let labelText = labelBuffer.lines.first ?? ""

        // Combine: indicator + label
        return styledIndicator + " " + labelText
    }
}

// MARK: - Radio Button Handler

/// Internal handler class for radio button group focus and selection management.
///
/// Persisted across renders via StateStorage to maintain focusedIndex and enable
/// Tab navigation between radio button groups.
final class RadioButtonGroupHandler: Focusable {
    let focusID: String
    var selection: Binding<AnyHashable>
    var itemValues: [AnyHashable]
    let orientation: RadioButtonOrientation
    var canBeFocused: Bool

    /// Whether arrowing past the first/last item wraps within the group
    /// (`true`) or relinquishes focus to the neighbouring control (`false`,
    /// the default). Synced each render from the environment. See
    /// ``View/radioButtonGroupWrapsAtEdge(_:)``.
    var wrapsAtEdge: Bool = false

    /// The currently focused item index within the group.
    /// Persisted across renders to maintain focus position.
    var focusedIndex: Int = 0

    init(
        focusID: String,
        selection: Binding<AnyHashable>,
        itemValues: [AnyHashable],
        orientation: RadioButtonOrientation,
        canBeFocused: Bool
    ) {
        self.focusID = focusID
        self.selection = selection
        self.itemValues = itemValues
        self.orientation = orientation
        self.canBeFocused = canBeFocused

        // Find current focused index based on selection
        if let currentIndex = itemValues.firstIndex(of: selection.wrappedValue) {
            self.focusedIndex = currentIndex
        }
    }
}

// MARK: - Focus Lifecycle

extension RadioButtonGroupHandler {
    func onFocusLost() {
        // Reset focusedIndex to the selected item when the group loses focus
        if let selectedIndex = itemValues.firstIndex(of: selection.wrappedValue) {
            focusedIndex = selectedIndex
        }
    }
}

// MARK: - Key Event Handling

extension RadioButtonGroupHandler {
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard !itemValues.isEmpty else { return false }

        // Clamp focusedIndex to valid range in case items changed
        focusedIndex = min(focusedIndex, itemValues.count - 1)

        switch event.key {
        // On the group's movement axis, an interior press moves focus within the
        // group; a press *past* the edge either wraps (opt-in) or relinquishes —
        // returning `false` lets FocusManager move to the neighbouring control in
        // that direction (the default; see `radioButtonGroupWrapsAtEdge`). A
        // cross-axis press is consumed as a no-op, as before.
        case .up:
            return moveOnAxis(.vertical, forward: false)

        case .down:
            return moveOnAxis(.vertical, forward: true)

        case .left:
            return moveOnAxis(.horizontal, forward: false)

        case .right:
            return moveOnAxis(.horizontal, forward: true)

        case .enter, .space:
            // Select the currently focused item (make it the selection)
            selection.wrappedValue = itemValues[focusedIndex]
            return true

        default:
            return false
        }
    }

    /// Handles an arrow press along `axis` (`forward` = down / right).
    ///
    /// A cross-axis press (the group's orientation differs from `axis`) is a
    /// consumed no-op, matching the previous behaviour. On the movement axis an
    /// interior press steps `focusedIndex` and consumes the event; a press past
    /// the first/last item wraps and consumes when ``wrapsAtEdge`` is set,
    /// otherwise returns `false` so `FocusManager` relinquishes focus to the
    /// neighbouring control in that direction.
    private func moveOnAxis(_ axis: RadioButtonOrientation, forward: Bool) -> Bool {
        guard orientation == axis else { return true }  // cross-axis: consumed no-op
        let lastIndex = itemValues.count - 1
        if forward {
            if focusedIndex < lastIndex {
                focusedIndex += 1
                return true
            }
            guard wrapsAtEdge else { return false }  // escape past the bottom / right
            focusedIndex = 0
            return true
        } else {
            if focusedIndex > 0 {
                focusedIndex -= 1
                return true
            }
            guard wrapsAtEdge else { return false }  // escape past the top / left
            focusedIndex = lastIndex
            return true
        }
    }
}

// MARK: - Radio Button Group Convenience Modifiers

extension RadioButtonGroup {
    /// Creates a disabled version of this radio button group.
    ///
    /// - Parameter disabled: Whether the group is disabled.
    /// - Returns: A new group with the disabled state.
    public func disabled(_ disabled: Bool = true) -> RadioButtonGroup<Value> {
        var newGroup = self
        newGroup.isDisabled = disabled
        return newGroup
    }

    /// Sets a custom focus identifier for this radio button group.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A group with the specified focus identifier.
    public func focusID(_ id: String) -> RadioButtonGroup<Value> {
        var copy = self
        copy.focusID = id
        return copy
    }
}

extension View {
    /// Styles the *label* text of every radio button in this view's subtree
    /// (a `.control(.radioButton)`-scoped style entry). The ●/○ indicator is
    /// unaffected.
    public func radioButtonTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.radioButton), build)
    }
}
