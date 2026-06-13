//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Table.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Table

/// A scrollable table with columns, keyboard navigation, and selection.
///
/// `Table` displays tabular data inside a bordered container with:
/// - Column headers in the container header section
/// - Optional footer section
/// - Keyboard navigation (Up/Down/Home/End/PageUp/PageDown)
/// - Single or multi-selection via bindings
/// - Configurable column widths (fixed, flexible, ratio)
/// - Column alignment (leading, center, trailing)
/// - ANSI-aware column layout
/// - Scrolling with automatic viewport management
///
/// ## Usage
///
/// ```swift
/// struct FileInfo: Identifiable {
///     let id: String
///     let name: String
///     let size: String
///     let modified: String
/// }
///
/// @State var selectedID: String?
///
/// Table(files, selection: $selectedID) {
///     TableColumn("Name", value: \.name)
///     TableColumn("Size", value: \.size)
///         .width(.fixed(10))
///         .alignment(.trailing)
///     TableColumn("Modified", value: \.modified)
///         .width(.ratio(0.3))
/// }
/// ```
///
/// ## Column Spacing
///
/// Columns are separated by spaces (no vertical lines) for a clean look.
public struct Table<Value: Identifiable & Sendable>: View where Value.ID: Hashable {
    /// The data items to display.
    let data: [Value]

    /// The column definitions.
    let columns: [TableColumn<Value>]

    /// Binding for single selection (optional ID).
    let singleSelection: Binding<Value.ID?>?

    /// Binding for multi-selection (Set of IDs).
    let multiSelection: Binding<Set<Value.ID>>?

    /// The selection mode derived from which binding is set.
    var selectionMode: SelectionMode {
        multiSelection != nil ? .multi : .single
    }

    /// The unique focus identifier for this table.
    let focusID: String?

    /// Whether the table is disabled.
    var isDisabled: Bool

    /// The placeholder text shown when the table is empty.
    let emptyPlaceholder: String

    /// The spacing between columns in characters.
    let columnSpacing: Int

    public var body: some View {
        _TableCore(
            data: data,
            columns: columns,
            singleSelection: singleSelection,
            multiSelection: multiSelection,
            selectionMode: selectionMode,
            focusID: focusID,
            isDisabled: isDisabled,
            emptyPlaceholder: emptyPlaceholder,
            columnSpacing: columnSpacing
        )
    }
}

// MARK: - Single Selection Initializer

extension Table {
    /// Creates a table with single selection.
    ///
    /// - Parameters:
    ///   - data: The data items to display.
    ///   - selection: A binding to the selected item's ID (nil = no selection).
    ///   - focusID: The unique focus identifier (default: auto-generated).

    ///   - columnSpacing: Spacing between columns (default: 2).
    ///   - emptyPlaceholder: Placeholder text when empty (default: "No items").
    ///   - columns: A builder that defines the table columns.
    public init(
        _ data: [Value],
        selection: Binding<Value.ID?>,
        focusID: String? = nil,

        columnSpacing: Int = 2,
        emptyPlaceholder: String = "No items",
        @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]
    ) {
        self.data = data
        self.columns = columns()
        self.singleSelection = selection
        self.multiSelection = nil
        self.focusID = focusID
        self.isDisabled = false

        self.columnSpacing = columnSpacing
        self.emptyPlaceholder = emptyPlaceholder
    }
}

// MARK: - Multi Selection Initializer

extension Table {
    /// Creates a table with multi-selection.
    ///
    /// - Parameters:
    ///   - data: The data items to display.
    ///   - selection: A binding to the set of selected item IDs.
    ///   - focusID: The unique focus identifier (default: auto-generated).

    ///   - columnSpacing: Spacing between columns (default: 2).
    ///   - emptyPlaceholder: Placeholder text when empty (default: "No items").
    ///   - columns: A builder that defines the table columns.
    public init(
        _ data: [Value],
        selection: Binding<Set<Value.ID>>,
        focusID: String? = nil,

        columnSpacing: Int = 2,
        emptyPlaceholder: String = "No items",
        @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]
    ) {
        self.data = data
        self.columns = columns()
        self.singleSelection = nil
        self.multiSelection = selection
        self.focusID = focusID
        self.isDisabled = false

        self.columnSpacing = columnSpacing
        self.emptyPlaceholder = emptyPlaceholder
    }
}

// MARK: - Convenience Modifiers

extension Table {
    /// Creates a disabled version of this table.
    ///
    /// - Parameter disabled: Whether the table is disabled.
    /// - Returns: A new table with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Table {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }
}

// MARK: - Table Core (Internal Rendering)

/// Internal core view that handles table rendering inside a ContainerView.
private struct _TableCore<Value: Identifiable & Sendable>: View, Renderable, Layoutable
where Value.ID: Hashable {
    let data: [Value]
    let columns: [TableColumn<Value>]
    let singleSelection: Binding<Value.ID?>?
    let multiSelection: Binding<Set<Value.ID>>?
    let selectionMode: SelectionMode
    let focusID: String?
    let isDisabled: Bool
    let emptyPlaceholder: String
    let columnSpacing: Int

    var body: Never {
        fatalError("_TableCore renders via Renderable")
    }

    /// Sizes the table without the render-to-measure fallback's *second* render.
    ///
    /// Being `Renderable`-only, `_TableCore` previously fell through `measureChild`
    /// to the fallback, which renders the table TWICE per measure — once at the
    /// proposal for its natural size, once at `naturalWidth + 8` purely to probe
    /// width-flexibility — on top of the real render. On a 20k-row table that was
    /// ~72% of the frame (`measureChild`).
    ///
    /// The probe is unnecessary here: a table grows with the available width iff a
    /// column is `.flexible`/`.ratio` (those scale the content, which makes the
    /// hugging container fill; all-`.fixed` columns give a fixed-width content the
    /// container hugs). So flexibility is derived analytically and only the natural
    /// render remains — a single render whose context mirrors the fallback's first
    /// render exactly (`isMeasuring`, cleared `hasExplicitWidth`, proposed size),
    /// so the reported size is identical to what the fallback produced.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var measureContext = context
        measureContext.isMeasuring = true
        // Match the fallback: report the natural (minimum) size, not an expanded one.
        measureContext.hasExplicitWidth = false
        if let width = proposal.width {
            measureContext.availableWidth = width
        }
        if let height = proposal.height {
            measureContext.availableHeight = height
        }
        let buffer = renderToBuffer(context: measureContext)

        let fillsWidth = columns.contains { column in
            switch column.width {
            case .flexible, .ratio: return true
            case .fixed: return false
            }
        }
        return fillsWidth
            ? ViewSize.flexibleWidth(minWidth: buffer.width, height: buffer.height)
            : ViewSize.fixed(buffer.width, buffer.height)
    }

    /// Populated-state snapshot the mouse handler needs.
    private struct PopulatedRenderState {
        let handler: ItemListHandler<Value.ID>
        let focusID: String
        let visibleRange: Range<Int>
        let scrollOffsetAbove: Int
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!

        // Calculate available width inside container (subtract
        // border + padding).
        let innerWidth = max(0, context.availableWidth - 4)
        let columnWidths = calculateColumnWidths(
            availableWidth: innerWidth, spacing: columnSpacing)
        let headerLine = renderHeader(columnWidths: columnWidths, palette: palette)

        let contentLines: [String]
        let renderState: PopulatedRenderState?
        if data.isEmpty {
            contentLines = [emptyPlaceholder]
            renderState = nil
        } else {
            let result = buildPopulatedContent(
                context: context,
                stateStorage: stateStorage,
                palette: palette,
                columnWidths: columnWidths,
                innerWidth: innerWidth
            )
            contentLines = result.lines
            renderState = result.state
        }

        let container = ContainerView(
            title: nil,
            style: ContainerStyle(showHeaderSeparator: true, showFooterSeparator: false),
            padding: EdgeInsets(horizontal: 1, vertical: 0)
        ) {
            VStack(spacing: 0) {
                _TableHeaderView(line: headerLine)
                _TableContentView(lines: contentLines)
            }
        }
        var buffer = TUIkit.renderToBuffer(container, context: context)

        if let state = renderState {
            attachMouseHandlers(to: &buffer, context: context, state: state)
        }
        return buffer
    }

    // MARK: - Populated content

    /// Renders the populated data rows + scroll indicators and
    /// captures the state the mouse handler needs.
    private func buildPopulatedContent(
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        columnWidths: [Int],
        innerWidth: Int
    ) -> (lines: [String], state: PopulatedRenderState) {
        // The fixed chrome is 3 lines: the top border, the bottom
        // border, and the column-header line. What's left is the
        // scrollable content area, shared between the visible rows
        // and whichever scroll indicators are present.
        let availableHeight = context.availableHeight
        let chromeRows = 3
        let contentHeight = max(1, availableHeight - chromeRows)
        let overflowing = data.count > contentHeight

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "table",
            propertyIndex: 1  // focusID
        )
        let handler = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            contentHeight: contentHeight,
            overflowing: overflowing
        )
        FocusRegistration.register(context: context, handler: handler)
        let tableHasFocus = FocusRegistration.isFocused(
            context: context, focusID: persistedFocusID)

        // Reserve a line for each scroll indicator actually present
        // at this offset so the rows plus indicators fill the content
        // area exactly — no wasted blank line at the ends (which used
        // to push the "N more below" indicator one row too high), no
        // overflow in the middle. Mirrors _ListCore.
        if overflowing {
            let aboveLines = handler.scrollOffset > 0 ? 1 : 0
            let remaining = data.count - handler.scrollOffset
            let rowsWithoutBelow = min(remaining, max(1, contentHeight - aboveLines))
            let belowShown = handler.scrollOffset + rowsWithoutBelow < data.count
            let visibleRowCount =
                belowShown
                ? max(1, contentHeight - aboveLines - 1)
                : rowsWithoutBelow
            handler.viewportHeight = max(1, min(visibleRowCount, remaining))
        }

        let lines = composeRowLines(
            handler: handler,
            tableHasFocus: tableHasFocus,
            columnWidths: columnWidths,
            innerWidth: innerWidth,
            context: context,
            palette: palette
        )

        return (
            lines: lines,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                visibleRange: handler.visibleRange,
                scrollOffsetAbove: handler.hasContentAbove ? 1 : 0
            )
        )
    }

    /// Fetches (or creates) the persistent ``ItemListHandler``
    /// and syncs its per-frame inputs.
    private func resolveHandler(
        persistedFocusID: String,
        stateStorage: StateStorage,
        context: RenderContext,
        contentHeight: Int,
        overflowing: Bool
    ) -> ItemListHandler<Value.ID> {
        // Clamp against the largest possible visible-row count (one
        // indicator, at an end); the exact viewport is finalised by
        // the caller once the offset is known.
        let provisionalViewport =
            overflowing ? max(1, contentHeight - 1) : contentHeight
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: 0)
        let handlerBox: StateBox<ItemListHandler<Value.ID>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID,
                itemCount: data.count,
                viewportHeight: provisionalViewport,
                selectionMode: selectionMode,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value
        handler.itemCount = data.count
        handler.contentHeight = contentHeight
        handler.viewportHeight = provisionalViewport
        handler.canBeFocused = !isDisabled
        // Resolve row ids lazily: the selection handler only ever asks for the
        // visible window + the focused row (O(1) each via `data[index].id`), so
        // materialising a full id array here was O(total) waste — and `_TableCore`
        // is render-to-measure, so it ran in *both* the measure and render passes
        // every frame (~30% of the 20k-row frame). All Table rows are content, so
        // an empty `selectableIndices` already means "all selectable". Mirrors the
        // windowed List path (_ListCore.resolvePopulatedHandler).
        handler.idAt = { data[$0].id }
        handler.itemIDs = []
        // Mutate the *persistent* scroll offset only on the real render pass.
        // A measure pass may be offered a larger height than the Table finally
        // renders into (e.g. when it shares space with fixed siblings), so a
        // measure-time clamp computes `maxOffset` against too large a viewport
        // and pulls the offset back every frame — the last rows then can't be
        // reached. The render pass runs last and clamps with the true viewport,
        // so legitimate clamping (e.g. the data shrinking) still happens.
        // Mirrors _ListCore / ScrollView.
        if !context.isMeasuring {
            handler.clampScrollOffset()
            // An "above" indicator that hides exactly one row wastes its
            // line: that line could just show the row. So never rest at
            // offset 1 — snap to 0, where the first row shows with no
            // indicator (the freed line keeps the bottom row visible).
            // Mirrors _ListCore.
            if overflowing, handler.scrollOffset == 1 {
                handler.scrollOffset = 0
            }
        }
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection
        return handler
    }

    /// Stitches scroll indicators around the visible data rows.
    private func composeRowLines(
        handler: ItemListHandler<Value.ID>,
        tableHasFocus: Bool,
        columnWidths: [Int],
        innerWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        var lines: [String] = []
        if handler.hasContentAbove {
            lines.append(renderScrollIndicator(
                direction: .up,
                count: handler.rowsAbove,
                width: innerWidth,
                palette: palette
            ))
        }
        let visibleRange = handler.visibleRange
        for rowIndex in visibleRange {
            let item = data[rowIndex]
            let isFocused = handler.isFocused(at: rowIndex) && tableHasFocus
            let isSelected = handler.isSelected(at: rowIndex)
            lines.append(renderRow(
                item: item,
                columnWidths: columnWidths,
                isFocused: isFocused,
                isSelected: isSelected,
                rowWidth: innerWidth,
                context: context,
                palette: palette
            ))
        }
        if handler.hasContentBelow {
            lines.append(renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                width: innerWidth,
                palette: palette
            ))
        }
        return lines
    }

    // MARK: - Mouse handler wiring

    /// Registers the table's container-wide mouse handler and
    /// emits its hit-test region. Same shape as _ListCore — scroll-
    /// wheel scrolls, click on a data row selects + focuses,
    /// click anywhere else focuses without changing selection.
    ///
    /// Buffer layout from the container wrap:
    /// ```
    ///   y=0           top border
    ///   y=1           column header line
    ///   y=2           top scroll indicator (only when hasContentAbove)
    ///   y=2 + offset  first data row (offset = 1 when scroll indicator present)
    ///   …             data rows, one per line
    ///   y=N           bottom scroll indicator / bottom border
    /// ```
    private func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        let firstRowY = 2 + state.scrollOffsetAbove
        let mouseHandlerID = mouseDispatcher.register(
            containerMouseHandler(
                state: state,
                focusManager: focusManager,
                firstRowY: firstRowY
            )
        )
        // Insert at the back so interactive children inside a
        // row still win the dispatcher's reverse-iteration
        // match. See the parallel comment in _ListCore.
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: buffer.width, height: buffer.height,
                handlerID: mouseHandlerID
            ),
            at: 0
        )
    }

    /// The closure invoked by the container-wide hit-test
    /// region. Routes wheel to the handler's scroll position
    /// (never the selection), left-release to row hit-testing
    /// + focus, and rejects everything else.
    private func containerMouseHandler(
        state: PopulatedRenderState,
        focusManager: FocusManager,
        firstRowY: Int
    ) -> @MainActor (MouseEvent) -> Bool {
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        let visibleRange = state.visibleRange
        return { event in
            // Wheel scrolls the viewport, never the selection.
            // See the matching comment in _ListCore for the
            // model. Routed through the shared
            // ScrollableOffsetState helper so the math lives
            // in one place.
            if captureHandler.handleWheelEvent(event) { return true }

            if event.button == .left {
                guard event.phase == .released else {
                    return event.phase == .pressed
                }
                // Each data row is one line tall.
                let dataRowIndex = event.y - firstRowY
                if dataRowIndex >= 0, dataRowIndex < visibleRange.count {
                    let absoluteIndex = visibleRange.lowerBound + dataRowIndex
                    captureHandler.focusedIndex = absoluteIndex
                    captureHandler.toggleSelectionAtFocusedIndex()
                }
                focusManager.focus(id: captureFocusID)
                return true
            }
            return false
        }
    }

    // MARK: - Column Width Calculation

    private func calculateColumnWidths(availableWidth: Int, spacing: Int) -> [Int] {
        guard !columns.isEmpty else { return [] }

        let totalSpacing = spacing * (columns.count - 1)
        let indicatorWidth = 2
        let contentWidth = max(0, availableWidth - totalSpacing - indicatorWidth)

        var widths = [Int](repeating: 0, count: columns.count)
        var usedWidth = 0
        var flexibleIndices: [Int] = []

        for (index, column) in columns.enumerated() {
            switch column.width {
            case .fixed(let fixedWidth):
                widths[index] = fixedWidth
                usedWidth += fixedWidth
            case .ratio(let ratio):
                let ratioWidth = Int(Double(contentWidth) * ratio)
                widths[index] = ratioWidth
                usedWidth += ratioWidth
            case .flexible:
                flexibleIndices.append(index)
            }
        }

        if !flexibleIndices.isEmpty {
            let remainingWidth = max(0, contentWidth - usedWidth)
            let perColumn = remainingWidth / flexibleIndices.count
            let remainder = remainingWidth % flexibleIndices.count

            for (offset, index) in flexibleIndices.enumerated() {
                widths[index] = perColumn + (offset < remainder ? 1 : 0)
            }
        }

        return widths.map { max(1, $0) }
    }

    // MARK: - Header Rendering

    private func renderHeader(columnWidths: [Int], palette: any Palette) -> String {
        let spacing = String(repeating: " ", count: columnSpacing)

        let cells = zip(columns, columnWidths).map { column, width -> String in
            let aligned = alignText(
                column.title,
                width: width,
                alignment: column.alignment,
                truncationMode: column.truncationMode
            )
            return ANSIRenderer.colorize(aligned, foreground: palette.foregroundSecondary, bold: true)
        }

        return "  " + cells.joined(separator: spacing)
    }

    // MARK: - Row Rendering

    private func renderRow(
        item: Value,
        columnWidths: [Int],
        isFocused: Bool,
        isSelected: Bool,
        rowWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> String {
        let spacing = String(repeating: " ", count: columnSpacing)
        let visualState = rowVisualState(
            isFocused: isFocused,
            isSelected: isSelected,
            context: context,
            palette: palette
        )

        let styledIndicator = ANSIRenderer.colorize(
            visualState.indicator,
            foreground: visualState.indicatorColor
        )

        // Build cells using environment foreground color
        let foregroundColor = context.environment.foregroundStyle ?? palette.foreground
        let cells = zip(columns, columnWidths).map { column, width -> String in
            let value = column.value(for: item)
            let aligned = alignText(
                value,
                width: width,
                alignment: column.alignment,
                truncationMode: column.truncationMode
            )
            return ANSIRenderer.colorize(aligned, foreground: foregroundColor)
        }

        let content = styledIndicator + " " + cells.joined(separator: spacing)

        if let bgColor = visualState.backgroundColor {
            let visibleLength = content.strippedLength
            let padding = max(0, rowWidth - visibleLength)
            let paddedContent = content + String(repeating: " ", count: padding)
            return paddedContent.withPersistentBackground(bgColor)
        } else {
            return content
        }
    }

    /// Determines indicator symbol, indicator color, and background color for a table row.
    private func rowVisualState(
        isFocused: Bool,
        isSelected: Bool,
        context: RenderContext,
        palette: any Palette
    ) -> (indicator: String, indicatorColor: Color, backgroundColor: Color?) {
        if isFocused && isSelected {
            let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
            let bg = Color.lerp(dimAccent, palette.accent.opacity(ViewConstants.focusPulseMax), phase: context.environment.pulsePhase)
            return ("●", palette.accent, bg)
        } else if isFocused {
            return (" ", palette.foregroundTertiary, palette.focusBackground)
        } else if isSelected {
            // Selected row while the table itself doesn't have
            // focus. Same model as _ListCore: the
            // `unfocusedSelectionVisibility` env value controls
            // whether the indicator is shown. `.hidden` collapses
            // the row's visual state into the same as an
            // unselected unfocused row.
            if context.environment.unfocusedSelectionVisibility == .hidden {
                return (" ", palette.foregroundTertiary, nil)
            }
            return ("●", palette.accent.opacity(ViewConstants.selectionIndicator), nil)
        } else {
            return (" ", palette.foregroundTertiary, nil)
        }
    }

    // MARK: - Text Alignment

    private func alignText(
        _ text: String,
        width: Int,
        alignment: HorizontalAlignment,
        truncationMode: TruncationMode
    ) -> String {
        // Clip the value to the column width *first*: a cell that is wider
        // than its column would otherwise shove every column to its right
        // out of alignment. An over-long value is shown truncated with an
        // ellipsis so the loss of content is visible.
        let clipped = text.truncatedToWidth(width, mode: truncationMode)
        let visibleLength = clipped.strippedLength
        let padding = max(0, width - visibleLength)

        switch alignment {
        case .leading:
            return clipped + String(repeating: " ", count: padding)
        case .center:
            let leftPad = padding / 2
            let rightPad = padding - leftPad
            return String(repeating: " ", count: leftPad) + clipped + String(repeating: " ", count: rightPad)
        case .trailing:
            return String(repeating: " ", count: padding) + clipped
        }
    }
}

// MARK: - Table Content View

/// Simple view that renders pre-computed lines.
private struct _TableContentView: View, Renderable {
    let lines: [String]

    var body: Never {
        fatalError("_TableContentView renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: lines)
    }
}

// MARK: - Table Header View

/// Simple view that renders the header line.
private struct _TableHeaderView: View, Renderable {
    let line: String

    var body: Never {
        fatalError("_TableHeaderView renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: [line])
    }
}
