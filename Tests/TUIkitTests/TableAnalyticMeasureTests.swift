//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableAnalyticMeasureTests.swift
//
//  Table's single-line measure path is analytic (O(columns), no row
//  rendering); the render path builds the real rows. The two must agree on
//  the table's dimensions for EVERY configuration — this sweep holds them
//  equal across row counts (empty/fitting/overflowing), terminal sizes,
//  scrollbar visibilities, and column-width mixes, including `.fit` columns
//  whose values saturate the interior (the early-out path).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

private struct MeasureRow: Identifiable {
    let id: Int
    let name: String
    let detail: String
}

@MainActor
@Suite("Table analytic measure equivalence")
struct TableAnalyticMeasureTests {

    private func rows(_ count: Int, wide: Bool = false) -> [MeasureRow] {
        (0..<count).map { index in
            MeasureRow(
                id: index,
                name: wide
                    ? "row-\(index) " + String(repeating: "x", count: 90)
                    : "row-\(index)",
                detail: "detail \(index)")
        }
    }

    /// Every column mix exercised by the sweep, as erased table builders.
    private func tables(
        data: [MeasureRow]
    ) -> [(label: String, table: AnyView)] {
        [
            (
                "flexible+fixed",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name)
                        TableColumn("Detail", value: \MeasureRow.detail).width(.fixed(10))
                    })
            ),
            (
                "fit",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).width(.fit)
                        TableColumn("Detail", value: \MeasureRow.detail).width(.fit)
                    })
            ),
            (
                "ratio",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).width(.ratio(0.6))
                        TableColumn("Detail", value: \MeasureRow.detail).width(.ratio(0.4))
                    })
            ),
        ]
    }

    @Test(
        "Analytic measure equals rendered size across the configuration matrix",
        arguments: [0, 1, 3, 12, 40, 150], [ScrollbarVisibility.automatic, .visible, .hidden])
    func analyticMatchesRender(rowCount: Int, barVisibility: ScrollbarVisibility) {
        for (width, height) in [(20, 8), (40, 12), (80, 24), (120, 43)] {
            for wide in [false, true] {
                let data = rows(rowCount, wide: wide)
                for (label, table) in tables(data: data) {
                    let context = makeRenderContext(width: width, height: height) { env, _ in
                        env.scrollbarVisibility = barVisibility
                    }

                    // The render ground truth, at the exact context shape the
                    // old render-based measure used (natural width).
                    var renderContext = context
                    renderContext.hasExplicitWidth = false
                    let buffer = renderToBuffer(table, context: renderContext)

                    let measured = measureChild(
                        table,
                        proposal: ProposedSize(width: width, height: height),
                        context: context)

                    #expect(
                        measured.width == buffer.width && measured.height == buffer.height,
                        """
                        \(label) rows=\(rowCount) wide=\(wide) \(width)x\(height) \
                        bar=\(barVisibility): measured \(measured.width)x\(measured.height) \
                        vs rendered \(buffer.width)x\(buffer.height)
                        """)
                }
            }
        }
    }

    @Test("The declined shape — overflowing with no bar — still measures equal")
    func declinedShapeStillMatches() {
        let data = rows(8, wide: true)
        let table = Table(data, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \MeasureRow.name).lineLimit(3)
            TableColumn("Detail", value: \MeasureRow.detail)
        }
        let context = makeRenderContext(width: 40, height: 16)
        var renderContext = context
        renderContext.hasExplicitWidth = false
        let buffer = renderToBuffer(table, context: renderContext)
        let measured = measureChild(
            table, proposal: ProposedSize(width: 40, height: 16), context: context)
        #expect(measured.width == buffer.width && measured.height == buffer.height)
    }

    /// The multi-line counterpart of the sweep above.
    ///
    /// `analyticMultiLineSize` answers the bar-drawn and rows-fit shapes and
    /// returns `nil` for the third, so the render decides that one.
    /// Which of the two answered is invisible from out here, and that is the
    /// point: the sweep asserts the outer contract — measured == rendered —
    /// over a matrix that straddles the boundary in every direction (rows that
    /// fit and rows that overflow; every scrollbar visibility; short and tall
    /// terminals; wide values that wrap and narrow ones that don't; one
    /// multi-line column and several).
    ///
    /// The boundary is exactly where a fast path is dangerous — a table that
    /// fits at one width overflows at another, and the measure must not be the
    /// one to disagree.
    private func multiLineTables(
        data: [MeasureRow]
    ) -> [(label: String, table: AnyView)] {
        [
            (
                "one multi-line column",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).lineLimit(3)
                        TableColumn("Detail", value: \MeasureRow.detail)
                    })
            ),
            (
                "two multi-line columns",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).lineLimit(4)
                        TableColumn("Detail", value: \MeasureRow.detail).lineLimit(2)
                    })
            ),
            (
                "multi-line + fixed",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).lineLimit(3)
                            .width(.fixed(12))
                        TableColumn("Detail", value: \MeasureRow.detail).width(.fit)
                    })
            ),
        ]
    }

    @Test(
        "Multi-line measure equals rendered size across the configuration matrix",
        arguments: [1, 2, 5, 20, 90], [ScrollbarVisibility.automatic, .visible, .hidden])
    func multiLineMatchesRender(rowCount: Int, barVisibility: ScrollbarVisibility) {
        for (width, height) in [(24, 9), (40, 12), (80, 24), (120, 43)] {
            for wide in [false, true] {
                let data = rows(rowCount, wide: wide)
                for (label, table) in multiLineTables(data: data) {
                    let context = makeRenderContext(width: width, height: height) { env, _ in
                        env.scrollbarVisibility = barVisibility
                    }
                    var renderContext = context
                    renderContext.hasExplicitWidth = false
                    let buffer = renderToBuffer(table, context: renderContext)
                    let measured = measureChild(
                        table,
                        proposal: ProposedSize(width: width, height: height),
                        context: context)

                    #expect(
                        measured.width == buffer.width && measured.height == buffer.height,
                        """
                        \(label) rows=\(rowCount) wide=\(wide) \(width)x\(height) \
                        bar=\(barVisibility): measured \(measured.width)x\(measured.height) \
                        vs rendered \(buffer.width)x\(buffer.height)
                        """)
                }
            }
        }
    }

    @Test("A tall budget — the extent ladder's case — still measures exactly")
    func laddersTallBudgetsMatchTheRender() {
        // `measureNaturalExtent` probes with budgets far past the content, and
        // that is precisely where the analytic path answers. Every rung must
        // agree with what rendering at that budget would produce.
        let data = rows(40, wide: true)
        for budget in [64, 256, 4096, 16_384] {
            for (label, table) in multiLineTables(data: data) {
                let context = makeRenderContext(width: 60, height: budget)
                var renderContext = context
                renderContext.hasExplicitWidth = false
                let buffer = renderToBuffer(table, context: renderContext)
                let measured = measureChild(
                    table, proposal: ProposedSize(width: 60, height: budget), context: context)
                #expect(
                    measured.width == buffer.width && measured.height == buffer.height,
                    """
                    \(label) budget=\(budget): measured \(measured.width)x\(measured.height) \
                    vs rendered \(buffer.width)x\(buffer.height)
                    """)
            }
        }
    }
}
