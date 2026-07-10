//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Table.swift
//
//  Created by LAYERED.work
//  License: MIT

// `Table` and its single cohesive render core `_TableCore` (column-width
// resolution, the single-line and multi-line layout paths, scroll indicators,
// and mouse wiring) are tightly coupled through the row/column/selection model;
// splitting them across files purely to satisfy the length ceiling would scatter
// that model for no clarity gain — the same rationale by which `type_body_length`
// is disabled project-wide and `_ListCore` keeps its `file_length` disable.
// swiftlint:disable file_length

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

    /// An action run when a row is ACTIVATED — double-clicked, or
    /// Return/Enter with the row focused (its `Value.ID` is passed). Set via
    /// ``onRowActivate(_:)``. Because a `Table`'s cells are value-based (not
    /// views), this is how a row gets an "open" action.
    var primaryAction: ((Value.ID) -> Void)?

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
            columnSpacing: columnSpacing,
            primaryAction: primaryAction
        )
    }
}

extension Table {
    /// Runs `action` when a row is double-clicked, passing that row's `id`.
    ///
    /// A `Table`'s cells are value-based rather than views, so a per-row
    /// `.onTapGesture` isn't possible; this modifier is how a row gets a
    /// double-click "open" action (e.g. a file browser opening a folder).
    /// Single clicks still select via the selection binding.
    ///
    /// This is a TUI-specific modifier — SwiftUI's `Table` has no direct
    /// equivalent.
    ///
    /// - Parameter action: Called with the double-clicked row's `id`.
    public func onRowActivate(_ action: @escaping (Value.ID) -> Void) -> Table {
        var copy = self
        copy.primaryAction = action
        return copy
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
    var primaryAction: ((Value.ID) -> Void)?

    var body: Never {
        fatalError("_TableCore renders via Renderable")
    }

    /// Sizes the table analytically rather than by rendering it to measure.
    ///
    /// Being `Renderable`-only, `_TableCore` previously fell through `measureChild`
    /// to the fallback, which rendered the table to measure it — at the time TWICE
    /// per measure (a second render at `naturalWidth + 8` probed width-flexibility,
    /// since retired) — on top of the real render. On a 20k-row table that was
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
            // `.fit` is content-sized (a fixed width derived from the data), so
            // like `.fixed` it does not grow with the available width.
            case .fixed, .fit: return false
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
        /// The line height of each visible row, in `visibleRange` order, so a
        /// click can map a line to its row when rows span multiple lines. Left
        /// empty for a single-line table (the line offset is the row offset, with
        /// no per-frame array to allocate).
        let visibleRowHeights: [Int]
        /// Whether a single-line scrollbar column was drawn (only the single-line
        /// path shows one). Drives the bar's mouse handler in `attachMouseHandlers`.
        var hasScrollbar = false
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!

        // Calculate available width inside container (subtract border + padding).
        let innerWidth = max(0, context.availableWidth - 4)

        // A single-line table decides a scrollbar cheaply (one line per row),
        // reserving a column inside the border for it. Multi-line tables wire the
        // scrollbar separately (their overflow needs the total wrapped height).
        let rowArea = max(1, context.availableHeight - 3)
        let barVisibility = context.environment.scrollbarVisibility
        let isMultiLine = columns.contains { $0.lineLimit > 1 }
        let wantsScrollbar =
            !isMultiLine && !data.isEmpty && barVisibility != .hidden
            && (barVisibility == .visible || data.count > rowArea)
        let contentInnerWidth = max(1, innerWidth - (wantsScrollbar ? 1 : 0))

        let columnWidths = calculateColumnWidths(
            availableWidth: contentInnerWidth, spacing: columnSpacing)
        var headerLine = renderHeader(columnWidths: columnWidths, palette: palette)
        if wantsScrollbar {
            // Pad the header to the full inner width so it aligns with the rows
            // (whose last column is the scrollbar); the cell above the bar is blank.
            headerLine += String(repeating: " ", count: max(0, innerWidth - headerLine.strippedLength))
        }

        let contentLines: [String]
        let renderState: PopulatedRenderState?
        if data.isEmpty {
            contentLines = [emptyPlaceholder]
            renderState = nil
        } else if wantsScrollbar {
            let result = buildScrollbarContent(
                context: context, stateStorage: stateStorage, palette: palette,
                columnWidths: columnWidths, contentInnerWidth: contentInnerWidth)
            contentLines = result.lines
            renderState = result.state
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
            // `.leading`: the header sits left, over its columns. A focused/selected
            // row or a scroll indicator must never be wider than the other lines, or
            // this VStack would centre the narrower header over them — so those are
            // padded to the same content width (see `contentWidth` below), not to the
            // full interior, keeping every line the same width.
            VStack(alignment: .leading, spacing: 0) {
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
        // Multi-line cells (any column with a line limit above 1) take a separate,
        // height-aware layout path. Single-line tables keep the original
        // row-per-line path below completely untouched.
        if columns.contains(where: { $0.lineLimit > 1 }) {
            return buildMultiLineContent(
                context: context, stateStorage: stateStorage, palette: palette,
                columnWidths: columnWidths, innerWidth: innerWidth)
        }

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
                scrollOffsetAbove: handler.hasContentAbove ? 1 : 0,
                // Single-line rows: leave empty (no per-frame array); the click
                // handler maps the line offset straight to the row.
                visibleRowHeights: []
            )
        )
    }

    // MARK: - Scrollbar content (single-line)

    /// The render path for a single-line table that shows a scrollbar. The bar
    /// supersedes the "N more" text indicators, so the whole row area is the
    /// viewport (no indicator reservation); each visible row is built one column
    /// narrower and the styled scrollbar cell is appended to its right, with the
    /// area below the last row left blank behind the bar.
    private func buildScrollbarContent(
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        columnWidths: [Int],
        contentInnerWidth: Int
    ) -> (lines: [String], state: PopulatedRenderState) {
        let contentHeight = max(1, context.availableHeight - 3)
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID, defaultPrefix: "table", propertyIndex: 1)
        let handler = resolveHandler(
            persistedFocusID: persistedFocusID, stateStorage: stateStorage, context: context,
            contentHeight: contentHeight, overflowing: data.count > contentHeight,
            showsScrollbar: true)
        // The whole row area is visible — the bar, not a text indicator, marks the
        // off-screen rows — so the viewport is the full content height.
        handler.viewportHeight = contentHeight
        if !context.isMeasuring {
            handler.clampScrollOffset()
        }
        FocusRegistration.register(context: context, handler: handler)
        let tableHasFocus = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let visibleRange = handler.scrollOffset..<min(data.count, handler.scrollOffset + contentHeight)
        let bar = ScrollbarRenderer.verticalScrollbar(
            height: contentHeight, extent: data.count, viewport: contentHeight, offset: handler.scrollOffset,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: ScrollbarColors(
                thumb: palette.foregroundSecondary, track: palette.foregroundQuaternary,
                arrow: palette.foregroundTertiary))
        let emptyCell = ANSIRenderer.colorize(" ", background: palette.foregroundQuaternary)

        var lines: [String] = []
        lines.reserveCapacity(contentHeight)
        for line in 0..<contentHeight {
            let rowLine: String
            if line < visibleRange.count {
                let rowIndex = visibleRange.lowerBound + line
                rowLine = renderRow(
                    item: data[rowIndex], columnWidths: columnWidths,
                    isFocused: handler.isFocused(at: rowIndex) && tableHasFocus,
                    isSelected: handler.isSelected(at: rowIndex),
                    rowWidth: contentInnerWidth, context: context, palette: palette)
            } else {
                rowLine = ""
            }
            let pad = max(0, contentInnerWidth - rowLine.strippedLength)
            lines.append(rowLine + String(repeating: " ", count: pad) + (line < bar.count ? bar[line] : emptyCell))
        }

        return (
            lines,
            PopulatedRenderState(
                handler: handler, focusID: persistedFocusID, visibleRange: visibleRange,
                scrollOffsetAbove: 0, visibleRowHeights: [], hasScrollbar: true))
    }

    // MARK: - Multi-line content (variable row heights)

    /// The render path for a table with multi-line cells. Rows can be taller than
    /// one line, so the visible window, the scroll bounds, focus-reveal, and the
    /// click mapping are all line-aware (driven by per-row heights). The
    /// single-line path above is left completely untouched.
    private func buildMultiLineContent(
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        columnWidths: [Int],
        innerWidth: Int
    ) -> (lines: [String], state: PopulatedRenderState) {
        // 3 = top border + column header + bottom border.
        let contentHeight = max(1, context.availableHeight - 3)

        // Row heights are answered lazily. The scroll arithmetic below touches only
        // a viewport's worth of rows — the visible window, plus the bottom suffix
        // that fixes the furthest scroll — so a tall table needn't wrap every
        // off-screen row (the optimisation a scrollbar's *absence* permits: nothing
        // exposes the total extent). Memoised within this render since the window
        // and the suffix overlap once scrolled near the end.
        var heightCache: [Int: Int] = [:]
        func heightOf(_ index: Int) -> Int {
            if let cached = heightCache[index] { return cached }
            let height = rowHeight(of: data[index], columnWidths: columnWidths)
            heightCache[index] = height
            return height
        }

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID, defaultPrefix: "table", propertyIndex: 1)
        let handlerKey = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let handlerBox: StateBox<ItemListHandler<Value.ID>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID, itemCount: data.count, viewportHeight: 1,
                selectionMode: selectionMode, canBeFocused: !isDisabled))
        let handler = handlerBox.value
        handler.itemCount = data.count
        handler.contentHeight = contentHeight
        handler.canBeFocused = !isDisabled
        handler.primaryAction = primaryAction
        // Captured at render so Shift+arrow can accelerate the focus cursor at
        // event time, when the environment is no longer reachable.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        handler.idAt = { data[$0].id }
        handler.itemIDs = []
        // The reveal-on-focus arithmetic (run between renders, on key events)
        // answers heights lazily too, from this frame's data and column widths.
        handler.rowHeight = { rowHeight(of: data[$0], columnWidths: columnWidths) }
        // Choose viewportHeight so the handler's row-based maxOffset
        // (itemCount − viewportHeight) equals the height-aware furthest scroll.
        let furthest = maxScrollOffset(count: data.count, contentHeight: contentHeight, height: heightOf)
        handler.viewportHeight = max(1, data.count - furthest)
        if !context.isMeasuring {
            handler.clampScrollOffset()
        }
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection

        FocusRegistration.register(context: context, handler: handler)
        let tableHasFocus = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let window = rowWindow(
            scrollOffset: handler.scrollOffset, count: data.count,
            contentHeight: contentHeight, height: heightOf)
        let lines = composeMultiLineRows(
            window: window, handler: handler, tableHasFocus: tableHasFocus,
            columnWidths: columnWidths, innerWidth: innerWidth, context: context, palette: palette)

        return (
            lines: lines,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                visibleRange: window.range,
                scrollOffsetAbove: window.showAbove ? 1 : 0,
                visibleRowHeights: window.range.map(heightOf)
            )
        )
    }

    /// The wrapped lines of each cell of a row plus the row's height (its tallest
    /// cell). Each cell is laid out into its column with `TextWrapping`, so an
    /// embedded newline or an over-long value expands within the column up to the
    /// column's line limit and then clips — the same model `Text` uses.
    private func cellLayout(
        for item: Value, columnWidths: [Int]
    ) -> (cells: [[String]], height: Int) {
        var cells: [[String]] = []
        cells.reserveCapacity(columns.count)
        var height = 1
        for (column, width) in zip(columns, columnWidths) {
            let wrapped = TextWrapping.fit(
                column.value(for: item), width: max(1, width),
                maxLines: column.lineLimit, mode: column.truncationMode)
            height = max(height, wrapped.count)
            cells.append(wrapped)
        }
        return (cells, height)
    }

    /// The height in lines of one row — its tallest cell wrapped into its column.
    /// Height-only (the wrapped lines are discarded), so the off-screen rows the
    /// scroll arithmetic has to measure are wrapped without also allocating their
    /// cell content; ``cellLayout(for:columnWidths:)`` returns the cells too, for
    /// the rows actually rendered.
    private func rowHeight(of item: Value, columnWidths: [Int]) -> Int {
        var height = 1
        for (column, width) in zip(columns, columnWidths) {
            let lineCount = TextWrapping.fit(
                column.value(for: item), width: max(1, width),
                maxLines: column.lineLimit, mode: column.truncationMode
            ).count
            height = max(height, lineCount)
        }
        return height
    }

    /// The furthest the table can scroll: the largest first-visible row such that
    /// the remaining rows still fill the content area (reserving a line for the
    /// "above" indicator that shows whenever the first visible row isn't row 0).
    private func maxScrollOffset(count: Int, contentHeight: Int, height: (Int) -> Int) -> Int {
        var used = 0
        var offset = count
        while offset > 0 {
            let aboveReserve = (offset - 1) > 0 ? 1 : 0
            let rowH = height(offset - 1)
            if used + rowH + aboveReserve > contentHeight { break }
            used += rowH
            offset -= 1
        }
        return offset
    }

    /// The window of rows visible at `scrollOffset`: accumulate row heights until
    /// the content area fills, reserving a line for each scroll indicator actually
    /// shown. Mirrors the single-line indicator reservation, height-aware.
    private func rowWindow(
        scrollOffset: Int, count: Int, contentHeight: Int, height: (Int) -> Int
    ) -> (range: Range<Int>, showAbove: Bool, showBelow: Bool) {
        guard count > 0 else { return (0..<0, false, false) }
        let offset = min(max(0, scrollOffset), count - 1)
        let showAbove = offset > 0

        func fill(budget: Int) -> Int {
            var used = 0
            var end = offset
            while end < count {
                let rowH = height(end)
                if used + rowH > budget && end > offset { break }
                used += rowH
                end += 1
            }
            return max(offset + 1, end)
        }

        var end = fill(budget: contentHeight - (showAbove ? 1 : 0))
        if end < count {
            end = fill(budget: contentHeight - (showAbove ? 1 : 0) - 1)
        }
        return (offset..<min(count, end), showAbove, end < count)
    }

    /// Stitches scroll indicators around the visible multi-line rows.
    private func composeMultiLineRows(
        window: (range: Range<Int>, showAbove: Bool, showBelow: Bool),
        handler: ItemListHandler<Value.ID>,
        tableHasFocus: Bool,
        columnWidths: [Int],
        innerWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        // Every line — focused-row backgrounds and indicators included — is padded
        // to the *content* width (the columns), not the full interior, so a focused
        // row or a scroll indicator is never wider than the header and rows; that
        // width mismatch is what made the wrapping VStack centre the header.
        let contentWidth = tableContentWidth(columnWidths, within: innerWidth)
        var lines: [String] = []
        if window.showAbove {
            lines.append(renderScrollIndicator(
                direction: .up, count: window.range.lowerBound, width: contentWidth, palette: palette))
        }
        for rowIndex in window.range {
            lines.append(contentsOf: renderMultiLineRow(
                item: data[rowIndex],
                isFocused: handler.isFocused(at: rowIndex) && tableHasFocus,
                isSelected: handler.isSelected(at: rowIndex),
                columnWidths: columnWidths, rowWidth: contentWidth, context: context, palette: palette))
        }
        if window.showBelow {
            lines.append(renderScrollIndicator(
                direction: .down, count: data.count - window.range.upperBound,
                width: contentWidth, palette: palette))
        }
        return lines
    }

    /// Renders one (possibly multi-line) row: the selection indicator on the first
    /// line, each column's wrapped cell lines beneath it, shorter cells padded with
    /// blank lines, and the selection/focus background spanning every line.
    private func renderMultiLineRow(
        item: Value,
        isFocused: Bool,
        isSelected: Bool,
        columnWidths: [Int],
        rowWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        let spacing = String(repeating: " ", count: columnSpacing)
        let visual = rowVisualState(
            isFocused: isFocused, isSelected: isSelected, context: context, palette: palette)
        let styledIndicator = ANSIRenderer.colorize(visual.indicator, foreground: visual.indicatorColor)
        let foreground = context.environment.foregroundStyle ?? palette.foreground
        let layout = cellLayout(for: item, columnWidths: columnWidths)

        var lines: [String] = []
        for lineIndex in 0..<layout.height {
            // The indicator shows only on the first line; continuation lines keep
            // the same two-cell gutter so the columns line up beneath it.
            let gutter = lineIndex == 0 ? styledIndicator + " " : "  "
            let cells = zip(columns, columnWidths).enumerated().map { index, pair -> String in
                let (column, width) = pair
                let cellLines = layout.cells[index]
                let text = lineIndex < cellLines.count ? cellLines[lineIndex] : ""
                let aligned = alignText(
                    text, width: width, alignment: column.alignment, truncationMode: column.truncationMode)
                return ANSIRenderer.colorize(aligned, foreground: foreground)
            }
            let content = gutter + cells.joined(separator: spacing)
            if let bgColor = visual.backgroundColor {
                let padding = max(0, rowWidth - content.strippedLength)
                lines.append(
                    (content + String(repeating: " ", count: padding)).withPersistentBackground(bgColor))
            } else {
                lines.append(content)
            }
        }
        return lines
    }

    /// Fetches (or creates) the persistent ``ItemListHandler``
    /// and syncs its per-frame inputs.
    private func resolveHandler(
        persistedFocusID: String,
        stateStorage: StateStorage,
        context: RenderContext,
        contentHeight: Int,
        overflowing: Bool,
        showsScrollbar: Bool = false
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
        handler.primaryAction = primaryAction
        handler.rowHeight = nil  // single-line path: uniform-height scroll math
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
            // Mirrors _ListCore. A scrollbar shows no such indicator line,
            // so it has nothing to waste — and the snap would otherwise undo a
            // single down-arrow click (0→1→0). Skip it when the bar is shown.
            if overflowing, !showsScrollbar, handler.scrollOffset == 1 {
                handler.scrollOffset = 0
            }
        }
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection
        return handler
    }

    /// The table's content width: the selection gutter plus the columns and their
    /// spacing, clamped to the interior. Focused-row backgrounds and indicators are
    /// padded to *this*, not the full interior, so every line is the same width and
    /// the table neither jumps wider on focus nor centres its header over a lone
    /// full-width row. A `.flexible` column already fills the interior, so there the
    /// two widths coincide and nothing changes.
    private func tableContentWidth(_ columnWidths: [Int], within innerWidth: Int) -> Int {
        let gutter = 2  // selection indicator + its trailing space
        let spacing = columnSpacing * max(0, columnWidths.count - 1)
        return min(innerWidth, gutter + columnWidths.reduce(0, +) + spacing)
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
        let contentWidth = tableContentWidth(columnWidths, within: innerWidth)
        var lines: [String] = []
        if handler.hasContentAbove {
            lines.append(renderScrollIndicator(
                direction: .up,
                count: handler.rowsAbove,
                width: contentWidth,
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
                rowWidth: contentWidth,
                context: context,
                palette: palette
            ))
        }
        if handler.hasContentBelow {
            lines.append(renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                width: contentWidth,
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

        // The scrollbar's own handler goes in first so the container's later
        // insert(at: 0) pushes it to a higher index — hit-tested ahead of the
        // container (reverse iteration) for its single column, while the container
        // still wins everywhere else. The bar is the rightmost interior column
        // (availableWidth − 3: border + padding each side, minus the bar) over the
        // content rows; it is row-exact (one cell per row) for the single-line path.
        if state.hasScrollbar {
            let barHeight = max(1, context.availableHeight - 3)
            let barHandler = ScrollbarRenderer.verticalMouseHandler(
                for: state.handler, length: barHeight,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                behavior: context.environment.scrollbarClickBehavior)
            let barHandlerID = mouseDispatcher.register(barHandler)
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: max(0, context.availableWidth - 3), offsetY: firstRowY,
                    width: 1, height: barHeight, handlerID: barHandlerID),
                at: 0
            )
            ScrollbarRenderer.driveAutoRepeat(
                state: state.handler,
                token: "table-scrollbar-repeat-\(context.identity.path)", context: context)
        }

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
        focusManager: FocusManager?,
        firstRowY: Int
    ) -> @MainActor (MouseEvent) -> Bool {
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        let visibleRange = state.visibleRange
        let visibleRowHeights = state.visibleRowHeights
        let rowIDs = data.map(\.id)
        let capturedPrimaryAction = primaryAction
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
                // Map the clicked line to its data row. Single-line tables leave
                // `visibleRowHeights` empty (no per-frame array) — the line offset
                // is the row. Multi-line tables walk the visible rows' heights, so
                // a click anywhere in a tall row selects it.
                let lineOffset = event.y - firstRowY
                var clickedIndex: Int?
                if visibleRowHeights.isEmpty {
                    if lineOffset >= 0, lineOffset < visibleRange.count {
                        clickedIndex = visibleRange.lowerBound + lineOffset
                    }
                } else if lineOffset >= 0 {
                    var accumulated = 0
                    for (offset, height) in visibleRowHeights.enumerated() {
                        if lineOffset < accumulated + height {
                            clickedIndex = visibleRange.lowerBound + offset
                            break
                        }
                        accumulated += height
                    }
                }
                if let index = clickedIndex {
                    captureHandler.focusedIndex = index
                    // A double-click fires the row's primary action ("open");
                    // a single click toggles selection as before.
                    if event.clickCount >= 2, let action = capturedPrimaryAction,
                        index >= 0, index < rowIDs.count
                    {
                        action(rowIDs[index])
                    } else {
                        captureHandler.toggleSelectionAtFocusedIndex()
                    }
                }
                focusManager?.focus(id: captureFocusID)
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
            case .fit:
                // Fit to the widest of the header and every cell value in this
                // column. O(rows) per column, but stable as the table scrolls
                // (all rows are considered, not just the visible ones).
                let fitted = data.reduce(column.title.strippedLength) { widest, item in
                    max(widest, column.value(for: item).strippedLength)
                }
                widths[index] = fitted
                usedWidth += fitted
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
            let bg = SelectionIndicator.resolve(isFocused: true, context: context)
                .color(dim: dimAccent, bright: palette.accent.opacity(ViewConstants.focusPulseMax))
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
