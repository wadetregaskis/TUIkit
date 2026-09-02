//  🖥️ TUIkit — Terminal UI Kit for Swift
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

/// A single option in a radio button group: a value, a label, and — optionally
/// — the controls that configure *that* option.
///
/// ```swift
/// RadioButtonGroup(selection: $colour) {
///     RadioButtonItem(.trueColor, "True colour")
///     RadioButtonItem(.greys, "Greys") {
///         Slider(value: $levels, in: 2...16, step: 1) { Text("Levels: \(levels)") }
///     }
/// }
/// ```
///
/// ```
///   ◯ True colour
///   ● Greys
///     Levels: 4  ├──●─────────┤
/// ```
///
/// ## What the content is for
///
/// An option that takes a parameter — how many greys, which two colours, how
/// wide — has nowhere sensible to put it but under the option it belongs to.
/// Putting it beside the group instead leaves the reader to work out which
/// option it configures, and putting each parameterised option in a group of
/// its own (the other way to draw this) costs the arrow keys that walk the
/// options.
///
/// The content is indented to start under the label, so it reads as part of the
/// option rather than as the next one.
///
/// ## Only the selected option's content is live
///
/// A group disables every unselected option's content, exactly as it would be
/// disabled by ``View/disabled(_:)`` — greyed, and not a focus stop. That is
/// what makes the keyboard convention unambiguous: whatever is reachable below
/// the group belongs to the option that is actually chosen. See
/// ``RadioButtonGroup`` for the keys.
public struct RadioButtonItem<Value: Hashable> {
    /// The value associated with this option.
    let value: Value

    /// The label view builder.
    let labelBuilder: @MainActor () -> AnyView

    /// Builds the option's own controls, shown under it — `nil` for an option
    /// that takes no parameters. Called only while the group renders, like any
    /// other view builder.
    let contentBuilder: (@MainActor () -> AnyView)?

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
        self.contentBuilder = nil
    }

    /// Creates a radio button item with a view label and controls of its own.
    ///
    /// Parameter order follows `DisclosureGroup(content:label:)`, which this is
    /// the option-list shape of.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - content: The controls that configure this option, shown under it.
    ///   - label: A view builder closure that returns the label.
    @MainActor
    public init<Content: View, Label: View>(
        _ value: Value,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.value = value
        self.labelBuilder = { AnyView(label()) }
        self.contentBuilder = { AnyView(content()) }
    }

    /// Creates a radio button item with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - labelKey: The key for the label text.
    @MainActor
    public init(
        _ value: Value,
        _ labelKey: LocalizedStringKey
    ) {
        self.init(value, labelKey.localized)
    }

    /// Creates a radio button item with a localized label and controls of its
    /// own, shown under it.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - labelKey: The key for the label text.
    ///   - content: The controls that configure this option.
    @MainActor
    public init<Content: View>(
        _ value: Value,
        _ labelKey: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(value, labelKey.localized, content: content)
    }

    /// Creates a radio button item with a string label, displayed as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``. Only the label is a key: `value` is what the
    /// option stands for, not text anyone reads.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - label: The label text.
    @MainActor
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ value: Value,
        _ label: S
    ) {
        self.value = value
        // Flattened to a `String` here rather than inside the closure. The
        // builder escapes — it is called later, while the group renders — so
        // what it captures is stored, and storing a `String` is what this held
        // before and what `Text` is built from anyway. Nothing generic outlives
        // the call.
        let text = String(label)
        self.labelBuilder = { AnyView(Text(text)) }
        self.contentBuilder = nil
    }

    /// Creates a radio button item with a string label, displayed as written,
    /// and controls of its own shown under it.
    ///
    /// Generic over `StringProtocol` for the same reason as the label-only
    /// overload above — see ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - label: The label text.
    ///   - content: The controls that configure this option.
    @MainActor
    @_disfavoredOverload
    public init<Content: View, S: StringProtocol>(
        _ value: Value,
        _ label: S,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.value = value
        let text = String(label)  // see the label-only overload above
        self.labelBuilder = { AnyView(Text(text)) }
        self.contentBuilder = { AnyView(content()) }
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
    /// Collects the items written directly in the group's body.
    ///
    /// The builder's entry point: every `RadioButtonGroup { … }` produces one
    /// call to this, with the block's items as its arguments.
    public static func buildBlock(_ items: RadioButtonItem<Value>...) -> [RadioButtonItem<Value>] {
        Array(items)
    }

    /// Supplies the empty list for an `if` with no `else` that did not run.
    ///
    /// What makes `if showAdvanced { RadioButtonItem(…) }` legal: the absent
    /// branch contributes no items rather than failing to type-check.
    public static func buildOptional(_ items: [RadioButtonItem<Value>]?) -> [RadioButtonItem<Value>] {
        items ?? []
    }

    /// Takes the `if` branch of an `if`/`else`.
    ///
    /// Paired with ``buildEither(second:)``; both arms of a conditional
    /// already produce the same type here, so neither erases anything.
    public static func buildEither(first items: [RadioButtonItem<Value>]) -> [RadioButtonItem<Value>] {
        items
    }

    /// Takes the `else` branch of an `if`/`else`. See ``buildEither(first:)``.
    public static func buildEither(second items: [RadioButtonItem<Value>]) -> [RadioButtonItem<Value>] {
        items
    }

    /// Flattens the per-iteration groups a `for`…`in` loop produces into one
    /// list, so a loop over a data array reads as the items it generates.
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
///
/// ## Options that carry their own controls
///
/// An option that takes a parameter can carry the control for it — see
/// ``RadioButtonItem``. The control is drawn under its option, indented to the
/// label, and it is live only while that option is the selection:
///
/// ```
///   ◯ True colour
///   ● Greys
///     Levels: 4  ├──●─────────┤     ← live
///   ◯ Sampled
///     Colours: 8 ├────●───────┤     ← drawn, disabled
/// ```
///
/// Every option's content is DRAWN whether or not it is selected, so the rows
/// an option occupies do not move as the selection does — a list that
/// rearranged itself while you arrowed down it would be unusable. What changes
/// is whether the content is enabled.
///
/// ## From the keyboard
///
/// The same shape as ``DisclosureGroup`` and ``OutlineGroup``, which is what a
/// group of options with things inside them is: **along** the group's axis to
/// move between siblings, **Right** to go in, **Left** to come back out.
///
/// - The group is ONE Tab stop, however many options it has. **Up** and
///   **Down** walk a vertical group, **Left** and **Right** a horizontal one;
///   **Home**, **End** and **Page** jump to its ends, and Shift accelerates the
///   on-axis arrow. **Return** or **Space** selects the option under the
///   cursor.
/// - **Right** (on a vertical group) steps out of the options and into the
///   selected option's controls, because those are the only controls in the
///   group that are enabled — an unselected option's are not focus stops at
///   all, so there is never a question of which option you have stepped into.
///   **Tab** does the same thing.
/// - **Left** comes back to the options — as ordinary focus movement, so a
///   control that wants Left for itself (a `Slider`, a `TextField`) keeps it
///   and **Shift-Tab** is the way back out of that one.
/// - The cross-axis arrow still leaves a group whose options carry nothing, as
///   it always has: there is nothing in that direction to step into, so the key
///   goes back to being focus movement. See
///   ``View/radioButtonGroupEdgeBehavior(_:)`` for what the ON-axis arrow does
///   at the first and last option.
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

    /// Keeps the persisted handler in sync with the CURRENT render's values —
    /// every field the view declares, or the handler keeps the creation
    /// render's (a stale `orientation` kept the old arrow-axis mapping after
    /// a responsive layout flipped the group).
    private func syncHandler(
        _ handler: RadioButtonGroupHandler,
        selection: Binding<AnyHashable>,
        itemValues: [AnyHashable],
        isDisabled: Bool,
        context: RenderContext
    ) {
        handler.selection = selection
        handler.itemValues = itemValues
        handler.orientation = orientation
        handler.canBeFocused = !isDisabled
        handler.edgeBehavior = context.environment.radioButtonGroupEdgeBehavior
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.stateStorage!

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

        syncHandler(
            handler, selection: erasedSelection, itemValues: itemValues,
            isDisabled: isDisabled, context: context)

        FocusRegistration.register(context: context, handler: handler)
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. The group
        // keeps the focus and the arrows keep moving between items.
        let groupHasFocus = context.indicatesFocus(
            FocusRegistration.isFocused(context: context, focusID: persistedFocusID))

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
        let rendered: RenderedItems
        switch orientation {
        case .vertical:
            rendered = renderVerticalWithRegions(
                context: context, handler: handler, groupHasFocus: groupHasFocus,
                hoveredIndex: hoveredIndex, palette: palette)
        case .horizontal:
            rendered = renderHorizontalWithRegions(
                context: context, handler: handler, groupHasFocus: groupHasFocus,
                hoveredIndex: hoveredIndex, palette: palette)
        }
        let itemRegions = rendered.regions

        // The items' own buffer, payload and all: an item's content may carry
        // hit regions, animated runs and overlays of its own, and a bare
        // `FrameBuffer(lines:)` here would silently drop every one of them.
        var buffer = rendered.buffer

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

    /// The items as one buffer, and where each option's own row sits within it.
    ///
    /// The buffer rather than a list of lines, because an item's content brings
    /// hit regions, animated runs, overlays and opacity regions of its own, and
    /// a bare `FrameBuffer(lines:)` would drop all four.
    ///
    /// The regions are the group's click targets, and they cover the OPTION
    /// rows only: the rows below an option belong to its content, which answers
    /// the pointer itself.
    private struct RenderedItems {
        let buffer: FrameBuffer
        let regions: [(x: Int, y: Int, width: Int)]
    }

    private func renderVerticalWithRegions(
        context: RenderContext,
        handler: RadioButtonGroupHandler,
        groupHasFocus: Bool,
        hoveredIndex: Int,
        palette: Palette
    ) -> RenderedItems {
        var buffer = FrameBuffer(lines: [])
        var regions: [(x: Int, y: Int, width: Int)] = []
        for (index, item) in items.enumerated() {
            let rendered = renderItem(
                index: index,
                item: item,
                isFocused: handler.focusedIndex == index && groupHasFocus,
                isSelected: selection.wrappedValue == item.value,
                isHovered: hoveredIndex == index,
                context: context,
                palette: palette
            )
            // Each item starts where the last one ended — which is one row on
            // for a plain option, and more when it carries content.
            regions.append((x: 0, y: buffer.lines.count, width: rendered.optionWidth))
            buffer.appendVertically(rendered.buffer)
        }
        return RenderedItems(buffer: buffer, regions: regions)
    }

    private func renderHorizontalWithRegions(
        context: RenderContext,
        handler: RadioButtonGroupHandler,
        groupHasFocus: Bool,
        hoveredIndex: Int,
        palette: Palette
    ) -> RenderedItems {
        let spacingWidth = 2
        var buffer = FrameBuffer(lines: [])
        var regions: [(x: Int, y: Int, width: Int)] = []
        for (index, item) in items.enumerated() {
            let rendered = renderItem(
                index: index,
                item: item,
                isFocused: handler.focusedIndex == index && groupHasFocus,
                isSelected: selection.wrappedValue == item.value,
                isHovered: hoveredIndex == index,
                context: context,
                palette: palette
            )
            // The same predicate `appendHorizontally` uses: a gap is charged
            // only between two occupied column ranges, so the first item starts
            // at column 0 whatever it rendered.
            let originX = buffer.width > 0 ? buffer.width + spacingWidth : 0
            regions.append((x: originX, y: 0, width: rendered.optionWidth))
            buffer.appendHorizontally(rendered.buffer, spacing: spacingWidth)
        }
        return RenderedItems(buffer: buffer, regions: regions)
    }

    /// One item, drawn: the option row, and under it whatever that option
    /// carries.
    private struct RenderedItem {
        let buffer: FrameBuffer
        /// The option row's own width — see ``RenderedItems``.
        let optionWidth: Int
    }

    /// Renders one item: its indicator and label on the first row, and its
    /// content — if it has any — indented underneath.
    ///
    /// The indent is the indicator plus the space after it, so the content
    /// starts under the LABEL rather than under the bullet: an option and the
    /// controls that configure it read as one thing.
    private func renderItem(
        index: Int,
        item: RadioButtonItem<Value>,
        isFocused: Bool,
        isSelected: Bool,
        isHovered: Bool,
        context: RenderContext,
        palette: Palette
    ) -> RenderedItem {
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
        // Set only on the focused branch: it is the one state in which the
        // indicator moves, and at most one item in a group is ever focused.
        var indicatorRun: AnimatedCellRun?
        if isDisabled {
            indicatorColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        } else if isFocused {
            // Focused: pulsing accent (whether selected or not) — taken as a
            // whole cycle rather than a phase, so the bullet can be handed to
            // the run loop to breathe on its own. Asking for the live phase
            // instead would keep the clock ticking and re-render this entire
            // page ten times a second to repaint one cell.
            let dimAccent = palette.accentPulse().dim
            let cycle = context.environment.selectionEmphasis.cycle(true)
            indicatorColor = cycle.colorNow(dim: dimAccent, bright: palette.accent)
            if !context.isMeasuring {
                indicatorRun = cycle.run(
                    indicator, dim: dimAccent, bright: palette.accent, offsetX: 0, offsetY: 0)
            }
        } else if isSelected {
            // Selected but not focused: solid accent
            indicatorColor = palette.accent
        } else if isHovered {
            // Hovered (and neither focused nor selected): the resting colour
            // LIFTED, not a tint of its own. It used to be the accent at
            // `focusBorderDim`, and on a 256-colour terminal that landed on the
            // same cube entry as the dim resting colour — measured on Green,
            // hovering an unselected item changed `#005f00` to `#005f00`, which
            // is to say it did nothing at all.
            indicatorColor = palette.hoveredForeground(
                palette.foregroundTertiary.opacity(
                    ViewConstants.disabledForeground, over: palette.background))
        } else {
            // Unselected, unfocused, unhovered: dimmed.
            indicatorColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        }

        let styledIndicator = ANSIRenderer.colorize(indicator, foreground: indicatorColor)

        // Every item renders at its OWN identity, one step off the group's, and
        // its label and content at one step further apiece. Without that the
        // items would share the group's storage slots with each other AND with
        // the group's own handler at index 0 — two sliders under two options
        // would be one slider.
        let itemContext = context.withChildIdentity(
            erasedType: RadioButtonItem<Value>.self, index: index)

        // Render label, tagged so its Text resolves `.control(.radioButton)`
        // style entries — but only when not already inside another control (e.g.
        // a Picker's radio-group style, which keeps its `.picker` identity).
        var labelContext = itemContext.withChildIdentity(erasedType: AnyView.self, index: 0)
        if labelContext.environment.controlKind == nil {
            labelContext.environment.controlKind = .radioButton
        }
        // The whole row is the click target, so the whole row answers the
        // pointer — indicator and label together, the way a `Toggle` does.
        if isHovered, !isDisabled {
            let base =
                labelContext.environment.foregroundStyle?.representative
                ?? labelContext.environment.styleCascade
                    .resolve(for: [.all, .text, .control(.radioButton)]).foreground
                ?? palette.foreground
            labelContext.environment.foregroundStyle = .color(palette.hoveredForeground(base))
        }
        let labelBuffer = item.labelBuilder().renderToBuffer(context: labelContext)

        // The indicator is one cell wide by construction — all three glyphs are
        // — and the space after it makes two.
        let indentWidth = indicator.strippedLength + 1
        let indent = String(repeating: " ", count: indentWidth)
        var lines = labelBuffer.lines.enumerated().map { row, line in
            row == 0 ? styledIndicator + " " + line : indent + line
        }
        if lines.isEmpty { lines = [styledIndicator + " "] }

        var buffer = FrameBuffer(lines: lines)
        // A label is usually a `Text`, but it is a VIEW, and a view that
        // rendered a button or an animated run has to keep it.
        buffer.overlays = labelBuffer.shiftedOverlays(byX: indentWidth, y: 0)
        buffer.hitTestRegions = labelBuffer.shiftedHitTestRegions(byX: indentWidth, y: 0)
        buffer.animatedCells = labelBuffer.shiftedAnimatedCells(byX: indentWidth, y: 0)
        buffer.opacityRegions = labelBuffer.shiftedOpacityRegions(byX: indentWidth, y: 0)
        if let indicatorRun {
            buffer.animatedCells.append(indicatorRun)
        }
        let optionWidth = lines[0].strippedLength

        if let contentBuilder = item.contentBuilder {
            // Disabled unless this option is the chosen one — so an unselected
            // option's controls are neither editable nor focus stops, and
            // whatever the keyboard reaches below the group belongs to the
            // option that is actually selected. See ``RadioButtonItem``.
            let contentView = contentBuilder()
                .padding(.leading, indentWidth)
                .disabled(isDisabled || !isSelected)
            buffer.appendVertically(
                TUIkitView.renderToBuffer(
                    contentView,
                    context: itemContext.withChildIdentity(erasedType: AnyView.self, index: 1)))
        }

        return RenderedItem(buffer: buffer, optionWidth: optionWidth)
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
    /// Mutable because the handler persists across renders while a responsive
    /// layout may flip the group between vertical and horizontal — a stale
    /// orientation kept the OLD arrow-axis mapping (Up/Down navigating a
    /// now-horizontal group, Left/Right relinquishing). Re-synced every
    /// render; same stale-handler-field class as `SliderHandler.bounds`.
    var orientation: RadioButtonOrientation
    var canBeFocused: Bool

    /// What an on-axis arrow past the first/last item does — contain (stay,
    /// the default), escape (relinquish to the neighbour), or wrap. Synced
    /// each render from the environment. See
    /// ``View/radioButtonGroupEdgeBehavior(_:)``.
    var edgeBehavior: RadioButtonGroupEdgeBehavior = .contain

    /// How many options a Shift-accelerated on-axis arrow jumps. Synced from
    /// `environment.shiftStepMultiplier` during render (default 5); a plain arrow
    /// moves one. See ``View/shiftStepMultiplier(_:)``. (Terminal.app strips
    /// Shift from Up/Down, so on a *vertical* group the accelerator only fires
    /// where the terminal keeps it — Home/End/Page always work regardless.)
    var shiftStepMultiplier: Int = 5

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

        // Home/End/Page and a Shift-accelerated on-axis arrow jump to a clamped
        // destination within the group (shared with the other option lists —
        // Picker, Menu, combo-box). A radio group has no scrolling viewport, so
        // Page collapses onto Home/End (pageSize == count). The on-axis arrows
        // follow the group's orientation, so Shift+Left/Right accelerates a
        // horizontal group and Shift+Up/Down a vertical one — the cross-axis
        // arrow still relinquishes below.
        let (onForward, onBackward): (Key, Key) =
            orientation == .vertical ? (.down, .up) : (.right, .left)
        if let destination = OptionListNavigation.clampedDestination(
            for: event, from: focusedIndex, count: itemValues.count,
            onAxisForward: onForward, onAxisBackward: onBackward,
            multiplier: shiftStepMultiplier, pageSize: itemValues.count)
        {
            focusedIndex = destination
            return true
        }

        switch event.key {
        // On the group's movement axis, an interior press moves focus within the
        // group; a press *past* the edge follows `edgeBehavior` (contain by
        // default — see `radioButtonGroupEdgeBehavior`). A cross-axis press
        // always relinquishes so a single-axis group can be left by arrow.
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
    /// A cross-axis press (the group's orientation differs from `axis`)
    /// relinquishes focus — returning `false` lets `FocusManager` move to the
    /// neighbouring control in that direction. This is what makes Up/Down step
    /// OUT of a horizontal group (to the control above / below) and Left/Right
    /// step out of a vertical one. (It was previously a consumed no-op, which
    /// swallowed Up on a horizontal group so you could never arrow back to the
    /// control above it.) It is INDEPENDENT of ``edgeBehavior``: a single-axis
    /// group has nowhere to move cross-axis, so relinquishing is the only way
    /// to leave it that way.
    ///
    /// On the movement axis an interior press steps `focusedIndex` and consumes
    /// the event; a press past the first/last item follows ``edgeBehavior``:
    /// `.contain` stays put and consumes (the default — you can't overshoot out
    /// of the group, which matters inside a scroll view), `.escape` returns
    /// `false` to relinquish to the neighbour, `.wrap` cycles to the far end.
    private func moveOnAxis(_ axis: RadioButtonOrientation, forward: Bool) -> Bool {
        guard orientation == axis else { return false }  // cross-axis: relinquish focus
        let lastIndex = itemValues.count - 1
        let atEdge = forward ? focusedIndex >= lastIndex : focusedIndex <= 0
        if !atEdge {
            focusedIndex += forward ? 1 : -1
            return true
        }
        switch edgeBehavior {
        case .contain:
            return true  // stay on the edge item; consume so focus doesn't leave
        case .escape:
            return false  // relinquish to the neighbouring control
        case .wrap:
            focusedIndex = forward ? 0 : lastIndex
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
