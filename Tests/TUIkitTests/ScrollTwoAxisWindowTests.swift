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
//  2. A WIDE ROW OUT OF SIGHT IS UNREACHABLE. The window measure answers width
//     from a sample: the rows the height budget reaches, capped at 64. A
//     120-cell row 200 rows down therefore reports nothing — the content
//     measures 8 wide, renders 8 wide, draws no horizontal bar, and that row's
//     tail cannot be scrolled to at any offset. The EAGER `VStack` of the same
//     content answers 120, because it measures every child, so this is the
//     twins disagreeing rather than a property of laziness.
//
//  The knot: the horizontal extent is metered by the RENDERED buffer's width,
//  which is the only thing making (1) harmless. Fixing (2) needs a width
//  measured over every row, and then (1) is safe. Both were implemented and
//  measured on 2026-09-22, on `app-shapes/code-editor` (2,000 syntax-coloured
//  lines, release, 120x40):
//
//      today (wrong)                    4.4 ms    1.9 composed, 1,963 served
//      exact width + vertical window   64.7 ms    1.9 composed,    39 served
//
//  Correctness costs 14.6× here, and the windowing does not begin to pay for
//  it, because the thing the window removes is already nearly free: the row
//  memo serves the rows it walks. What the exact width costs is a MEASURE of
//  every row every frame — a view build, two reflection walks and a measure,
//  none of which the measure memo catches (0.2% hits) — and that is strictly
//  more than the memo lookups it saves.
//
//  So the fix has to be a cheap exact width, not this one: per-ordinal row
//  widths kept across frames, which is a caching design of its own (the records
//  exist in `StackWindowState`, seeded only for VISITED rows and answered per
//  prefix). Noted for the owner; nothing is landed.
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

    /// What the windowing would cost, and why it is not taken.
    ///
    /// Nothing on screen at the top knows the content is 120 cells wide — the
    /// one row that is lives 200 rows down. Today the full render finds it and
    /// the bar is drawn. Metering the axis from a windowed measure does not, and
    /// the wide row's tail becomes unreachable.
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
