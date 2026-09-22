//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTwoAxisWindowTests.swift
//
//  Two things a `LazyVStack` inside a two-axis `ScrollView` gets wrong, pinned
//  together because they are the same knot and neither can be fixed alone.
//
//  1. IT WALKS EVERY ROW. `renderedContent` publishes its visible-row window
//     only when the horizontal axis is off, on the reasoning that "horizontal
//     scrolling has no row concept" — true of the horizontal axis, and not of
//     the rows the vertical one still has. `app-shapes/code-editor` asks about
//     2,000 rows a frame to draw 37. It is cheaper than it sounds: the row memo
//     serves 1,963 of them, so a settled editor is 4.4 ms, and what the window
//     would save is the LOOKUPS rather than the composition.
//
//  2. A WIDE ROW OUT OF SIGHT IS UNREACHABLE. The horizontal extent comes from
//     `measureNaturalExtent(along: .horizontal)` — an UNBOUNDED width ask under
//     a height budget that reaches every row — and the windowed stack answers it
//     from a sample: the first sixteen rows, for a collection over 256. A
//     120-cell row 200 rows down therefore reports nothing; the content measures
//     8 wide, renders 8 wide, draws no horizontal bar, and that row's tail
//     cannot be scrolled to at any offset. The EAGER `VStack` of the same
//     content answers 120, because it measures every child, so this is the twins
//     disagreeing rather than a property of laziness.
//
//  WHAT THE FIX COSTS, measured properly on 2026-09-22 — and the first attempt
//  at this number was wrong in a way worth recording, because the mistake is
//  reusable. It read "none of which the measure memo catches (0.2% hits)", and
//  concluded the work was uncacheable. The 0.2% is the hit rate the Stress
//  harness prints, and that counter is `RenderCache.MeasureKey` ALONE — per-pass
//  scratch, emptied by every `beginRenderPass()`. A walk that measures each of
//  2,000 rows exactly once a frame hands it 2,000 lookups and no hits BY
//  CONSTRUCTION. It was never evidence about caching; it was evidence that the
//  walk walks. (The corroboration is the per-type table: paths that measure a
//  row twice a pass sit at 50%, paths that measure it once sit at 0%.)
//
//  The cache that could serve it is the other one — `RenderCache.SizeKey`, the
//  cross-frame table `_ListCore.widestRowWidth` and `Table.fitWidth` already use
//  to keep ONE integer against the rows' data. Built for a lazy stack
//  (`_VStackCore.contentWidthOverAllRows`, on the `two-axis-exact-width` branch)
//  and measured paired, 10 reps, release, 120x40:
//
//      app-shapes/code-editor           4,400 →   4,847 µs    +9.9%  (CI  +9.3 …  +10.5)
//      app-shapes/code-editor-tailing  50,311 → 130,636 µs  +159.4%  (CI +158.1 … +161.6)
//
//  The same code, twice, and the difference between the two rows is entirely
//  whether the memo can serve: a settled document keys on an unchanging
//  collection and pays only the machinery, a growing one re-walks every frame
//  and pays 2.6×. So the answer to "can a width memo work where the measure memo
//  could not" is yes — and a data-keyed memo is exactly as good as its data is
//  stable, which is why `code-editor-tailing` now exists to say so.
//
//  NOT LANDED. +159% on a growing document is the same class of regression the
//  14.6× was, and the cheaper design is visible from here: the width over all
//  rows is a MAXIMUM, so a collection that grew by appending needs only its new
//  rows measured. Making that sound needs an "does this data extend that data"
//  question the extractors do not answer today (`ForEach` could, for a `Range`
//  outright and for an `Equatable` collection by a prefix compare that costs a
//  memcmp against 2,000 view measures). That is a caching design of its own, and
//  it is noted for the owner rather than guessed at here.
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
        anchor: UnitPoint?, tally: RowRenderTally, wideRow: Int = 0, width: Int = 40
    ) -> FrameBuffer {
        let content = ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<Self.rows, id: \.self) { index in
                    TallyRow(
                        index: index, tally: tally, width: Self.wideRowWidth, wideRow: wideRow)
                }
            }
        }
        let view = anchor.map { AnyView(content.defaultScrollAnchor($0)) } ?? AnyView(content)
        let context = RenderContext(
            availableWidth: width, availableHeight: Self.viewport, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
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
        withKnownIssue("the window measure samples the width; see the file comment") {
            #expect(
                buffer.lines.last?.stripped.contains("\u{25C0}") == true,
                "no horizontal bar for the wide row at 200: \(buffer.lines.last?.stripped ?? "")")
        }
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
