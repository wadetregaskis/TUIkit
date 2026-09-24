//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewIdealBarTests.swift
//
//  A scroll view's ideal size counts the bars it will draw. A scrollbar is
//  chrome the CONTENT knows nothing about: it takes a column (vertical) or a
//  row (horizontal) out of the viewport. The ideal size used to be the
//  content's alone, so a parent that sizes to it — a `TabView` panel, a row in
//  a lazy stack — handed the scroll view exactly its content's size, and the
//  bar either squeezed the content by a cell or was clipped off, on every
//  frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Counts its own measures: a row whose `sizeThatFits` says how many times the
/// content was walked.
private final class MeasureCount: @unchecked Sendable {
    var value = 0
}

private struct CountedRow: View, Layoutable {
    let text: String
    let count: MeasureCount
    var body: Never { fatalError("CountedRow renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        count.value += 1
        return ViewSize.fixed(text.count, 1)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: [text])
    }
}

@MainActor
@Suite("A ScrollView's ideal size counts its bars")
struct ScrollViewIdealBarTests {

    // MARK: Fixtures

    /// Two frames, the way the run loop draws them, so nothing here depends on
    /// a first-frame special case.
    private func render(_ view: some View, width: Int, height: Int) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.stateStorage = StateStorage()
        environment.applyRuntimeServices(from: tui)
        var context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        _ = renderToBuffer(view, context: context)
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    private func measureContext(width: Int, height: Int) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.stateStorage = StateStorage()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// `count` rows of "row N" from `first`: every row from 10 up is six cells
    /// wide, so a column taken out of six squeezes them visibly.
    private func rows(from first: Int = 0, count: Int) -> ScrollView<some View> {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(first..<(first + count), id: \.self) { Text("row \($0)") }
            }
        }
    }

    /// A strip of twenty items, 131 cells of content that does not wrap: the
    /// row HStack squeezes rather than folds, so its height is one line at any
    /// width.
    private var strip: ScrollView<some View> {
        ScrollView(.horizontal) {
            HStack(spacing: 1) { ForEach(0..<20, id: \.self) { Text("item\($0)") } }
        }
    }

    private func dump(_ lines: [String]) -> String {
        lines.map { "[\($0)]" }.joined(separator: "\n")
    }

    /// Both shapes of the ideal-width ask: neither axis stated — what a stack
    /// and a `TabView` send, where the content's own measure answers the bar —
    /// and the height stated, where a second measure has to.
    nonisolated private static let askShapes = [
        ProposedSize(width: nil, height: nil), ProposedSize(width: nil, height: 10),
    ]

    // MARK: The measure contract

    /// The vertical bar widens the ideal width by its column exactly when it
    /// will be drawn: `.automatic` when the content overflows, `.visible`
    /// always, and never under `.hidden` or the `.text` style — which takes
    /// lines, not a column.
    @Test(
        "The ideal width includes the vertical bar's column exactly when the bar is drawn",
        arguments: [
            // (rows, visibility, style, expected width)
            (50, ScrollIndicatorVisibility.automatic, ScrollIndicatorStyle.scrollbar, 7),
            (3, .automatic, .scrollbar, 5),
            (50, .visible, .scrollbar, 7),
            (3, .visible, .scrollbar, 6),
            (50, .hidden, .scrollbar, 6),
            (50, .never, .scrollbar, 6),
            (50, .automatic, .text, 6),
            (50, .visible, .text, 6),
        ])
    func idealWidthCountsTheBar(
        rowCount: Int, visibility: ScrollIndicatorVisibility, style: ScrollIndicatorStyle,
        expected: Int
    ) {
        let view = rows(count: rowCount).scrollIndicators(visibility).scrollIndicatorStyle(style)
        for proposal in Self.askShapes {
            let size = measureChild(view, proposal: proposal, context: measureContext(width: 40, height: 10))
            #expect(
                size.width == expected,
                "\(rowCount) rows, \(visibility), \(style), proposal \(proposal): width \(size.width)")
        }
    }

    /// Asking whether the content overflows is the content's own measure, one
    /// row taller than the space: the answer is still the size that space
    /// gives, not a row more of it.
    @Test(
        "The ideal height is the content's, clamped to the space, not a row past it",
        arguments: [(9, 9), (10, 10), (11, 10), (50, 10)])
    func idealHeightIsNotTheProbe(rowCount: Int, expected: Int) {
        let size = measureChild(
            rows(count: rowCount), proposal: ProposedSize(width: nil, height: nil),
            context: measureContext(width: 40, height: 10))
        #expect(size.height == expected, "\(rowCount) rows in 10: height \(size.height)")
    }

    /// The cost, pinned. Asked with no height stated, the ideal size is ONE walk
    /// of the content, as it was before it counted the bar: the measure that
    /// sizes the content is offered one row more than the space, and says
    /// whether it overflows. A separate measure for the bar was a whole extra
    /// walk of an eager stack on every frame, wherever the answer is not taken
    /// — a `VStack` lays a scroll view out across its width whatever width it
    /// answers — and cost `scrolleager` +22.6%.
    @Test("Asked with no height, the bar costs no walk of the content", arguments: [5, 50])
    func theBarCostsNoWalk(rowCount: Int) {
        let count = MeasureCount()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { CountedRow(text: "row \($0)", count: count) }
            }
        }
        let size = measureChild(
            view, proposal: ProposedSize(width: nil, height: nil),
            context: measureContext(width: 40, height: 10))
        #expect(size.width == (rowCount > 10 ? 7 : 5), "width \(size.width)")
        #expect(count.value == rowCount, "\(rowCount) rows were measured \(count.value) times")
    }

    /// The answer is only worth anything if the render agrees with it: placed at
    /// exactly the width it answered, the view draws a bar exactly when the
    /// answer made room for one. The ideal-size question is answered with one
    /// measure bounded by the viewport, where the render climbs the whole
    /// natural-extent ladder, so this pins the two together where they could
    /// part: content a row short of the viewport, exactly its height, a row
    /// over it.
    @Test(
        "Placed at its ideal width, a scroll view draws the bar the answer made room for",
        arguments: [9, 10, 11], askShapes)
    func renderAgreesWithTheAnswer(rowCount: Int, proposal: ProposedSize) {
        let view = rows(count: rowCount)
        // "row 0" … "row 9" are five cells; "row 10" is six.
        let contentWidth = rowCount > 10 ? 6 : 5
        let ideal = measureChild(
            view, proposal: proposal, context: measureContext(width: 40, height: 10)
        ).width
        let lines = render(view, width: ideal, height: 10)
        let drawsBar = lines.contains { $0.contains("▲") || $0.contains("▼") }
        #expect(ideal == contentWidth + (rowCount > 10 ? 1 : 0), "\(rowCount) rows: ideal \(ideal)")
        #expect(drawsBar == (ideal > contentWidth), "\(rowCount) rows at \(ideal):\n\(dump(lines))")
    }

    /// The same agreement through a lazy stack of three-row rows, whose pitch
    /// does not divide the one-row-over budget the overflow test measures at:
    /// four rows are twelve, over a ten-row viewport, though only three of them
    /// fit the eleven-row budget. The stack reports the budget when it runs
    /// past it (the natural-extent ladder's own contract), not the nine rows of
    /// the whole rows that fit.
    @Test(
        "Placed at its ideal width, a scroll view of a lazy stack agrees with the answer",
        arguments: [3, 4], askShapes)
    func renderAgreesThroughALazyStack(rowCount: Int, proposal: ProposedSize) {
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { Text("row \($0)").frame(height: 3) }
            }
        }
        let ideal = measureChild(
            view, proposal: proposal, context: measureContext(width: 40, height: 10)
        ).width
        let lines = render(view, width: ideal, height: 10)
        let drawsBar = lines.contains { $0.contains("▲") || $0.contains("▼") }
        #expect(ideal == (rowCount > 3 ? 6 : 5), "\(rowCount) rows: ideal \(ideal)")
        #expect(drawsBar == (ideal > 5), "\(rowCount) rows at \(ideal):\n\(dump(lines))")
    }

    /// The same agreement for content that takes whatever height it is offered:
    /// the render's ladder and the bounded measure must read it alike, whichever
    /// way that is.
    @Test(
        "Placed at its ideal width, a scroll view of height-filling content agrees with it",
        arguments: askShapes)
    func renderAgreesForFillingContent(proposal: ProposedSize) {
        let view = ScrollView { Text("x").frame(maxHeight: .infinity) }
        let ideal = measureChild(
            view, proposal: proposal, context: measureContext(width: 40, height: 10)
        ).width
        let lines = render(view, width: ideal, height: 10)
        let drawsBar = lines.contains { $0.contains("▲") || $0.contains("▼") }
        #expect(drawsBar == (ideal > 1), "ideal \(ideal):\n\(dump(lines))")
        #expect(lines.contains { $0.contains("x") }, "the content was squeezed out:\n\(dump(lines))")
    }

    /// A stated width is the stated width: the bar comes out of it, as it
    /// always has, rather than being added to it.
    @Test("A proposed width is not widened")
    func proposedWidthIsKept() {
        let size = measureChild(
            rows(count: 50), proposal: ProposedSize(width: 12, height: nil),
            context: measureContext(width: 40, height: 10))
        #expect(size.width == 12)
    }

    /// The bar never pushes the answer past the space there is: content that
    /// already fills the width gives up the column instead.
    @Test("The bar does not widen the answer past the available width")
    func barIsCappedAtTheAvailableWidth() {
        let size = measureChild(
            rows(count: 50), proposal: ProposedSize(width: nil, height: 10),
            context: measureContext(width: 6, height: 10))
        #expect(size.width == 6, "a 6-cell content in 6 available cells: \(size.width)")
    }

    /// The horizontal twin: a bottom bar heightens the ideal height by its row
    /// exactly when it will be drawn. The `.text` style is vertical only, so
    /// the horizontal bar stands under it.
    @Test(
        "The ideal height includes the horizontal bar's row exactly when the bar is drawn",
        arguments: [
            // (width, visibility, style, expected height)
            (30, ScrollIndicatorVisibility.automatic, ScrollIndicatorStyle.scrollbar, 2),
            (200, .automatic, .scrollbar, 1),
            (30, .visible, .scrollbar, 2),
            (200, .visible, .scrollbar, 2),
            (30, .hidden, .scrollbar, 1),
            (30, .automatic, .text, 2),
        ])
    func idealHeightCountsTheBar(
        width: Int, visibility: ScrollIndicatorVisibility, style: ScrollIndicatorStyle,
        expected: Int
    ) {
        let view = strip.scrollIndicators(visibility).scrollIndicatorStyle(style)
        let size = measureChild(
            view, proposal: ProposedSize(width: width, height: nil),
            context: measureContext(width: width, height: 10))
        #expect(size.height == expected, "\(width) wide, \(visibility), \(style): height \(size.height)")
    }

    // MARK: Drawn

    /// The reported shape. A `TabView` sizes its panel to its widest tab, so
    /// with a strip no wider than the content the panel IS the scroll view's
    /// ideal width. The bar is drawn, and it took its column out of the
    /// content: every six-cell row was squeezed into five ("row 1" for
    /// "row 10").
    @Test(
        "A scroll view in a TabView keeps its rows whole",
        arguments: [TabViewStyle.compact, .bordered])
    func tabViewKeepsTheRowsWhole(style: TabViewStyle) {
        let lines = render(
            TabView(selection: .constant(0)) {
                Tab("A", value: 0) { rows(from: 10, count: 50) }
            }
            .tabViewStyle(style),
            width: 30, height: 12)
        #expect(lines.contains { $0.contains("row 10") }, "row 10 was squeezed:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("row 11") }, "row 11 was squeezed:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("▲") }, "no bar:\n\(dump(lines))")
    }

    /// The same panel around a view that scrolls both ways. Its rows are
    /// exactly as wide as its ideal width, so they fit — until the vertical bar
    /// took a column the answer had not counted, pushed the widest row past the
    /// viewport, and called up a horizontal bar that then took a row as well.
    @Test("A two-axis scroll view in a TabView draws no bar it does not need")
    func tabViewTwoAxisViewDrawsNoSpuriousBar() {
        let lines = render(
            TabView(selection: .constant(0)) {
                Tab("Both", value: 0) {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<40, id: \.self) { Text("row \($0) wide wide") }
                        }
                    }
                }
            },
            width: 30, height: 12)
        #expect(
            !lines.contains { $0.contains("◀") || $0.contains("▶") },
            "a horizontal bar for rows that fit:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("row 10 wide wide") }, "row 10 was cut:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("▲") }, "no vertical bar:\n\(dump(lines))")
    }

    /// The horizontal twin, drawn: a lazy stack gives each row its ideal
    /// height, and a strip's ideal height left out its bar's row — so the bar
    /// was clipped off and the strip gave no sign it scrolled.
    @Test("A horizontal strip in a lazy stack keeps its scrollbar")
    func lazyStackKeepsTheStripsBar() {
        let lines = render(
            ScrollView {
                LazyVStack(spacing: 0) {
                    Text("top")
                    strip
                    Text("next")
                }
            },
            width: 30, height: 10)
        #expect(
            lines.contains { $0.contains("◀") && $0.contains("▶") },
            "no horizontal bar:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("item0") }, "the strip is gone:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("next") }, "the row below is gone:\n\(dump(lines))")
    }
}
