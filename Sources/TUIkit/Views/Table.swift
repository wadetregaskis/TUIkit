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

import Foundation
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

    /// The action that reorders the data, set via ``onMove(_:)``. Present means
    /// the rows can be dragged into a new order.
    var moveAction: ((IndexSet, Int) -> Void)?

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
            primaryAction: primaryAction,
            moveAction: moveAction
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

    /// Lets the rows be dragged into a new order, calling `action` to perform the
    /// move — the same signature as SwiftUI's `DynamicViewContent.onMove(perform:)`
    /// and satisfied the same way, with `move(fromOffsets:toOffset:)`:
    ///
    /// ```swift
    /// Table(tasks, selection: $selected) {
    ///     TableColumn("Task", value: \.title)
    /// }
    /// .onMove { tasks.move(fromOffsets: $0, toOffset: $1) }
    /// ```
    ///
    /// The drag shows whatever ``View/rowReorderFeedback(_:)`` asks for, exactly as
    /// a `List`'s does: they share one state machine.
    ///
    /// This is a modifier on the `Table` rather than on its rows, because a
    /// `Table`'s rows are values and its cells are not views — there is no
    /// `ForEach` to attach SwiftUI's row-level `onMove` to. A **multi-line**
    /// table (any column with a `lineLimit` above 1) reorders too, but always
    /// with ``RowReorderFeedback/live`` feedback: a drop slot there would have to
    /// take part in the line-budget arithmetic that lets a tall row be partially
    /// clipped, and moving the rows themselves needs no slot.
    ///
    /// - Parameter action: Called with the offsets being moved and the
    ///   destination offset, measured against the collection before the move.
    public func onMove(_ action: @escaping (IndexSet, Int) -> Void) -> Table {
        var copy = self
        copy.moveAction = action
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

        // Clamped: spacing reaches `String(repeating:count:)` in three
        // places, which traps on a negative count. `columnSpacing:` is a
        // public init parameter with no other validation, so a caller
        // computing it (or just passing -1) would kill the app. Clamp once
        // here, at the boundary, so every use downstream is safe by
        // construction rather than by remembering.
        self.columnSpacing = max(0, columnSpacing)
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

        // Clamped: spacing reaches `String(repeating:count:)` in three
        // places, which traps on a negative count. `columnSpacing:` is a
        // public init parameter with no other validation, so a caller
        // computing it (or just passing -1) would kill the app. Clamp once
        // here, at the boundary, so every use downstream is safe by
        // construction rather than by remembering.
        self.columnSpacing = max(0, columnSpacing)
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
    /// The inset between the table's border and its row lines.
    ///
    /// One constant because two things must agree about it: the layout that
    /// draws the rows there, and the mouse maths that works out which cell of a
    /// row a press landed on. They drifted apart once already — see
    /// `rowContentLeft` in `attachMouseHandlers`.
    static var containerPadding: EdgeInsets { EdgeInsets(horizontal: 1, vertical: 0) }

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
    var moveAction: ((IndexSet, Int) -> Void)?

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

        // A single-line table's dimensions are analytic — every row is one
        // line, so the height is a row count and the width is column
        // arithmetic. Rendering the whole table (styled cells, ANSI-aware
        // padding) just to read the buffer's size dominated the measure
        // pass of large tables. Multi-line tables keep the render-based
        // measure: their height is the sum of per-row wrapped heights.
        let size: (width: Int, height: Int)
        if columns.contains(where: { $0.lineLimit > 1 }) {
            let buffer = renderToBuffer(context: measureContext)
            size = (buffer.width, buffer.height)
        } else {
            size = analyticSingleLineSize(context: measureContext)
        }

        let fillsWidth = columns.contains { column in
            switch column.width {
            case .flexible, .ratio: return true
            // `.fit` is content-sized (a fixed width derived from the data), so
            // like `.fixed` it does not grow with the available width.
            case .fixed, .fit: return false
            }
        }
        return fillsWidth
            ? ViewSize.flexibleWidth(minWidth: size.width, height: size.height)
            : ViewSize.fixed(size.width, size.height)
    }

    /// The single-line table's rendered size, computed without building its
    /// rows: the header and column arithmetic are O(columns), the content
    /// block is a fixed-size stand-in reporting the exact line count and
    /// width the real rows would occupy, and the shared ``ContainerView``
    /// chrome is *measured* for real so padding/border/fill semantics stay
    /// exactly the render path's. Mirrors the corresponding line/width
    /// choices in `renderToBuffer` / `buildScrollbarContent` /
    /// `buildPopulatedContent` — TableAnalyticMeasureTests holds the two
    /// paths equal across the configuration matrix.
    private func analyticSingleLineSize(context: RenderContext) -> (width: Int, height: Int) {
        let palette = context.environment.palette
        let innerWidth = max(0, context.availableWidth - 4)
        let rowArea = max(1, context.availableHeight - 3)
        let barVisibility = context.environment.scrollbarVisibility
        let wantsScrollbar =
            !data.isEmpty && barVisibility != .hidden
            && (barVisibility == .visible || data.count > rowArea)
        let contentInnerWidth = max(1, innerWidth - (wantsScrollbar ? 1 : 0))
        let columnWidths = calculateColumnWidths(
            availableWidth: contentInnerWidth, spacing: columnSpacing)
        var headerLine = renderHeader(columnWidths: columnWidths, palette: palette)
        if wantsScrollbar {
            headerLine += String(
                repeating: " ", count: max(0, innerWidth - headerLine.strippedLength))
        }

        let contentSize: (width: Int, height: Int)
        if data.isEmpty {
            contentSize = (emptyPlaceholder.strippedLength, 1)
        } else if wantsScrollbar {
            // The scrollbar path fills the whole content area: every line is
            // the row content padded to `contentInnerWidth` plus the bar cell.
            contentSize = (contentInnerWidth + 1, rowArea)
        } else {
            // The plain path emits the visible rows plus indicator lines,
            // filling the content area exactly when overflowing; rows are
            // padded to the table's content width, but an indicator line can
            // exceed it ("▼ N more below" on narrow tables), so the ones the
            // render pass would draw at the current scroll state are built
            // (O(1) each) and folded into the width.
            let contentWidth = tableContentWidth(columnWidths, within: innerWidth)
            var widest = contentWidth
            if data.count > rowArea {
                let persistedFocusID = FocusRegistration.persistFocusID(
                    context: context, explicitFocusID: focusID,
                    defaultPrefix: "table", propertyIndex: 1)
                let handler = resolveHandler(
                    persistedFocusID: persistedFocusID,
                    stateStorage: context.environment.stateStorage!,
                    context: context, contentHeight: rowArea, overflowing: true)
                reserveIndicatorLines(handler: handler, contentHeight: rowArea)
                // Measure with the SAME locale the display path uses, or a
                // grouped "12,000" would be measured as "12000" and the column
                // sized one cell short.
                let measureLocale = context.environment.locale
                if handler.hasContentAbove {
                    widest = max(
                        widest,
                        renderScrollIndicator(
                            direction: .up, count: handler.rowsAbove,
                            unit: .rows,
                            width: contentWidth, palette: palette, locale: measureLocale
                        ).strippedLength)
                }
                if handler.hasContentBelow {
                    widest = max(
                        widest,
                        renderScrollIndicator(
                            direction: .down, count: handler.rowsBelow,
                            unit: .rows,
                            width: contentWidth, palette: palette, locale: measureLocale
                        ).strippedLength)
                }
            }
            contentSize = (widest, min(data.count, rowArea))
        }

        let container = ContainerView(
            title: nil,
            style: ContainerStyle(showHeaderSeparator: true, showFooterSeparator: false),
            padding: Self.containerPadding
        ) {
            VStack(alignment: .leading, spacing: 0) {
                _TableHeaderView(line: headerLine)
                _TableSizeStub(width: contentSize.width, height: contentSize.height)
            }
        }
        let measured = measureChild(
            container,
            proposal: ProposedSize(
                width: context.availableWidth, height: context.availableHeight),
            context: context)
        return (measured.width, measured.height)
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

        /// This frame's column widths and row width — enough to re-render any
        /// row on demand, which is how a ``RowReorderFeedback/cursor`` drag gets
        /// its floating preview.
        ///
        /// Deliberately NOT the row line as drawn: that line is styled for the
        /// grid it sits in (selection background, padding out to the interior
        /// width, the scrollbar's column beside it), and floating it painted
        /// over the scrollbar and the right border. What rides the pointer is
        /// the row as its own object — the contract `_ListCore` already keeps by
        /// floating the row's own content buffer.
        var columnWidths: [Int] = []
        var rowContentWidth = 0
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!

        // Rows beyond the viewport are skipped, not gone: retain their state
        // (see StateStorage.retainSubtree). Render path only, per the
        // measure-side-effect rule.
        if !context.isMeasuring {
            stateStorage.retainSubtree(context.identity)
        }

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
        handler.publishEscapeClaim(context: context, isFocused: tableHasFocus)

        if overflowing {
            reserveIndicatorLines(handler: handler, contentHeight: contentHeight)
        }

        let composed = composeRowLines(
            handler: handler,
            tableHasFocus: tableHasFocus,
            columnWidths: columnWidths,
            innerWidth: innerWidth,
            context: context,
            palette: palette
        )

        return (
            lines: composed.lines,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                visibleRange: handler.visibleRange,
                scrollOffsetAbove: handler.hasContentAbove ? 1 : 0,
                // Single-line rows: leave empty (no per-frame array); the click
                // handler maps the line offset straight to the row.
                visibleRowHeights: [],
                columnWidths: columnWidths,
                rowContentWidth: innerWidth
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
        handler.publishEscapeClaim(context: context, isFocused: tableHasFocus)

        // The handler's accessor, not a raw `scrollOffset..<min(…)`: the
        // persisted offset can exceed a freshly-shrunk `data.count` during a
        // measure pass (the clamp above is render-gated), and the raw form
        // would construct an inverted range (e.g. `1300..<2`) and trap.
        let visibleRange = handler.visibleRange
        let bar = ScrollbarRenderer.verticalScrollbar(
            height: contentHeight, extent: data.count, viewport: contentHeight, offset: visibleRange.lowerBound,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: ScrollbarColors(
                thumb: palette.foregroundSecondary, track: palette.foregroundQuaternary,
                arrow: palette.foregroundTertiary))
        let emptyCell = ANSIRenderer.colorize(" ", background: palette.foregroundQuaternary)

        // Content-only row lines; the bar cell is merged in at the END, keyed by
        // absolute line index, so an overscroll slide moves the rows and leaves
        // the bar exactly where it is (§1.5).
        //
        // Drawn in reorder order (the dragged row out, a slot where it would
        // land) — see `composeRowLines` for the same two lines of it.
        let drawn = handler.reorderDrawnRows(visibleRange)
        publishRowBands(handler: handler, drawn: drawn, slide: handler.overscrollState.excursion)
        var rowLines: [String] = []
        rowLines.reserveCapacity(contentHeight)
        for line in 0..<contentHeight {
            let rowLine: String
            switch line < drawn.count ? drawn[line] : nil {
            case .row(let rowIndex):
                rowLine = renderRow(
                    item: data[rowIndex], columnWidths: columnWidths,
                    isFocused: handler.isCursorRow(rowIndex) && tableHasFocus,
                    isSelected: handler.isSelected(at: rowIndex),
                    rowWidth: contentInnerWidth, context: context, palette: palette)
            case .slot:
                rowLine = reorderSlotLine(
                    handler: handler, columnWidths: columnWidths, rowWidth: contentInnerWidth,
                    context: context, palette: palette)
            case nil:
                rowLine = ""
            }
            let pad = max(0, contentInnerWidth - rowLine.strippedLength)
            rowLines.append(rowLine + String(repeating: " ", count: pad))
        }
        let blankRow = String(repeating: " ", count: max(0, contentInnerWidth))
        let lines = handler.overscrollState.slid(rowLines, blank: blankRow)
            .enumerated()
            .map { $0.element + ($0.offset < bar.count ? bar[$0.offset] : emptyCell) }

        return (
            lines,
            PopulatedRenderState(
                handler: handler, focusID: persistedFocusID, visibleRange: visibleRange,
                scrollOffsetAbove: 0, visibleRowHeights: [], hasScrollbar: true,
                columnWidths: columnWidths, rowContentWidth: contentInnerWidth))
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
        handler.onMove = moveAction
        // Multi-line rows reorder with `.live` feedback only: a drop slot would
        // have to take part in the line-budget arithmetic below that lets a tall
        // row be partially clipped, and moving the rows themselves needs no slot.
        // Stated in ``Table/onMove(_:)``.
        handler.reorderFeedback = .live
        // Captured at render so Shift+arrow can accelerate the focus cursor at
        // event time, when the environment is no longer reachable.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        // The app-customisable key bindings, resolved once here rather than
        // per keystroke (see RowShortcuts.lookup).
        handler.shortcuts = context.environment.rowShortcuts.lookup(
            commandKey: context.environment.commandKey)
        // `.cursor` feedback needs a session to float the row above the frame.
        handler.canFloatDraggedRow = context.environment.dragAndDropSession != nil
        // Captured so a cancel can take the floating preview down itself.
        handler.dragSession = context.environment.dragAndDropSession
        handler.isScrollEnabled = context.environment.isScrollEnabled
        // §1.5: how far past its edges this view may be pushed, re-resolved
        // every frame (a `.viewport`-relative allowance moves with the
        // terminal) and pulling any existing excursion back inside it.
        handler.overscrollState.resolve(
            top: context.environment.scrollOverscrollTop,
            bottom: context.environment.scrollOverscrollBottom,
            viewportHeight: handler.viewportHeight)
        handler.wheelEdgeHold.delayNanos = context.environment.scrollChainingDelay.clampedNanoseconds
        // Captured at render so a USER wheel scroll can release a bound anchor
        // at event time, and so the anchor hold below can resolve its mode.
        // Mirrors _ListCore.resolvePopulatedHandler — a Table anchors exactly
        // as a List does.
        handler.anchorPositionBinding = context.environment.anchorPosition
        handler.declaredAnchorMode = ScrollAnchorMode.resolved(
            defaultScrollAnchor: context.environment.defaultScrollAnchor)
        handler.idAt = { data[$0].id }
        handler.itemIDs = []
        // The reveal-on-focus arithmetic (run between renders, on key events)
        // answers heights lazily too, from this frame's data and column widths.
        handler.rowHeight = { rowHeight(of: data[$0], columnWidths: columnWidths) }
        // Captured for wheel events, which arrive when the environment is out
        // of reach — line granularity steps by lines through the tall rows.
        handler.scrollGranularity = context.environment.scrollGranularity
        handler.followMargin = context.environment.scrollFollowMargin
        // Choose viewportHeight so the handler's row-based maxOffset
        // (itemCount − viewportHeight) equals the height-aware furthest scroll.
        let furthest = maxScrollOffset(count: data.count, contentHeight: contentHeight, height: heightOf)
        handler.viewportHeight = max(1, data.count - furthest)
        if !context.isMeasuring {
            handler.clampScrollOffset()
            handler.clampTopClip()
            // Apply whichever anchor is in effect (§1.1) — a `.row` designation
            // pins that row, a `.bottom` edge follows the tail. Render pass only
            // (it mutates the persistent offset), and after `idAt` above so a row
            // key resolves. A no-op for an unanchored Table. Mirrors _ListCore.
            handler.applyAnchorHold()
        }
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection

        FocusRegistration.register(context: context, handler: handler)
        let tableHasFocus = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        handler.publishEscapeClaim(context: context, isFocused: tableHasFocus)

        let window = rowWindow(
            scrollOffset: handler.scrollOffset, count: data.count,
            contentHeight: contentHeight, topClip: handler.scrollTopClipLines,
            lineGranularity: context.environment.scrollGranularity == .line, height: heightOf)
        // The window may have absorbed a top clip (or a whole first row) that
        // an indicator would otherwise have announced — the rows are drawn
        // from ITS position, so the mouse mapping must measure from it too.
        let topClip = window.topClip
        let lines = composeMultiLineRows(
            window: window, handler: handler, tableHasFocus: tableHasFocus,
            columnWidths: columnWidths, innerWidth: innerWidth,
            contentHeight: contentHeight, context: context, palette: palette)

        // The first row's on-screen height is net of the line-granularity top
        // clip — the mouse row-mapping walks these heights from the first
        // visible line, so they must be as-rendered.
        var visibleRowHeights = window.range.map(heightOf)
        if topClip > 0, !visibleRowHeights.isEmpty {
            visibleRowHeights[0] = max(1, visibleRowHeights[0] - topClip)
        }
        publishMultiLineRowBands(
            handler: handler, range: window.range, heights: visibleRowHeights)
        return (
            lines: lines,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                visibleRange: window.range,
                scrollOffsetAbove: window.showAbove ? 1 : 0,
                visibleRowHeights: visibleRowHeights
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
        scrollOffset: Int, count: Int, contentHeight: Int, topClip: Int = 0,
        lineGranularity: Bool = false, height: (Int) -> Int
    ) -> (range: Range<Int>, showAbove: Bool, showBelow: Bool, topClip: Int) {
        guard count > 0 else { return (0..<0, false, false, 0) }
        var offset = min(max(0, scrollOffset), count - 1)
        var topClip = topClip
        // An "▲ N more" indicator spends a line to report that content is
        // hidden. Where no more lines are hidden than the indicator itself
        // costs, that is pure loss — it says "1 more row above" in the very
        // line the row would have occupied. Start the window one row earlier
        // instead and show the content itself; the freed indicator line pays
        // for it exactly, so nothing below moves.
        //
        // Only an offset of 0 or 1 can qualify (every row is at least one
        // line), which keeps this O(1) — no walking a tall table's rows.
        let hiddenAbove =
            switch offset {
            case 0: topClip
            case 1: height(0) + topClip
            default: 2  // ">= 2", enough to earn the indicator
            }
        if hiddenAbove == 1 {
            offset = 0
            topClip = 0
        }
        // A line-granularity clip partially hides the top row — content above.
        let showAbove = offset > 0 || topClip > 0

        func fill(budget: Int) -> Int {
            // The clipped lines of the top row don't occupy the viewport.
            var used = -topClip
            var end = offset
            while end < count {
                let rowH = height(end)
                if used + rowH > budget && end > offset {
                    // Line granularity fills the viewport EXACTLY: the row
                    // that straddles the budget enters the window (the
                    // renderer clips its tail), rather than leaving the
                    // spare lines empty — a whole-row window underfills
                    // whenever the visible rows don't sum to the budget,
                    // which made the table's frame breathe as it scrolled.
                    if lineGranularity && used < budget { end += 1 }
                    break
                }
                used += rowH
                end += 1
            }
            return max(offset + 1, end)
        }

        var end = fill(budget: contentHeight - (showAbove ? 1 : 0))
        if end < count {
            end = fill(budget: contentHeight - (showAbove ? 1 : 0) - 1)
        }
        return (offset..<min(count, end), showAbove, end < count, topClip)
    }

    /// Stitches scroll indicators around the visible multi-line rows.
    private func composeMultiLineRows(
        window: (range: Range<Int>, showAbove: Bool, showBelow: Bool, topClip: Int),
        handler: ItemListHandler<Value.ID>,
        tableHasFocus: Bool,
        columnWidths: [Int],
        innerWidth: Int,
        contentHeight: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        // Every line — focused-row backgrounds and indicators included — is padded
        // to the *content* width (the columns), not the full interior, so a focused
        // row or a scroll indicator is never wider than the header and rows; that
        // width mismatch is what made the wrapping VStack centre the header.
        let contentWidth = tableContentWidth(columnWidths, within: innerWidth)
        // A focused table with no scrollbar pulses its "N more" indicators.
        let indicatorEmphasis = scrollIndicatorEmphasis(
            isFocused: tableHasFocus, context: context)
        let numberLocale = context.environment.locale
        var lines: [String] = []
        if window.showAbove {
            lines.append(renderScrollIndicator(
                direction: .up, count: max(1, window.range.lowerBound),
                unit: .rows,
                width: contentWidth, palette: palette, emphasis: indicatorEmphasis,
                locale: numberLocale))
        }
        // Line granularity fills the content area EXACTLY: the bottom row may
        // be partially clipped (the top row already can be, via
        // `scrollTopClipLines`), so the table's height never changes with
        // which rows happen to be visible. Row granularity keeps whole rows.
        let rowLineBudget: Int? =
            context.environment.scrollGranularity == .line
            ? max(1, contentHeight - lines.count - (window.showBelow ? 1 : 0))
            : nil
        var rowLinesEmitted = 0
        // The rows are collected apart from the indicator chrome so that only
        // they take an overscroll slide (§1.5).
        var slidableRows: [String] = []
        for rowIndex in window.range {
            var rowLines = renderMultiLineRow(
                item: data[rowIndex],
                isFocused: handler.isFocused(at: rowIndex) && tableHasFocus,
                isSelected: handler.isSelected(at: rowIndex),
                columnWidths: columnWidths, rowWidth: contentWidth, context: context, palette: palette)
            // Line granularity: the top row enters partially, its first
            // `scrollTopClipLines` lines scrolled off above the viewport…
            if rowIndex == handler.scrollOffset, handler.scrollTopClipLines > 0 {
                rowLines.removeFirst(min(handler.scrollTopClipLines, rowLines.count - 1))
            }
            // …and the bottom row leaves partially, clipped at the budget.
            if let rowLineBudget {
                let remaining = rowLineBudget - rowLinesEmitted
                if remaining <= 0 { break }
                if rowLines.count > remaining {
                    rowLines.removeLast(rowLines.count - remaining)
                }
            }
            slidableRows.append(contentsOf: rowLines)
            rowLinesEmitted += rowLines.count
        }
        lines.append(contentsOf: handler.overscrollState.slid(
            slidableRows, blank: String(repeating: " ", count: max(0, contentWidth))))
        if window.showBelow {
            lines.append(renderScrollIndicator(
                direction: .down, count: data.count - window.range.upperBound,
                unit: .rows,
                width: contentWidth, palette: palette, emphasis: indicatorEmphasis,
                locale: numberLocale))
        }
        // A scrolled/overflowing table fills its content area EXACTLY,
        // whatever the granularity: whole rows can underfill under row
        // granularity, so pad the shortfall — a fixed-height table's frame
        // must not breathe as rows of different heights scroll through.
        // A non-overflowing table (no indicators, no clip) keeps its
        // natural, content-sized height.
        if window.showAbove || window.showBelow || window.topClip > 0 {
            while lines.count < contentHeight {
                lines.append(String(repeating: " ", count: contentWidth))
            }
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
        // A scrollbar reserves no indicator line, so the focus-reveal / offset
        // arithmetic must claim the full content height (matches the List path).
        handler.showsScrollbar = showsScrollbar
        // Unlike a List, a Table draws its "N more" indicators even when the
        // scrollbar is shown — the bar takes a column, the indicators take
        // lines — so the reveal must budget for them either way.
        handler.drawsScrollIndicators = overflowing
        handler.viewportHeight = provisionalViewport
        handler.canBeFocused = !isDisabled
        handler.primaryAction = primaryAction
        handler.onMove = moveAction
        handler.reorderFeedback = context.environment.rowReorderFeedback
        handler.rowHeight = nil  // single-line path: uniform-height scroll math
        // With uniform rows lines == rows, so granularity is moot here — but
        // sync it (and zero any stale clip below) in case the table's rows
        // switch between the single-line and multi-line paths across frames.
        handler.scrollGranularity = context.environment.scrollGranularity
        handler.followMargin = context.environment.scrollFollowMargin
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        // The app-customisable key bindings, resolved once here rather than
        // per keystroke (see RowShortcuts.lookup).
        handler.shortcuts = context.environment.rowShortcuts.lookup(
            commandKey: context.environment.commandKey)
        // `.cursor` feedback needs a session to float the row above the frame.
        handler.canFloatDraggedRow = context.environment.dragAndDropSession != nil
        // Table configures its handler from TWO independent places — here for
        // single-line rows, and inline in `buildMultiLineContent` for multi-line
        // ones. Anything captured in only one of them is silently dead on the
        // other path, which is how `017683fa` found every anchor behaviour
        // missing from Table while its twin List had them all. These two are the
        // same class: `.scrollDisabled` reached only the multi-line path when it
        // shipped, and the overscroll allowance would have had the same hole.
        handler.isScrollEnabled = context.environment.isScrollEnabled
        handler.overscrollState.resolve(
            top: context.environment.scrollOverscrollTop,
            bottom: context.environment.scrollOverscrollBottom,
            viewportHeight: provisionalViewport)
        // Same event-time capture as the multi-line path above: a user wheel
        // scroll releases a bound anchor, and the hold below reads the mode.
        handler.anchorPositionBinding = context.environment.anchorPosition
        handler.declaredAnchorMode = ScrollAnchorMode.resolved(
            defaultScrollAnchor: context.environment.defaultScrollAnchor)
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
            handler.clampTopClip()
            // Never rest at offset 1 — see `settleRestingOffset`, shared with
            // _ListCore. Rows on this path are one line each, so the
            // line-granularity exception can never apply here; the shared rule
            // is what keeps a drag auto-scroll able to leave the top.
            handler.settleRestingOffset(
                overflowing: overflowing, showsScrollbar: showsScrollbar, firstRowHeight: 1)
            // Apply the anchor in effect — see the multi-line path above.
            handler.applyAnchorHold()
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

    /// Reserves a line for each scroll indicator actually present at this
    /// offset so the rows plus indicators fill the content area exactly — no
    /// wasted blank line at the ends (which used to push the "N more below"
    /// indicator one row too high), no overflow in the middle. Mirrors
    /// _ListCore. Shared by the render pass and the analytic measure (both
    /// must agree on which indicators show).
    private func reserveIndicatorLines(
        handler: ItemListHandler<Value.ID>, contentHeight: Int
    ) {
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

    /// Stitches scroll indicators around the visible data rows.
    private func composeRowLines(
        handler: ItemListHandler<Value.ID>,
        tableHasFocus: Bool,
        columnWidths: [Int],
        innerWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> (lines: [String], rowLines: [String]) {
        let contentWidth = tableContentWidth(columnWidths, within: innerWidth)
        let indicatorEmphasis = scrollIndicatorEmphasis(
            isFocused: tableHasFocus, context: context)
        let numberLocale = context.environment.locale
        // The "N more" indicators are chrome — they describe where the content
        // sits — so the rows are collected separately and only they slide (§1.5).
        var lines: [String] = []
        var rowLines: [String] = []
        if handler.hasContentAbove {
            lines.append(renderScrollIndicator(
                direction: .up,
                count: handler.rowsAbove,
                unit: .rows,
                width: contentWidth,
                palette: palette,
                emphasis: indicatorEmphasis,
                locale: numberLocale
            ))
        }
        let visibleRange = handler.visibleRange
        // A reorder drag takes the dragged row out and opens a slot where it
        // would land, so what is DRAWN is the order a drop would produce. The
        // sequence (and the arithmetic behind it) is the handler's, shared with
        // `List`; outside a drag it is just the visible range.
        let drawn = handler.reorderDrawnRows(visibleRange)
        for entry in drawn {
            switch entry {
            case .row(let rowIndex):
                rowLines.append(renderRow(
                    item: data[rowIndex],
                    columnWidths: columnWidths,
                    isFocused: handler.isCursorRow(rowIndex) && tableHasFocus,
                    isSelected: handler.isSelected(at: rowIndex),
                    rowWidth: contentWidth,
                    context: context,
                    palette: palette
                ))
            case .slot:
                rowLines.append(reorderSlotLine(
                    handler: handler, columnWidths: columnWidths, rowWidth: contentWidth,
                    context: context, palette: palette))
            }
        }
        publishRowBands(handler: handler, drawn: drawn, slide: handler.overscrollState.excursion)
        lines.append(contentsOf: handler.overscrollState.slid(
            rowLines, blank: String(repeating: " ", count: max(0, contentWidth))))
        if handler.hasContentBelow {
            lines.append(renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                unit: .rows,
                width: contentWidth,
                palette: palette,
                emphasis: indicatorEmphasis,
                locale: numberLocale
            ))
        }
        // The row lines are handed back separately for a `.cursor` drag's
        // floating preview; the press frame is drawn in plain data order, so
        // indexing them by `visibleRange` offset is exact.
        return (lines, handler.onMove == nil ? [] : rowLines)
    }

    // MARK: - Reorder drag

    /// The drop slot's line: a faint copy of the dragged row under
    /// ``RowReorderFeedback/dimmed``, and a gap the row's size under
    /// ``RowReorderFeedback/cursor`` (which has the row itself on the pointer, so
    /// drawing it here too would read as a duplicate).
    private func reorderSlotLine(
        handler: ItemListHandler<Value.ID>,
        columnWidths: [Int],
        rowWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> String {
        // A keyboard move has no pointer to say where the row is, so the slot
        // says it: the row you are steering reads as emphasis, not as a hole.
        // (`isFocused` rather than a bespoke colour — the pulse a focused row
        // already uses is exactly the "this one" cue, and it walks the palette
        // ramp so it survives a 256-colour terminal.)
        let held = handler.isKeyboardMove
        guard handler.effectiveReorderFeedback == .dimmed,
            let source = handler.reorderRemovedRow, data.indices.contains(source)
        else {
            // No source to show (a `.cursor` drag carries the row on the
            // pointer). A keyboard move never lands here: it resolves `.cursor`
            // to `.dimmed`, precisely because there is no pointer to carry it.
            return String(repeating: " ", count: max(0, rowWidth))
        }
        let line = renderRow(
            item: data[source], columnWidths: columnWidths,
            isFocused: held, isSelected: held, rowWidth: rowWidth,
            context: context, palette: palette)
        guard !held else { return line }
        // Persistent: `renderRow` emits a reset per styled run — starting with
        // the selection-indicator gutter, so a bare wrapper died at cell one.
        return ANSIRenderer.applyPersistentDim(line)
    }

    /// Hands this frame's drawn row geometry to the shared publisher.
    ///
    /// `yStart` is measured from the first row line (past any "N more above"
    /// indicator), which is the space the mouse handler's `lineOffset` is in,
    /// and it must include the overscroll `slide` — the rows are drawn shifted
    /// by it, so a drag hit-tests the wrong row without it.
    private func publishRowBands(
        handler: ItemListHandler<Value.ID>,
        drawn: [ItemListHandler<Value.ID>.DrawnRow],
        slide: Int
    ) {
        typealias Handler = ItemListHandler<Value.ID>
        handler.publishRowBands(drawn.enumerated().compactMap { line, entry in
            let yStart = line + slide
            guard yStart >= 0 else { return nil }  // slid off the top
            switch entry {
            case .row(let rowIndex):
                return Handler.DrawnBand(entry: .row(rowIndex), yStart: yStart, height: 1)
            case .slot:
                return Handler.DrawnBand(entry: .slot, yStart: yStart, height: 1)
            }
        })
    }

    /// The multi-line path's bands: rows of different heights, no slot (that
    /// path forces ``RowReorderFeedback/live``, which moves the data instead of
    /// opening a gap).
    ///
    /// It published nothing at all until now, which did not merely disable
    /// drag-reorder there — it made the gesture swallow the click while doing
    /// nothing, since `dropTarget` had no bands to hit-test against.
    private func publishMultiLineRowBands(
        handler: ItemListHandler<Value.ID>,
        range: Range<Int>,
        heights: [Int]
    ) {
        typealias Handler = ItemListHandler<Value.ID>
        var yStart = 0
        handler.publishRowBands(range.enumerated().map { offset, rowIndex in
            let height = offset < heights.count ? max(1, heights[offset]) : 1
            defer { yStart += height }
            return Handler.DrawnBand(entry: .row(rowIndex), yStart: yStart, height: height)
        })
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

        // The border columns are chrome: a click there (however row-aligned its
        // y) must not select — see the x-guard in the handler. Tables always
        // render inside a bordered container, so one column each side. (The
        // List sibling got this guard in a6ba424d; this is its Table mirror.)
        let contentColumns = 1..<max(1, buffer.width - 1)
        // The row, rendered as its own object: no selection background, no
        // padding out to the grid's interior. Built on demand — only a drag
        // that actually starts pays for it.
        let palette = context.environment.palette
        let columnWidths = state.columnWidths
        let rowContentWidth = state.rowContentWidth
        let previewLine: @MainActor (Int) -> String? = { index in
            guard data.indices.contains(index), !columnWidths.isEmpty else { return nil }
            return renderRow(
                item: data[index], columnWidths: columnWidths,
                isFocused: false, isSelected: false, rowWidth: rowContentWidth,
                context: context, palette: palette)
        }
        // Where a ROW LINE's first cell sits in the buffer: past the border and
        // past the container's own padding. Not the same as the first clickable
        // column — the padding column is clickable but belongs to no row — and
        // measuring the reorder grab point from the wrong one of the two put
        // the floating row a cell off the pointer. `_ListCore` passes the
        // equivalent `rowContentLeft`.
        let rowContentLeft = contentColumns.lowerBound + Self.containerPadding.leading
        let mouseHandlerID = mouseDispatcher.register(
            containerMouseHandler(
                state: state,
                context: context,
                focusManager: focusManager,
                firstRowY: firstRowY,
                contentColumns: contentColumns,
                rowContentLeft: rowContentLeft,
                previewLine: previewLine
            )
        )
        // Insert at the back so interactive children inside a
        // row still win the dispatcher's reverse-iteration
        // match. See the parallel comment in _ListCore.
        // The table's focusID rides on this region: it is how an enclosing
        // ScrollView locates the focused table to scroll it into view
        // (`snapViewportToFocusedControl` scans regions by focusID).
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: buffer.width, height: buffer.height,
                handlerID: mouseHandlerID,
                focusID: state.focusID
            ),
            at: 0
        )

        // Register the table as a drag auto-scroll zone (sharing the container
        // region id): a drag hovering near its top/bottom edge scrolls the rows
        // to reveal an off-screen drop target. Auto-scroll is a gesture, so
        // `.scrollDisabled` withholds the zone entirely.
        if context.environment.isScrollEnabled {
            context.environment.dragAndDropSession?.registerAutoScrollZone(
                DragAndDropSession.AutoScrollZone(
                    handlerID: mouseHandlerID,
                    vertical: state.handler,
                    horizontal: nil,
                    delayNanos: context.environment.dragAutoScrollDelay.clampedNanoseconds))
        }

        // A one-row region at the keyboard cursor's on-screen line, ahead of
        // the whole-table region so an enclosing ScrollView follows the
        // cursor row — not just the table's top — through a table taller than
        // the outer viewport. Mirrors the marker in _ListCore (see the
        // comment there); the y math mirrors containerMouseHandler's
        // click-to-row mapping.
        let cursor = state.handler.focusedIndex
        if state.visibleRange.contains(cursor) {
            let rowOffset = cursor - state.visibleRange.lowerBound
            let cursorY: Int
            let cursorHeight: Int
            if state.visibleRowHeights.isEmpty {
                cursorY = firstRowY + rowOffset
                cursorHeight = 1
            } else if rowOffset < state.visibleRowHeights.count {
                cursorY = firstRowY + state.visibleRowHeights[0..<rowOffset].reduce(0, +)
                cursorHeight = max(1, state.visibleRowHeights[rowOffset])
            } else {
                return
            }
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: 0, offsetY: cursorY,
                    width: buffer.width, height: cursorHeight,
                    handlerID: mouseHandlerID,
                    focusID: state.focusID
                ),
                at: 0
            )
        }
    }

    /// The closure invoked by the container-wide hit-test
    /// region. Routes wheel to the handler's scroll position
    /// (never the selection), left-release to row hit-testing
    /// + focus, and rejects everything else.
    private func containerMouseHandler(
        state: PopulatedRenderState,
        context: RenderContext,
        focusManager: FocusManager?,
        firstRowY: Int,
        contentColumns: Range<Int>,
        rowContentLeft: Int,
        previewLine: @escaping @MainActor (Int) -> String?
    ) -> @MainActor (MouseEvent) -> Bool {
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        let visibleRange = state.visibleRange
        let visibleRowHeights = state.visibleRowHeights
        let rowIDs = data.map(\.id)
        let capturedPrimaryAction = primaryAction
        let dragSession = context.environment.dragAndDropSession
        // Where inside the grabbed row the press landed — the cell a `.cursor`
        // drag keeps under the pointer. Held in the closure because the closure
        // IS the gesture (see RowReorderGrabPoint).
        let grab = RowReorderGrabPoint()
        return { event in
            // Wheel scrolls the viewport, never the selection.
            // See the matching comment in _ListCore for the
            // model. Routed through the shared
            // ScrollableOffsetState helper so the math lives
            // in one place.
            if captureHandler.handleWheelEvent(event) { return true }

            if event.button == .left {
                /// The clicked line's data row, from the press-frame geometry.
                /// Single-line tables leave `visibleRowHeights` empty (no
                /// per-frame array) — the line offset is the row. Multi-line
                /// tables walk the visible rows' heights, so a click anywhere in
                /// a tall row hits it.
                func rowAt(y: Int) -> Int? {
                    let lineOffset = y - firstRowY
                    guard lineOffset >= 0 else { return nil }
                    if visibleRowHeights.isEmpty {
                        return lineOffset < visibleRange.count
                            ? visibleRange.lowerBound + lineOffset : nil
                    }
                    var accumulated = 0
                    for (offset, height) in visibleRowHeights.enumerated() {
                        if lineOffset < accumulated + height {
                            return visibleRange.lowerBound + offset
                        }
                        accumulated += height
                    }
                    return nil
                }

                /// The drag's position in the handler's band space (lines from the
                /// first row line), or `nil` once the cursor leaves the content
                /// columns — which holds the current drop target rather than
                /// snapping it somewhere the user isn't pointing.
                var dragContentY: Int? {
                    contentColumns.contains(event.x) ? event.y - firstRowY : nil
                }

                switch event.phase {
                case .pressed:
                    // Pick up the row for a possible reorder (only when the table
                    // is reorderable). Claim the press either way so the matching
                    // drag / release routes back here.
                    if captureHandler.onMove != nil, contentColumns.contains(event.x),
                        let index = rowAt(y: event.y)
                    {
                        captureHandler.beginReorder(grabbing: index)
                        // Edge auto-scroll applies to reordering too, and the
                        // two feedback modes that open no drag session
                        // (`.live`, `.dimmed`) have to say so explicitly.
                        dragSession?.armAutoScroll()
                        // Focus follows the gesture, so the keyboard reaches
                        // this list for the length of it — that is what lets
                        // Escape cancel a drag on a list not previously focused.
                        focusManager?.focus(id: captureFocusID)
                        // Relative to the ROW LINE, which is what the preview
                        // is — not to the first clickable column.
                        grab.x = max(0, event.x - rowContentLeft)
                        grab.y = 0  // one line per row on every reorderable path
                    }
                    return true

                case .dragged:
                    // Any motion during a grab is a reorder, not a click. What it
                    // looks like is the feedback mode's business — and `.cursor`'s
                    // reaches outside the table: its row rides the pointer above
                    // every other view, which only the drag session can draw.
                    let wasActive = captureHandler.isReordering
                    captureHandler.dragReorder(toContentY: dragContentY)
                    if let dragSession, let floating = captureHandler.reorderFloatingRow {
                        if !wasActive, let line = previewLine(floating) {
                            // The row's own line, floated at the cursor. No hit
                            // regions to strip: it is a plain rendered line.
                            let preview = FrameBuffer(lines: [line])
                            dragSession.begin(
                                payload: RowReorderPayload(), preview: preview,
                                grabX: grab.x, grabY: 0)  // `begin` trims and clamps
                        } else {
                            // `begin` samples the cursor once; only `dragMoved`
                            // tracks it — see the same call in _ListCore.
                            dragSession.dragMoved()
                        }
                    }
                    return true

                case .released:
                    // Whatever this turns out to be — a drop, or a click that
                    // never moved — the gesture is over, so let go of the edge
                    // auto-scroll. (`end()` below only runs for a real drop.)
                    dragSession?.disarmAutoScroll()
                    // Escape already put the row back and ended the drag; the
                    // release that follows is the tail of a cancelled gesture,
                    // not a click on whatever is under the pointer.
                    if captureHandler.reorderCancelled {
                        captureHandler.reorderCancelled = false
                        return true
                    }

                default:
                    return false
                }

                // A reorder drop. `.live` has already moved the row; the other
                // modes move it exactly here. `end`, never `performDrop`: the
                // payload is unnameable, so no `dropDestination` could take it,
                // and the table has already placed the row itself.
                // Asked BEFORE the drop, which clears the state: a release with
                    // no slot and no row under the pointer is the gesture
                    // saying "nothing happened".
                    let landsNowhere = captureHandler.reorderPlaceholder == nil && dragContentY == nil
                    if captureHandler.dropReorder(atContentY: dragContentY) {
                    // Nowhere to land — released off the rows, and the mode
                    // showed no slot — so the row walks home rather than
                    // vanishing where the pointer happens to be.
                    if landsNowhere {
                        dragSession?.cancelReturningToOrigin()
                    } else {
                        dragSession?.end()
                    }
                    focusManager?.focus(id: captureFocusID)
                    return true
                }

                // Border columns are chrome: a click there shares a row's y but
                // nobody clicking the frame means "select that row" — focus the
                // table (below) and stop. Mirrors _ListCore's x-guard.
                guard contentColumns.contains(event.x) else {
                    focusManager?.focus(id: captureFocusID)
                    return true
                }
                if let index = rowAt(y: event.y) {
                    // A double-click fires the row's primary action ("open");
                    // a single click selects with macOS semantics (plain =
                    // sole selection, shift = range, ctrl/option = toggle) —
                    // see ItemListHandler.handleClickSelection.
                    if event.clickCount >= 2, let action = capturedPrimaryAction,
                        index >= 0, index < rowIDs.count
                    {
                        captureHandler.focusedIndex = index
                        action(rowIDs[index])
                    } else {
                        captureHandler.handleClickSelection(at: index, event: event)
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

        // Single-line cells are CLIPPED to their column, so once a `.fit`
        // column's widest-so-far already spans the whole interior, no later
        // row can change anything visible — stop scanning. Multi-line cells
        // instead WRAP at the column width, so there the true maximum
        // matters and the scan must run to the end.
        let fitScanCap =
            columns.contains(where: { $0.lineLimit > 1 }) ? nil : Optional(contentWidth)

        var widths = [Int](repeating: 0, count: columns.count)
        var usedWidth = 0
        var flexibleIndices: [Int] = []

        for (index, column) in columns.enumerated() {
            switch column.width {
            case .fixed(let fixedWidth):
                widths[index] = fixedWidth
                usedWidth += fixedWidth
            case .ratio(let ratio):
                // `.ratio` takes an unvalidated Double from public API, and a
                // ratio is usually computed (`part / whole`) — so NaN and ±infinity
                // arrive in practice, and `Int(Double)` traps on both, as it does
                // on any value past Int's range. Treat a non-finite ratio as zero
                // and clamp the rest to the space actually available: a bad ratio
                // should render a degenerate column, not kill the app.
                // Clamped in Double space, BEFORE the conversion: `Int(_: Double)`
                // traps on NaN, on ±infinity, and on any finite value past Int's
                // range (`1e30` is finite and still traps), so no post-conversion
                // clamp can save it. A column can never be wider than the content
                // area anyway, so bounding to that is both safe and correct.
                let scaled = Double(contentWidth) * ratio
                let ratioWidth = scaled.isFinite ? Int(min(max(0, scaled), Double(contentWidth))) : 0
                widths[index] = ratioWidth
                usedWidth += ratioWidth
            case .fit:
                // Fit to the widest of the header and every cell value in this
                // column. O(rows) per column, but stable as the table scrolls
                // (all rows are considered, not just the visible ones) — with
                // the early-out above once the interior is saturated.
                var fitted = column.title.strippedLength
                for item in data {
                    fitted = max(fitted, column.value(for: item).strippedLength)
                    if let cap = fitScanCap, fitted >= cap { break }
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
            let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background)
            let bg = SelectionIndicator.resolve(isFocused: true, context: context)
                .color(
                    dim: dimAccent,
                    bright: palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background))
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
            return ("●", palette.accent.opacity(ViewConstants.selectionIndicator, over: palette.background), nil)
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

/// A fixed-size stand-in for the table's content lines, used only by the
/// analytic measure path: it reports the size the real lines would occupy
/// without building them, so measuring the table's ``ContainerView`` chrome
/// is O(chrome) instead of O(rows × cells).
private struct _TableSizeStub: View, Renderable, Layoutable {
    let width: Int
    let height: Int

    var body: Never {
        fatalError("_TableSizeStub renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize.fixed(width, height)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Only reached if a parent measures by rendering; blank lines of the
        // reported size keep that path dimension-accurate too.
        FrameBuffer(
            lines: Array(
                repeating: String(repeating: " ", count: width), count: height))
    }
}
