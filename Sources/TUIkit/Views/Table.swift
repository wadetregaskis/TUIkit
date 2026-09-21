//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// ## Sorting
///
/// Give the table a `sortOrder` binding and the sortable columns' headers
/// become clickable, exactly as in SwiftUI. A column is sortable when it was
/// built from a key path (``TableColumn/init(_:value:)-(LocalizedStringKey,(Value)->String)`` /
/// ``TableColumn/init(_:value:content:)-(LocalizedStringKey,_,_)``); one built from a closure is not,
/// because nothing there says how to order the rows.
///
/// ```swift
/// @State private var sortOrder = [KeyPathComparator(\FileInfo.name)]
///
/// Table(files, selection: $selectedID, sortOrder: $sortOrder) {
///     TableColumn("Name", value: \.name)
///     TableColumn("Size", value: \.byteCount) { "\($0.byteCount) B" }
/// }
/// .onChange(of: sortOrder) { files.sort(using: $0) }
/// ```
///
/// The table publishes the order and the app applies it — SwiftUI's division
/// of labour, and the reason for that `onChange`. Clicking the column already
/// sorted by reverses it; clicking another makes it the primary sort and keeps
/// the previous one behind it as the tie-break. The column being sorted by
/// carries a `▲` / `▼`, and every sortable column reserves that glyph's width
/// so the table does not change shape as you sort it.
///
/// From the keyboard, on the focused table: `Ctrl-S` sorts by the next sortable
/// column — the same gesture as clicking its header, wrapping round to the
/// first — and `Ctrl-D` reverses the current direction. Both are rebindable,
/// like every other row chord: see ``RowAction/sortNextColumn``,
/// ``RowAction/reverseSortOrder`` and ``RowShortcuts``.
///
/// ## Column Spacing
///
/// Columns are separated by spaces (no vertical lines) for a clean look.
///
/// ## The cursor row where the terminal decides the colours
///
/// The cursor row marks itself with a fill of the palette's accent over its
/// page, breathing while the table has focus. Where the palette names colours
/// the terminal decides — its own foreground or background, or one of its
/// sixteen slots — and the terminal has not said what it paints for them, there
/// is no tint between them to draw, so the row draws **reverse video** instead,
/// over the palette's own ink and page. It is steady rather than breathing, and
/// it keeps its `●`. A selected row that is not the cursor draws its `●` and no
/// fill, which is what it has always done. A palette that states ordinary
/// colours is unaffected, on any terminal.
public struct Table<Value: Identifiable & Sendable>: View where Value.ID: Hashable {
    /// The data items to display.
    let data: [Value]

    /// The column definitions.
    let columns: [TableColumn<Value>]

    /// Binding for single selection (optional ID).
    let singleSelection: Binding<Value.ID?>?

    /// Binding for multi-selection (Set of IDs).
    let multiSelection: Binding<Set<Value.ID>>?

    /// The sort the table's headers drive, when it was given one.
    ///
    /// Its presence is what makes the headers clickable at all — exactly as in
    /// SwiftUI, where a `Table` without a `sortOrder` binding has inert
    /// headers. The table never sorts the data itself; it publishes the order
    /// the user asked for and the app applies it (`data.sort(using:)`), which
    /// is also SwiftUI's division of labour.
    let sortOrder: Binding<[KeyPathComparator<Value>]>?

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

    /// The `.dropDestination(for:action:)` insertion action, if attached:
    /// `(insertion index, payloads)`. Type-erased so `Table` need not carry the
    /// payload type; the erased pair is `(accepts, perform)`.
    var dropInsertion: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)?

    public var body: some View {
        _TableCore(
            data: data,
            columns: columns,
            singleSelection: singleSelection,
            multiSelection: multiSelection,
            sortOrder: sortOrder,
            selectionMode: selectionMode,
            focusID: focusID,
            isDisabled: isDisabled,
            emptyPlaceholder: emptyPlaceholder,
            columnSpacing: columnSpacing,
            primaryAction: primaryAction,
            moveAction: moveAction,
            dropInsertion: dropInsertion
        )
        // The same pairing as `ScrollView.body` and `List.body`. A table's rows
        // are its own focus stops, so its stored flag alone already suppressed
        // everything it draws today — but the flag and the subtree disable are
        // still two different statements, and the three containers agreeing is
        // what stops the next interactive cell from reintroducing the gap.
        .disabled(isDisabled)
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

    /// Makes the ROWS a drop destination that reports WHERE the drop landed —
    /// the `Table` counterpart of `ForEach.dropDestination(for:action:)`.
    ///
    /// A `Table`'s rows are values, not views, so there is no `ForEach` to carry
    /// SwiftUI's row-level modifier; it lives on the table itself, exactly as
    /// ``onMove(_:)`` does and for the same reason. (SwiftUI's own `Table` has
    /// neither.)
    ///
    /// While a compatible drag hovers, the table opens a gap at the prospective
    /// index — the same gap a ``RowReorderFeedback/cursor`` reorder shows,
    /// because it is the same machinery and means the same thing. On release the
    /// app is told the index it was pointing at; a drop past the last row
    /// reports one past the end, which is also how an EMPTY table is filled.
    ///
    /// - Parameters:
    ///   - payloadType: The payload type these rows accept.
    ///   - action: Inserts the payloads at the given index.
    public func dropDestination<Payload>(
        for payloadType: Payload.Type = Payload.self,
        action: @escaping (Int, [Payload]) -> Void
    ) -> Table {
        var copy = self
        copy.dropInsertion = (
            accepts: { $0 is Payload },
            perform: { index, values in action(index, values.compactMap { $0 as? Payload }) }
        )
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
    ///   - sortOrder: A binding to the sort the column headers drive. Supplying
    ///     one makes the sortable columns' headers clickable, and Ctrl-S /
    ///     Ctrl-D sort from the keyboard; omitting it leaves them inert, as a
    ///     SwiftUI `Table` without one has them.
    ///   - focusID: The unique focus identifier (default: auto-generated).
    ///   - columnSpacing: Spacing between columns (default: 2).
    ///   - emptyPlaceholder: Placeholder text when empty (default: the localized "No items").
    ///   - columns: A builder that defines the table columns.
    public init(
        _ data: [Value],
        selection: Binding<Value.ID?>,
        sortOrder: Binding<[KeyPathComparator<Value>]>? = nil,
        focusID: String? = nil,
        columnSpacing: Int = 2,
        emptyPlaceholder: String = ViewConstants.localizedEmptyListPlaceholder,
        @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]
    ) {
        self.init(
            data, single: selection, multi: nil, sortOrder: sortOrder, focusID: focusID,
            columnSpacing: columnSpacing, emptyPlaceholder: emptyPlaceholder, columns: columns)
    }

    /// The one initializer that stores anything; the public three differ only
    /// in which selection binding they hand it, and `nil` for both is the
    /// no-selection table.
    private init(
        _ data: [Value],
        single: Binding<Value.ID?>?,
        multi: Binding<Set<Value.ID>>?,
        sortOrder: Binding<[KeyPathComparator<Value>]>?,
        focusID: String?,
        columnSpacing: Int,
        emptyPlaceholder: String,
        @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]
    ) {
        self.data = data
        self.columns = columns()
        self.singleSelection = single
        self.multiSelection = multi
        self.sortOrder = sortOrder
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

// MARK: - No-Selection Initializer

extension Table {
    /// Creates a table with no selection.
    ///
    /// SwiftUI's `Table(_:columns:)`. Nothing is selectable and there is no
    /// binding to write into. The rows still carry a keyboard CURSOR — it is
    /// what the arrow, Home/End and Page keys scroll with, it wears the focus
    /// background, and a click lands it on a row — only the selection gutter
    /// and the selection itself are absent. (An earlier version of this note
    /// said there was no cursor to move; there is, and the keyboard scrolling
    /// the next sentence relies on is that cursor.)
    ///
    /// Worth reaching for whenever the rows are a display and nothing should
    /// be chosen from them. `.disabled(true)` is not the same thing: that also
    /// greys the rows and takes the table out of the focus ring, so it can no
    /// longer be scrolled from the keyboard.
    ///
    /// - Parameters:
    ///   - data: The data items to display.
    ///   - sortOrder: A binding to the sort the column headers drive. Supplying
    ///     one makes the sortable columns' headers clickable, and Ctrl-S /
    ///     Ctrl-D sort from the keyboard; omitting it leaves them inert, as a
    ///     SwiftUI `Table` without one has them.
    ///   - focusID: The unique focus identifier (default: auto-generated).
    ///   - columnSpacing: Spacing between columns (default: 2).
    ///   - emptyPlaceholder: Placeholder text when empty (default: the localized "No items").
    ///   - columns: A builder that defines the table columns.
    public init(
        _ data: [Value],
        sortOrder: Binding<[KeyPathComparator<Value>]>? = nil,
        focusID: String? = nil,
        columnSpacing: Int = 2,
        emptyPlaceholder: String = ViewConstants.localizedEmptyListPlaceholder,
        @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]
    ) {
        // No binding at all, rather than a `.constant` one. A constant binding
        // reads as a single-selection table whose selection happens to be
        // empty — which is how the gutter for a mark that can never be drawn
        // survived, and what `isReserved(hasSelection:environment:)` asks
        // about.
        self.init(
            data, single: nil, multi: nil, sortOrder: sortOrder,
            focusID: focusID, columnSpacing: columnSpacing,
            emptyPlaceholder: emptyPlaceholder, columns: columns)
    }
}

// MARK: - Multi Selection Initializer

extension Table {
    /// Creates a table with multi-selection.
    ///
    /// - Parameters:
    ///   - data: The data items to display.
    ///   - selection: A binding to the set of selected item IDs.
    ///   - sortOrder: A binding to the sort the column headers drive. Supplying
    ///     one makes the sortable columns' headers clickable, and Ctrl-S /
    ///     Ctrl-D sort from the keyboard; omitting it leaves them inert, as a
    ///     SwiftUI `Table` without one has them.
    ///   - focusID: The unique focus identifier (default: auto-generated).
    ///   - columnSpacing: Spacing between columns (default: 2).
    ///   - emptyPlaceholder: Placeholder text when empty (default: the localized "No items").
    ///   - columns: A builder that defines the table columns.
    public init(
        _ data: [Value],
        selection: Binding<Set<Value.ID>>,
        sortOrder: Binding<[KeyPathComparator<Value>]>? = nil,
        focusID: String? = nil,
        columnSpacing: Int = 2,
        emptyPlaceholder: String = ViewConstants.localizedEmptyListPlaceholder,
        @TableColumnBuilder<Value> columns: () -> [TableColumn<Value>]
    ) {
        self.init(
            data, single: nil, multi: selection, sortOrder: sortOrder, focusID: focusID,
            columnSpacing: columnSpacing, emptyPlaceholder: emptyPlaceholder, columns: columns)
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

/// `_TableCore`'s `StateStorage` slots, by name.
///
/// Required of every `_*Core` — the project rule is "never use bare integer
/// literals for `propertyIndex`" — and this was one of the last two views still
/// writing `propertyIndex: 1  // focusID`, at seven call sites, where a comment
/// is the only thing saying which slot that is and nothing checks it.
///
/// `0...`, not the negative reserved range: a table renders no caller-supplied
/// content at its OWN identity, so these can never alias a composite content
/// view's first `@State`. At file scope rather than nested, because
/// `_TableCore` is generic and a nested type inherits that generic context,
/// where a `static let` is not allowed (`_ImageCore` and `_UserResizableCore`
/// do the same).
private enum StateIndex {
    /// The persisted ``ItemListHandler`` — selection, cursor, scroll offset.
    static let handler = 0
    /// The focus id, persisted so it survives a frame where the declaration is
    /// momentarily absent (see `FocusRegistration.persistFocusID`).
    static let focusID = 1
}

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

    /// The gap between columns in a row that is riding the pointer.
    static var previewColumnSpacing: Int { 2 }

    /// The cells a row spends on its selection mark when it has one: the glyph
    /// and the gap to the first column.
    ///
    /// Everything that places anything on a row line goes through
    /// ``selectionGutter(_:)`` rather than this — the header indent, the column
    /// widths, the row content, the ramp's column walk, the header's click
    /// ranges and the row-in-hand preview — because a table with nothing to
    /// mark reserves none of it and they would otherwise disagree by two cells.
    static var selectionGutterWidth: Int { 2 }

    let data: [Value]
    let columns: [TableColumn<Value>]
    let singleSelection: Binding<Value.ID?>?
    let multiSelection: Binding<Set<Value.ID>>?
    let sortOrder: Binding<[KeyPathComparator<Value>]>?
    let selectionMode: SelectionMode
    let focusID: String?
    let isDisabled: Bool
    let emptyPlaceholder: String
    let columnSpacing: Int
    var primaryAction: ((Value.ID) -> Void)?
    var moveAction: ((IndexSet, Int) -> Void)?
    var dropInsertion: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)?

    var body: Never {
        fatalError("_TableCore renders via Renderable")
    }

    /// Whether this table has a selection binding — the only thing that can
    /// ever put a mark in the gutter.
    private var hasSelection: Bool { singleSelection != nil || multiSelection != nil }

    /// The cells this table's rows open with, before the first column:
    /// ``selectionGutterWidth`` when a mark could appear there, none when it
    /// could not. See ``RowSelectionIndicator/isReserved(hasSelection:environment:)``.
    private func selectionGutter(_ environment: EnvironmentValues) -> Int {
        RowSelectionIndicator.isReserved(hasSelection: hasSelection, environment: environment)
            ? Self.selectionGutterWidth : 0
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

        // A table's dimensions are arithmetic, not something to be discovered
        // by building the thing and measuring the result. Rendering the whole
        // table — styled cells, ANSI-aware padding, scrollbar, chrome — just to
        // read its buffer's size back off it dominated the measure pass of
        // large tables, and the sizing passes ask far more often than the
        // render does. Single-line tables are answered outright; multi-line
        // ones in every shape but one (see `analyticMultiLineSize`).
        let size: (width: Int, height: Int)
        // Both analytic paths answer "the rows, and the indicator lines an
        // OVERFLOWING table draws". Under
        // ``EnvironmentValues/alwaysShowsVerticalTextIndicators`` the two lines
        // are drawn whether or not anything is hidden, so a table whose rows fit
        // measured two lines shorter than it drew — and a container that
        // believed the measurement then handed it a viewport two lines too
        // short, in which the reservation ate two of the three rows it exists to
        // protect. The render is the authority on what the render does; a mode
        // this rare does not earn a third copy of the reservation arithmetic
        // (which is what the first two copies disagreeing about it cost).
        // The style question too: `.visible` with a SCROLLBAR spends a column,
        // not a line, and both analytic paths already handle that shape.
        if measureContext.environment.alwaysShowsVerticalTextIndicators,
            measureContext.environment.scrollIndicatorStyle == .text
        {
            let buffer = renderToBuffer(context: measureContext)
            size = (buffer.width, buffer.height)
        } else if columns.contains(where: { $0.lineLimit > 1 }) {
            size =
                analyticMultiLineSize(context: measureContext)
                ?? {
                    let buffer = renderToBuffer(context: measureContext)
                    return (buffer.width, buffer.height)
                }()
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
        let gutter = selectionGutter(context.environment)
        let innerWidth = max(0, context.availableWidth - 4)
        let rowArea = max(1, context.availableHeight - 3)
        let wantsScrollbar =
            !data.isEmpty
            && context.environment.verticalScrollIndicators(
                overflowing: data.count > rowArea
            ).bar
        let contentInnerWidth = max(1, innerWidth - (wantsScrollbar ? 1 : 0))
        let columnWidths = calculateColumnWidths(
            availableWidth: contentInnerWidth, spacing: columnSpacing, gutter: gutter)
        var headerLine = renderHeader(
            columnWidths: columnWidths, gutter: gutter, palette: palette
        ).text
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
            let contentWidth = tableContentWidth(columnWidths, within: innerWidth, gutter: gutter)
            var widest = contentWidth
            if data.count > rowArea {
                let persistedFocusID = FocusRegistration.persistFocusID(
                    context: context, explicitFocusID: focusID,
                    defaultPrefix: "table",
                    propertyIndex: StateIndex.focusID)
                let (handler, _) = resolveHandler(
                    persistedFocusID: persistedFocusID,
                    stateStorage: context.stateStorage!,
                    context: context, contentHeight: rowArea, overflows: { _ in true })
                let window = reserveIndicatorLines(
                    handler: handler, contentHeight: rowArea, context: context)
                // Measure with the SAME locale the display path uses, or a
                // grouped "12,000" would be measured as "12000" and the column
                // sized one cell short.
                let measureLocale = context.environment.locale
                // From the pair just computed, NOT from the handler: this is a
                // measure pass and it no longer publishes them there.
                let rowsAbove = window.origin
                let rowsBelow = max(0, data.count - (window.origin + window.viewport))
                if rowsAbove > 0 {
                    widest = max(
                        widest,
                        scrollIndicatorWidth(
                            direction: .up, count: rowsAbove,
                            unit: .rows,
                            width: contentWidth, locale: measureLocale))
                }
                if rowsBelow > 0 {
                    widest = max(
                        widest,
                        scrollIndicatorWidth(
                            direction: .down, count: rowsBelow,
                            unit: .rows,
                            width: contentWidth, locale: measureLocale))
                }
            }
            contentSize = (widest, min(data.count, rowArea))
        }

        return analyticSize(headerLine: headerLine, content: contentSize, context: context)
    }

    /// A multi-line table's size, computed rather than rendered — or `nil` for
    /// the one shape that cannot be, which falls back to the render.
    ///
    /// Two of the three shapes are pure arithmetic:
    ///
    /// * **A bar is drawn.** The bar costs a column, not a line, and
    ///   ``composeMultiLineRows`` pads its output to the content area before
    ///   merging the bar in as the rightmost cell. The block is therefore the
    ///   content area exactly, whatever the rows do — not one row need be
    ///   wrapped to know the size.
    /// * **The rows fit.** No indicator, no clip, so the block is the sum of
    ///   their heights. Bounded work: rows that fit are at most a viewport's
    ///   worth.
    ///
    /// The third — overflowing with no bar — has the content area for a height
    /// but a *width* that a "▼ N more rows below" line can exceed on a narrow
    /// table, and that N comes from the scroll window. Reimplementing the
    /// window here would put a second copy of that arithmetic in this file, the
    /// mistake that keeps `List` and `Table` drifting apart, so it renders.
    ///
    /// This matters because the *sizing* passes ask far more often than the
    /// render does: `measureNaturalExtent` walks a ladder of ever-larger height
    /// budgets looking for the content's natural extent (see the ScrollView
    /// extent ladder), and every rung was building the whole table to read
    /// `buffer.height` back off it.
    ///
    /// `TableAnalyticMeasureTests` holds this equal to the rendered size across
    /// the multi-line configuration matrix, including the ladder's tall budgets.
    private func analyticMultiLineSize(
        context: RenderContext
    ) -> (width: Int, height: Int)? {
        // Empty is a placeholder line, not rows — the render's business.
        guard !data.isEmpty else { return nil }
        let palette = context.environment.palette
        let gutter = selectionGutter(context.environment)
        let innerWidth = max(0, context.availableWidth - 4)
        let rowArea = max(1, context.availableHeight - 3)
        // Decide the bar exactly as `renderToBuffer` does — at the width a bar
        // WOULD leave, where rows wrap taller and so overflow soonest.
        let overflows = multiLineOverflows(rowArea: rowArea, innerWidth: innerWidth - 1, gutter: gutter)
        let wantsScrollbar = context.environment.verticalScrollIndicators(
            overflowing: overflows
        ).bar
        let contentInnerWidth = max(1, innerWidth - (wantsScrollbar ? 1 : 0))
        let columnWidths = calculateColumnWidths(
            availableWidth: contentInnerWidth, spacing: columnSpacing, gutter: gutter)
        let contentWidth = tableContentWidth(columnWidths, within: innerWidth, gutter: gutter)

        let content: (width: Int, height: Int)
        if wantsScrollbar {
            // A bar costs a column, not a line, and ``composeMultiLineRows``
            // pads its output to the content area before merging the bar in as
            // the rightmost cell. So the block is the area, exactly, whatever
            // the rows do — no row need be wrapped at all to know this.
            content = (contentWidth + 1, rowArea)
        } else if !overflows {
            // Rows that fit draw no indicator and take no clip, so the block is
            // exactly their lines, each padded to the row content width.
            var totalLines = 0
            for item in data {
                totalLines += rowHeight(of: item, columnWidths: columnWidths)
            }
            content = (contentWidth, totalLines)
        } else {
            // Overflowing without a bar: the height is the content area, but a
            // "▼ N more rows below" line can be WIDER than the rows on a narrow
            // table, and that N comes from the scroll window. Declined rather
            // than reimplemented — see above.
            return nil
        }
        // The chrome is then *measured* for real, exactly as the single-line
        // analytic does, so border/padding semantics stay the render path's
        // rather than being duplicated as arithmetic here.
        var headerLine = renderHeader(
            columnWidths: columnWidths, gutter: gutter, palette: palette
        ).text
        if wantsScrollbar {
            headerLine += String(
                repeating: " ", count: max(0, innerWidth - headerLine.strippedLength))
        }
        return analyticSize(headerLine: headerLine, content: content, context: context)
    }

    /// The table's outer size, given the header line and the content block's
    /// dimensions: the shared ``ContainerView`` chrome measured around a
    /// fixed-size stand-in for the rows. Both analytic paths end here so
    /// neither can drift from the container `renderToBuffer` builds.
    private func analyticSize(
        headerLine: String, content: (width: Int, height: Int), context: RenderContext
    ) -> (width: Int, height: Int) {
        let container = ContainerView(
            title: nil,
            style: ContainerStyle(showHeaderSeparator: true, showFooterSeparator: false),
            padding: Self.containerPadding
        ) {
            VStack(alignment: .leading, spacing: 0) {
                // No claims on the analytic MEASURE path: it reports a size and draws
                // nothing, and a claim describes cells that were never on screen.
                _TableHeaderView(line: headerLine, claims: [])
                _TableSizeStub(width: content.width, height: content.height)
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
        /// One when this frame drew an "N more above" line, zero otherwise —
        /// each path answering with the condition it actually drew by.
        ///
        /// Only the scrollbar's region needs it (see `attachMouseHandlers`);
        /// the bands carry the same offset for everything else.
        let scrollOffsetAbove: Int
        /// Where every drawn entry landed, in ``ItemListHandler/DrawnBand``'s
        /// space — lines from the interior's first CONTENT line, indicator and
        /// overscroll slide already in.
        ///
        /// The frame's ONE answer to "what is on this line": the hit-test
        /// closure maps a click through it, the keyboard cursor's marker takes
        /// its rectangle from it, and the handler is handed the same array for
        /// the drag to resolve against. `_ListCore` has always worked this way
        /// (`visibleRowYRanges`); `Table` re-derived it from `visibleRange`,
        /// per-row heights and a live "is an indicator drawn?" predicate, and
        /// the predicate did not match the one the rows were drawn by.
        let drawnBands: [ItemListHandler<Value.ID>.DrawnBand]
        /// Whether a scrollbar column was drawn — by either layout path. Drives
        /// the bar's mouse handler in `attachMouseHandlers`.
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
        let stateStorage = context.stateStorage!

        // Rows beyond the viewport are skipped, not gone: retain their state
        // (see StateStorage.retainSubtree). Render path only, per the
        // measure-side-effect rule.
        if !context.isMeasuring {
            stateStorage.retainSubtree(context.identity)
        }

        // Calculate available width inside container (subtract border + padding).
        let gutter = selectionGutter(context.environment)
        let innerWidth = max(0, context.availableWidth - 4)

        // A single-line table decides a scrollbar cheaply (one line per row).
        // A multi-line table's overflow is its total WRAPPED height, so that
        // walk is only run when a bar is in play at all — scrollbars are opt-in
        // (`.hidden` by default), which is what keeps the default path free of
        // it (see `multiLineOverflows`).
        let rowArea = max(1, context.availableHeight - 3)
        let isMultiLine = columns.contains { $0.lineLimit > 1 }
        let wantsScrollbar =
            !data.isEmpty
            && context.environment.verticalScrollIndicators(
                overflowing: isMultiLine
                    ? multiLineOverflows(rowArea: rowArea, innerWidth: innerWidth - 1, gutter: gutter)
                    : data.count > rowArea
            ).bar
        let contentInnerWidth = max(1, innerWidth - (wantsScrollbar ? 1 : 0))

        let columnWidths = calculateColumnWidths(
            availableWidth: contentInnerWidth, spacing: columnSpacing, gutter: gutter)
        let header = renderHeader(columnWidths: columnWidths, gutter: gutter, palette: palette)
        var headerLine = header.text
        if wantsScrollbar {
            // Pad the header to the full inner width so it aligns with the rows
            // (whose last column is the scrollbar); the cell above the bar is blank.
            headerLine += String(repeating: " ", count: max(0, innerWidth - headerLine.strippedLength))
        }

        let contentLines: [String]
        var contentRuns: [AnimatedCellRun] = []
        var contentClaims: [OpacityRegion] = []
        let renderState: PopulatedRenderState?
        if data.isEmpty {
            contentLines = [emptyPlaceholder]
            // Empty is a state, not an absence: the table still occupies its
            // frame, so it is still the thing under the pointer, still
            // clickable, still focusable, and still somewhere a drag can be
            // dropped. All of that hangs off this state — without it the table
            // contributed no hit region at all and a drag over it resolved
            // nothing. Same fix as `_ListCore`'s.
            renderState = emptyRenderState(
                context: context, stateStorage: stateStorage, contentHeight: rowArea)
        } else if wantsScrollbar, !isMultiLine {
            let result = buildScrollbarContent(
                context: context, stateStorage: stateStorage, palette: palette,
                columnWidths: columnWidths, contentInnerWidth: contentInnerWidth)
            contentLines = result.lines
            contentRuns = result.runs
            contentClaims = result.claims
            renderState = result.state
        } else {
            let result = buildPopulatedContent(
                context: context,
                stateStorage: stateStorage,
                palette: palette,
                columnWidths: columnWidths,
                showsScrollbar: wantsScrollbar,
                innerWidth: innerWidth
            )
            contentLines = result.lines
            contentRuns = result.runs
            contentClaims = result.claims
            renderState = result.state
        }

        // A table that was GIVEN a height fills it. `hasExplicitHeight` is
        // documented on ``RenderContext/withAvailableHeight(_:)`` as the flag by
        // which "child views (like List) know to expand to fill the available
        // height", and `Table` was the one row view that did not keep it:
        // `Table(threeRows).frame(height: 12)` drew a six-line bordered box with
        // six blank lines beneath it. On the Example's Emoji page, where a filter
        // narrows 1,212 rows to one, the box collapsed from twenty lines to three
        // on a keystroke and jumped the page under the cursor.
        //
        // Padded to the width the rows already have, so the box's width cannot
        // move either — a wider blank line would widen the container, a narrower
        // one is fine but says nothing.
        //
        // An unframed table in a `VStack` reaches none of this and still hugs,
        // which is what it wants.
        let filledContentLines: [String]
        if context.hasExplicitHeight, contentLines.count < rowArea {
            let padWidth = contentLines.map(\.strippedLength).max() ?? 0
            filledContentLines =
                contentLines
                + Array(
                    repeating: String(repeating: " ", count: padWidth),
                    count: rowArea - contentLines.count)
        } else {
            filledContentLines = contentLines
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
                _TableHeaderView(line: headerLine, claims: header.claims)
                _TableContentView(
                    lines: filledContentLines, runs: contentRuns, claims: contentClaims)
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
        showsScrollbar: Bool = false,
        innerWidth: Int
    ) -> (
        lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion],
        state: PopulatedRenderState
    ) {
        // Multi-line cells (any column with a line limit above 1) take a separate,
        // height-aware layout path. Single-line tables keep the original
        // row-per-line path below completely untouched.
        if columns.contains(where: { $0.lineLimit > 1 }) {
            return buildMultiLineContent(
                context: context, stateStorage: stateStorage, palette: palette,
                columnWidths: columnWidths, showsScrollbar: showsScrollbar,
                innerWidth: innerWidth)
        }

        // The fixed chrome is 3 lines: the top border, the bottom
        // border, and the column-header line. What's left is the
        // scrollable content area, shared between the visible rows
        // and whichever scroll indicators are present.
        let availableHeight = context.availableHeight
        let chromeRows = 3
        let contentHeight = max(1, availableHeight - chromeRows)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "table",
            propertyIndex: StateIndex.focusID
        )
        let (handler, overflowing) = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            contentHeight: contentHeight,
            overflows: { data.count + $0 > contentHeight }
        )
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. `engageFocus`
        // still runs with the true answer: it publishes the Escape claim and
        // the status bar's Return verb, and sets `isFocusEngaged`, none of
        // which are focus EFFECTS.
        let tableHasFocus = context.indicatesFocus(
            handler.engageFocus(context: context, focusID: persistedFocusID))

        // Also when nothing overflows but `.scrollIndicators(.visible)` asked for
        // the lines anyway: they come out of the rows' budget there too, and this
        // is what publishes that. Skipped only where no line is spent at all.
        // `(false, false)` when the branch is not taken, which is the whole of
        // what "this frame reserved nothing" means — and it is stated here rather
        // than left to whatever a previous frame published.
        var drawnIndicators = (above: false, below: false)
        if overflowing || handler.alwaysReservesIndicatorLines {
            // The landing slot is drawn among the rows and takes one of their
            // lines, so the rows are budgeted the content area minus it.
            let reserved = reserveIndicatorLines(
                handler: handler,
                contentHeight: contentHeight - (handler.dropSlotAddsRow ? 1 : 0),
                context: context)
            drawnIndicators = (reserved.above, reserved.below)
        }

        let composed = composeRowLines(
            handler: handler,
            tableHasFocus: tableHasFocus,
            indicators: drawnIndicators,
            columnWidths: columnWidths,
            innerWidth: innerWidth,
            context: context,
            palette: palette
        )

        return (
            lines: composed.lines,
            runs: composed.runs,
            claims: composed.claims,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                // As DRAWN — the origin after the single-line absorb — so the
                // click map subscripts the rows actually on screen.
                visibleRange: handler.drawnVisibleRange,
                // Same predicate as the click map above and as the drawing
                // condition, rather than `hasContentAbove` alone — the
                // multi-line twin already spells it out. Its consumer is the
                // ScrollView cursor-follow marker, which was aiming one line
                // low in the same configuration.
                scrollOffsetAbove: drawnIndicators.above ? 1 : 0,
                drawnBands: composed.bands,
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
    ) -> (
        lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion],
        state: PopulatedRenderState
    ) {
        let contentHeight = max(1, context.availableHeight - 3)
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID, defaultPrefix: "table",
            propertyIndex: StateIndex.focusID)
        let (handler, _) = resolveHandler(
            persistedFocusID: persistedFocusID, stateStorage: stateStorage, context: context,
            contentHeight: contentHeight, overflows: { data.count + $0 > contentHeight },
            showsScrollbar: true)
        // The whole row area is visible — the bar, not a text indicator, marks the
        // off-screen rows — so the viewport is the full content height, less the
        // line a hovering drag's landing slot takes from the rows.
        if !context.isMeasuring {
            // Render only, for the reason `reserveIndicatorLines` gives at
            // length: a measure pass is offered a different height and would
            // leave a later clamp reading another proposal's viewport.
            handler.viewportHeight = max(1, contentHeight - (handler.dropSlotAddsRow ? 1 : 0))
            // A bar spends no indicator line, so this path absorbs nothing: the
            // rows are drawn from the offset itself. Published anyway, so a
            // frame that took another path cannot leave a stale origin behind.
            handler.drawnOffset = handler.scrollOffset
            handler.clampScrollOffset()
        }
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. `engageFocus`
        // still runs with the true answer: it publishes the Escape claim and
        // the status bar's Return verb, and sets `isFocusEngaged`, none of
        // which are focus EFFECTS.
        let tableHasFocus = context.indicatesFocus(
            handler.engageFocus(context: context, focusID: persistedFocusID))

        // The handler's accessor, not a raw `scrollOffset..<min(…)`: the
        // persisted offset can exceed a freshly-shrunk `data.count` during a
        // measure pass (the clamp above is render-gated), and the raw form
        // would construct an inverted range (e.g. `1300..<2`) and trap.
        let visibleRange = handler.visibleRange
        var bar = ScrollbarRenderer.verticalScrollbar(
            height: contentHeight, extent: data.count, viewport: contentHeight, offset: visibleRange.lowerBound,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: ScrollbarColors(
                thumb: palette.foregroundSecondary, track: ScrollbarColors.track(in: palette),
                arrow: palette.foregroundTertiary))

        // Content-only row lines; the bar cell is merged in at the END, keyed by
        // absolute line index, so an overscroll slide moves the rows and leaves
        // the bar exactly where it is (§1.5).
        //
        // Drawn in reorder order (the dragged row out, a slot where it would
        // land) — see `composeRowLines` for the same two lines of it.
        let drawn = handler.reorderDrawnRows(visibleRange)
        func padded(_ line: String) -> String {
            line + String(repeating: " ", count: max(0, contentInnerWidth - line.strippedLength))
        }
        var rowLines: [String] = []
        // Heights, not entries: the slot stands for every row in hand, so it can
        // be several lines tall and the entries no longer map one-to-one onto
        // lines. Same shape as `composeRowLines`.
        var drawnHeights: [(entry: ItemListHandler<Value.ID>.DrawnRow, height: Int)] = []
        /// The breathing rows' lines and every frame of each, at their position
        /// among `rowLines` — turned into runs once the clip and the slide have
        /// settled where those lines actually ended up.
        var pulseRuns: [PulseRun] = []
        /// The rows' claims, at their position among `rowLines` — moved by the same
        /// slide the runs are, once the clip has settled where the lines landed.
        var rowOpacity: [OpacityRegion] = []
        rowLines.reserveCapacity(contentHeight)
        // One sampler for the frame, not one per row: building it quantises the
        // ramp, which is an array a row must not allocate.
        let rowRamp = cellRamp(rowWidth: contentInnerWidth, context: context)
        for entry in drawn {
            switch entry {
            case .row(let rowIndex):
                let row = renderRow(
                    item: data[rowIndex],
                    paint: RowPaint(row: rowIndex, ramp: rowRamp, width: contentInnerWidth),
                    columnWidths: columnWidths,
                    isFocused: handler.isCursorRow(rowIndex) && tableHasFocus,
                    isSelected: handler.isSelected(at: rowIndex),
                    isReturningHome: handler.returningRows.contains(rowIndex),
                    context: context, palette: palette)
                collect(
                    line: row.line, frames: row.pulseFrames, timing: row.pulseTiming, claims: row.claims,
                    into: &rowLines, runs: &pulseRuns, claims: &rowOpacity, transform: padded)
                drawnHeights.append((entry, 1))
            case .slot:
                let slot = reorderSlotLines(
                    handler: handler, columnWidths: columnWidths, rowWidth: contentInnerWidth,
                    context: context, palette: palette)
                collect(
                    slot, into: &rowLines, runs: &pulseRuns, claims: &rowOpacity,
                    transform: padded)
                drawnHeights.append((entry, slot.lines.count))
            }
        }
        // See `composeRowLines`: clipped away from the slot, never through it.
        // The excursion term is NEGATED: `slid()` draws unslid line y at
        // y − excursion (both signs), so the bands must move the same way —
        // `+ excursion` sent them in the OPPOSITE direction, 2×excursion away
        // from the drawn rows. `ScrollOverscrollState.slidRange` (the List's
        // path) subtracts for the same reason.
        let slide =
            clipOverrun(&rowLines, to: contentHeight, drawn: drawnHeights)
            - handler.overscrollState.excursion
        // The scrollbar path draws no "N more above" line at all — the bar is
        // the indicator — so nothing sits between the header and the first row.
        let bands = publishRowBands(
            handler: handler, drawn: drawnHeights, slide: slide,
            indicatorLines: 0, lineCount: contentHeight)
        while rowLines.count < contentHeight { rowLines.append(padded("")) }
        let blankRow = String(repeating: " ", count: max(0, contentInnerWidth))
        let slid = handler.overscrollState.slid(rowLines, blank: blankRow)
        // A bar cell on every line — plain track below a bar shorter than the lines.
        bar.fit(toCount: slid.count, field: ScrollbarColors.track(in: palette))
        let lines = zip(slid, bar.lines).map { $0 + $1 }

        return (
            lines,
            // The runs travel exactly as the hit bands do — same slide, no
            // indicator line on this path — so a run and the band it belongs to
            // can never end up on different rows.
            rowRuns(pulseRuns, slide: slide, topOffset: 0, lineCount: lines.count),
            // The bar's claims are NOT slid: the bar stays put while the rows move.
            rowClaims(rowOpacity, slide: slide, topOffset: 0, lineCount: lines.count)
                + bar.claims(atColumn: contentInnerWidth),
            PopulatedRenderState(
                handler: handler, focusID: persistedFocusID, visibleRange: visibleRange,
                scrollOffsetAbove: 0, drawnBands: bands, hasScrollbar: true,
                columnWidths: columnWidths, rowContentWidth: contentInnerWidth))
    }

    // MARK: - Multi-line content (variable row heights)

    /// The render path for a table with multi-line cells. Rows can be taller than
    /// one line, so the visible window, the scroll bounds, focus-reveal, and the
    /// click mapping are all line-aware (driven by per-row heights). The
    /// single-line path above is left completely untouched.
    ///
    /// Marks the rows it can't show with a scrollbar when `showsScrollbar`, "N
    /// more above/below" indicator lines otherwise — the same choice every other
    /// scrollable makes. The bar costs a column instead of a line, so the rows
    /// get the whole content area, and nothing here reserves an indicator line
    /// (which is what lets the table reach its true last screenful).
    private func buildMultiLineContent(
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        columnWidths: [Int],
        showsScrollbar: Bool,
        innerWidth: Int
    ) -> (
        lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion],
        state: PopulatedRenderState
    ) {
        let gutter = selectionGutter(context.environment)
        // 3 = top border + column header + bottom border.
        let contentHeight = max(1, context.availableHeight - 3)

        // Row heights are answered lazily. The scroll arithmetic below touches only
        // a viewport's worth of rows — the visible window, plus the bottom suffix
        // that fixes the furthest scroll — so a tall table needn't wrap every
        // off-screen row (the optimisation a scrollbar's *absence* permits: nothing
        // exposes the total extent).
        //
        // TWO memos, not one, because the rows fall into two kinds and only one of
        // them is worth remembering the CELLS of. A row that will be DRAWN is laid
        // out once, cells and all, and `composeMultiLineRows` draws from that same
        // answer — it used to call `cellLayout` again, so every visible cell's value
        // String was built twice a frame and hashed into `TextWrapping`'s fit memo
        // twice. A row that is only MEASURED — the bottom suffix `maxScrollOffset`
        // walks, the rows `ScrollExtentEstimator` samples — keeps `rowHeight`'s
        // height-only path, which is the whole reason that function exists: one
        // shared memo carrying cells would retain a `[[String]]` per measured row
        // too, and under ``ScrollExtentPrecision/exact`` (or for any table at or
        // below its 256-row limit) the estimator measures every row — turning an
        // O(1)-cells walk into an O(rows)-cells one.
        //
        // What the split gives up, since this is where the single memo's own note
        // used to claim it: scrolled near the end the window and the suffix overlap,
        // and an overlapping row is now measured height-only by the suffix walk AND
        // laid out by the window walk — a height pass plus a layout per drawn row,
        // which is exactly what it cost before, so nothing is lost there and nothing
        // is saved either. The saving is the whole window at every offset where the
        // two don't overlap. Routing the suffix through `layoutOf` as well would
        // recover the end of the table and pay for it everywhere else, allocating
        // cells for a screenful of rows nothing draws.
        var layoutCache: [Int: (cells: [[String]], height: Int)] = [:]
        var heightCache: [Int: Int] = [:]
        /// The wrapped cells and the height of a row that is about to be drawn.
        func layoutOf(_ index: Int) -> (cells: [[String]], height: Int) {
            if let cached = layoutCache[index] { return cached }
            let layout = cellLayout(for: data[index], columnWidths: columnWidths)
            layoutCache[index] = layout
            return layout
        }
        /// The height of a row that may only be measured. The layout memo is asked
        /// first because most callers ask about rows that are IN the window: by the
        /// time the scrollbar's extent estimator and `onScreenRowHeights` run, every
        /// window row is already laid out.
        func heightOf(_ index: Int) -> Int {
            if let cached = layoutCache[index] { return cached.height }
            if let cached = heightCache[index] { return cached }
            let height = rowHeight(of: data[index], columnWidths: columnWidths)
            heightCache[index] = height
            return height
        }

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID, defaultPrefix: "table",
            propertyIndex: StateIndex.focusID)
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<ItemListHandler<Value.ID>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID, itemCount: data.count, viewportHeight: 1,
                selectionMode: selectionMode, canBeFocused: !isDisabled(in: context)))
        let handler = handlerBox.value
        handler.itemCount = data.count
        // As on the single-line path: a hovering drag's landing slot is a line
        // nothing left to make room for, so the rows are budgeted the content
        // area minus it and ``ItemListHandler/extent`` gains the row that lets
        // the viewport reach past the last one.
        // A landing slot occupies a line whoever opened it. A drag of this
        // control's OWN rows pays for it with the lines those rows gave up —
        // but only while those rows are still in the window, which is the
        // question ``ItemListHandler/reorderSlotNeedsALine`` answers.
        handler.dropSlotAddsRow = handler.externalDropSlot != nil || handler.reorderSlotNeedsALine
        handler.syncReturningRows(with: context.environment.dragAndDropSession)
        let rowArea = max(1, contentHeight - (handler.dropSlotAddsRow ? 1 : 0))
        // The FULL area, not `rowArea`: `dropSlotAddsRow` is already set above,
        // and every reader inside the handler that has to account for the slot
        // subtracts it itself (``rowLineBudget``). Passing the reduced figure
        // charges for the slot twice — see the twin at the single-line path,
        // which passes `contentHeight` for the same reason.
        handler.contentHeight = contentHeight
        handler.canBeFocused = !isDisabled(in: context)
        handler.primaryAction = primaryAction
        handler.onMove = moveAction
        handler.onSort = sortKeyAction
        // BEFORE the rows are composed — see the List's twin call site.
        handler.carryReorderTargetThroughAutoScroll()
        // As on the single-line path, in one shared call — see
        // `ItemListHandler.syncFrameInputs`.
        //
        // `reorderFeedback: .live` — multi-line rows reorder live only: a drop
        // slot would have to take part in the line-budget arithmetic below that
        // lets a tall row be partially clipped, and moving the rows themselves
        // needs no slot. Stated in ``Table/onMove(_:)``.
        //
        // `keyboardMoveIsLive: true` — for the same reason. The handler
        // otherwise previews a keyboard move `.dimmed`, at a slot this composer
        // never draws, so Ctrl-R moved nothing visible and parked the cursor on
        // the slot's neighbour.
        //
        // `rowHeight` — the reveal-on-focus arithmetic runs between renders, on
        // key events, and answers heights lazily from this frame's data and
        // column widths.
        handler.syncFrameInputs(
            environment: context.environment,
            reorderFeedback: .live,
            keyboardMoveIsLive: true,
            rowHeight: { rowHeight(of: data[$0], columnWidths: columnWidths) })
        handler.idAt = { data[$0].id }
        handler.itemIDs = []
        // `viewportHeight` is set once the window is cut, below. It used to be
        // set HERE to the row count of the tail screenful — an
        // offset-independent number that once calibrated the handler's
        // row-based maxOffset, a job the height walk in `resolvedMaxOffset`
        // has done since `rowHeight` and `contentHeight` are both set on this
        // path — and that made PageDown, Shift+Page and the row-move page step
        // travel by the wrong count wherever the rows at the end are taller or
        // shorter than the rows on screen.
        let furthest = syncIndicatorChrome(
            handler, showsScrollbar: showsScrollbar, rowArea: rowArea,
            contentHeight: contentHeight, context: context, heightOf: heightOf)
        // §1.5, in LINES — not against `viewportHeight`, which on this path is
        // a ROW count (set from the window further down). Resolving against
        // that made `.viewport(minus:)` mean "rows visible − n" lines here
        // while the List twin meant "viewport lines − n"; and being a frame
        // stale, the first blocked tick resolved against a fresh handler's
        // default of 1.
        handler.resolveOverscroll(
            environment: context.environment, contentHeight: contentHeight)
        // Clamp, snap off the resting duplicate, apply the anchor — the sequence
        // `_ListCore` and the single-line path below run too, and the render-pass
        // guard that has to wrap it. See `settleScrollPosition`.
        handler.settleScrollPosition(
            measuring: context.isMeasuring, overflowing: furthest > 0,
            drawsTextIndicators: handler.drawsScrollIndicators,
            firstRowHeight: heightOf(0))
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection

        // Drawing only — see `RenderContext.indicatesFocus(_:)`. `engageFocus`
        // still runs with the true answer: it publishes the Escape claim and
        // the status bar's Return verb, and sets `isFocusEngaged`, none of
        // which are focus EFFECTS.
        let tableHasFocus = context.indicatesFocus(
            handler.engageFocus(context: context, focusID: persistedFocusID))

        let window = ScrollRowWindow.resolve(
            scrollOffset: handler.scrollOffset, count: data.count,
            contentHeight: contentHeight, topClip: handler.scrollTopClipLines,
            drawsTextIndicators: handler.drawsScrollIndicators,
            alwaysDrawsIndicators: context.environment.alwaysShowsVerticalTextIndicators,
            // `layoutOf`, not `heightOf`: every row this walk asks about is a row it
            // then puts IN the window (the one straddling the budget included — see
            // `ScrollRowWindow.fill`), so laying it out here with its cells is what
            // `composeMultiLineRows` draws instead of laying it out a second time.
            height: { layoutOf($0).height })
        // The window may have absorbed a top clip (or a whole first row) that
        // an indicator would otherwise have announced — the rows are drawn
        // from ITS position, so the mouse mapping must measure from it too.
        let topClip = window.topClip
        publishMultiLineWindow(handler: handler, range: window.range, context: context)
        // The bar is metered in LINES, like the `List`'s over multi-line rows:
        // its extent is the whole wrapped height and its offset the lines
        // above the window. That total is the one thing this path otherwise
        // never needs (see `heightOf`), so it is summed only when a bar is
        // actually drawn — the same discipline `_ListCore.listScrollbarCells`
        // keeps.
        let bar =
            showsScrollbar
            ? multiLineScrollbarCells(
                window: window, contentHeight: contentHeight,
                height: heightOf, handler: handler, columnWidths: columnWidths,
                context: context, palette: palette)
            : ClaimingColumn()
        let composed = composeMultiLineRows(
            window: window, handler: handler, tableHasFocus: tableHasFocus,
            rows: MultiLineRowLayouts(columnWidths: columnWidths, layout: layoutOf),
            innerWidth: innerWidth,
            contentHeight: contentHeight, bar: bar, context: context)

        // ONE answer, named once, for everything that has to agree with what
        // `composeMultiLineRows` just drew — `window.showsAbove` rather than the
        // handler's `hasContentAbove`, which is false for a top clip inside
        // row 0 while the indicator is on screen.
        let indicatorLines = window.reservesAbove ? 1 : 0
        let bands = multiLineRowBands(
            handler: handler, range: window.range,
            heights: onScreenRowHeights(window.range, height: heightOf, topClip: topClip),
            // The row block's DRAWN end, not the content area's. The heights are
            // whole rows below the top clip, and the row straddling the budget is
            // drawn short — `ScrollRowWindow.fill` admits it so the viewport fills
            // exactly — so a band trimmed only at `contentHeight` ran on over the
            // "▼ N more rows below" line: a click there selected the cut row, and
            // with `.onMove` a press grabbed it for a `.live` reorder. A push past
            // the top did the same with the rows' slid-off tail. A ceiling rather
            // than per-row drawn heights, because a cut at the bottom moves no row
            // below it; and the ceiling `_ListCore` (`slidRows.count`) and the
            // single-line path (`lines.count + rowLines.count`) already pass.
            indicatorLines: indicatorLines, lineCount: composed.rowsEnd)
        // Built either way — the render state below carries them, and a measure
        // pass's state is thrown away — but PUBLISHED only by the render, for
        // the reason the gate above gives and one more: publishing runs
        // ``ItemListHandler/retargetForAutoScroll()`` in a `defer`, which for a
        // `.live` reorder calls `onMove` — the APP's data, moved from a measure
        // pass, and moved to wherever the parent's proposal happened to put the
        // rows. Two publishes a frame meant two crossings a tick, so an
        // auto-scrolling drag inside a stack invoked `onMove` about twice as
        // often as it moved a row.
        if !context.isMeasuring { handler.publishRowBands(bands) }
        return (
            lines: composed.lines,
            runs: composed.runs,
            claims: composed.claims,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                visibleRange: window.range,
                scrollOffsetAbove: indicatorLines,
                drawnBands: bands,
                hasScrollbar: showsScrollbar,
                columnWidths: columnWidths,
                rowContentWidth: tableContentWidth(columnWidths, within: innerWidth, gutter: gutter)
            )
        )
    }

    /// The vertical scrollbar cells for a multi-line table — one styled cell per
    /// content line, metered in LINES so the thumb tracks fine wheel steps
    /// through tall rows exactly as the `List`'s does.
    ///
    /// This is the one place that needs the table's TOTAL wrapped height, which
    /// is why it is reached only when a bar is drawn: everything else here works
    /// from a screenful of memoised heights.
    ///
    /// And it doesn't need that total *exactly*. The off-screen rows reach the
    /// screen only as a thumb position and a thumb size, so under the default
    /// ``ScrollExtentPrecision/approximate`` they are sampled rather than
    /// wrapped — the shared ``ScrollExtentEstimator`` does the arithmetic for
    /// both twins, and pins both ends of the travel either way.
    private func multiLineScrollbarCells(
        window: ScrollRowWindow,
        contentHeight: Int,
        height: (Int) -> Int,
        handler: ItemListHandler<Value.ID>,
        columnWidths: [Int],
        context: RenderContext,
        palette: any Palette
    ) -> ClaimingColumn {
        // Everything that shapes a row's wrapped height, so a stale mean
        // cannot outlive the layout that produced it (see `extentMeanCache`).
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(context.environment.scrollExtentPrecision)
        for (column, width) in zip(columns, columnWidths) {
            hasher.combine(width)
            hasher.combine(column.lineLimit)
        }
        let signature = hasher.finalize()
        let cachedMean =
            handler.extentMeanCache.flatMap { $0.signature == signature ? $0.mean : nil }
        let metrics = ScrollExtentEstimator.lineMetrics(
            visible: window.range, count: data.count, topClip: window.topClip,
            precision: context.environment.scrollExtentPrecision,
            cachedMean: cachedMean, height: height)
        if !context.isMeasuring, let mean = metrics.mean {
            handler.extentMeanCache = (signature: signature, mean: mean)
        }
        return ScrollbarRenderer.verticalScrollbar(
            height: contentHeight, extent: metrics.extent, viewport: contentHeight,
            offset: metrics.offset,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: ScrollbarColors(
                thumb: palette.foregroundSecondary, track: ScrollbarColors.track(in: palette),
                arrow: palette.foregroundTertiary))
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

    /// Whether the "N more above / below" lines are this table's indicator:
    /// not when a scrollbar marks the hidden rows instead, and not when the
    /// view's indicators are hidden outright.
    ///
    /// Asked at `overflowing: true` because whether the rows DO overflow is
    /// itself decided using this answer (see `maxScrollOffset`), so it cannot
    /// also be an input to it — and under the default `.automatic` a table that
    /// turns out to fit reserves nothing either way, having nothing hidden to
    /// announce. Under `.scrollIndicators(.visible)` it reserves both lines
    /// whatever is hidden (`d1c54212`), which is a reservation this answer gates
    /// — see `alwaysReservesIndicatorLines` below — but does not decide.
    ///
    /// `contentHeight` is the CONTENT AREA, and it must not be the row area.
    /// The two differ by the drag landing slot, so gating on the row area would
    /// blink the "N more" lines out mid-drag on a three-line table — where the
    /// compose had three lines to spend and never overflowed anything.
    private func drawsTextIndicators(
        _ showsScrollbar: Bool, _ context: RenderContext, contentHeight: Int
    ) -> Bool {
        !showsScrollbar
            && context.environment.verticalScrollIndicators(overflowing: true)
                .fitting(contentHeight: contentHeight).text
    }

    /// The multi-line path's indicator chrome, published to the handler, and
    /// the furthest scroll offset the wrapped heights allow — the one number
    /// both flags depend on, handed back for the overscroll settle below.
    ///
    /// Sync both chrome flags in case the rows switch between the single-line
    /// and multi-line paths across frames (the single-line resolve sets them
    /// from ITS chrome; stale values would mis-budget the focus-reveal
    /// arithmetic). Same divergence class as the `017683fa` capture notes on
    /// the single-line path.
    private func syncIndicatorChrome(
        _ handler: ItemListHandler<Value.ID>, showsScrollbar: Bool, rowArea: Int,
        contentHeight: Int, context: RenderContext,
        heightOf: @escaping (Int) -> Int
    ) -> Int {
        // `rowArea` budgets the rows; `contentHeight` decides whether the
        // indicators fit at all. See ``drawsTextIndicators(_:_:contentHeight:)``
        // for why the two must not be conflated here.
        let draws = drawsTextIndicators(showsScrollbar, context, contentHeight: contentHeight)
        let furthest = maxScrollOffset(
            count: data.count, contentHeight: rowArea,
            drawsTextIndicators: draws, height: heightOf)
        handler.showsScrollbar = showsScrollbar
        // Not `!showsScrollbar`: a table whose indicators are hidden draws
        // neither, and the "N more" arithmetic must know that.
        // `.visible` asks for the affordance, not for a hint: the lines are drawn
        // even where the rows all fit, so the overflow test does not gate them.
        handler.alwaysReservesIndicatorLines =
            draws && !showsScrollbar && context.environment.alwaysShowsVerticalTextIndicators
        handler.drawsScrollIndicators =
            draws && (furthest > 0 || handler.alwaysReservesIndicatorLines)
        return furthest
    }

    /// The furthest the table can scroll: the largest first-visible row such that
    /// the remaining rows still fill the content area (reserving a line for the
    /// "above" indicator that shows whenever the first visible row isn't row 0 —
    /// a table drawing no such line, because it has a bar or no indicator at
    /// all, reserves nothing and can reach its true last screenful).
    private func maxScrollOffset(
        count: Int, contentHeight: Int, drawsTextIndicators: Bool = true,
        height: (Int) -> Int
    ) -> Int {
        var used = 0
        var offset = count
        while offset > 0 {
            let aboveReserve = (drawsTextIndicators && (offset - 1) > 0) ? 1 : 0
            let rowH = height(offset - 1)
            if used + rowH + aboveReserve > contentHeight { break }
            used += rowH
            offset -= 1
        }
        return offset
    }
    /// Whether a multi-line table's wrapped rows are taller than its row area —
    /// stopping the moment they are, so a tall table sums a screenful rather
    /// than all of it, and a table that fits has at most `rowArea` rows to sum.
    /// The same early-exit shape as `_ListCore.rowsOverflow`.
    ///
    /// Measured at the width a bar WOULD leave, where rows wrap taller and so
    /// overflow soonest: if they don't overflow even there they cannot overflow
    /// at the full width either, so answering "no bar" is final and the real
    /// column widths are then computed without the reservation.
    private func multiLineOverflows(rowArea: Int, innerWidth: Int, gutter: Int) -> Bool {
        let widths = calculateColumnWidths(
            availableWidth: max(1, innerWidth), spacing: columnSpacing, gutter: gutter)
        var lines = 0
        for item in data {
            lines += rowHeight(of: item, columnWidths: widths)
            if lines > rowArea { return true }
        }
        return false
    }

    /// Stitches the visible multi-line rows together with whichever chrome marks
    /// the hidden ones: a scrollbar down the right-hand column when `bar` is
    /// non-empty, "N more above/below" lines when the handler says those are
    /// this table's indicator, and nothing at all when they are hidden. Never
    /// both — the bar says everything the indicators would, and takes no line
    /// to say it.
    ///
    /// `rowsEnd` is where the row block's DRAWN lines stop, in the band space —
    /// the "N more above" line counted in, the "▼ N more below" line and any
    /// padding after it not. It is the ceiling the hit bands are trimmed to; see
    /// its one caller.
    private func composeMultiLineRows(
        window: ScrollRowWindow,
        handler: ItemListHandler<Value.ID>,
        tableHasFocus: Bool,
        rows: MultiLineRowLayouts,
        innerWidth: Int,
        contentHeight: Int,
        bar: ClaimingColumn,
        context: RenderContext
    ) -> (lines: [String], runs: [AnimatedCellRun], claims: [OpacityRegion], rowsEnd: Int) {
        let palette = context.environment.palette
        let gutter = selectionGutter(context.environment)
        // Every line — focused-row backgrounds and indicators included — is padded
        // to the *content* width (the columns), not the full interior, so a focused
        // row or a scroll indicator is never wider than the header and rows; that
        // width mismatch is what made the wrapping VStack centre the header.
        let contentWidth = tableContentWidth(rows.columnWidths, within: innerWidth, gutter: gutter)
        let showsBar = !bar.isEmpty
        // Whether the "N more" lines are this table's indicator — false for a
        // bar AND for hidden indicators, which is why it is the handler's
        // resolved answer rather than `!showsBar`.
        let drawsText = handler.drawsScrollIndicators
        // A focused table with no scrollbar pulses its "N more" indicators.
        // Resolve the emphasis ONLY when an indicator will actually be drawn.
        // Resolving consults the cursor clock, and that read is what tells the
        // demand-driven loop the frame consumed it — so asking before knowing
        // whether anything will be painted re-renders the whole page ~20 times
        // a second to draw nothing. Same class as the Stepper's ungated
        // `pulsePhase` read (8ebc3385).
        let drawsIndicator = drawsText && (window.showsAbove || window.showsBelow)
        let indicatorCycle =
            drawsIndicator
            ? scrollIndicatorCycle(isFocused: tableHasFocus, context: context) : nil
        let numberLocale = context.environment.locale
        let indicatorSurface = context.environment.enclosingSurface
        var lines: [String] = []
        /// The indicators' own runs. They are chrome — the rows slide past them
        /// — so each sits at the assembled line it was appended to, whatever
        /// the rows did.
        var chromeRuns: [AnimatedCellRun] = []
        /// …and their claims, placed the same way (§53).
        var chromeClaims: [OpacityRegion] = []
        // Drawn iff a line was RESERVED — see `ScrollRowWindow.reservesAbove`. The
        // count is legitimately 0 under `alwaysShowsVerticalTextIndicators`.
        if window.reservesAbove {
            let indicator = renderScrollIndicator(
                // At least one whenever anything IS hidden — a top clip hides
                // part of the first row, so the whole-row count can be 0 with a
                // row genuinely off screen. See the `List` twin.
                direction: .up,
                count: window.showsAbove ? max(1, window.range.lowerBound) : 0,
                unit: .rows,
                width: contentWidth, palette: palette, cycle: indicatorCycle,
                over: indicatorSurface, locale: numberLocale)
            appendIndicator(indicator, to: &lines, runs: &chromeRuns, claims: &chromeClaims)
        }
        // The content area fills EXACTLY: the bottom row may be partially
        // clipped (the top row already can be, via `scrollTopClipLines`), so
        // the table's height never changes with which rows happen to be
        // visible. Under EITHER granularity — a whole-row viewport underfills
        // whenever the visible rows don't sum to the budget, and the blank
        // lines that left at the bottom read as the table truncating itself.
        let rowLineBudget =
            max(1, contentHeight - lines.count - (window.reservesBelow ? 1 : 0))
        var rowLinesEmitted = 0
        // The rows are collected apart from the indicator chrome so that only
        // they take an overscroll slide (§1.5).
        var slidableRows: [String] = []
        /// The breathing row's lines and every frame of each, at their position
        /// among `slidableRows` — see `collect`.
        var pulseRuns: [PulseRun] = []
        var rowOpacity: [OpacityRegion] = []
        let rowRamp = cellRamp(rowWidth: contentWidth, context: context)
        for rowIndex in window.range {
            let rendered = renderMultiLineRow(
                layout: rows.layout(rowIndex),
                paint: RowPaint(row: rowIndex, ramp: rowRamp, width: contentWidth),
                isFocused: handler.isFocused(at: rowIndex) && tableHasFocus,
                isSelected: handler.isSelected(at: rowIndex),
                columnWidths: rows.columnWidths, context: context, palette: palette)
            var rowLines = rendered.lines
            // Clipped alongside the lines, so `pulseFrames[i]` stays the frames
            // of `rowLines[i]`.
            var pulseFrames = rendered.pulseFrames
            // A top clip means the top row enters partially, its first lines
            // scrolled off above the viewport. Clip by the WINDOW's resolved
            // origin, not the handler's raw state — the window may have
            // absorbed a one-line clip (drawing the line instead of a "▲ 1
            // more" indicator), and clipping it here anyway made that line
            // silently vanish while every row sat one line above its hit band.
            // Clipped alongside them too: a claim names a line by index, so lines
            // taken off the FRONT move every survivor's index down by as many.
            var rowRegions = rendered.claims
            if rowIndex == window.range.lowerBound, window.topClip > 0 {
                // Total by `max(0, …)`: the same guard `_ListCore.clipRow` carries,
                // for the same reason — `clampTopClip()` keeps a zero-line row's clip at
                // zero, and `removeFirst(-1)` would trap if that ever stopped holding.
                let clipped = min(window.topClip, max(0, rowLines.count - 1))
                rowLines.removeFirst(clipped)
                pulseFrames?.removeFirst(clipped)
                rowRegions = rowRegions.compactMap { claim in
                    guard claim.offsetY >= clipped else { return nil }
                    return claim.shifted(byX: 0, y: -clipped)
                }
            }
            // …and the bottom row leaves partially, clipped at the budget.
            let remaining = rowLineBudget - rowLinesEmitted
            if remaining <= 0 { break }
            if rowLines.count > remaining {
                let dropped = rowLines.count - remaining
                rowLines.removeLast(dropped)
                pulseFrames?.removeLast(dropped)
                rowRegions = rowRegions.filter { $0.offsetY < rowLines.count }
            }
            collect(
                RenderedRow(
                    lines: rowLines, pulseFrames: pulseFrames, pulseTiming: rendered.pulseTiming,
                    claims: rowRegions),
                into: &slidableRows, runs: &pulseRuns, claims: &rowOpacity)
            rowLinesEmitted += rowLines.count
        }
        // The rows' own coordinates start below whatever indicator lines are
        // already in `lines`; `slid` shifts them by −excursion, exactly as the
        // bands are shifted elsewhere.
        let rowsTop = lines.count
        lines.append(contentsOf: handler.overscrollState.slid(
            slidableRows, blank: String(repeating: " ", count: max(0, contentWidth))))
        // `slid` keeps the count, so this is the block's end whatever the
        // excursion — short of `contentHeight` by the "▼ N more below" line
        // appended next and by any padding after that.
        let rowsEnd = rowsTop + slidableRows.count
        let runs = rowRuns(
            pulseRuns, slide: -handler.overscrollState.excursion, topOffset: rowsTop,
            lineCount: rowsEnd)
        let claims = rowClaims(
            rowOpacity, slide: -handler.overscrollState.excursion, topOffset: rowsTop,
            lineCount: rowsEnd)
        if window.reservesBelow {
            let indicator = renderScrollIndicator(
                direction: .down, count: data.count - window.range.upperBound,
                unit: .rows,
                width: contentWidth, palette: palette, cycle: indicatorCycle,
                over: indicatorSurface, locale: numberLocale)
            appendIndicator(indicator, to: &lines, runs: &chromeRuns, claims: &chromeClaims)
        }
        // A scrolled/overflowing table fills its content area EXACTLY,
        // whatever the granularity: whole rows can underfill under row
        // granularity, so pad the shortfall — a fixed-height table's frame
        // must not breathe as rows of different heights scroll through.
        // A non-overflowing table keeps its natural, content-sized height, unless
        // it was GIVEN one — which `renderToBuffer` handles for both paths at once.
        if window.showsAbove || window.showsBelow || window.topClip > 0
            || window.reservesAbove || window.reservesBelow
        {
            while lines.count < contentHeight {
                lines.append(String(repeating: " ", count: contentWidth))
            }
        }
        guard showsBar else { return (lines, runs + chromeRuns, claims + chromeClaims, rowsEnd) }
        // The bar is the rightmost interior column, merged in by absolute line
        // index so an overscroll slide moves the rows and leaves it where it
        // is (§1.5) — the same composition the single-line path uses, claims
        // included: plain track below a bar shorter than the lines, and the
        // bar's claims on its own column, unslid.
        while lines.count < contentHeight {
            lines.append(String(repeating: " ", count: contentWidth))
        }
        var bar = bar
        bar.fit(toCount: lines.count, field: ScrollbarColors.track(in: palette))
        return (
            zip(lines, bar.lines).map { $0 + $1 },
            runs + chromeRuns, claims + chromeClaims + bar.claims(atColumn: contentWidth), rowsEnd)
    }

    /// Renders one (possibly multi-line) row: the selection indicator on the first
    /// line, each column's wrapped cell lines beneath it, shorter cells padded with
    /// blank lines, and the selection/focus background spanning every line.
    ///
    /// Takes the row's `layout` rather than the row: the caller's window walk had to
    /// wrap the cells to learn the row's HEIGHT before it could decide the row was
    /// visible at all, so wrapping them again here to draw them was the same work a
    /// second time — see `buildMultiLineContent`'s layout memo.
    private func renderMultiLineRow(
        layout: (cells: [[String]], height: Int),
        paint: RowPaint,
        isFocused: Bool,
        isSelected: Bool,
        columnWidths: [Int],
        context: RenderContext,
        palette: any Palette
    ) -> RenderedRow {
        let (row, ramp, rowWidth) = (paint.row, paint.ramp, paint.width)
        let gutter = selectionGutter(context.environment)
        let spacing = asciiSpaces(columnSpacing)
        let visual = rowVisualState(
            isFocused: isFocused, isSelected: isSelected, context: context, palette: palette)
        let styledIndicator = ANSIRenderer.colorize(
            visual.indicator, foreground: visual.indicatorColor.opaqueSpelling)
        // See `renderRow`: one step of the ramp per ROW, so every line of a
        // wrapped row shares its colour, and a ramp that varies along the row
        // paints cell by cell instead.
        let bandsAcrossRow = ramp?.variesAcrossRow ?? false
        let foreground = cellColour(row: row, ramp: ramp, context: context, palette: palette)

        // One SGR introducer for every cell of every line — see ``renderRow``,
        // which this is the multi-line twin of. Here it matters more: the
        // per-cell colorize and the per-line array-plus-join ran once per LINE
        // per row, so `table-multiline` was the one table shape that did not
        // move when `renderRow` was rewritten.
        var cellStyle = TextStyle()
        cellStyle.foregroundColor = foreground.opaqueSpelling
        let cellSequence = bandsAcrossRow ? nil : ANSIRenderer.styleSequence(for: cellStyle)
        var rampSequences: [String?] = []
        let cellCount = min(columns.count, columnWidths.count)
        var claims: [OpacityRegion] = []

        var lines: [String] = []
        lines.reserveCapacity(layout.height)
        // Only a breathing row needs its lines kept bare: everything else would
        // be an array built per row per frame and thrown away.
        let pulseColors = visual.background.pulseColors
        // Hoisted out of the per-line loop: `claimableFill` is a switch, and both the
        // claim and the fill below want the same answer for every line of the row.
        let claimableFill = pulseColors == nil ? visual.background.claimableFill : nil
        /// The same lines WITHOUT their background, kept so a pulse can be
        /// applied to each of them per step (see the single-line path).
        var bareLines: [String] = []
        for lineIndex in 0..<layout.height {
            // The indicator shows only on the first line; continuation lines keep
            // the same gutter so the columns line up beneath it. A table with
            // nothing to mark has no gutter at all, and both are empty.
            var content =
                gutter == 0
                ? "" : (lineIndex == 0 ? styledIndicator + " " : String(repeating: " ", count: gutter))
            content.reserveCapacity(rowWidth * 2)

            var cellColumn = gutter
            for index in 0..<cellCount {
                if index > 0 {
                    content.append(contentsOf: spacing)
                    cellColumn += columnSpacing
                }
                let column = columns[index]
                let cellWidth = columnWidths[index]
                let cellLines = layout.cells[index]
                let text = lineIndex < cellLines.count ? cellLines[lineIndex] : ""
                if let ramp, bandsAcrossRow {
                    var walked = cellColumn
                    PaintRenderer.band(
                        alignText(
                            text, width: cellWidth, alignment: column.alignment,
                            truncationMode: column.truncationMode),
                        column: &walked, row: row, style: cellStyle,
                        sampler: ramp, sequences: &rampSequences, into: &content)
                } else if let cellSequence {
                    content += cellSequence
                    appendAligned(
                        text, width: cellWidth, alignment: column.alignment,
                        truncationMode: column.truncationMode, into: &content)
                    content += ANSIRenderer.reset
                } else {
                    appendAligned(
                        text, width: cellWidth, alignment: column.alignment,
                        truncationMode: column.truncationMode, into: &content)
                }
                cellColumn += cellWidth
            }

            // Row-local, and per LINE: the mark is on the first line only, as the
            // badge is — a tall row is one entry in the list, and one entry earns one
            // mark.
            claims += SelectableRowClaims.claims(
                line: lineIndex, width: rowWidth, cells: gutter..<cellColumn,
                ink: bandsAcrossRow ? nil : foreground,
                mark: gutter > 0 && lineIndex == 0 ? visual.indicatorColor : nil,
                fill: claimableFill)
            // A banded row's ink is not one colour, so it is not one rectangle: the
            // ramp answers per cell and the claim is a run per equal alpha across the
            // span the cells actually occupy. Every line of a tall row shares the
            // ramp's row step (see `bandsAcrossRow` above), so they share the runs too.
            if let ramp, bandsAcrossRow {
                claims += ramp.alphaClaims(
                    row: row, line: lineIndex, columns: gutter..<cellColumn)
            }
            guard case .none = visual.background else {
                content.append(contentsOf: asciiSpaces(rowWidth - content.strippedLength))
                if pulseColors != nil { bareLines.append(content) }
                lines.append(visual.background.painting(content))
                continue
            }
            lines.append(content)
        }
        // Same recolour-the-finished-line trick the single-line path uses: one
        // recolouring per step, not one render of the row per step.
        guard let pulseColors else { return RenderedRow(lines: lines, claims: claims) }
        return RenderedRow(
            lines: lines,
            pulseFrames: bareLines.map { bare in
                pulseColors.map { bare.withPersistentBackground($0) }
            },
            pulseTiming: visual.background.pulseTiming,
            claims: claims)
    }

    /// Fetches (or creates) the persistent ``ItemListHandler``
    /// and syncs its per-frame inputs.
    /// - Parameter overflows: Whether the rows overflow `contentHeight`, given
    ///   the extra lines they must share it with — 1 while a hovering drag is
    ///   drawing a landing slot, 0 otherwise. A closure rather than a `Bool`
    ///   because the answer depends on ``ItemListHandler/dropSlotAddsRow``,
    ///   which is a question about the handler this call is still resolving.
    /// - Returns: The handler and the overflow answer, which the caller needs
    ///   for its indicator reservation and cannot compute itself.
    private func resolveHandler(
        persistedFocusID: String,
        stateStorage: StateStorage,
        context: RenderContext,
        contentHeight: Int,
        overflows: (Int) -> Bool,
        showsScrollbar: Bool = false
    ) -> (handler: ItemListHandler<Value.ID>, overflowing: Bool) {
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<ItemListHandler<Value.ID>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID,
                itemCount: data.count,
                // Provisional: replaced below once the overflow answer exists,
                // and again by the caller once the offset is known.
                viewportHeight: contentHeight,
                selectionMode: selectionMode,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value
        handler.itemCount = data.count
        // A drag from elsewhere draws its landing slot as an extra line —
        // nothing left this table to make room for it. `Table` has no
        // same-table case to exclude: its rows are built from `data`, so they
        // cannot be `.draggable`.
        // A landing slot occupies a line whoever opened it. A drag of this
        // control's OWN rows pays for it with the lines those rows gave up —
        // but only while those rows are still in the window, which is the
        // question ``ItemListHandler/reorderSlotNeedsALine`` answers.
        handler.dropSlotAddsRow = handler.externalDropSlot != nil || handler.reorderSlotNeedsALine
        handler.syncReturningRows(with: context.environment.dragAndDropSession)
        let overflowing = overflows(handler.dropSlotAddsRow ? 1 : 0)
        // Clamp against the largest possible visible-row count (one
        // indicator, at an end); the exact viewport is finalised by
        // the caller once the offset is known.
        //
        // ROWS, like the exact one — minus the landing slot's line, which the
        // content height still contains. Without that subtraction the two
        // writes to `viewportHeight` mean different things (this one an entry
        // capacity, `reserveIndicatorLines`' a row count) and the bound taken
        // from this one is a row too TIGHT: `clampScrollOffset` then ejected
        // the offset auto-scroll had just reached, every frame, and the drag
        // stopped one row short of the end for ever.
        let provisionalViewport =
            max(1, (overflowing ? contentHeight - 1 : contentHeight)
                - (handler.dropSlotAddsRow ? 1 : 0))
        handler.contentHeight = contentHeight
        // A scrollbar reserves no indicator line, so the focus-reveal / offset
        // arithmetic must claim the full content height (matches the List path).
        handler.showsScrollbar = showsScrollbar
        // …and neither does a table whose indicators are hidden. The bar path
        // passes `showsScrollbar: true` and composes its own rows, so this is
        // the "N more" answer for both.
        let drawsText = drawsTextIndicators(
            showsScrollbar, context, contentHeight: contentHeight)
        // `.visible` asks for the affordance, not for a hint that appears when it
        // has something to say — so the overflow test does not gate it.
        handler.alwaysReservesIndicatorLines =
            drawsText && !showsScrollbar
            && context.environment.alwaysShowsVerticalTextIndicators
        handler.drawsScrollIndicators =
            drawsText && (overflowing || handler.alwaysReservesIndicatorLines)
        // Provisional, and RENDER-ONLY for the reason `reserveIndicatorLines`
        // spells out: a measure pass is handed a height the frame may not get,
        // and this value outlives the pass that wrote it.
        if !context.isMeasuring { handler.viewportHeight = provisionalViewport }
        handler.canBeFocused = !isDisabled(in: context)
        handler.primaryAction = primaryAction
        handler.onMove = moveAction
        handler.onSort = sortKeyAction
        // BEFORE the rows are composed — see the List's twin call site.
        handler.carryReorderTargetThroughAutoScroll()
        // Everything the handler's EVENTS will read out of the environment, in
        // one shared call — see `ItemListHandler.syncFrameInputs`, which exists
        // because this block used to be hand-copied here, in
        // `buildMultiLineContent` and in `_ListCore`, and a capture added to one
        // of the three was silently dead on the other two.
        //
        // `rowHeight: nil` — uniform single-line rows, so the scroll arithmetic
        // counts rows and the granularity is moot (it is still captured, and any
        // stale clip zeroed below, in case a table's rows switch between this
        // path and the multi-line one across frames).
        //
        // `keyboardMoveIsLive: false` — this path's composer DOES draw a reorder
        // slot, so the faint copy at it is the preview. Stated rather than left
        // alone because the handler persists at one identity: a table whose
        // columns stop reporting `lineLimit > 1` arrives here still carrying the
        // other path's `true`.
        handler.syncFrameInputs(
            environment: context.environment,
            reorderFeedback: context.environment.rowReorderFeedback,
            keyboardMoveIsLive: false,
            rowHeight: nil)
        handler.resolveOverscroll(
            environment: context.environment, contentHeight: contentHeight)
        // Resolve row ids lazily: the selection handler only ever asks for the
        // visible window + the focused row (O(1) each via `data[index].id`), so
        // materialising a full id array here was O(total) waste — and `_TableCore`
        // is render-to-measure, so it ran in *both* the measure and render passes
        // every frame (~30% of the 20k-row frame). All Table rows are content, so
        // an empty `selectableIndices` already means "all selectable". Mirrors the
        // windowed List path (_ListCore.resolvePopulatedHandler).
        handler.idAt = { data[$0].id }
        handler.itemIDs = []
        // As the multi-line path — see `settleScrollPosition`. Rows here are one
        // line each, so the snap's line-granularity exception can never apply.
        handler.settleScrollPosition(
            measuring: context.isMeasuring, overflowing: overflowing,
            drawsTextIndicators: handler.drawsScrollIndicators,
            firstRowHeight: 1)
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection
        return (handler, overflowing)
    }

    /// The table's content width: the selection gutter plus the columns and their
    /// spacing, clamped to the interior. Focused-row backgrounds and indicators are
    /// padded to *this*, not the full interior, so every line is the same width and
    /// the table neither jumps wider on focus nor centres its header over a lone
    /// full-width row. A `.flexible` column already fills the interior, so there the
    /// two widths coincide and nothing changes.
    private func tableContentWidth(
        _ columnWidths: [Int], within innerWidth: Int, gutter: Int
    ) -> Int {
        let spacing = columnSpacing * max(0, columnWidths.count - 1)
        return min(innerWidth, gutter + columnWidths.reduce(0, +) + spacing)
    }

    /// Reserves a line for each scroll indicator actually present at this
    /// offset so the rows plus indicators fill the content area exactly — no
    /// wasted blank line at the ends (which used to push the "N more below"
    /// indicator one row too high), no overflow in the middle. Mirrors
    /// _ListCore. Shared by the render pass and the analytic measure (both
    /// must agree on which indicators show).
    @discardableResult
    private func reserveIndicatorLines(
        handler: ItemListHandler<Value.ID>, contentHeight: Int, context: RenderContext
    ) -> (viewport: Int, origin: Int, above: Bool, below: Bool) {
        // Nothing is set aside when the "N more" lines are not what this table
        // draws — hidden indicators cost nothing, and the bar path never calls
        // this at all.
        // The shared rule, at uniform height — the same one the multi-line path
        // and `_ListCore` ask, which is what stops the three drifting. Every row
        // is one line here, so what it works out in lines this path reads as a
        // count. It absorbs the top clip too (at offset 1 a "▲ 1 more" line would
        // hide exactly the one row it stands for, so the window draws from row 0
        // instead — the resting settle normally snaps 1 → 0 before render, but
        // deliberately not while steering, which is when offset 1 survives here).
        let window = ScrollRowWindow.resolve(
            scrollOffset: handler.scrollOffset, count: data.count,
            contentHeight: contentHeight, topClip: 0,
            drawsTextIndicators: handler.drawsScrollIndicators,
            alwaysDrawsIndicators: context.environment.alwaysShowsVerticalTextIndicators,
            height: { _ in 1 })
        let origin = window.range.lowerBound
        let viewport = max(1, window.range.count)
        // A MEASURE pass must not publish either of these. It is offered a
        // different height than the frame is finally drawn into — the analytic
        // path measures at the full row area while the render subtracts the
        // landing slot's line — so a measure that wrote `viewportHeight` left
        // the NEXT render's `clampScrollOffset` (which asks `maxOffset`, which
        // asks the viewport) working from a viewport belonging to another
        // proposal. Symptom: auto-scroll advanced a row per tick and the very
        // next frame pulled it straight back, so a drag stopped one row short
        // of the end for ever. It is the measure-side-effect class, and it was
        // invisible until the borrowed slot line made the two viewports differ.
        if !context.isMeasuring {
            handler.viewportHeight = viewport
            // Published for the same reason the scrollbar path does — and the
            // indicators and the row window below count from it.
            handler.drawnOffset = origin
        }
        // Which lines the viewport gave up is RETURNED, not published: the
        // composer needs the answer for THIS pass, and the handler is the wrong
        // place to keep it. Latched there it had two failure modes, and both
        // shipped. A measure pass does not publish (see above), so the composer
        // read `(false, false)` and drew no indicator lines — a table measured
        // two lines shorter than it drew, and a container that believed the
        // measurement gave it a viewport two lines too short. And a frame that
        // skips the reservation entirely — the table stopped overflowing, and
        // `scrollOffset` did not change, so its didSet did not clear the latch —
        // read the PREVIOUS frame's answer and drew "▼ 0 more rows below" under
        // a table with nothing below it.
        return (viewport, origin, window.reservesAbove, window.reservesBelow)
    }

    /// The interaction state of a table with no rows: a real handler (its
    /// `itemCount` freshly zeroed, so the count from its last populated frame
    /// cannot leak into a later index), an empty visible range, no rows.
    ///
    /// It registers focus exactly as the populated path does — an empty table is
    /// still a Tab stop, and an enclosing `ScrollView` still has to be able to
    /// find it to reveal it.
    private func emptyRenderState(
        context: RenderContext,
        stateStorage: StateStorage,
        contentHeight: Int
    ) -> PopulatedRenderState {
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "table",
            propertyIndex: StateIndex.focusID
        )
        let (handler, _) = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            contentHeight: contentHeight,
            overflows: { _ in false }
        )
        // The empty path used to be the one that forgot `isFocusEngaged`, so an
        // emptied table kept whatever its last populated frame left. It cannot
        // now: the four statements are one call.
        handler.engageFocus(context: context, focusID: persistedFocusID)
        // Clears the bands the last populated frame left behind, so nothing
        // hit-tests against rows that are no longer drawn.
        handler.publishRowBands([])
        return PopulatedRenderState(
            handler: handler,
            focusID: persistedFocusID,
            visibleRange: 0..<0,
            scrollOffsetAbove: 0,
            drawnBands: []
        )
    }

    /// Stitches scroll indicators around the visible data rows.
    private func composeRowLines(
        handler: ItemListHandler<Value.ID>,
        tableHasFocus: Bool,
        /// Which indicator lines this pass's window set aside — see
        /// `reserveIndicatorLines`, which is the only thing that can answer it.
        indicators: (above: Bool, below: Bool),
        columnWidths: [Int],
        innerWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> (
        lines: [String], rowLines: [String], runs: [AnimatedCellRun],
        claims: [OpacityRegion],
        bands: [ItemListHandler<Value.ID>.DrawnBand]
    ) {
        let gutter = selectionGutter(context.environment)
        let contentWidth = tableContentWidth(columnWidths, within: innerWidth, gutter: gutter)
        // Resolve the emphasis ONLY when an indicator will actually be drawn:
        // resolving consults the cursor clock, and that read is what tells the
        // demand-driven loop the frame consumed it. Asking before knowing
        // whether anything will be painted re-renders the whole page ~20 times
        // a second to draw nothing. Same class as the Stepper's ungated
        // `pulsePhase` read (8ebc3385).
        // …and only when they are this table's indicator at all: hidden ones
        // draw nothing, and the bar has its own compose path.
        let drawnAbove = handler.drawnOffset
        let drawnBelow = max(0, handler.itemCount - handler.drawnVisibleRange.upperBound)

        let indicatorCycle =
            indicators.above || indicators.below
            ? scrollIndicatorCycle(isFocused: tableHasFocus, context: context) : nil
        let numberLocale = context.environment.locale
        let indicatorSurface = context.environment.enclosingSurface
        // The "N more" indicators are chrome — they describe where the content
        // sits — so the rows are collected separately and only they slide (§1.5).
        var lines: [String] = []
        var rowLines: [String] = []
        /// The indicators' own runs, at the assembled lines they were appended
        /// to — the rows slide past them, so those positions are final.
        var chromeRuns: [AnimatedCellRun] = []
        /// …and their claims, placed the same way (§53).
        var chromeClaims: [OpacityRegion] = []
        if indicators.above {
            let indicator = renderScrollIndicator(
                direction: .up,
                count: drawnAbove,
                unit: .rows,
                width: contentWidth,
                palette: palette,
                cycle: indicatorCycle,
                over: indicatorSurface,
                locale: numberLocale
            )
            appendIndicator(indicator, to: &lines, runs: &chromeRuns, claims: &chromeClaims)
        }
        let visibleRange = handler.drawnVisibleRange
        // A reorder drag takes the dragged row out and opens a slot where it
        // would land, so what is DRAWN is the order a drop would produce. The
        // sequence (and the arithmetic behind it) is the handler's, shared with
        // `List`; outside a drag it is just the visible range.
        let drawn = handler.reorderDrawnRows(visibleRange)
        // Heights, not entries, drive the bands: the slot stands for every row
        // in hand, so a multi-row drag opens a gap several lines tall and the
        // rows after it are no longer one line per entry.
        var drawnHeights: [(entry: ItemListHandler<Value.ID>.DrawnRow, height: Int)] = []
        /// The breathing rows' lines and every frame of each, at their position
        /// among `rowLines` — see `collect`.
        var pulseRuns: [PulseRun] = []
        var rowOpacity: [OpacityRegion] = []
        // One sampler for the frame — see the twin in the single-line path.
        let rowRamp = cellRamp(rowWidth: contentWidth, context: context)
        for entry in drawn {
            switch entry {
            case .row(let rowIndex):
                let row = renderRow(
                    item: data[rowIndex],
                    paint: RowPaint(row: rowIndex, ramp: rowRamp, width: contentWidth),
                    columnWidths: columnWidths,
                    isFocused: handler.isCursorRow(rowIndex) && tableHasFocus,
                    isSelected: handler.isSelected(at: rowIndex),
                    isReturningHome: handler.returningRows.contains(rowIndex),
                    context: context,
                    palette: palette
                )
                collect(
                    line: row.line, frames: row.pulseFrames, timing: row.pulseTiming, claims: row.claims,
                    into: &rowLines, runs: &pulseRuns, claims: &rowOpacity)
                drawnHeights.append((entry, 1))
            case .slot:
                let slot = reorderSlotLines(
                    handler: handler, columnWidths: columnWidths, rowWidth: contentWidth,
                    context: context, palette: palette)
                collect(slot, into: &rowLines, runs: &pulseRuns, claims: &rowOpacity)
                drawnHeights.append((entry, slot.lines.count))
            }
        }
        // A drag never changes how much is on screen, so an overrun is clipped —
        // but never the SLOT. It overruns when rows in hand have scrolled out of
        // the visible range, and when the slot is the last entry (the "move to
        // the end" destination) the tail IS the slot: clipping it took away the
        // only thing on screen saying where the rows would land, which reads as
        // the selection falling off the bottom of the table.
        // Negated excursion for the same reason as the scrollbar path above:
        // bands must travel WITH the slid rows, not mirror them.
        // Rows PLUS the line the slot borrowed (``dropSlotAddsRow``). Clipping
        // to the row count alone dropped a real row instead: the slot is
        // deliberately never the thing clipped, so the overrun came out of the
        // rows — a full table showed the slot and the indicator and no rows at
        // all, while the reserve arithmetic said one should be visible.
        let drawnBudget = visibleRange.count + (handler.dropSlotAddsRow ? 1 : 0)
        let slide =
            clipOverrun(&rowLines, to: drawnBudget, drawn: drawnHeights)
            - handler.overscrollState.excursion
        // …and a SHORTFALL is filled, for the same reason the overrun is
        // clipped: a drag never changes how much is on screen. `.cursor` drops
        // its gap the moment the pointer leaves the rows while the rows it is
        // carrying stay out of the drawing, so those frames are a line short —
        // and a table that is one line shorter is a table whose bottom border
        // has stepped up over the last row, which is then not where the user is
        // aiming at it. Dragging below the last row and back onto it therefore
        // released onto the BORDER, and `.cursor` reads a release off the rows
        // as a cancel: the row flew home and the reorder was silently lost.
        // Outside a drag the rows are one line each and this adds nothing.
        // (The scrollbar path fills to its own `contentHeight` already.)
        while rowLines.count < drawnBudget {
            rowLines.append(String(repeating: " ", count: max(0, contentWidth)))
        }
        let bands = publishRowBands(
            handler: handler, drawn: drawnHeights, slide: slide,
            // Whatever chrome is already in `lines` — which at this point is
            // the "N more above" indicator and nothing else, since the rows go
            // in on the next statement and the "below" indicator after them.
            // Counted rather than re-derived from a predicate so it cannot
            // disagree with what was drawn.
            indicatorLines: lines.count, lineCount: lines.count + rowLines.count)
        // The rows start below whatever "N more above" indicator is already in
        // `lines`; their runs take the same slide the bands just did.
        let rowsTop = lines.count
        lines.append(contentsOf: handler.overscrollState.slid(
            rowLines, blank: String(repeating: " ", count: max(0, contentWidth))))
        let runs = rowRuns(
            pulseRuns, slide: slide, topOffset: rowsTop, lineCount: rowsTop + rowLines.count)
        let claims = rowClaims(
            rowOpacity, slide: slide, topOffset: rowsTop, lineCount: rowsTop + rowLines.count)
        if indicators.below {
            let indicator = renderScrollIndicator(
                direction: .down,
                count: drawnBelow,
                unit: .rows,
                width: contentWidth,
                palette: palette,
                cycle: indicatorCycle,
                over: indicatorSurface,
                locale: numberLocale
            )
            appendIndicator(indicator, to: &lines, runs: &chromeRuns, claims: &chromeClaims)
        }
        // The row lines are handed back separately for a `.cursor` drag's
        // floating preview; the press frame is drawn in plain data order, so
        // indexing them by `visibleRange` offset is exact.
        return (
            lines, handler.onMove == nil ? [] : rowLines, runs + chromeRuns, claims + chromeClaims,
            bands)
    }

    // MARK: - Reorder drag

    /// The drop slot's line: a faint copy of the dragged row under
    /// ``RowReorderFeedback/dimmed``, and a gap the row's size under
    /// ``RowReorderFeedback/cursor`` (which has the row itself on the pointer, so
    /// drawing it here too would read as a duplicate).
    private func reorderSlotLines(
        handler: ItemListHandler<Value.ID>,
        columnWidths: [Int],
        rowWidth: Int,
        context: RenderContext,
        palette: any Palette
    ) -> RenderedRow {
        // A keyboard move has no pointer to say where the row is, so the slot
        // says it: the row you are steering reads as emphasis, not as a hole.
        // (`isFocused` rather than a bespoke colour — the pulse a focused row
        // already uses is exactly the "this one" cue, and it walks the palette
        // ramp so it survives a 256-colour terminal.)
        let held = handler.isKeyboardMove
        // EVERY row in hand: they land as one block, so the slot is one gap the
        // size of all of them. A blank line each under `.cursor` (which carries
        // them on the pointer, where drawing them here too would read as
        // duplicates); a faint copy each under `.dimmed`.
        let sources = handler.reorderRemovedRows.filter { data.indices.contains($0) }
        let blank = String(repeating: " ", count: max(0, rowWidth))
        guard handler.effectiveReorderFeedback == .dimmed, !sources.isEmpty else {
            // A keyboard move never takes the `.cursor` path: it resolves that
            // to `.dimmed`, precisely because there is no pointer to carry a row.
            return RenderedRow(lines: Array(repeating: blank, count: max(1, sources.count)))
        }
        // The row the cursor is on stays at full strength while the rest of the
        // block goes faint — the slot's pulse covers all of them, so without
        // this a multi-row hold marks no row in particular. `nil` for one row
        // and for every mouse drag: see `reorderPrimaryHeldRow`.
        let primary = handler.reorderPrimaryHeldRow
        let rowRamp = cellRamp(rowWidth: rowWidth, context: context)
        let rendered = sources.map { source -> (line: String, frames: [String]?, timing: IndicatorCycleTiming?, claims: [OpacityRegion]) in
            let row = renderRow(
                item: data[source],
                paint: RowPaint(row: source, ramp: rowRamp, width: rowWidth),
                columnWidths: columnWidths,
                isFocused: held, isSelected: held, context: context, palette: palette)
            let line = row.line
            let frames = row.pulseFrames
            guard source != primary else { return (line, frames, row.pulseTiming, row.claims) }
            // ADDITIVE, as it is in `_ListCore`: the emphasis says "you are
            // steering this", the dim says "it is not in the list right now",
            // and both are true at once. Substituting one for the other is why
            // a Table stopped dimming as soon as the move came from the
            // keyboard. Persistent: `renderRow` emits a reset per styled run —
            // starting with the selection-indicator gutter, so a bare wrapper
            // died at cell one. The dim goes onto every frame of the pulse for
            // the same reason it goes onto the drawn line: a run that replayed
            // the undimmed row would un-dim it on the first tick.
            return (
                ANSIRenderer.applyPersistentDim(line),
                frames.map { $0.map(ANSIRenderer.applyPersistentDim) },
                row.pulseTiming, row.claims)
        }
        return RenderedRow(
            lines: rendered.map(\.line),
            pulseFrames: rendered.contains { $0.frames != nil }
                ? rendered.map { $0.frames ?? [] } : nil,
            // Every copy is held and breathes on the one focus cycle, so any copy's
            // timing is all of theirs.
            pulseTiming: rendered.lazy.compactMap(\.timing).first,
            // Each copy's claims, on its own line of the slot. The dim moves no cell,
            // so they name the cells they did; dropped, a translucent row showed at
            // its opaque spelling for as long as it was held (§52). The claims and
            // not the runs are what the `List` twin's `dimmed(_:)` carries, too.
            claims: rendered.enumerated().flatMap { line, copy in
                copy.claims.map { $0.shifted(byX: 0, y: line) }
            })
    }

    /// Registers the table's rows as a drop destination that reports WHERE —
    /// the ``Table/dropDestination(for:action:)`` half, and the twin of
    /// `_ListCore.registerRowDropDestination`.
    ///
    /// The hovered index goes through the SHARED handler state
    /// (`externalDropSlot`), so the gap it opens is drawn by the same code the
    /// reorder slot uses and lands at the index the drop reports.
    private func registerRowDropDestination(
        zoneID: HitTestRegion.HandlerID,
        state: PopulatedRenderState,
        context: RenderContext,
        interiorTopY: Int
    ) {
        let handler = state.handler
        guard let insertion = dropInsertion,
            let session = context.environment.dragAndDropSession
        else {
            handler.externalDropSlot = nil
            return
        }
        session.registerTarget(
            DragAndDropSession.Target(
                handlerID: zoneID,
                accepts: insertion.accepts,
                perform: { payload, _ in
                    insertion.perform(handler.takeExternalDropSlot(), [payload])
                    return true
                },
                setTargeted: { targeted in
                    if !targeted { handler.externalDropSlot = nil }
                },
                hovering: { _, y in
                    // The band under the pointer names the row it would land
                    // BEFORE; past the last row it appends. Measured from the
                    // INTERIOR top, which is the space the bands are in — the
                    // same space `_ListCore` publishes and reads in. Through the
                    // handler so the line is remembered for an auto-scroll tick,
                    // which has no pointer event to go on.
                    handler.hoverExternalDrop(atContentY: y - interiorTopY)
                }),
            in: context)
    }

    /// Appends a rendered row's lines to `lines`, and its pulse frames to
    /// `runs` at the positions those lines landed in.
    ///
    /// One place, because every path that draws rows has to keep the two in
    /// step: a run is spliced over cells by position, so a line appended
    /// without its frames stops breathing, and frames recorded at the wrong
    /// index repaint the row above or below — every tick, until something else
    /// forces a full render.
    ///
    /// `transform` is whatever the path does to each line on the way in (the
    /// scrollbar path pads them to the content width); it is applied to the
    /// frames too, or the run would claim a different span than its line
    /// occupies.
    private func collect(
        line: String, frames: [String]?, timing: IndicatorCycleTiming?,
        claims rowClaims: [OpacityRegion] = [],
        into lines: inout [String], runs: inout [PulseRun],
        claims: inout [OpacityRegion], transform: (String) -> String = { $0 }
    ) {
        if let frames, let timing {
            runs.append((y: lines.count, frames: frames.map(transform), timing: timing))
        }
        // Shifted the way the run's `y` is recorded, and by the same number: a claim
        // at the wrong index fades the row above or below, every frame, exactly as a
        // misrecorded run repaints one. `transform` is not applied — the paths that
        // use it pad on the RIGHT, which adds bare cells a claim does not want.
        //
        // Guarded, because this runs once per drawn row per frame and nearly every
        // row is opaque — the same reason the derivations themselves ask the alphas
        // first.
        if !rowClaims.isEmpty {
            claims += rowClaims.map { $0.shifted(byX: 0, y: lines.count) }
        }
        lines.append(transform(line))
    }

    /// The multi-line form: see the single-line overload above.
    private func collect(
        _ rendered: RenderedRow, into lines: inout [String],
        runs: inout [PulseRun], claims: inout [OpacityRegion],
        transform: (String) -> String = { $0 }
    ) {
        let base = lines.count
        lines.append(contentsOf: rendered.lines.map(transform))
        if !rendered.claims.isEmpty {
            claims += rendered.claims.map { $0.shifted(byX: 0, y: base) }
        }
        guard let pulseFrames = rendered.pulseFrames, let timing = rendered.pulseTiming else { return }
        for (offset, frames) in pulseFrames.enumerated() where !frames.isEmpty {
            runs.append((y: base + offset, frames: frames.map(transform), timing: timing))
        }
    }

    /// Appends a "N more" line to `lines`, with its run and its claims moved to the
    /// row it lands on. Chrome, not a row: the rows slide past it, so the line it is
    /// appended as is where it stays. The one spelling of what all four indicator
    /// sites — two paths, two ends — do.
    private func appendIndicator(
        _ indicator: ScrollIndicatorLine, to lines: inout [String],
        runs: inout [AnimatedCellRun], claims: inout [OpacityRegion]
    ) {
        if let run = indicator.animation { runs.append(run.shifted(byX: 0, y: lines.count)) }
        claims += indicator.claims(atRow: lines.count)
        lines.append(indicator.text)
    }

    /// The collected pulse frames as runs, moved the way the row bands are
    /// moved: by the overscroll `slide`, then past any "N more above" indicator.
    ///
    /// A run whose line was slid off the top, or clipped off the bottom, is
    /// dropped rather than left claiming cells that are no longer its own.
    /// The collected claims, moved exactly as ``rowRuns(_:slide:topOffset:lineCount:)``
    /// moves the runs — the same slide, the same indicator offset, the same drop for a
    /// line that ended up off the top or past the bottom.
    ///
    /// One function beside that one rather than a second spelling of the arithmetic: a
    /// claim and the run on its own row disagreeing about where they are is the same
    /// class of bug as a run and its hit band disagreeing, and that is what `collect`
    /// exists to prevent one level down.
    private func rowClaims(
        _ collected: [OpacityRegion], slide: Int, topOffset: Int, lineCount: Int
    ) -> [OpacityRegion] {
        guard !collected.isEmpty else { return [] }
        return collected.compactMap { claim in
            let y = claim.offsetY + slide + topOffset
            guard y >= topOffset, y < lineCount else { return nil }
            return claim.shifted(byX: 0, y: y - claim.offsetY)
        }
    }

    @MainActor
    private func rowRuns(
        _ pulseRuns: [PulseRun], slide: Int, topOffset: Int, lineCount: Int
    ) -> [AnimatedCellRun] {
        pulseRuns.compactMap { run in
            let y = run.y + slide + topOffset
            guard y >= topOffset, y < lineCount, let first = run.frames.first else { return nil }
            return AnimatedCellRun(
                offsetX: 0, offsetY: y, width: first.strippedLength, frames: run.frames,
                frameTicks: run.timing.frameTicks, clock: run.timing.clock)
        }
    }

    /// Trims `lines` to `budget`, taking the overrun off whichever end is NOT
    /// the drop slot, and reports how far the survivors shifted (negative when
    /// the front was dropped) so the published bands move with them.
    ///
    /// A front clip is reported as a NEGATIVE shift, which `drawnBands` trims
    /// the bands against: a row the clip took entirely is dropped, and one it
    /// cut through keeps a band for the lines it still has. It used to drop both,
    /// which left a partly-clipped row answering no click.
    ///
    /// Reunited with its function; see `publishRowBands` on why that is worth a
    /// commit. WHICH end gives way, and by how much, is
    /// ``ItemListHandler/reorderOverrun(lineCount:budget:endsWithSlot:)`` —
    /// shared with `_ListCore.clipReorderOverrun`, which is the twin. This half
    /// is only the application: the lines are Table's to move, and the caller
    /// carries the shift into the bands.
    private func clipOverrun(
        _ lines: inout [String], to budget: Int,
        drawn: [(entry: ItemListHandler<Value.ID>.DrawnRow, height: Int)]
    ) -> Int {
        let clip = ItemListHandler<Value.ID>.reorderOverrun(
            lineCount: lines.count, budget: budget, endsWithSlot: drawn.last?.entry == .slot)
        if clip.back > 0 { lines.removeLast(clip.back) }
        if clip.front > 0 { lines.removeFirst(clip.front) }
        return -clip.front
    }

    /// Hands this frame's drawn row geometry to the shared publisher.
    ///
    /// `yStart` lands in ``ItemListHandler/DrawnBand/yStart``'s space: lines
    /// from the first CONTENT line of the interior, so `indicatorLines` — the
    /// chrome drawn above the rows — and the overscroll `slide` both go in. The
    /// rows are drawn shifted by the slide, so a drag hit-tests the wrong row
    /// without it.
    ///
    /// This comment spent a while attached to `registerRowDropDestination`
    /// instead, three hundred lines above, having been separated from its
    /// function by an edit that left two doc blocks touching. That is not a
    /// tidiness point: the rule it states — bands must include the slide — is
    /// the one `multiLineRowBands` was written without, and it was written that
    /// way while the rule was sitting on someone else's function where nobody
    /// writing a second publisher would read it. (Fixed in 5d9fbaf2, which put
    /// both views on one band builder; kept here as the reason the rule lives
    /// on the function it governs.)
    @discardableResult
    private func publishRowBands(
        handler: ItemListHandler<Value.ID>,
        drawn: [(entry: ItemListHandler<Value.ID>.DrawnRow, height: Int)],
        slide: Int,
        indicatorLines: Int,
        lineCount: Int
    ) -> [ItemListHandler<Value.ID>.DrawnBand] {
        typealias Handler = ItemListHandler<Value.ID>
        let bands = Handler.drawnBands(
            drawn.map { entry, height in
                switch entry {
                case .row(let rowIndex): return (.row(rowIndex), height)
                case .slot: return (.slot, height)
                }
            },
            slide: slide, rowsTop: indicatorLines, lineCount: lineCount)
        handler.publishRowBands(bands)
        // Handed back as well as published: the frame keeps them on its render
        // state so the click map and the cursor marker read the same geometry
        // the drag does, rather than each deriving its own.
        return bands
    }

    /// Starts the floating preview on the first movement of a `.cursor` drag,
    /// or advances it on every movement after that.
    ///
    /// `begin` samples the cursor once; only `dragMoved` tracks it — and a
    /// reorder drag reaches the view's own mouse closure rather than the
    /// `.draggable` modifier that normally calls it.
    @MainActor
    private func floatCarriedRows(
        session: DragAndDropSession?,
        handler: any RowReorderHosting,
        wasActive: Bool,
        grabX: Int,
        previewLine: @MainActor (Int) -> [String]?
    ) {
        guard let session, !handler.reorderFloatingRows.isEmpty else { return }
        let carried = handler.reorderFloatingRows.compactMap(previewLine)
        guard !wasActive, !carried.isEmpty else {
            session.dragMoved()
            return
        }
        // The rows' own lines, floated at the cursor. No hit regions to strip:
        // they are plain rendered lines. One line per row here, so the grab
        // point moves down the block by however many of its rows sit above the
        // one the pointer took hold of.
        //
        // Each row hands back its whole travel, grid layout first; the block's
        // frame N is every row's frame N, so a block of rows condenses as one
        // picture rather than as a column of independently-timed ones.
        let steady = FrameBuffer(lines: carried.map { $0.last ?? "" })
        let morph = (0..<Self.previewMorphSteps).map { step in
            FrameBuffer(lines: carried.map { $0[min(step, $0.count - 1)] })
        }
        session.begin(
            payload: RowReorderPayload(), preview: steady, morph: morph,
            grabX: grabX, grabY: handler.reorderHeldRowsAboveGrab.count)
    }

    /// The visible rows' heights with the TOP clip taken off — the first row's
    /// is net of the line-granularity top clip, because the mouse row-mapping
    /// walks these from the first visible line and a full-height first row
    /// would put every row below it off its hit band.
    ///
    /// NOT net of the bottom clip. The last row keeps its whole height where
    /// `composeMultiLineRows` cut its tail at the line budget; that cut moves no
    /// row below it, so the bands are capped instead, by the row block's drawn
    /// end passed to `multiLineRowBands` as `lineCount`. Read as "as rendered"
    /// all the way down, which it is not there, the last band ran on over the
    /// "▼ N more rows below" line.
    private func onScreenRowHeights(
        _ range: Range<Int>, height: (Int) -> Int, topClip: Int
    ) -> [Int] {
        var heights = range.map(height)
        if topClip > 0, !heights.isEmpty {
            heights[0] = max(1, heights[0] - topClip)
        }
        return heights
    }

    /// The window the multi-line path just DREW, handed to the persistent
    /// handler — the multi-line twin of `reserveIndicatorLines`' last two
    /// statements, gated the same way and for the same reason.
    ///
    /// A MEASURE pass must not publish either of these, and this is the ONE
    /// path that could, because it is the one that renders itself to measure:
    /// `analyticMultiLineSize` declines for an overflowing table with no bar,
    /// so `sizeThatFits` falls back to `renderToBuffer`. (The single-line paths
    /// are never reached under `isMeasuring` at all, which is why their own
    /// writes read as unguarded neighbours of a guard.)
    ///
    /// A measure pass is offered whatever height the PARENT proposed, not the
    /// height the frame is drawn into: an eager `VStack` measures every child
    /// at the stack's whole height and then renders each into its distributed
    /// share, so a table sharing a stack with any sibling is measured a line
    /// taller than it is drawn, every frame. Ungated, that measure published a
    /// window belonging to a proposal — a `viewportHeight` counting rows
    /// nothing drew, and a `drawnOffset` the indicators then counted from.
    private func publishMultiLineWindow(
        handler: ItemListHandler<Value.ID>, range: Range<Int>, context: RenderContext
    ) {
        guard !context.isMeasuring else { return }
        // The window may have absorbed a top clip (or a whole first row) that an
        // indicator would otherwise have announced, so the indicators must count
        // from ITS position. See ``ItemListHandler/drawnOffset``.
        handler.drawnOffset = range.lowerBound
        // The rows actually on screen — what a page moves by, and what the
        // `List` and the single-line path publish. See the note above
        // `syncIndicatorChrome`'s call site for what used to stand here.
        handler.viewportHeight = max(1, range.count)
    }

    /// The multi-line path's bands: rows of different heights, no slot (that
    /// path forces ``RowReorderFeedback/live``, which moves the data instead of
    /// opening a gap).
    ///
    /// Nothing produced these at all until this function existed, which did not
    /// merely disable drag-reorder there — it made the gesture swallow the click
    /// while doing nothing, since `dropTarget` had no bands to hit-test against.
    ///
    /// Builds them; it does NOT publish them, unlike its single-line twin
    /// `publishRowBands`. This is the path that renders itself to measure, and
    /// handing a measure pass's bands to the handler both replaces the drawn
    /// geometry and fires the auto-scroll retarget — so the caller publishes,
    /// under `!context.isMeasuring`.
    ///
    /// `indicatorLines` must be the DRAWING condition `composeMultiLineRows`
    /// uses (`window.showsAbove && drawsText`), not the handler's
    /// `hasContentAbove`: `showAbove` is also true for a line-granularity top
    /// clip inside row 0, where `hasContentAbove` is false.
    private func multiLineRowBands(
        handler: ItemListHandler<Value.ID>,
        range: Range<Int>,
        heights: [Int],
        indicatorLines: Int,
        lineCount: Int
    ) -> [ItemListHandler<Value.ID>.DrawnBand] {
        typealias Handler = ItemListHandler<Value.ID>
        return Handler.drawnBands(
            range.enumerated().map { offset, rowIndex in
                (.row(rowIndex), offset < heights.count ? max(1, heights[offset]) : 1)
            },
            // The terms this builder never had. It emitted from `yStart = 0`
            // with neither the indicator line the frame had just drawn nor the
            // overscroll excursion, so a scrolled or overscrolling multi-line
            // table hit-tested a drag against geometry its rows were not drawn
            // at.
            slide: -handler.overscrollState.excursion,
            rowsTop: indicatorLines,
            lineCount: lineCount)
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
    /// The scrollbar's own mouse handler, registered BEFORE the container's so
    /// the container's later `insert(at: 0)` pushes this one to a higher index —
    /// hit-tested ahead of the container (reverse iteration) for its single
    /// column, while the container still wins everywhere else. The bar is the
    /// rightmost interior column (availableWidth − 3: border + padding each
    /// side, minus the bar) over the content rows; it is row-exact (one cell per
    /// row) for the single-line path.
    private func attachScrollbarMouseHandler(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        mouseDispatcher: MouseEventDispatcher,
        firstRowY: Int
    ) {
        guard state.hasScrollbar else { return }
        let barHeight = max(1, context.availableHeight - 3)
        let barHandler = ScrollbarRenderer.verticalMouseHandler(
            for: state.handler, length: barHeight,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            behavior: context.environment.scrollbarClickBehavior)
        let barHandlerID = mouseDispatcher.register(
            in: context,
            ScrollbarRenderer.focusing(
                barHandler, focusID: state.focusID,
                focusManager: context.environment.focusManager))
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

    /// Makes each sortable column's header title a click target that re-sorts.
    ///
    /// One region per column rather than one for the whole header line: which
    /// column was clicked is the entire content of the gesture, and a single
    /// region would have to re-derive it from an x the dispatcher already knows
    /// how to route. A column with no comparator registers nothing, so clicks
    /// there fall through to the table's own handler and simply focus it — the
    /// header of an unsortable column stays as inert as it looks.
    ///
    /// The header line is `y = 1`: the container's top border is `y = 0` and
    /// the rows start below it (see the layout sketch above).
    @MainActor
    private func attachHeaderSortHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        mouseDispatcher: MouseEventDispatcher
    ) {
        guard sortOrder != nil, !state.columnWidths.isEmpty else { return }
        let focusManager = context.environment.focusManager
        let focusID = state.focusID
        let originX = 1 + Self.containerPadding.leading
        for (index, xRange) in headerColumnRanges(
            columnWidths: state.columnWidths, originX: originX,
            gutter: selectionGutter(context.environment))
        where columns.indices.contains(index) && columns[index].sortComparator != nil {
            let column = columns[index]
            let handlerID = mouseDispatcher.register(in: context) { event in
                guard event.button == .left else { return false }
                // Claim the press so the release routes back here, and act on
                // the release — the same press/release split every other
                // click target in the framework uses, so sliding off the
                // header before letting go cancels.
                guard event.phase == .released else { return event.phase == .pressed }
                toggleSort(column: column)
                focusManager?.focus(id: focusID)
                return true
            }
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: xRange.lowerBound, offsetY: 1,
                    width: xRange.count, height: 1, handlerID: handlerID),
                at: 0
            )
        }
    }

    private func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState
    ) {
        guard !isDisabled(in: context), !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        // The table's interior: past the top border (0) and the column header
        // (1). A constant — the header is always drawn, and nothing else sits
        // between it and the content.
        //
        // THIS is the origin the drag geometry works in, matching `_ListCore`'s
        // `topInset`: `DrawnBand.yStart` counts from the first CONTENT line, so
        // the "N more above" indicator's line is inside the band space rather
        // than subtracted out before it. Anything that hit-tests a BAND —
        // `ReorderHost.topInset`, the drop destination, the session-less
        // `dragContentY` — measures from here.
        let interiorTopY = 2
        // …and the first ROW line, which is one lower when an indicator is
        // drawn. Only the scrollbar wants this now: its cells are one per ROW,
        // so the bar's region has to start where the rows do. Everything that
        // hit-tests a LINE — the click map, the cursor marker, the drag —
        // works in the band space above instead.
        let firstRowY = interiorTopY + state.scrollOffsetAbove

        // The scrollbar's own handler goes in first so the container's later
        // insert(at: 0) pushes it to a higher index — hit-tested ahead of the
        // container (reverse iteration) for its single column, while the container
        // still wins everywhere else. The bar is the rightmost interior column
        // (availableWidth − 3: border + padding each side, minus the bar) over the
        // content rows; it is row-exact (one cell per row) for the single-line path.
        attachScrollbarMouseHandler(
            to: &buffer, context: context, state: state,
            mouseDispatcher: mouseDispatcher, firstRowY: firstRowY)

        // Sortable column headers, for the same reason and by the same trick as
        // the scrollbar above: registered first so the container's later
        // `insert(at: 0)` leaves these at a higher index, where the reverse
        // hit-test finds them before the table's own catch-all.
        attachHeaderSortHandlers(
            to: &buffer, context: context, state: state, mouseDispatcher: mouseDispatcher)

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
        let previewLine: @MainActor (Int) -> [String]? = { index in
            guard data.indices.contains(index), !columnWidths.isEmpty else { return nil }
            return previewMorphLines(
                item: data[index], row: index, columnWidths: columnWidths,
                steps: Self.previewMorphSteps, context: context, palette: palette)
        }
        // Where a ROW LINE's first cell sits in the buffer: past the border and
        // past the container's own padding. Not the same as the first clickable
        // column — the padding column is clickable but belongs to no row — and
        // measuring the reorder grab point from the wrong one of the two put
        // the floating row a cell off the pointer. `_ListCore` passes the
        // equivalent `rowContentLeft`.
        let rowContentLeft = contentColumns.lowerBound + Self.containerPadding.leading
        let mouseHandlerID = mouseDispatcher.register(
            in: context,
            containerMouseHandler(
                state: state,
                context: context,
                focusManager: focusManager,
                dispatcher: mouseDispatcher,
                interiorTopY: interiorTopY,
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

        // A landing place for a reorder of its own rows, on the container's
        // rectangle. Registered unconditionally (not under `isScrollEnabled`,
        // as the auto-scroll zone below is): a drop is not a scroll, and a
        // table that did not register is one a gesture cannot land in.
        if state.handler.onMove != nil {
            context.environment.dragAndDropSession?.registerReorderHost(
                DragAndDropSession.ReorderHost(
                    focusID: state.focusID,
                    handlerID: mouseHandlerID,
                    // The INTERIOR top, not the first row line: the session
                    // resolves a drag through `DragAndDropSession.contentY`
                    // (`event.y - localOriginY - topInset`) and hit-tests the
                    // published bands with it, so this has to name the same
                    // origin the bands do. `_ListCore` passes its content
                    // `topInset` here for exactly that reason.
                    topInset: interiorTopY,
                    contentColumns: contentColumns,
                    handler: state.handler),
                in: context)
        }

        // The external drop destination is registered unconditionally too, for
        // the same reason as the reorder host above: a drop is not a scroll,
        // and a pinned `.scrollDisabled` staging table must still take drops —
        // as the List twin already does (`_ListCore.registerRowTargets`, which
        // gates only its auto-scroll zone). This sat inside the
        // `isScrollEnabled` gate below, so a non-scrolling table silently
        // refused every external drag: no slot opened, and release flew home.
        registerRowDropDestination(
            zoneID: mouseHandlerID, state: state, context: context,
            interiorTopY: interiorTopY)

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
                    delayNanos: context.environment.dragAutoScrollDelay.clampedNanoseconds,
                    // The column header is not part of the scrollable band. Left
                    // in, it ate the whole upward hot margin: the border and the
                    // header were the two hot rows, so the "▲ N more above" line
                    // — the one place a user aims to scroll up — was inert.
                    topInset: 1,
                    shiftStep: context.environment.shiftStepMultiplier),
                in: context)
        }

        // A one-row region at the keyboard cursor's on-screen line, ahead of
        // the whole-table region so an enclosing ScrollView follows the
        // cursor row — not just the table's top — through a table taller than
        // the outer viewport. Mirrors the marker in _ListCore, and now takes
        // its rectangle the same way: straight off the band the row was drawn
        // as. The band already carries the indicator's offset and the
        // overscroll slide, so there is nothing left to re-derive — the sum of
        // per-row heights, and the excursion correction that used to follow it,
        // were both this arithmetic done a second time.
        let cursor = state.handler.focusedIndex
        if let band = state.drawnBands.first(where: {
            if case .row(let index) = $0.entry { return index == cursor }
            return false
        }) {
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: 0, offsetY: interiorTopY + band.yStart,
                    width: buffer.width, height: max(1, band.height),
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
        dispatcher: MouseEventDispatcher,
        interiorTopY: Int,
        contentColumns: Range<Int>,
        rowContentLeft: Int,
        previewLine: @escaping @MainActor (Int) -> [String]?
    ) -> @MainActor (MouseEvent) -> Bool {
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        // The press frame's geometry, captured: a press and its release
        // describe one unchanging layout, and it is the CLICK path that needs
        // it. The reorder path deliberately reads the handler's freshly
        // published bands instead — `.live` feedback moves the rows out from
        // under this copy as the drag goes. Same split as `_ListCore`.
        let drawnBands = state.drawnBands
        // `data` itself, not `data.map(\.id)`: this closure is rebuilt every
        // render pass, and materialising every row's id each time cost O(rows)
        // per frame for a lookup that is made once per click.
        let rows = data
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
                /// The clicked line's data row, from the press frame's bands.
                ///
                /// One lookup for both layouts. It used to walk `visibleRange`
                /// (single-line) or a per-row height array (multi-line) from a
                /// `firstRowY` recomputed on every event, undoing the overscroll
                /// slide by hand on the way. Every one of those terms is already
                /// in the band, and re-deriving them is how the click map came
                /// to disagree with the drawing: its "is an indicator drawn?"
                /// test was `hasContentAbove`, while the multi-line path draws
                /// by `showAbove`, which is also true for a line-granularity
                /// clip inside row 0. Scrolled one line into the first row, the
                /// indicator was on screen and every click landed a row low.
                func rowAt(y: Int) -> Int? {
                    let contentY = y - interiorTopY
                    for band in drawnBands
                    where contentY >= band.yStart && contentY < band.yStart + band.height {
                        if case .row(let rowIndex) = band.entry { return rowIndex }
                        return nil
                    }
                    return nil
                }

                /// The drag's position in the handler's band space — lines from
                /// the interior's first CONTENT line, the same origin
                /// ``ItemListHandler/DrawnBand/yStart`` counts from — or `nil`
                /// once the cursor leaves the rows, in either axis. The session
                /// path asks the same two questions of the same shared rule,
                /// having localised the cursor itself.
                var dragContentY: Int? {
                    captureHandler.rowSpaceContentY(
                        x: event.x, y: event.y, contentColumns: contentColumns,
                        topInset: interiorTopY)
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
                        // Which control the gesture belongs to is the session's
                        // to know from here on — see the twin in `_ListCore`.
                        captureHandler.armReorderSession(
                            dragSession, focusID: captureFocusID)
                        // Focus follows the gesture, so the keyboard reaches
                        // this list for the length of it — that is what lets the
                        // navigators scroll a list that was not focused before
                        // the drag began.
                        focusManager?.focus(id: captureFocusID)
                        // Relative to the ROW LINE, which is what the preview
                        // is — not to the first clickable column.
                        grab.x = max(0, event.x - rowContentLeft)
                        grab.y = 0  // one line per row on every reorderable path
                    }
                    return true

                case .dragged:
                    // Edge auto-scroll, armed on the first MOTION rather than
                    // at the press — see the twin in `_ListCore` for why (a
                    // motionless long-press near an edge must not scroll).
                    dragSession?.armReorderAutoScrollOnMotion(owner: captureHandler)
                    // Any motion during a grab is a reorder, not a click. What it
                    // looks like is the feedback mode's business — and `.cursor`'s
                    // reaches outside the table: its row rides the pointer above
                    // every other view, which only the drag session can draw.
                    // Tracked through the session — see the twin in `_ListCore`
                    // for why, and for what the session-less fallback is.
                    let wasActive = (dragSession?.reorderHandler ?? captureHandler).isReordering
                    if let dragSession {
                        dragSession.trackReorder()
                    } else {
                        captureHandler.dragReorder(toContentY: dragContentY)
                    }
                    floatCarriedRows(
                        session: dragSession,
                        handler: dragSession?.reorderHandler ?? captureHandler,
                        wasActive: wasActive, grabX: grab.x, previewLine: previewLine)
                    return true

                case .released:
                    // Whatever this turns out to be — a drop, or a click that
                    // never moved — the gesture is over, so let go of the edge
                    // auto-scroll. (`end()` below only runs for a real drop.)
                    dragSession?.disarmAutoScroll()
                    // A cancel already put the rows back and ended the drag; the
                    // release that follows is the tail of a cancelled gesture,
                    // not a click on whatever is under the pointer. Session
                    // first, for the adopted-handler reason the List twin
                    // documents (`DragAndDropSession.cancelReorder`).
                    if dragSession?.consumeReorderCancellation() == true { return true }
                    let releasing = dragSession?.reorderHandler ?? captureHandler
                    if releasing.reorderCancelled {
                        releasing.reorderCancelled = false
                        return true
                    }

                default:
                    return false
                }

                // A reorder drop, if this gesture was one. Committed through
                // the session — see the twin in `_ListCore`.
                if dragSession?.performReorderDrop()
                    ?? captureHandler.dropReorder(atContentY: dragContentY)
                {
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
                    if captureHandler.completesMultiClick(on: index, clickCount: event.clickCount),
                        let action = capturedPrimaryAction,
                        index >= 0, index < rows.count
                    {
                        captureHandler.focusedIndex = index
                        // Spent — see the twin in `_ListCore`.
                        dispatcher.endMultiClickSequence()
                        action(rows[index].id)
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

    private func calculateColumnWidths(availableWidth: Int, spacing: Int, gutter: Int) -> [Int] {
        guard !columns.isEmpty else { return [] }

        let totalSpacing = spacing * (columns.count - 1)
        let contentWidth = max(0, availableWidth - totalSpacing - gutter)

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
                // The header measured here is the one that will be DRAWN, sort
                // indicator and all: measuring the bare title instead fitted the
                // column two cells short and truncated its own header ("Track…").
                var fitted = headerTitle(for: column).strippedLength
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

    private func renderHeader(
        columnWidths: [Int], gutter: Int, palette: any Palette
    ) -> ClaimingRow {
        // Through `ClaimingRow` so the header's own colour states its opaque spelling
        // and sends its alpha up as a region. `foregroundSecondary` is a re-spelling of
        // the palette's foreground and carries its alpha, so a faded theme reaches here
        // — and the row is what knows which columns each cell occupies, gutter and
        // spacing included. Adjacent cells owe one alpha, so it coalesces to a single
        // rectangle across the titles.
        var row = ClaimingRow()
        row.skip(cells: gutter)
        for (offset, index) in columns.indices.enumerated() where offset < columnWidths.count {
            if offset > 0 { row.skip(cells: columnSpacing) }
            let column = columns[index]
            let width = columnWidths[offset]
            let aligned = alignText(
                headerTitle(for: column, fittingWidth: width),
                width: width,
                alignment: column.alignment,
                truncationMode: column.truncationMode
            )
            row.append(
                aligned, cells: width, ink: palette.foregroundSecondary, bold: true)
        }
        return row
    }

    /// A column's header text, with the sort indicator when the table sorts.
    ///
    /// Every SORTABLE column reserves the indicator's width, not just the one
    /// being sorted by: a slot that appeared and disappeared would re-measure
    /// `.fit` columns on every click, so the table would change width as you
    /// sorted it. Columns that cannot sort — and every column of a table with
    /// no `sortOrder` binding — reserve nothing, so an existing table renders
    /// exactly as it did.
    ///
    /// - Parameter width: The cells the header cell will actually get, when the
    ///   caller is about to draw it. Omit it (the measuring path) for the
    ///   natural width, which ALWAYS reserves the slot — that reservation is
    ///   what keeps a column from resizing when you sort it.
    ///
    /// Passing the width changes two things, both about what is DRAWN rather
    /// than how wide the column is:
    ///
    /// - An unsorted column draws its bare title, with no trailing blank. The
    ///   slot is still reserved in the width, but padding the text into it
    ///   pushed a `.trailing` header two cells off its column's right edge —
    ///   misaligning the common case (no sort on this column) to reserve room
    ///   for the rare one. The text shifts left when an arrow actually appears.
    /// - When there is an arrow and the column is too narrow for both, the TITLE
    ///   gives way first: `Tra… ▼`, not `Track…`. The arrow is the part you
    ///   cannot reconstruct by guessing, and one that vanishes exactly when the
    ///   table is cramped hides which column you just sorted by.
    private func headerTitle(for column: TableColumn<Value>, fittingWidth width: Int? = nil)
        -> String
    {
        guard sortOrder != nil, column.sortComparator != nil else { return column.title }
        let indicator = sortIndicator(for: column)
        let suffix = " " + indicator
        guard let width else { return column.title + suffix }
        guard indicator != Self.noSortIndicator else {
            return column.title.truncatedToWidth(width, mode: column.truncationMode)
        }
        let room = width - suffix.strippedLength
        // Narrower than the indicator's own slot: drop the separating space and
        // the title, and keep the arrow alone. Truncating `suffix` here would
        // keep the SPACE and lose the arrow, which is the wrong end.
        guard room > 0 else { return indicator.truncatedToWidth(width, mode: .tail) }
        return column.title.truncatedToWidth(room, mode: column.truncationMode) + suffix
    }

    /// What ``sortIndicator(for:)`` returns for a sortable column that is not
    /// the one being sorted by — a blank the width calculation still reserves.
    private static var noSortIndicator: String { " " }

    /// `▲` / `▼` for the column the rows are currently ordered by, a space for
    /// any other sortable column.
    ///
    /// Only the PRIMARY comparator is marked. Later ones in the sort order are
    /// real — they break the primary's ties — but marking them would say the
    /// rows are ordered by them, which they are not, and macOS marks one too.
    private func sortIndicator(for column: TableColumn<Value>) -> String {
        guard let comparator = column.sortComparator,
            let primary = sortOrder?.wrappedValue.first,
            primary.keyPath == comparator.keyPath
        else { return Self.noSortIndicator }
        return primary.order == .forward ? "▲" : "▼"
    }

    /// The x range each column's header occupies within the table's buffer,
    /// paired with the column's index.
    ///
    /// Derived from the same widths and spacing `renderHeader` lays the titles
    /// out with, so a click lands on the title it is under. `originX` is where
    /// the header line starts inside the buffer: past the border and the
    /// container's padding, then past the indicator indent.
    private func headerColumnRanges(
        columnWidths: [Int], originX: Int, gutter: Int
    ) -> [(Int, Range<Int>)] {
        var ranges: [(Int, Range<Int>)] = []
        var x = originX + gutter
        for (index, width) in zip(columnWidths.indices, columnWidths) {
            ranges.append((index, x..<(x + width)))
            x += width + columnSpacing
        }
        return ranges
    }

    /// Which column the rows are currently ordered by, or `nil` when the sort
    /// order is empty or names a key path no column carries.
    ///
    /// The same predicate `sortIndicator(for:)` draws the arrow from, so the
    /// arrow and the chords cannot disagree about which column is primary.
    private var primarySortColumnIndex: Int? {
        guard let primary = sortOrder?.wrappedValue.first else { return nil }
        return columns.firstIndex { $0.sortComparator?.keyPath == primary.keyPath }
    }

    /// The keyboard half of the header click, handed to the handler each frame
    /// (see `ItemListHandler.onSort`).
    ///
    /// `.sortNextColumn` runs `toggleSort(column:)` on the next sortable column,
    /// wrapping — with exactly ONE sortable column that is the primary itself,
    /// so the chord flips its direction, precisely as clicking the one clickable
    /// header twice does. `.reverseSortOrder` runs it on the primary, which
    /// reverses it, and does nothing while the sort order is empty: there is no
    /// direction to reverse yet, and Ctrl-S establishes one.
    ///
    /// `nil` — leaving both chords to the app — for a table with no `sortOrder`
    /// binding or no sortable column, which is exactly when no header takes a
    /// click either.
    private var sortKeyAction: ((RowAction) -> Void)? {
        // NOT a convenience ordering: the binding is tested first, and with
        // `contains(where:)` rather than a `filter`, because this property runs
        // on every pass of every table — measure passes included, which is why
        // `viewportHeight` above is gated on `isMeasuring`. Building the index
        // list here charged an array allocation per pass to tables that have no
        // `sortOrder` binding at all, which is most of them.
        guard sortOrder != nil, columns.contains(where: { $0.sortComparator != nil })
        else { return nil }
        return { action in
            // Walked when a key actually arrives rather than once per pass: a
            // keystroke is rare and this allocates. Non-empty, per the guard.
            let sortable = columns.indices.filter { columns[$0].sortComparator != nil }
            let index: Int?
            switch action {
            case .sortNextColumn:
                let current = primarySortColumnIndex
                index = current.flatMap { c in sortable.first { $0 > c } } ?? sortable.first
            case .reverseSortOrder:
                index = primarySortColumnIndex
            // The handler passes only the two sort actions; every other row verb
            // is the handler's own business. Written out rather than defaulted so
            // the next `RowAction` has to be answered here too.
            case .selectAll, .extendSelection, .pickUpRow, .placeRow, .cancelMove,
                .moveRowUp, .moveRowDown, .moveRowToTop, .moveRowToBottom,
                .moveRowPageUp, .moveRowPageDown:
                index = nil
            }
            guard let index else { return }
            toggleSort(column: columns[index])
        }
    }

    /// Applies a click on `column`'s header to the bound sort order.
    ///
    /// Clicking the column already sorted by flips its direction; clicking any
    /// other sortable column makes it the primary sort, ascending, and pushes
    /// what was there down behind it — so the previous sort survives as the
    /// tie-break, which is what a macOS table does and what makes a two-key
    /// sort reachable by clicking two headers in turn.
    private func toggleSort(column: TableColumn<Value>) {
        guard let sortOrder, let comparator = column.sortComparator else { return }
        var order = sortOrder.wrappedValue
        if let first = order.first, first.keyPath == comparator.keyPath {
            order[0].order = first.order == .forward ? .reverse : .forward
        } else {
            var promoted = comparator
            promoted.order = .forward
            order.removeAll { $0.keyPath == comparator.keyPath }
            order.insert(promoted, at: 0)
        }
        sortOrder.wrappedValue = order
    }

    // MARK: - Row Rendering

    private func renderRow(
        item: Value,
        paint: RowPaint,
        columnWidths: [Int],
        isFocused: Bool,
        isSelected: Bool,
        isReturningHome: Bool = false,
        context: RenderContext,
        palette: any Palette,
    ) -> (
        line: String, pulseFrames: [String]?, pulseTiming: IndicatorCycleTiming?,
        claims: [OpacityRegion]
    ) {
        let (row, ramp, rowWidth) = (paint.row, paint.ramp, paint.width)
        // A row whose picture is still walking back to it keeps its space and
        // draws nothing in it — see ``ItemListHandler/returningRows``, and
        // `_ListCore.renderRow`, which does the same for the same reason.
        // Nothing animates: a run would paint over the blank on its next tick.
        guard !isReturningHome else {
            return (String(repeating: " ", count: max(0, rowWidth)), nil, nil, [])
        }
        let visualState = rowVisualState(
            isFocused: isFocused,
            isSelected: isSelected,
            context: context,
            palette: palette
        )

        let styledIndicator = ANSIRenderer.colorize(
            visualState.indicator,
            foreground: visualState.indicatorColor.opaqueSpelling
        )
        let gutter = selectionGutter(context.environment)

        // Every cell of every row is coloured the same, so derive its SGR
        // introducer ONCE rather than rebuilding an identical `TextStyle` and
        // re-joining its codes per cell (`ANSIRenderer.render` was 18.1%
        // inclusive of a `tables-scroll` frame, `buildStyleCodes` 6.8%).
        // `sequence + text + reset` is byte-for-byte what `colorize` produces.
        // A ramp that varies ALONG the row cannot have one introducer for the
        // whole row, so that case paints cell by cell instead — through the
        // same walk `Text` uses, so the two cannot disagree about where a
        // colour changes. Every other case, ramp or not, keeps the single
        // introducer this comment is about.
        let bandsAcrossRow = ramp?.variesAcrossRow ?? false
        let cellInk = cellColour(row: row, ramp: ramp, context: context, palette: palette)
        var cellStyle = TextStyle()
        // Opaque on both arms. A banded row's cells take their colour from the ramp
        // rather than from this style, so what is spelled here only reaches the
        // single-introducer arm — but a `TextStyle` carrying a translucent colour into
        // `band` at all is the shape §18.3 warns about, and the answer is the same
        // either way now that both arms claim (§36).
        cellStyle.foregroundColor = cellInk.opaqueSpelling
        let cellSequence = bandsAcrossRow ? nil : ANSIRenderer.styleSequence(for: cellStyle)
        var rampSequences: [String?] = []

        // One buffer for the whole row. The previous form built a `[String]` of
        // styled cells, `joined` them, and concatenated the indicator and the
        // padding — an array plus a fresh String per cell and per join, thrown
        // away immediately. Table rendering was spending **26% of the frame
        // inside the allocator** (`tiny_free_*` / `tiny_malloc_*`), and rows
        // are the bulk of it. Spacing and padding come from the shared
        // `asciiSpaces` run, so neither allocates either.
        let spacing = asciiSpaces(columnSpacing)
        var content = gutter == 0 ? "" : styledIndicator
        content.reserveCapacity(rowWidth * 2)
        if gutter > 0 { content += " " }

        let cellCount = min(columns.count, columnWidths.count)
        // Where the cells start, for a ramp that varies along the row: the
        // indicator and the gap after it, or column zero when there is neither.
        var cellColumn = gutter
        for index in 0..<cellCount {
            if index > 0 {
                content.append(contentsOf: spacing)
                cellColumn += columnSpacing
            }
            let column = columns[index]
            let cellWidth = columnWidths[index]
            // Hoisted, so the column's value closure still runs exactly once and
            // in the same order whichever branch below draws it.
            let cellText = column.value(for: item)
            if let ramp, bandsAcrossRow {
                var walked = cellColumn
                PaintRenderer.band(
                    alignText(
                        cellText, width: cellWidth, alignment: column.alignment,
                        truncationMode: column.truncationMode),
                    column: &walked, row: row, style: cellStyle,
                    sampler: ramp, sequences: &rampSequences, into: &content)
            } else if let cellSequence {
                content += cellSequence
                appendAligned(
                    cellText, width: cellWidth, alignment: column.alignment,
                    truncationMode: column.truncationMode, into: &content)
                content += ANSIRenderer.reset
            } else {
                appendAligned(
                    cellText, width: cellWidth, alignment: column.alignment,
                    truncationMode: column.truncationMode, into: &content)
            }
            cellColumn += cellWidth
        }

        // The background is applied to the FINISHED line, so a pulse is one
        // recolouring of it per step rather than one render of the row per step
        // — the same trick the menu row's bar uses. It works only because the
        // row itself paints no background of its own: an inner one would beat
        // the outer paint for the cells it covers.
        /// What this row's line owes, from the one derivation `_ListCore` also calls.
        ///
        /// The cells' rectangle stops at `cellColumn`, which the loop above has walked
        /// to the end of the last column — not at `rowWidth`, because the padding past
        /// it is bare and an ink claim on a cell with no ink of its own lets what is
        /// behind it through.
        func claims(fill: Color?) -> [OpacityRegion] {
            var stated = SelectableRowClaims.claims(
                line: 0, width: rowWidth, cells: gutter..<cellColumn,
                ink: bandsAcrossRow ? nil : cellInk,
                mark: gutter > 0 ? visualState.indicatorColor : nil, fill: fill)
            if let ramp, bandsAcrossRow {
                stated += ramp.alphaClaims(
                    row: row, line: 0, columns: gutter..<cellColumn)
            }
            return stated
        }
        guard case .none = visualState.background else {
            // `cellColumn` IS this line's visible width, so nothing rescans it:
            // the loop above walked it from `gutter` through every spacing and
            // every column, `appendAligned` puts exactly `cellWidth` cells in
            // each, and the mark is one cell by ``RowSelectionIndicator``'s
            // documented invariant (a mark of another width would move the
            // row's content, which is why it has one). A `strippedLength` here
            // was a second walk of the whole assembled row — escapes and all,
            // so the general path rather than the byte one — for every
            // selected or focused row of every frame.
            content.append(contentsOf: asciiSpaces(rowWidth - cellColumn))
            let fill = visualState.background.claimableFill
            guard let colors = visualState.background.pulseColors else {
                return (visualState.background.painting(content), nil, nil, claims(fill: fill))
            }
            let frames = colors.map { content.withPersistentBackground($0) }
            // The pulse's own frames need no spelling and earn no fill claim: both
            // ends of `accentFillPulse` spend a translucent tint's alpha against the
            // page, so every frame states a concrete colour (§29). The INK claim
            // still applies — the run repaints the field, not the glyphs, and
            // `resolvingOpacity` re-blends every frame through it.
            return (
                frames[visualState.background.stepNow], frames,
                visualState.background.pulseTiming, claims(fill: nil))
        }
        // A bare line, not a one-element array: a table renders every visible
        // row every frame, and the allocator is where its time goes (see the
        // one-SGR-introducer notes above). The multi-line and slot paths do
        // produce several lines, and say so with `RenderedRow`.
        return (content, nil, nil, claims(fill: nil))
    }

    /// A breathing line and every frame of it, at its position among the lines being
    /// assembled, with the frame duration and clock its cycle is laid out on.
    private typealias PulseRun = (y: Int, frames: [String], timing: IndicatorCycleTiming)

    /// A row's rendered lines, plus — when its background breathes — every frame
    /// of each line, ready to become an ``AnimatedCellRun`` once the caller
    /// knows where among the content lines it ended up.
    ///
    /// The twin of `_ListCore.RenderedRow`, for the same reason and with the
    /// same contract: `pulseFrames[line][step]`, index-aligned with `lines`, so
    /// whatever clipping the caller applies to one it applies to the other.
    private struct RenderedRow {
        let lines: [String]
        var pulseFrames: [[String]]?

        /// The frame duration and clock `pulseFrames` step on: the cycle's, carried
        /// to where the runs are built rather than assumed there.
        var pulseTiming: IndicatorCycleTiming?

        /// The cells this row's lines owe a blend, with `offsetY` an index into
        /// ``lines`` — the same frame `pulseFrames` is indexed in, so whatever
        /// clipping the caller applies to one it applies to all three.
        var claims: [OpacityRegion] = []
    }

    /// How many frames a row's travel is cut into.
    ///
    /// The flights ask for 30 fps and run for 120 ms (out) and 200 ms (back),
    /// so eight frames is more than either can show — which is the right side
    /// to err on: a frame nobody draws costs one string, and a step nobody
    /// interpolates is a visible jump.
    static var previewMorphSteps: Int { 8 }

    /// One row's picture on its way from the GRID to the HAND: `steps` lines,
    /// the first laid out as the table draws the row and the last as a carried
    /// row is drawn. One step asks for the hand layout alone.
    ///
    /// Not `renderRow`. What makes a grid row as wide as the table is not the
    /// spacing between columns — it is that every cell is padded out to its
    /// layout width, and a `.flexible` column's width is all the room left
    /// over. A row in your hand is not a slice of the grid, so it takes each
    /// value clipped to its column (a pathological value still cannot out-grow
    /// the row it came from) and joins them with two cells, with no padding and
    /// no per-column alignment — there is no column to align within.
    ///
    /// The two layouts place the SAME clipped text and differ only in where.
    /// Interpolating the x of each cell's text between them is the whole
    /// animation — the difference used to happen between two frames, so the
    /// cells appeared to jump.
    ///
    /// Each cell is placed no further left than the end of the one before it,
    /// which cannot bind for any spacing the table allows but costs one
    /// comparison to guarantee — two cells overlapping would corrupt the line
    /// rather than merely look wrong.
    private func previewMorphLines(
        item: Value,
        row: Int,
        columnWidths: [Int],
        steps: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        // The morph is a transient animation of ONE row, so it takes that row's
        // colour from the ramp and does not band along itself — the cells are
        // sliding, and a colour that moved with them would read as a second
        // animation.
        let foregroundColor = cellColour(
            row: row, ramp: cellRamp(rowWidth: columnWidths.reduce(0, +), context: context),
            context: context, palette: palette)
        let count = min(columns.count, columnWidths.count)
        // The row in the hand keeps whatever gutter the grid gave it, so the
        // grab point — measured from the row line's first cell — still lands in
        // the column it was taken from.
        let gutter = selectionGutter(context.environment)
        let pad = String(repeating: " ", count: gutter)
        guard count > 0, steps > 0 else { return Array(repeating: pad, count: max(0, steps)) }

        let clipped = (0..<count).map {
            columns[$0].value(for: item)
                .truncatedToWidth(columnWidths[$0], mode: columns[$0].truncationMode)
        }
        let widths = clipped.map(\.strippedLength)

        var gridX: [Int] = []
        var cursor = gutter
        for index in 0..<count {
            gridX.append(
                cursor
                    + columns[index].alignment.childOffset(
                        childWidth: widths[index], in: columnWidths[index]))
            cursor += columnWidths[index] + columnSpacing
        }
        var handX: [Int] = []
        cursor = gutter
        for index in 0..<count {
            handX.append(cursor)
            cursor += widths[index] + Self.previewColumnSpacing
        }

        return (0..<steps).map { step in
            // A single step IS the hand layout — that is how `previewRow` asks
            // for the steady picture.
            let phase = steps > 1 ? Double(step) / Double(steps - 1) : 1
            var line = pad
            var column = gutter
            for index in 0..<count {
                let target =
                    gridX[index]
                    + Int((Double(handX[index] - gridX[index]) * phase).rounded())
                let start = max(column, target)
                line += String(repeating: " ", count: start - column)
                line += ANSIRenderer.colorize(clipped[index], foreground: foregroundColor)
                column = start + widths[index]
            }
            return line
        }
    }

    /// Determines indicator symbol, indicator color, and background for a table row.
    /// Everything a row renderer needs in order to colour its cells: which row
    /// it is, the ramp running down the table, and how wide the row is.
    ///
    /// One value rather than three parameters because they are one question —
    /// "what colour is this row, and where does it change?" — and because the
    /// renderers were already at the limit of what a signature should carry.
    struct RowPaint {
        /// The row's ordinal in `data`.
        let row: Int

        /// The ramp, or `nil` to paint flat. See ``Table/cellRamp(rowWidth:context:)``.
        let ramp: RampSampler?

        /// The row's full width in cells — what the ramp was measured across.
        let width: Int
    }

    /// The laid-out cells of the rows a multi-line render is about to draw, and the
    /// column widths they were laid into.
    ///
    /// One value rather than two parameters for the reason ``RowPaint`` is one: the
    /// widths and the cells wrapped to them are a single fact — a row's cells and
    /// the widths they were measured against must never come from different frames —
    /// and `composeMultiLineRows` was already at the parameter count a signature
    /// should carry.
    struct MultiLineRowLayouts {
        /// The resolved width of each column, in cells.
        let columnWidths: [Int]

        /// The wrapped cells and height of the row at an index, memoised for the
        /// whole render — see `buildMultiLineContent`.
        let layout: (Int) -> (cells: [[String]], height: Int)
    }

    /// The ramp the cells are painted with, or `nil` when the paint is a plain
    /// colour — which is the ordinary case, and the one that keeps a table's
    /// row at a single SGR introducer.
    ///
    /// A table's unit is the ROW: the ramp steps once per row, so row *i* sits
    /// at *i* of `data.count`. Nothing inside a row can disagree with that,
    /// because a table paints its own cells rather than hosting views — which
    /// is what makes the ordinal safe here and not in a `List`, where a row's
    /// content offsets itself by lines. A row that wraps to several lines is
    /// therefore one step of the ramp.
    ///
    /// Built once per frame rather than once per row: the sampler does the
    /// divisions in its initialiser and answers per cell.
    ///
    /// - Parameters:
    ///   - rowWidth: The width the ramp runs across, for a horizontal one.
    ///   - context: The render context.
    /// - Returns: The sampler, or `nil` to paint flat.
    private func cellRamp(rowWidth: Int, context: RenderContext) -> RampSampler? {
        guard let paint = context.environment.foregroundStyle else { return nil }
        let extent =
            context.gradientContentFrame(width: rowWidth, height: max(1, data.count))
            ?? GradientFrame(width: rowWidth, height: max(1, data.count))
        return RampSampler(
            paint: paint, extent: extent, depth: ColorDepth.current,
            cellAspect: context.environment.imageCellAspect)
    }

    /// The colour a row's cells take: the ramp's answer at that row, or the
    /// flat foreground. Never asks the ramp when it varies ALONG the row —
    /// that case paints per cell, through ``PaintRenderer/band(_:column:row:style:sampler:sequences:into:)``.
    private func cellColour(
        row: Int, ramp: RampSampler?, context: RenderContext, palette: any Palette
    ) -> Color {
        guard let ramp else {
            return context.environment.foregroundStyle?.representative ?? palette.foreground
        }
        return ramp.colour(row: row).resolve(with: palette)
    }

    private func rowVisualState(
        isFocused: Bool,
        isSelected: Bool,
        context: RenderContext,
        palette: any Palette
    ) -> (indicator: String, indicatorColor: Color, background: RowBackground) {
        // The glyph is ``RowSelectionIndicator``'s answer, not a fourth copy of
        // the rules: `_ListCore` asks the same thing for the same gutter.
        let indicator = RowSelectionIndicator.forRow(
            isFocused: isFocused, isSelected: isSelected, context: context, palette: palette)
        let background: RowBackground =
            if isFocused && isSelected {
                // The cursor row of a focused table breathes. As a CYCLE, not a
                // live phase: the phase read marks the frame as having consulted
                // the clock, so the whole page was re-rendered on every tick to
                // recolour one row. The caller turns the cycle into
                // ``AnimatedCellRun``s over the row's own lines. Same colour
                // pair as `_ListCore`'s cursor row, from the same place.
                .focusedSelection(in: context, palette: palette)
            } else if isFocused {
                // The focus wash, or a reversal where it cannot be measured — the same
                // answer `_ListCore` takes for the same row, from the same place.
                .focused(palette: palette)
            } else {
                // A selected row while the table itself does not have focus
                // draws its mark and no fill; `.hidden` suppresses both, and
                // the indicator has already agreed to that.
                .none
            }
        return (indicator.glyph, indicator.color, background)
    }

    // MARK: - Text Alignment

    /// A cell's text clipped and padded into its column, written straight into
    /// the row buffer the caller is already assembling.
    ///
    /// This is the whole rule; `alignText` below is a wrapper for the two
    /// callers that need the cell as a value. It runs once per CELL per drawn
    /// line per frame — 1,040 times a frame on the `tables-scroll` shape (8
    /// tables x 25 rows x 5 columns, plus the headers) — and the previous form
    /// built two pad strings and a third for the `+`-chain result, only for the
    /// caller to copy that result into `content` and drop it. Appending instead
    /// reuses the two pieces every other pad site in the framework uses: the
    /// borrowed `asciiSpaces` run, and a buffer that was already reserved. Same
    /// reason the row itself stopped building a `[String]` of cells (see the
    /// one-buffer note in `renderRow`): a table's time goes to the allocator.
    private func appendAligned(
        _ text: String,
        width: Int,
        alignment: HorizontalAlignment,
        truncationMode: TruncationMode,
        into content: inout String
    ) {
        // Clip the value to the column width *first*: a cell that is wider
        // than its column would otherwise shove every column to its right
        // out of alignment. An over-long value is shown truncated with an
        // ellipsis so the loss of content is visible.
        let clipped = text.truncatedToWidth(width, mode: truncationMode)
        let visibleLength = clipped.strippedLength
        let padding = max(0, width - visibleLength)

        // Guide arithmetic, same as every other placement: the cell's visible
        // text is a `visibleLength`-wide child inside a `width`-wide column.
        let leftPad = alignment.childOffset(childWidth: visibleLength, in: width)
        let rightPad = padding - leftPad
        // Not a `String(repeating:)` pair. `childOffset(childWidth:in:)` clamps
        // its answer to `0...max(0, width - visibleLength)`, so both pads are
        // non-negative and both runs are plain ASCII U+0020 — byte-for-byte what
        // the `+` chain produced, minus the three temporaries.
        content += asciiSpaces(leftPad)
        content += clipped
        content += asciiSpaces(rightPad)
    }

    /// `appendAligned` as a value, for the two callers that cannot append.
    ///
    /// A banded cell goes to
    /// ``PaintRenderer/band(_:column:row:style:sampler:sequences:into:)`` whole
    /// — that call emits one SGR introducer per ramp entry across its argument,
    /// so splitting the cell into pad/text/pad would restart the run at each
    /// piece and change the bytes. The header wraps its cell in
    /// `ANSIRenderer.colorize`. Both share the body above rather than keeping a
    /// second copy of the clip-and-pad rule.
    ///
    /// Deliberately no `reserveCapacity`: reserving on an empty String forces
    /// native heap storage, and a header title or a narrow cell padded to its
    /// column usually fits the 15-byte small-string form, which the appends
    /// below keep. Reserving here would make this wrapper allocate where the
    /// `+` chain it replaces did not.
    private func alignText(
        _ text: String,
        width: Int,
        alignment: HorizontalAlignment,
        truncationMode: TruncationMode
    ) -> String {
        var aligned = ""
        appendAligned(
            text, width: width, alignment: alignment, truncationMode: truncationMode,
            into: &aligned)
        return aligned
    }
}

// MARK: - Table Content View

/// Simple view that renders pre-computed lines.
private struct _TableContentView: View, Renderable {
    let lines: [String]

    /// The breathing row's cells, already positioned among `lines` — the header
    /// above and the container around shift them along with the lines.
    var runs: [AnimatedCellRun] = []

    /// The rows' opacity claims, positioned the same way and travelling the same
    /// route: a `Table` paints its rows' ink, its selection marks and its still
    /// backgrounds itself, and a translucent one of any of those owes a blend.
    var claims: [OpacityRegion] = []

    var body: Never {
        fatalError("_TableContentView renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: lines)
        // A measure pass draws nothing, so a run left on it would describe
        // cells that were never on screen — and keep the clock alive from a
        // pass that produced no frame. A claim on a measure buffer is harmless
        // by comparison, but it is the same statement about cells nobody drew.
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells = runs
        buffer.opacityRegions = claims
        return buffer
    }
}

// MARK: - Table Header View

/// Simple view that renders the header line.
private struct _TableHeaderView: View, Renderable {
    let line: String

    /// What the header's own colours owe, in the line's columns.
    ///
    /// The header is painted in `foregroundSecondary`, which is a re-SPELLING of the
    /// palette's foreground and carries its alpha — so a theme that fades its text
    /// fades the header, and the claim has to travel with the line rather than being
    /// derived from it later. `_TableContentView`'s twin, added for the same reason
    /// (§33) one commit apart.
    let claims: [OpacityRegion]

    var body: Never {
        fatalError("_TableHeaderView renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [line])
        buffer.opacityRegions += claims
        return buffer
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

// MARK: - Disabled state

extension _TableCore {
    /// Whether this table is disabled, counting an ancestor's
    /// `.disabled(true)`.
    ///
    /// The same hole `_ListCore` had, for the same reason: `Table`'s concrete
    /// `disabled(_:) -> Self` overload wins overload resolution, so
    /// `Table(…).disabled(true)` sets ``isDisabled`` directly — but
    /// `VStack { Table(…) }.disabled(true)` publishes `\.isEnabled` and
    /// nothing here read it, so the table stayed focusable, selectable and
    /// sortable inside a disabled subtree. See ``_ListCore/isDisabled(in:)``.
    func isDisabled(in context: RenderContext) -> Bool {
        isDisabled || !context.environment.isEnabled
    }
}
