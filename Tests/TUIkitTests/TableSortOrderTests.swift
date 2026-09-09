//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableSortOrderTests.swift
//
//  Clicking a Table's column header re-sorts it — SwiftUI's behaviour, driven
//  by the same `sortOrder` binding of `KeyPathComparator`s. The table publishes
//  the order and the app applies it; these pin what the table publishes, what
//  it draws while it does, and which parts of the header are clickable at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Table sort order")
struct TableSortOrderTests {

    private struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
        let size: Int
        var sizeText: String { "\(size) B" }
    }

    private static let rows = [
        Row(id: 1, name: "charlie", size: 30),
        Row(id: 2, name: "alpha", size: 10),
        Row(id: 3, name: "bravo", size: 20),
    ]

    /// Renders a table and drives clicks at absolute screen positions.
    @MainActor
    private final class Harness {
        let tui = TUIContext()
        let dispatcher: MouseEventDispatcher
        let focusManager = FocusManager()
        var sortOrder: [KeyPathComparator<Row>]?
        var buffer = FrameBuffer(lines: [])

        init(sortOrder: [KeyPathComparator<Row>]?) {
            self.sortOrder = sortOrder
            dispatcher = tui.mouseEventDispatcher
            dispatcher.setActiveSupport(.full)
        }

        var binding: Binding<[KeyPathComparator<Row>]>? {
            guard sortOrder != nil else { return nil }
            return Binding(get: { self.sortOrder ?? [] }, set: { self.sortOrder = $0 })
        }

        @discardableResult
        func render(
            sortableSizeColumn: Bool = true,
            fitFirstColumn: Bool = false,
            width: Int = 40,
            nameTitle: String = "Name",
            trailingSizeColumn: Bool = false,
            markHidden: Bool = false
        ) -> FrameBuffer {
            dispatcher.beginRenderPass()
            var env = EnvironmentValues()
            env.mouseEventDispatcher = dispatcher
            env.focusManager = focusManager
            let context = RenderContext(
                availableWidth: width, availableHeight: 10, environment: env, tuiContext: tui)
            // Built as an explicit array: `TableColumnBuilder` cannot compose
            // an `if`/`else` (its `buildEither` yields an array its variadic
            // `buildBlock` will not take), which is its own bug, not this
            // test's subject.
            let sizeColumn =
                sortableSizeColumn
                ? TableColumn("Size", value: \Row.size) { $0.sizeText }
                : TableColumn("Size", value: { (row: Row) in row.sizeText })
            let nameColumn = TableColumn(nameTitle, value: \Row.name)
            let table = Table(rows, selection: .constant(Int?.none), sortOrder: binding) {
                fitFirstColumn ? nameColumn.width(.fit) : nameColumn
                trailingSizeColumn ? sizeColumn.alignment(.trailing) : sizeColumn
            }
            buffer = renderToBuffer(
                markHidden ? AnyView(table.rowSelectionIndicator(.hidden)) : AnyView(table),
                context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        var rows: [Row] { TableSortOrderTests.rows }

        /// The rendered header line (row 1 of the table's own buffer).
        var headerLine: String { buffer.lines.count > 1 ? buffer.lines[1].stripped : "" }

        /// Clicks the first cell of `title` where it is drawn on the header.
        @discardableResult
        func clickHeader(_ title: String) -> Bool {
            guard let x = headerLine.range(of: title).map({ headerLine.distance(
                from: headerLine.startIndex, to: $0.lowerBound) })
            else {
                Issue.record("\(title) not on the header line: \(headerLine.debugDescription)")
                return false
            }
            let pressed = dispatcher.dispatch(
                MouseEvent(button: .left, phase: .pressed, x: x, y: 1))
            let released = dispatcher.dispatch(
                MouseEvent(button: .left, phase: .released, x: x, y: 1))
            return pressed && released
        }

        /// Renders inside a focus pass — so the table's handler registers and
        /// `endRenderPass` auto-focuses it — then presses `event` the way a real
        /// key press arrives. Both the chord table and `onSort` are captured
        /// during the render, so the order matters.
        @discardableResult
        func press(_ event: KeyEvent, multiLine: Bool = false) -> Bool {
            focusManager.beginRenderPass()
            render(fitFirstColumn: multiLine)
            focusManager.endRenderPass()
            return focusManager.dispatchKeyEvent(event)
        }
    }

    // MARK: - What the header draws

    @Test("Without a sortOrder binding the header is exactly what it always was")
    func noBindingLeavesHeaderAlone() {
        let harness = Harness(sortOrder: nil)
        harness.render()
        #expect(!harness.headerLine.contains("▲"))
        #expect(!harness.headerLine.contains("▼"))
    }

    @Test("The column being sorted by carries the direction it is sorted in")
    func primaryColumnShowsItsDirection() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name, order: .forward)])
        harness.render()
        #expect(harness.headerLine.contains("Name ▲"), "header: \(harness.headerLine)")
        #expect(!harness.headerLine.contains("Size ▲"), "header: \(harness.headerLine)")

        harness.sortOrder = [KeyPathComparator(\Row.name, order: .reverse)]
        harness.render()
        #expect(harness.headerLine.contains("Name ▼"), "header: \(harness.headerLine)")
    }

    /// A column too narrow for both loses TITLE, not indicator. The arrow is
    /// the part a reader cannot reconstruct — "Tra…" could be any of several
    /// columns and says nothing about the order — and a cramped table is
    /// exactly when you most need to see which column you just sorted by.
    @Test("A column too narrow for both keeps the indicator and truncates the title")
    func indicatorOutranksTheTitle() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name, order: .reverse)])
        harness.render(width: 20, nameTitle: "Trackname")
        let header = harness.headerLine
        #expect(header.contains("▼"), "header: \(header.debugDescription)")
        #expect(header.contains("…"), "header should be truncated: \(header.debugDescription)")
        #expect(!header.contains("Trackname"), "header: \(header.debugDescription)")
        // …and the arrow is still the LAST thing in that column, not stranded
        // before the ellipsis.
        #expect(header.contains("… ▼"), "header: \(header.debugDescription)")
    }

    /// Reserving the arrow's slot must not cost the COMMON case its alignment.
    /// A `.trailing` header on an unsorted column has to sit on the column's
    /// right edge; padding the title into a slot nothing is drawn in pushed it
    /// two cells in, so a right-aligned column read as misaligned unless it
    /// happened to be the one being sorted by.
    @Test("A trailing header keeps its edge until an arrow needs the room")
    func trailingHeaderStaysRightAligned() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name, order: .forward)])
        harness.render(trailingSizeColumn: true)
        // A row's own trailing-aligned cell marks where the column ends; the
        // header has to land on the same column, which is the whole complaint.
        let unsorted = harness.headerLine
        let cellEnd = harness.buffer.lines[2].stripped.range(of: "30 B")?.upperBound
        let headerEnd = unsorted.range(of: "Size")?.upperBound
        guard let cellEnd, let headerEnd else {
            Issue.record("missing Size header or cell: \(unsorted.debugDescription)")
            return
        }
        let cellColumn = harness.buffer.lines[2].stripped.distance(
            from: harness.buffer.lines[2].stripped.startIndex, to: cellEnd)
        let headerColumn = unsorted.distance(from: unsorted.startIndex, to: headerEnd)
        #expect(
            headerColumn == cellColumn,
            "unsorted header ends at \(headerColumn), cells at \(cellColumn): \(unsorted)")

        // Sorting BY Size gives the arrow the room, and the title shifts left
        // to make it — the arrow now sits where the title's last cell was.
        harness.sortOrder = [KeyPathComparator(\Row.size, order: .forward)]
        harness.render(trailingSizeColumn: true)
        let sorted = harness.headerLine
        guard let arrowEnd = sorted.range(of: "Size ▲")?.upperBound else {
            Issue.record("no arrow: \(sorted.debugDescription)")
            return
        }
        #expect(
            sorted.distance(from: sorted.startIndex, to: arrowEnd) == cellColumn,
            "sorted header ends at \(sorted.distance(from: sorted.startIndex, to: arrowEnd)), cells at \(cellColumn): \(sorted)")
    }

    /// The indicator slot is reserved on every sortable column, so sorting the
    /// table cannot change its column widths — the reason to reserve it.
    @Test("Column widths do not move as the sort changes")
    func layoutIsStableAcrossSorts() {
        // In CELLS, not `String.Index`: an indicator is three UTF-8 bytes, so
        // byte offsets shift with the glyph even when nothing on screen moves.
        func column(_ title: String, in buffer: FrameBuffer) -> Int? {
            let header = buffer.lines[1].stripped
            return header.range(of: title).map {
                header.distance(from: header.startIndex, to: $0.lowerBound)
            }
        }

        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name)])
        let forward = harness.render()
        let sizeX = column("Size", in: forward)
        #expect(sizeX != nil)

        harness.sortOrder = [KeyPathComparator(\Row.name, order: .reverse)]
        #expect(column("Size", in: harness.render()) == sizeX)

        harness.sortOrder = [KeyPathComparator(\Row.size)]
        let bySize = harness.render()
        #expect(column("Size", in: bySize) == sizeX)
        #expect(column("Name", in: bySize) == column("Name", in: forward))
        #expect(bySize.width == forward.width)
        #expect(bySize.height == forward.height)
        // The rows themselves never moved either.
        #expect(bySize.lines[3].stripped == forward.lines[3].stripped)
    }

    /// A `.fit` column sizes to the widest of its header and its cells — and
    /// the header it has to fit is the one that will be DRAWN, indicator and
    /// all. Measuring the bare title left the column two cells short, so a
    /// sortable `.fit` column truncated its own header ("Track…").
    @Test("A .fit column makes room for its own sort indicator")
    func fitColumnFitsItsIndicator() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name)])
        harness.render(fitFirstColumn: true)
        #expect(harness.headerLine.contains("Name ▲"), "header: \(harness.headerLine)")
        #expect(!harness.headerLine.contains("…"), "header: \(harness.headerLine)")
    }

    // MARK: - What a click does

    @Test("Clicking the sorted column's header reverses it")
    func clickingTheSortedColumnReverses() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name, order: .forward)])
        harness.render()
        #expect(harness.clickHeader("Name"))
        #expect(harness.sortOrder?.count == 1)
        #expect(harness.sortOrder?.first?.keyPath == \Row.name)
        #expect(harness.sortOrder?.first?.order == .reverse)

        harness.render()
        #expect(harness.clickHeader("Name"))
        #expect(harness.sortOrder?.first?.order == .forward)
    }

    /// The same four sort states a click reaches, reached without a mouse. A
    /// table that draws a `▲`/`▼` and reserves the cells for it, but can only be
    /// sorted by pointer, breaks the framework's own rule that a mouse-only
    /// gesture needs a keyboard route.
    @Test("Ctrl-D reverses the sort and Ctrl-S moves it to the next column")
    func chordsSortTheTable() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name, order: .forward)])
        let ctrlS = KeyEvent(key: .character("s"), ctrl: true)
        let ctrlD = KeyEvent(key: .character("d"), ctrl: true)

        #expect(harness.press(ctrlD))
        #expect(harness.sortOrder?.count == 1)
        #expect(harness.sortOrder?.first?.keyPath == \Row.name)
        #expect(harness.sortOrder?.first?.order == .reverse)

        #expect(harness.press(ctrlS))
        #expect(harness.sortOrder?.first?.keyPath == \Row.size)
        #expect(harness.sortOrder?.first?.order == .forward, "promoted ascending")
        #expect(harness.sortOrder?.count == 2, "the displaced sort stays as the tie-break")
        #expect(harness.sortOrder?.last?.keyPath == \Row.name)

        // …and the next one wraps back to the first sortable column.
        #expect(harness.press(ctrlS))
        #expect(harness.sortOrder?.first?.keyPath == \Row.name)
        harness.render()
        #expect(harness.headerLine.contains("Name ▲"), "header: \(harness.headerLine)")
    }

    /// The multi-line viewport is a second call site, and it assigns `onSort`
    /// separately — so it gets its own press rather than riding on the
    /// single-line path's coverage.
    @Test("The chords work on a table whose rows wrap too")
    func chordsSortAWrappingTable() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name, order: .forward)])
        #expect(harness.press(KeyEvent(key: .character("d"), ctrl: true), multiLine: true))
        #expect(harness.sortOrder?.first?.order == .reverse)
    }

    /// A second column becomes the primary sort, ascending — and the one it
    /// displaced stays on as the tie-break, which is what makes a two-key sort
    /// reachable by clicking two headers in turn.
    @Test("Clicking another column promotes it and keeps the old sort behind it")
    func clickingAnotherColumnPromotesIt() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name, order: .reverse)])
        harness.render()
        #expect(harness.clickHeader("Size"))
        #expect(harness.sortOrder?.count == 2)
        #expect(harness.sortOrder?.first?.keyPath == \Row.size)
        #expect(harness.sortOrder?.first?.order == .forward)
        #expect(harness.sortOrder?.last?.keyPath == \Row.name)
        #expect(harness.sortOrder?.last?.order == .reverse)

        // …and coming back to the first column promotes it again rather than
        // stacking a third entry.
        harness.render()
        #expect(harness.clickHeader("Name"))
        #expect(harness.sortOrder?.count == 2)
        #expect(harness.sortOrder?.first?.keyPath == \Row.name)
        #expect(harness.sortOrder?.first?.order == .forward)
    }

    @Test("A column with no comparator has an inert header")
    func closureColumnHeaderIsInert() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name)])
        harness.render(sortableSizeColumn: false)
        let before = harness.sortOrder
        // Nothing there takes the click; it falls through to the table itself.
        _ = harness.clickHeader("Size")
        #expect(harness.sortOrder?.first?.keyPath == before?.first?.keyPath)
        #expect(harness.sortOrder?.first?.order == before?.first?.order)
        #expect(!harness.headerLine.contains("Size ▲"), "header: \(harness.headerLine)")
    }

    @Test("Without a sortOrder binding a header click sorts nothing")
    func noBindingMeansNoSorting() {
        let harness = Harness(sortOrder: nil)
        harness.render()
        _ = harness.clickHeader("Name")
        #expect(harness.sortOrder == nil)
    }

    /// The table reports the order and leaves the data alone — SwiftUI's
    /// division of labour, and the reason `.onChange(of: sortOrder)` is where
    /// an app sorts.
    @Test("Sorting is published, not performed")
    func theTableDoesNotSortTheData() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name)])
        let before = harness.render().lines.map(\.stripped)
        #expect(harness.clickHeader("Name"))
        let after = harness.render().lines.map(\.stripped)
        // The rows are drawn in their original (unsorted) order both times;
        // only the indicator moved.
        func rowOrder(_ lines: [String]) -> [String] {
            lines.compactMap { line in
                ["charlie", "alpha", "bravo"].first { line.contains($0) }
            }
        }
        #expect(rowOrder(before) == ["charlie", "alpha", "bravo"])
        #expect(rowOrder(after) == rowOrder(before))
    }

    /// What the app does with the published order, end to end.
    @Test("Applying the published order sorts the rows")
    func applyingThePublishedOrderSorts() {
        var order = [KeyPathComparator(\Row.name, order: .forward)]
        var rows = Self.rows
        rows.sort(using: order)
        #expect(rows.map(\.name) == ["alpha", "bravo", "charlie"])

        order = [KeyPathComparator(\Row.size, order: .reverse)]
        rows.sort(using: order)
        #expect(rows.map(\.size) == [30, 20, 10])
    }

    // MARK: - Where the click has to land

    /// The regions have to line up with the titles as DRAWN — the whole point
    /// of deriving both from one column-width list.
    @Test("Each header region covers its own column and no other")
    func headerRegionsMatchTheDrawnTitles() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name)])
        let buffer = harness.render()
        let header = buffer.lines[1].stripped
        let regions = buffer.hitTestRegions.filter { $0.offsetY == 1 && $0.height == 1 }
        #expect(regions.count == 2, "one per sortable column: \(regions)")

        for (title, region) in zip(["Name", "Size"], regions.sorted { $0.offsetX < $1.offsetX }) {
            guard let found = header.range(of: title) else {
                Issue.record("\(title) missing from \(header.debugDescription)")
                continue
            }
            let start = header.distance(from: header.startIndex, to: found.lowerBound)
            #expect(
                region.offsetX <= start && start < region.offsetX + region.width,
                """
                \(title) is drawn at \(start), outside \
                \(region.offsetX)..<\(region.offsetX + region.width)
                """)
        }
    }

    /// …including when the selection gutter is not there to be skipped.
    ///
    /// The regions and the titles are derived from one column-width list, but
    /// they arrive at the first column by two different routes — `renderHeader`
    /// writes the indent, `headerColumnRanges` adds it to `originX` — so a
    /// table that reserves nothing is exactly where the two can disagree by two
    /// cells and hand every sortable header the column to its left.
    @Test("Each header region covers its own column with no mark to indent past")
    func headerRegionsFollowTheGutterAway() {
        let harness = Harness(sortOrder: [KeyPathComparator(\Row.name)])
        let buffer = harness.render(markHidden: true)
        let header = buffer.lines[1].stripped
        #expect(
            header.hasPrefix("\u{2502} Name"),
            "the border, its pad, then the title: \(header.debugDescription)")

        let regions = buffer.hitTestRegions.filter { $0.offsetY == 1 && $0.height == 1 }
        #expect(regions.count == 2, "one per sortable column: \(regions)")
        for (title, region) in zip(["Name", "Size"], regions.sorted { $0.offsetX < $1.offsetX }) {
            guard let found = header.range(of: title) else {
                Issue.record("\(title) missing from \(header.debugDescription)")
                continue
            }
            let start = header.distance(from: header.startIndex, to: found.lowerBound)
            #expect(
                region.offsetX <= start && start < region.offsetX + region.width,
                """
                \(title) is drawn at \(start), outside \
                \(region.offsetX)..<\(region.offsetX + region.width)
                """)
        }

        // …and the click that lands there actually sorts, which is the whole
        // point of the region being in the right place.
        harness.buffer = buffer
        harness.dispatcher.setRegions(buffer.hitTestRegions)
        #expect(harness.clickHeader("Size"))
        #expect(harness.sortOrder?.first?.keyPath == \Row.size)
    }
}
