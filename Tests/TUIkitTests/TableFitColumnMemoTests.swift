//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableFitColumnMemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A `.fit` column fits the widest of its header and EVERY cell value — all
/// the rows, so the column does not change width as the table scrolls — and
/// that scan runs more than once per frame. The answer is kept across frames
/// for as long as the rows have not changed.
///
/// What has to hold, and what each test here holds it to:
///
/// - the scan really is skipped (counted, not inferred from a clock);
/// - a width that is kept is the width that would have been computed, and it
///   follows the data rather than lagging it;
/// - a row type that cannot be compared gets no memo and no wrong answer —
///   which is also this suite's report on a compiler warning that claims the
///   comparison is not a real one.
@MainActor
@Suite("Table .fit column width memo")
struct TableFitColumnMemoTests {

    /// Counts how many times the column's value closure runs, which is how many
    /// rows the fit scan walked. A `final class` rather than a captured `var`
    /// so the closure can stay `@Sendable`.
    private final class Calls: @unchecked Sendable {
        var count = 0
    }

    private struct ComparableRow: Identifiable, Sendable, Equatable {
        let id: Int
        let name: String
    }

    /// The same rows, with no `Equatable` conformance. `Table` requires only
    /// `Identifiable`, so this is a shape an app really has.
    private struct UncomparableRow: Identifiable, Sendable {
        let id: Int
        let name: String
    }

    private func context(width: Int = 40, height: Int = 12) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private func comparableTable(_ rows: [ComparableRow], calls: Calls) -> some View {
        Table(rows, selection: Binding<Int?>.constant(nil)) {
            TableColumn("Name") { (row: ComparableRow) -> String in
                calls.count += 1
                return row.name
            }
            .width(.fit)
            TableColumn("ID") { (row: ComparableRow) in "\(row.id)" }
        }
    }

    private func uncomparableTable(_ rows: [UncomparableRow], calls: Calls) -> some View {
        Table(rows, selection: Binding<Int?>.constant(nil)) {
            TableColumn("Name") { (row: UncomparableRow) -> String in
                calls.count += 1
                return row.name
            }
            .width(.fit)
            TableColumn("ID") { (row: UncomparableRow) in "\(row.id)" }
        }
    }

    private func rows(_ count: Int, longest: String = "Wolfgang") -> [ComparableRow] {
        (0..<count).map { ComparableRow(id: $0, name: $0 == 0 ? longest : "ab") }
    }

    /// Renders `view` `frames` times through one cache, the way a run loop
    /// would, and answers how many rows each frame walked.
    private func scanCounts(
        frames: Int, in context: RenderContext, calls: Calls, _ view: some View
    ) -> [Int] {
        (0..<frames).map { frame in
            if frame > 0 { context.renderCache?.beginRenderPass() }
            calls.count = 0
            _ = renderToBuffer(view, context: context)
            return calls.count
        }
    }

    /// A settled table over unchanged rows walks none of them.
    ///
    /// Three frames, not two, and the third is the one that matters. The table
    /// builds its own `@State` while rendering frame 1; that write invalidates
    /// its subtree, and the cache applies it at the start of frame 2 — which
    /// therefore scans and stores, and frame 3 is the first that can be served.
    /// Every memo in the framework has a version of this warm-up; here it is
    /// visible because the oracle is a count rather than a clock.
    ///
    /// The residue each frame is the VISIBLE rows: `renderRow` asks each
    /// column for the cell it draws, which no memo removes and none should.
    @Test("A settled table does not re-scan its rows")
    func settledFrameSkipsTheScan() {
        let context = self.context()
        let data = rows(200)
        let calls = Calls()
        let counts = scanCounts(frames: 3, in: context, calls: calls, comparableTable(data, calls: calls))

        #expect(counts[0] >= data.count, "frame 1 walks every row: \(counts)")
        #expect(counts[1] >= data.count, "frame 2 re-walks after the state write: \(counts)")
        #expect(counts[2] < 50, "frame 3 walked \(counts[2]) rows, of 200: \(counts)")
    }

    /// And the width it keeps is the width it would have computed — checked by
    /// where the second column's header lands, which is what a wrong fit width
    /// would move.
    @Test("The kept width is the computed width")
    func keptWidthMatchesComputed() {
        let data = rows(50)
        let calls = Calls()
        let warm = context()
        let view = comparableTable(data, calls: calls)
        for frame in 0..<2 {
            if frame > 0 { warm.renderCache?.beginRenderPass() }
            _ = renderToBuffer(view, context: warm)
        }
        warm.renderCache?.beginRenderPass()
        let served = renderToBuffer(view, context: warm)

        let cold = context()
        let fresh = renderToBuffer(comparableTable(data, calls: Calls()), context: cold)

        #expect(served.lines == fresh.lines, "a served width drew a different table")
    }

    /// The property a stale width would break: change the widest value and the
    /// column has to move on the very next frame.
    @Test("A changed row changes the width")
    func changedDataChangesTheWidth() {
        let context = self.context()
        let narrow = renderToBuffer(comparableTable(rows(30, longest: "ab"), calls: Calls()), context: context)
        context.renderCache?.beginRenderPass()
        let wide = renderToBuffer(
            comparableTable(rows(30, longest: "Bartholomew"), calls: Calls()), context: context)

        #expect(narrow.lines != wide.lines, "the widened value did not widen the column")
        #expect(wide.lines.contains { $0.stripped.contains("Bartholomew") })
    }

    /// A row type with no `Equatable` conformance has no signature, so there is
    /// nothing to compare a kept answer against and the scan runs every frame.
    ///
    /// This is also the runtime answer to a compiler claim. Spelled against the
    /// concrete `[Value]`, `data as? any Equatable` draws
    /// "conditional cast … always succeeds" on 6.2.4 — inside these modules
    /// only; the same code in a standalone file does not. If the cast really
    /// did always succeed, a non-`Equatable` row type would be boxed as an
    /// `any Equatable` it does not conform to, and this table would either trap
    /// or serve its neighbour's width. It does neither: the count below says
    /// the memo declined.
    @Test("A row type that cannot be compared is scanned every frame")
    func uncomparableRowsAreNotMemoised() {
        let context = self.context()
        let data = (0..<40).map { UncomparableRow(id: $0, name: $0 == 0 ? "Wolfgang" : "ab") }
        let calls = Calls()

        let counts = scanCounts(
            frames: 3, in: context, calls: calls, uncomparableTable(data, calls: calls))
        #expect(
            counts.allSatisfy { $0 >= data.count },
            "a frame skipped the scan for data it cannot compare: \(counts)")

        context.renderCache?.beginRenderPass()
        let drawn = renderToBuffer(uncomparableTable(data, calls: calls), context: context)
        #expect(drawn.lines.contains { $0.stripped.contains("Wolfgang") })
    }
}
