//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollExtentPrecisionTests.swift
//
//  A List/Table whose rows span multiple lines meters its scrollbar in LINES,
//  which historically meant measuring every row — wrapping thousands of
//  off-screen cells per frame to place one thumb. `ScrollExtentPrecision`
//  makes that sampled by default, so these tests pin the two things an
//  estimate must not break: the ends of the travel (thumb flush at top and
//  bottom), and the cost (O(1) in the row count, not O(rows)).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

private struct ExtentRow: Identifiable {
    let id: Int
    let name: String
    let detail: String
}

@MainActor
@Suite("Scroll extent precision")
struct ScrollExtentPrecisionTests {

    /// A height oracle that records how many rows were actually asked about.
    private final class Heights {
        let values: [Int]
        private(set) var asked: Set<Int> = []
        init(_ values: [Int]) { self.values = values }
        func height(_ index: Int) -> Int {
            asked.insert(index)
            return values[index]
        }
        var total: Int { values.reduce(0, +) }
    }

    /// Row heights that repeat 1,2,3,4 — enough variety that a wrong estimate
    /// shows, without the mean being an integer coincidence.
    private func varyingHeights(_ count: Int) -> [Int] {
        (0..<count).map { $0 % 4 + 1 }
    }

    // MARK: - Exactness

    @Test("Exact precision sums every row, on screen or not")
    func exactSumsEverything() {
        let heights = Heights(varyingHeights(1000))
        let metrics = ScrollExtentEstimator.lineMetrics(
            visible: 400..<410, count: 1000, topClip: 0, precision: .exact,
            height: heights.height)

        #expect(metrics.extent == heights.total)
        #expect(metrics.offset == heights.values[0..<400].reduce(0, +))
        #expect(heights.asked.count == 1000, "exact must measure every row")
    }

    @Test("Small collections are measured exactly whatever the precision")
    func smallCollectionsAreAlwaysExact() {
        let count = ScrollExtentPrecision.exactRowLimit
        let heights = Heights(varyingHeights(count))
        let approximate = ScrollExtentEstimator.lineMetrics(
            visible: 10..<20, count: count, topClip: 0, precision: .approximate,
            height: heights.height)
        let exact = ScrollExtentEstimator.lineMetrics(
            visible: 10..<20, count: count, topClip: 0, precision: .exact,
            height: heights.height)

        #expect(approximate == exact)
        #expect(approximate.extent == heights.total)
    }

    @Test("Uniform rows estimate exactly — the sample cannot be wrong")
    func uniformRowsAreExactEitherWay() {
        let count = 5000
        let heights = Heights(Array(repeating: 3, count: count))
        let metrics = ScrollExtentEstimator.lineMetrics(
            visible: 100..<110, count: count, topClip: 0, precision: .approximate,
            height: heights.height)

        #expect(metrics.extent == count * 3)
        #expect(metrics.offset == 100 * 3)
    }

    // MARK: - Cost

    @Test("Approximate is O(1) in the row count")
    func approximateDoesNotWalkEveryRow() {
        let count = 20_000
        let heights = Heights(varyingHeights(count))
        _ = ScrollExtentEstimator.lineMetrics(
            visible: 9000..<9010, count: count, topClip: 0, precision: .approximate,
            height: heights.height)

        // The ten visible rows, plus the fixed sample. Nothing that grows with
        // `count` — this is the whole point of the change, and the assertion
        // that fails if someone reinstates a full walk.
        #expect(heights.asked.count <= 10 + ScrollExtentPrecision.sampleCount)
        #expect(heights.asked.count < count / 100)
    }

    @Test("The sample does not shift as the view scrolls")
    func estimateIsStableAcrossScrollPositions() {
        let count = 4000
        let values = varyingHeights(count)
        // A window of constant total height, slid along, must report a
        // constant extent: a thumb that resized mid-drag would be a defect.
        let extents = stride(from: 0, to: 3900, by: 100).map { start in
            ScrollExtentEstimator.lineMetrics(
                visible: start..<(start + 8), count: count, topClip: 0,
                precision: .approximate, height: { values[$0] }
            ).extent
        }
        let spread = (extents.max() ?? 0) - (extents.min() ?? 0)
        #expect(
            spread <= 4,
            "extent wandered by \(spread) lines as the window slid: \(extents)")
    }

    // MARK: - The ends of the travel

    @Test("Scrolled to the top the offset is zero", arguments: [ScrollExtentPrecision.approximate, .exact])
    func topOfTravelIsPinned(precision: ScrollExtentPrecision) {
        let values = varyingHeights(3000)
        let metrics = ScrollExtentEstimator.lineMetrics(
            visible: 0..<9, count: values.count, topClip: 0, precision: precision,
            height: { values[$0] })
        #expect(metrics.offset == 0)
    }

    @Test(
        "At the furthest scroll the thumb reaches the bottom",
        arguments: [ScrollExtentPrecision.approximate, .exact])
    func bottomOfTravelIsPinned(precision: ScrollExtentPrecision) {
        let values = varyingHeights(3000)
        let viewport = 20

        // Walk back from the last row until the window fills the viewport —
        // the furthest a scrollable can go.
        var start = values.count
        var used = 0
        while start > 0, used + values[start - 1] <= viewport {
            used += values[start - 1]
            start -= 1
        }
        let metrics = ScrollExtentEstimator.lineMetrics(
            visible: start..<values.count, count: values.count, topClip: 0,
            precision: precision, height: { values[$0] })

        #expect(
            metrics.offset + used == metrics.extent,
            """
            thumb short of the bottom: offset \(metrics.offset) + visible \(used) \
            != extent \(metrics.extent)
            """)
    }

    @Test("A line-granularity top clip counts toward the offset, not the extent")
    func topClipMovesTheThumbWithoutResizingIt() {
        let values = varyingHeights(3000)
        let unclipped = ScrollExtentEstimator.lineMetrics(
            visible: 500..<510, count: values.count, topClip: 0, precision: .approximate,
            height: { values[$0] })
        let clipped = ScrollExtentEstimator.lineMetrics(
            visible: 500..<510, count: values.count, topClip: 2, precision: .approximate,
            height: { values[$0] })

        #expect(clipped.offset == unclipped.offset + 2)
        #expect(clipped.extent == unclipped.extent, "clipped lines are hidden, not absent")
    }

    // MARK: - Through a real Table

    /// Rows whose `name` wraps to the SAME number of lines in the fixed column
    /// below — so the sampled mean is the true mean and the two precisions must
    /// agree cell for cell. Any drift in the estimator's arithmetic (a topClip
    /// counted twice, an off-by-one on the window bounds) shows up as a
    /// different bar even though the estimate itself is perfect.
    private func uniformRows(_ count: Int) -> [ExtentRow] {
        (0..<count).map { index in
            ExtentRow(id: index, name: "alpha beta gamma", detail: "detail \(index)")
        }
    }

    private func render(_ data: [ExtentRow], precision: ScrollExtentPrecision) -> FrameBuffer {
        let table = Table(data, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \ExtentRow.name).lineLimit(4).width(.fixed(7))
            TableColumn("Detail", value: \ExtentRow.detail)
        }
        .scrollbarVisibility(.visible)
        return renderToBuffer(
            table,
            context: makeRenderContext(width: 44, height: 18) { env, _ in
                env.scrollExtentPrecision = precision
            })
    }

    @Test("A multi-line Table draws the same bar under either precision")
    func tableBarMatchesWhenTheEstimateIsPerfect() {
        let data = uniformRows(600)
        #expect(render(data, precision: .approximate).lines == render(data, precision: .exact).lines)
    }

    @Test("Precision changes nothing when every row is one line")
    func singleLineRowsAreUnaffected() {
        let data = uniformRows(600)
        let table = Table(data, selection: .constant(Int?.none)) {
            TableColumn("Detail", value: \ExtentRow.detail)
        }
        .scrollbarVisibility(.visible)

        let approximate = renderToBuffer(
            table,
            context: makeRenderContext(width: 44, height: 18) { env, _ in
                env.scrollExtentPrecision = .approximate
            })
        let exact = renderToBuffer(
            table,
            context: makeRenderContext(width: 44, height: 18) { env, _ in
                env.scrollExtentPrecision = .exact
            })
        #expect(approximate.lines == exact.lines)
    }
}
