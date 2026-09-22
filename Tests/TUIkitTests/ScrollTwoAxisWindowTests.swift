//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTwoAxisWindowTests.swift
//
//  Two things a `LazyVStack` inside a two-axis `ScrollView` got wrong. They
//  were one knot, and they are both untied.
//
//  1. A WIDE ROW OUT OF SIGHT WAS UNREACHABLE. The horizontal extent comes from
//     `measureNaturalExtent(along: .horizontal)`, an unbounded width ask, and
//     the windowed stack answered it from a sample: the first SIXTEEN rows, for
//     any collection over 256, wherever the viewport was. So the cut-off was an
//     ordinal and it did not move — measured, on 400 rows in a 40-column
//     viewport:
//
//         wide row at 15   bar drawn, tail reachable
//         wide row at 16   no bar
//         wide row at 200  no bar at the top, and none at the bottom either
//         wide row at 399  no bar with the view anchored to .bottom — where
//                          that row is ON SCREEN, drawn truncated, ending in an
//                          ellipsis that nothing can scroll to
//
//     Answered over every row now, by `StackContentWidth.swift`.
//
//  2. IT DREW EVERY ROW TO SHOW A SCREENFUL. `renderedContent` published its
//     visible-row window only when the horizontal axis was off, on the
//     reasoning that "horizontal scrolling has no row concept" — true of the
//     horizontal axis, and not of the rows the vertical one still has.
//
//  What tied them together: the horizontal extent used to be metered from the
//  RENDERED buffer's width, so windowing the rows would have taken the width of
//  every row outside the band with it, and (1) would have gone from bad to
//  total. Fixing (1) is what made (2) safe — `syncHorizontalAxis` meters from
//  the measure now — and (2) is where the whole cost of (1) comes back, several
//  times over:
//
//      app-shapes/code-editor           4,648 → 395 µs   −91.5%   2000 → 39 rows
//      app-shapes/code-editor-tailing  35,810 → 976 µs   −97.3%   2066 → 40 rows
//
//  and −6.8 MB of resident memory. Against the frame that had the bug in it,
//  before any of this, the settled editor is −91% and the growing one −98%, with
//  byte-identical output on every scenario in the corpus.
//
//  Still refused on a horizontal-capable view: a `scrollTo` seek, which rides
//  this window. It has never worked there, and turning it on is a parity item
//  of its own (`SwiftUI-semantic-audit-2026-08.md` names it) rather than a
//  by-product of this.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Which rows a pass touched, split by what the pass was for.
@MainActor
final class TwoAxisPassCounter {
    var measured: Set<Int> = []
    var rendered: Set<Int> = []
    func reset() {
        measured.removeAll()
        rendered.removeAll()
    }
}

/// Counts the rows whose body actually ran.
@MainActor
final class RowRenderTally {
    private(set) var rendered: Set<Int> = []
    func note(_ index: Int) { rendered.insert(index) }
    func reset() { rendered.removeAll() }
}

/// A row that says when it was built. `Text` alone cannot: the whole question
/// is which rows the lazy stack asked for.
private struct TallyRow: View {
    let index: Int
    let tally: RowRenderTally
    let width: Int
    /// Which row is the wide one — the row that settles the horizontal extent,
    /// and is on screen only when the viewport is over it.
    var wideRow = 0

    var body: some View {
        tally.note(index)
        return Text(String(repeating: "\(index % 10)", count: index == wideRow ? width : 8))
    }
}

@MainActor
@Suite("A two-axis ScrollView and its rows")
struct ScrollTwoAxisWindowTests {
    private static let rows = 400
    private static let viewport = 12
    private static let wideRowWidth = 120

    private func render(
        anchor: UnitPoint?, tally: RowRenderTally, wideRow: Int = 0, width: Int = 40,
        rows: Int? = nil, tuiContext: TUIContext? = nil
    ) -> FrameBuffer {
        let count = rows ?? Self.rows
        let content = ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    TallyRow(
                        index: index, tally: tally, width: Self.wideRowWidth, wideRow: wideRow)
                }
            }
        }
        let view = anchor.map { AnyView(content.defaultScrollAnchor($0)) } ?? AnyView(content)
        // A caller that supplies the context is driving several frames through
        // ONE cache, which is the only way to exercise a cross-frame memo; the
        // default is a private cache per render, as every other test here wants.
        guard let tuiContext else {
            let context = RenderContext(
                availableWidth: width, availableHeight: Self.viewport, tuiContext: TUIContext()
            ).isolatingRenderCache()
            return renderToBuffer(view, context: context)
        }
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let buffer = renderToBuffer(
            view,
            context: RenderContext(
                availableWidth: width, availableHeight: Self.viewport,
                environment: environment, tuiContext: tuiContext))
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer
    }

    /// The cost, stated as a count rather than a clock.
    ///
    /// Counted on the RENDER pass alone, with the render cache cleared between
    /// frames — which is the state any app is in after a `@State` write, and
    /// also the state that forces every row's body to run rather than be served
    /// from the row memo, so the count means something.
    ///
    /// The MEASURE pass legitimately touches every row here and is not asserted
    /// on: a whole-cache clear takes the content-width record with it
    /// (`RenderCache.clearGeneration`), so the exact width is walked again. That
    /// is the trade — a theme change costs a re-walk — and it is the reason this
    /// test says nothing about measures while `LazyMeasureProbeTests` says
    /// everything about them for the vertical-only case.
    @Test("Only the visible band is drawn, however many rows there are")
    func windowsVerticallyOnBothAxes() {
        let sink = TwoAxisPassCounter()
        let tuiContext = TUIContext()
        let view = ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<Self.rows, id: \.self) { index in
                    Text(String(repeating: "\(index % 10)", count: index == 200 ? 120 : 8))
                        .onRenderPass { pass in
                            if pass == .measure {
                                sink.measured.insert(index)
                            } else {
                                sink.rendered.insert(index)
                            }
                        }
                }
            }
        }
        func frame() {
            sink.reset()
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            _ = renderToBuffer(
                AnyView(view),
                context: RenderContext(
                    availableWidth: 40, availableHeight: Self.viewport,
                    environment: environment, tuiContext: tuiContext))
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }
        frame()
        for pass in 0..<3 {
            tuiContext.renderCache.clearAll()
            frame()
            #expect(
                sink.rendered.count <= Self.viewport + 4,
                "pass \(pass): drew \(sink.rendered.count) of \(Self.rows) rows")
            #expect(sink.rendered.contains(0), "pass \(pass): the band starts at the top")
            #expect(
                !sink.rendered.contains(200),
                "pass \(pass): the wide row 200 rows down is not drawn to be measured")
        }
    }

    /// Nothing on screen at the top knows the content is 120 cells wide — the
    /// one row that is lives 200 rows down, outside the band the render draws
    /// and outside the sixteen-row sample the measure used to answer from. So
    /// no horizontal bar was drawn, and a bar that is not drawn is a row whose
    /// tail cannot be reached at any offset, not a missing decoration.
    ///
    /// The control after it is the EAGER `VStack` of the same content, which
    /// answers 120 — so this is about laziness and not about the rows.
    @Test("A wide row far from the viewport still widens the content")
    func wideRowInTheMiddleIsReachable() {
        let tally = RowRenderTally()
        let buffer = render(anchor: UnitPoint?.none, tally: tally, wideRow: 200)
        #expect(
            buffer.lines.last?.stripped.contains("\u{25C0}") == true,
            "no horizontal bar for the wide row at 200: \(buffer.lines.last?.stripped ?? "")")
        let eager = renderToBuffer(
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Self.rows, id: \.self) { index in
                        TallyRow(
                            index: index, tally: tally, width: Self.wideRowWidth, wideRow: 200)
                    }
                }
            },
            context: RenderContext(
                availableWidth: 40, availableHeight: Self.viewport, tuiContext: TUIContext()
            ).isolatingRenderCache())
        #expect(
            eager.lines.last?.stripped.contains("\u{25C0}") == true,
            "the eager VStack lost the wide row too: \(eager.lines.last?.stripped ?? "")")
    }

    /// The memo's own rule, which is the whole reason the walk is affordable at
    /// all: the kept width is checked against the rows' DATA, so a stack whose
    /// collection changed gets a fresh walk rather than the old answer.
    ///
    /// Driven through ONE cache, because a per-render cache cannot serve a
    /// cross-frame memo and so cannot fail this way. The second collection is
    /// longer and its wide row is past the end of the first, so a kept answer
    /// would be the 8-cell one from before the data moved — and the bar would go
    /// missing exactly as it does without the walk.
    @Test("The exact width is re-walked when the collection changes")
    func theExactWidthFollowsTheData() {
        let tally = RowRenderTally()
        let tuiContext = TUIContext()
        let first = render(
            anchor: UnitPoint?.none, tally: tally, wideRow: 200, rows: 400,
            tuiContext: tuiContext)
        #expect(
            first.lines.last?.stripped.contains("\u{25C0}") == true,
            "no bar for 400 rows wide at 200: \(first.lines.last?.stripped ?? "")")
        let second = render(
            anchor: UnitPoint?.none, tally: tally, wideRow: 450, rows: 500,
            tuiContext: tuiContext)
        #expect(
            second.lines.last?.stripped.contains("\u{25C0}") == true,
            "no bar for 500 rows wide at 450: \(second.lines.last?.stripped ?? "")")
    }

    /// The gate's own regression test, and the reason it is not written in
    /// terms of the rows a budget reaches.
    ///
    /// The horizontal probe's HEIGHT budget is pinned at 4,096 lines
    /// (`naturalExtentStartingBudget(forVisible:)` — the horizontal ladder grows
    /// the WIDTH, not the height), so a first version of this fix asked "does
    /// the budget reach every row" and silently stopped firing above four
    /// thousand of them: identical output at 8,000 rows, differing at 2,000 and
    /// 4,000. That is the wrong way round — a collection too big for the budget
    /// is exactly the one whose wide row is furthest out of sight.
    @Test("A wide row is reachable in a collection larger than the height budget")
    func theFixSurvivesPastTheHeightBudget() {
        let tally = RowRenderTally()
        let buffer = render(
            anchor: UnitPoint?.none, tally: tally, wideRow: 4_500, rows: 5_000)
        #expect(
            buffer.lines.last?.stripped.contains("\u{25C0}") == true,
            "no bar for 5,000 rows wide at 4,500: \(buffer.lines.last?.stripped ?? "")")
    }

    /// The other half of the same trade: the extent must not move when the
    /// vertical offset does. A band-metered axis would resize the thumb as the
    /// wide row scrolled out of view.
    @Test("The horizontal bar is the same at the top and at the bottom")
    func horizontalExtentSurvivesScrolling() {
        let tally = RowRenderTally()
        let top = render(anchor: UnitPoint?.none, tally: tally)
        tally.reset()
        let bottom = render(anchor: .bottom, tally: tally)
        #expect(
            bottom.lines.last?.stripped == top.lines.last?.stripped,
            """
            the horizontal bar changed with the vertical offset:             top \(top.lines.last?.stripped ?? "") bottom \(bottom.lines.last?.stripped ?? "")
            """)
        #expect(
            top.lines.last?.stripped.contains("\u{25C0}") == true,
            "no horizontal scrollbar was drawn at all: \(top.lines.last?.stripped ?? "")")
    }
}
