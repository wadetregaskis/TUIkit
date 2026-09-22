//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTwoAxisWindowTests.swift
//
//  What a `LazyVStack` inside a two-axis `ScrollView` gets wrong — one of the
//  two fixed, and the other left with its reason written down.
//
//  FIXED — A WIDE ROW OUT OF SIGHT WAS UNREACHABLE. The horizontal extent comes
//  from `measureNaturalExtent(along: .horizontal)`, an unbounded width ask, and
//  the windowed stack answered it from a sample: the first SIXTEEN rows, for
//  any collection over 256, wherever the viewport was. So the cut-off was an
//  ordinal and it did not move — measured, on 400 rows in a 40-column viewport:
//
//      wide row at 15   bar drawn, tail reachable
//      wide row at 16   no bar
//      wide row at 200  no bar at the top, and none at the bottom either
//      wide row at 399  no bar with the view anchored to .bottom — where that
//                       row is ON SCREEN, drawn truncated, ending in an
//                       ellipsis that nothing can scroll to
//
//  On `app-shapes/code-editor` the content measured 135 cells against a true
//  142, so fifteen of the twenty-two columns of horizontal travel the document
//  needs were reachable and the tails of its longest lines were not. The eager
//  `VStack` of the same content answers correctly, so this was the twins
//  disagreeing rather than a property of laziness.
//
//  The answer is now taken over every row, by `StackContentWidth.swift`, which
//  owns the whole design: a ceiling the walk stops at, a kept answer, a kept
//  PREFIX that an appended collection extends rather than re-derives, and the
//  walk itself only when none of those can answer. Paired A/B, 12 reps,
//  release, 120x40, against the frame that had the bug:
//
//      app-shapes/code-editor           4,422 →  4,669 µs    +5.4%
//      app-shapes/code-editor-tailing  52,000 → 36,811 µs   −29.2%
//
//  The growing document comes out FASTER than it was with the bug in, because
//  the walk shares a commit with the wrap memo it would otherwise have blown
//  (see `TextWrapping.unwrapped`). Taken alone the walk is +4.6% and +18.4%,
//  and the naive version of it — no ceiling, no kept prefix, one entry per
//  ladder rung — was +9.9% and +159.4%.
//
//  STILL OPEN — IT WALKS EVERY ROW TO DRAW A SCREENFUL. `renderedContent`
//  publishes its visible-row window only when the horizontal axis is off, on
//  the reasoning that "horizontal scrolling has no row concept" — true of the
//  horizontal axis, and not of the rows the vertical one still has.
//  `app-shapes/code-editor` builds 2,000 rows a frame to draw 37. It is
//  cheaper than it sounds: the row memo serves 1,963 of them. What kept it
//  open was that the horizontal extent was metered by what the eager render
//  produced, so windowing the vertical axis would have taken the wide row's
//  extent with it; that is no longer true — the extent is measured above,
//  independently of what the render drew — so the remaining question is
//  whether windowing PAYS, which nobody has measured.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

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
    /// A `withKnownIssue` FAILS when the issue does not occur, so the day the
    /// window is published for two-axis scroll views this test fails and says
    /// where to look — including at its neighbour below, which is the reason it
    /// is not published today.
    @Test("Every row is built, however few are on screen")
    func doesNotWindowVertically() {
        let tally = RowRenderTally()
        _ = render(anchor: UnitPoint?.none, tally: tally)
        #expect(tally.rendered.contains(0), "the first row is on screen and was not built")
        withKnownIssue("a two-axis ScrollView renders its whole content; see the file comment") {
            #expect(
                tally.rendered.count < Self.rows / 4,
                "built \(tally.rendered.count) of \(Self.rows) rows")
        }
    }

    /// Nothing on screen at the top knows the content is 120 cells wide — the
    /// one row that is lives 200 rows down, outside the band the render draws
    /// and outside the sixteen-row sample the measure answers from. So no
    /// horizontal bar is drawn, and a bar that is not drawn is a row whose tail
    /// cannot be reached at any offset, not a missing decoration.
    ///
    /// The assertion below is the one the fix in the file comment makes pass;
    /// the control after it is the EAGER `VStack` of the same content, which
    /// answers 120 — so this is about laziness and not about the rows.
    @Test("A wide row far from the viewport still widens the content")
    func wideRowInTheMiddleIsReachable() {
        let tally = RowRenderTally()
        let buffer = render(anchor: UnitPoint?.none, tally: tally, wideRow: 200)
        #expect(
            buffer.lines.last?.stripped.contains("\u{25C0}") == true,
            "no horizontal bar for the wide row at 200: \(buffer.lines.last?.stripped ?? "")")
        // The eager twin of the same content, which does measure every child —
        // so the assertion above is about laziness and not about the rows.
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
