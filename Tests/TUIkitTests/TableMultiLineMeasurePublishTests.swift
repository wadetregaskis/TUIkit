//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableMultiLineMeasurePublishTests.swift
//
//  What a MEASURE pass is allowed to leave on a multi-line table's handler.
//
//  The multi-line `Table` is the one control that renders itself to measure:
//  `analyticMultiLineSize` declines for an overflowing table with no scrollbar
//  (the default indicator style), so `sizeThatFits` falls back to
//  `renderToBuffer` at whatever height the parent proposed. Everything the
//  render path publishes to the persistent handler therefore gets published
//  from sizing passes too — and a sizing pass is not offered the height the
//  frame is drawn into. An eager `VStack` measures every child at the stack's
//  whole height and then renders each into its distributed share, so a table
//  sharing a stack with any sibling is measured a line taller than it is drawn,
//  every frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Multi-line table measure publishing")
struct TableMultiLineMeasurePublishTests {

    private struct Row: Identifiable, Sendable {
        let id: String
        /// Four lines' worth at the width below, one repeated letter per row —
        /// the same shape `TableMultiLineDragGeometryTests` uses, so a drawn
        /// line names the row it came from wherever in the wrap it is.
        var name: String {
            (0..<8).map { _ in String(repeating: id, count: 8) }.joined(separator: " ")
        }
    }

    /// An UNFRAMED multi-line table: the size it is asked for is the size it
    /// works in, which is the whole point here. (`.frame(height:)` pins the two
    /// passes together and hides everything this suite is about — which is why
    /// the drag-geometry fixture next door cannot cover it.)
    @MainActor
    private final class Fixture {
        var rows: [String]
        /// How many times the table has performed `onMove`.
        var moves = 0
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(rows: [String]) {
            self.rows = rows
            env.focusManager = FocusManager()
            // No bar: the shape `analyticMultiLineSize` declines to answer, and
            // so the only one that renders itself to measure.
            env.scrollIndicatorStyle = .text
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }
        var session: DragAndDropSession { tui.dragAndDropSession }
        var handler: ItemListHandler<String>? {
            env.focusManager?.currentFocused as? ItemListHandler<String>
        }

        var table: some View {
            Table(rows.map(Row.init), selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.name).lineLimit(4)
            }
            .onMove { offsets, destination in
                self.rows.move(fromOffsets: offsets, toOffset: destination)
                self.moves += 1
            }
        }

        func context(height: Int) -> RenderContext {
            RenderContext(
                availableWidth: 22, availableHeight: height, environment: env, tuiContext: tui)
        }

        /// Renders the table on its own, or as the second child of an eager
        /// `VStack` under a one-line header — which measures it at `height` and
        /// draws it at `height - 1`.
        @discardableResult
        func render(height: Int, underHeader: Bool = false) -> FrameBuffer {
            dispatcher.beginRenderPass()
            session.beginFrame()
            let buffer: FrameBuffer
            if underHeader {
                let stack = VStack(spacing: 0) {
                    Text(verbatim: "hdr")
                    table
                }
                buffer = renderToBuffer(stack, context: context(height: height))
            } else {
                buffer = renderToBuffer(table, context: context(height: height))
            }
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        @discardableResult
        func measure(height: Int) -> ViewSize {
            measureChild(table, proposal: .unspecified, context: context(height: height))
        }

        /// The drag geometry the handler is publishing right now, as a
        /// comparable value.
        var publishedGeometry: String {
            guard let handler else { return "no handler" }
            let bands = handler.visibleRowBands.map { "\($0.yStart)+\($0.height)@\($0.dropIndex ?? -1)" }
            return "viewport=\(handler.viewportHeight) drawn=\(handler.drawnOffset) "
                + "bands=[\(bands.joined(separator: " "))]"
        }
    }

    /// The invariant, stated the way `reserveIndicatorLines` states it for the
    /// single-line twin: a measure pass must not publish a window.
    ///
    /// It did. Asking the table for a size at a budget four lines taller
    /// rewrote `viewportHeight` (3 rows → 4), moved the band set on to a fourth
    /// row, and — through `publishRowBands`' deferred
    /// `retargetForAutoScroll()` — re-answered any drag in flight against rows
    /// that were never drawn.
    @Test("A measure pass leaves the multi-line table's drag geometry alone")
    func measurePassPublishesNoWindow() {
        let fixture = Fixture(rows: "abcdefgh".map(String.init))
        let buffer = fixture.render(height: 13)
        guard let handler = fixture.handler else {
            Issue.record("the table registered a handler")
            return
        }
        // The shape that renders itself to measure: overflowing, indicators as
        // text rather than a bar.
        #expect(
            buffer.lines.contains { $0.stripped.contains("▼") },
            "the table overflows: \(buffer.lines.map(\.stripped))")
        #expect(handler.drawsScrollIndicators)

        let drawn = fixture.publishedGeometry
        let measured = fixture.measure(height: 17)
        #expect(measured.height == 17, "still overflowing at the taller budget, so still rendered to measure")
        #expect(fixture.publishedGeometry == drawn, "a measure pass republished the window")

        // Not vacuous: the taller budget really is a different window, so the
        // measure had something else to publish and simply must not have.
        fixture.render(height: 17)
        #expect(fixture.publishedGeometry != drawn, "the 17-line budget draws a different window")
    }

    /// The harm, through the parent that actually produces the two budgets.
    ///
    /// `VStack` measures its children at the stack's full height and renders
    /// them into their distributed shares, so the table below is measured at 14
    /// and drawn at 13 — pixel-for-pixel the same frame it draws on its own at
    /// 13. Publishing from both passes ran the auto-scroll retarget twice a
    /// frame, and the multi-line path forces `RowReorderFeedback.live`, whose
    /// retarget MOVES THE DATA: the app's `onMove` fired about twice per
    /// auto-scroll tick, half the time against a window belonging to the
    /// measure's proposal.
    @Test("A stack's measure pass does not move the rows a second time per tick")
    func stackedTableMovesRowsOncePerTick() {
        func run(underHeader: Bool) -> (moves: Int, order: String, drawn: [String]) {
            let fixture = Fixture(rows: "abcdefghijkl".map(String.init))
            let height = underHeader ? 14 : 13
            var buffer = fixture.render(height: height, underHeader: underHeader)
            // Press the first row's first line, then hold in the bottom hot
            // margin so auto-scroll runs under a motionless pointer.
            let firstRowY = underHeader ? 3 : 2
            fixture.dispatcher.dispatch(
                MouseEvent(button: .left, phase: .pressed, x: 4, y: firstRowY))
            buffer = fixture.render(height: height, underHeader: underHeader)
            let edge = max(0, buffer.lines.count - 2)
            fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 4, y: edge))
            buffer = fixture.render(height: height, underHeader: underHeader)
            for tick in 0...10 {
                fixture.session.driveAutoScroll(nowNanos: UInt64(tick) &* 1_000_000_000)
                buffer = fixture.render(height: height, underHeader: underHeader)
            }
            // The stack's own header line dropped, so the two runs' table
            // buffers are directly comparable.
            let drawn = Array(buffer.lines.map(\.stripped).suffix(13))
            return (fixture.moves, fixture.rows.joined(), drawn)
        }

        let alone = run(underHeader: false)
        let stacked = run(underHeader: true)
        #expect(alone.moves > 0, "the drag actually reordered")
        #expect(stacked.drawn == alone.drawn, "the two runs draw the same table")
        #expect(stacked.order == alone.order, "…and end with the same rows")
        #expect(
            stacked.moves == alone.moves,
            "onMove ran \(stacked.moves) times under a stack against \(alone.moves) alone")
    }
}
