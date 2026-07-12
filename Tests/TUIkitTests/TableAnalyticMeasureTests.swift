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

    @Test("Multi-line tables keep the render-based measure (still equal)")
    func multiLineUnchanged() {
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
}
