//  🖥️ TUIKit — Terminal UI Kit for Swift
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
        func render(sortableSizeColumn: Bool = true) -> FrameBuffer {
            dispatcher.beginRenderPass()
            var env = EnvironmentValues()
            env.mouseEventDispatcher = dispatcher
            env.focusManager = focusManager
            let context = RenderContext(
                availableWidth: 40, availableHeight: 10, environment: env, tuiContext: tui)
            // Built as an explicit array: `TableColumnBuilder` cannot compose
            // an `if`/`else` (its `buildEither` yields an array its variadic
            // `buildBlock` will not take), which is its own bug, not this
            // test's subject.
            let sizeColumn =
                sortableSizeColumn
                ? TableColumn("Size", value: \Row.size) { $0.sizeText }
                : TableColumn("Size", value: { (row: Row) in row.sizeText })
            let table = Table(rows, selection: .constant(Int?.none), sortOrder: binding) {
                TableColumn("Name", value: \Row.name)
                sizeColumn
            }
            buffer = renderToBuffer(table, context: context)
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
}
