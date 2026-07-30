//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableReorderDragTests.swift
//
//  Mouse drag-to-reorder for a `Table.onMove` — the same gesture, state machine
//  and feedback modes as `List`'s (see ListReorderDragTests), driven here through
//  a Table's own geometry: a column header, "N more" indicators or a scrollbar,
//  and rows that are lines of text rather than child buffers.
//
//  The two views keep drifting apart where they hold the same rules in two
//  places, so the pairs that must agree are asserted on BOTH sides: the drop
//  index is a drawn position, the slot is a drop target, and a motionless press
//  is still a click.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Table drag-to-reorder")
struct TableReorderDragTests {

    private struct Row: Identifiable, Sendable {
        let id: String
        var name: String { id }
    }

    /// A row-order holder plus the pieces to render it. A reference type so the
    /// `onMove` closure — which fires during a later mouse dispatch, not during
    /// the render that installed it — writes straight back into `rows`.
    @MainActor
    private final class Fixture {
        var rows: [String]
        let reorderable: Bool
        private(set) var moves = 0
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(
            rows: [String] = ["a", "b", "c", "d", "e"], reorderable: Bool = true,
            feedback: RowReorderFeedback = .live,
            scrollbar: ScrollbarVisibility = .hidden
        ) {
            self.rows = rows
            self.reorderable = reorderable
            env.focusManager = FocusManager()
            env.rowReorderFeedback = feedback
            env.scrollbarVisibility = scrollbar
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let base = Table(rows.map(Row.init), selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.name)
            }
            let table =
                reorderable
                ? base.onMove {
                    self.moves += 1
                    self.rows.move(fromOffsets: $0, toOffset: $1)
                }
                : base
            let view = table.frame(width: 20, height: 9)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        /// The screen line of the row whose text IS `label`, matched on its
        /// letters alone.
        ///
        /// Not "contains": a Table draws a column HEADER ("Name"), and matching
        /// by containment pressed that instead of row "a". And not the whole
        /// stripped line either: the scrollbar path appends a bar cell (▲/█/▼) to
        /// every row, which is why the same test passed without a bar and missed
        /// every row with one.
        func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
            buffer.lines.firstIndex { $0.stripped.filter(\.isLetter) == label } ?? -1
        }

        /// Press on `source`'s line, drag to `target`'s, release there — with a
        /// render between each step, as the run loop has.
        func drag(from source: String, to target: String) {
            let buffer = render()
            let ySource = rowY(buffer, source)
            let yTarget = rowY(buffer, target)
            dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
            render()
            dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
            render()
            dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
            render()
        }
    }

    // MARK: - The gesture

    @Test("Dragging a row downward drops it after the target")
    func dragDown() {
        let fixture = Fixture()
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
    }

    @Test("Dragging a row upward drops it before the target")
    func dragUp() {
        let fixture = Fixture()
        fixture.drag(from: "d", to: "b")
        #expect(fixture.rows == ["a", "d", "b", "c", "e"])
    }

    @Test("A table with no onMove does not reorder", arguments: [true, false])
    func withoutOnMoveNothingMoves(scrollbar: Bool) {
        let fixture = Fixture(
            reorderable: false, scrollbar: scrollbar ? .visible : .hidden)
        fixture.drag(from: "a", to: "d")
        #expect(fixture.rows == ["a", "b", "c", "d", "e"], "the rows are exactly as they were")
    }

    @Test("A press released without moving is a click, not a reorder")
    func motionlessPressIsAClick() {
        let fixture = Fixture()
        let buffer = fixture.render()
        let y = fixture.rowY(buffer, "b")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: y))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: y))
        fixture.render()

        #expect(fixture.rows == ["a", "b", "c", "d", "e"])
        #expect(fixture.moves == 0, "nothing was moved by pressing and letting go")
    }

    /// The same gesture over a table that draws a scrollbar instead of "N more"
    /// indicators — a separate render path, and one that reserves no line above
    /// the rows, so the click-to-line mapping differs.
    @Test("Reordering works on the scrollbar path too")
    func dragWithScrollbar() {
        let fixture = Fixture(scrollbar: .visible)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
    }

    // MARK: - Feedback modes

    /// `.live` is the preview: the rows themselves move as the cursor crosses
    /// each slot, so one drag fires `onMove` more than once.
    @Test("Live feedback moves the rows as the drag goes")
    func liveMovesAsItGoes() {
        let fixture = Fixture(feedback: .live)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
        #expect(fixture.moves >= 1, "the list itself was the preview")
    }

    /// `.dimmed` and `.cursor` take the row OUT and open a slot, so the table
    /// keeps its length mid-drag and the data moves exactly once, on the drop.
    @Test(
        "Dimmed and cursor feedback move the row exactly once, on the drop",
        arguments: [RowReorderFeedback.dimmed, .cursor])
    func slotModesMoveOnceOnDrop(feedback: RowReorderFeedback) {
        let fixture = Fixture(feedback: feedback)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
        #expect(fixture.moves == 1, "one move, at the drop — the drag showed a slot instead")
    }

    /// Mid-drag, the dragged row has left its place: the rows below close up and
    /// a slot opens where it would land. So the row is drawn once (in the slot,
    /// faintly, under `.dimmed`) — never twice.
    @Test("Mid-drag the row is out of the table, and the slot is where it lands")
    func midDragShowsTheSlot() {
        let fixture = Fixture(feedback: .dimmed)
        let buffer = fixture.render()
        let ySource = fixture.rowY(buffer, "a")
        let yTarget = fixture.rowY(buffer, "c")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        let dragging = fixture.render()

        let order = dragging.lines.compactMap { line -> String? in
            let text = line.stripped.filter { !"│╭╮╰╯─ ".contains($0) }
            return ["a", "b", "c", "d", "e"].contains(text) ? text : nil
        }
        #expect(
            order == ["b", "c", "a", "d", "e"],
            """
            the drawn order IS the order a drop would produce, with "a" appearing \
            once — in the slot: \(dragging.lines.map(\.stripped))
            """)

        // And the drop lands it exactly where the slot showed it.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
        fixture.render()
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
    }

    /// The slot's own line is a drop target: after every step of the drag the
    /// pointer is resting on it, so releasing there must commit the move it has
    /// been advertising rather than reading as "off the rows".
    @Test("Releasing on the slot commits the move it was showing")
    func releaseOnTheSlotCommits() {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        let ySource = fixture.rowY(buffer, "a")
        let yTarget = fixture.rowY(buffer, "d")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
        fixture.render()
        // Two steps to the same line: the second lands on the gap the first
        // opened there.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
        fixture.render()

        #expect(fixture.rows == ["b", "c", "d", "a", "e"])
    }

    /// Dragging back to the row's own place is a legitimate destination — mid-drag
    /// it is the only way to change your mind — and it must leave the order alone.
    @Test("Dragging back to where it started changes nothing")
    func dragBackToTheOrigin() {
        let fixture = Fixture(feedback: .dimmed)
        let buffer = fixture.render()
        let yOrigin = fixture.rowY(buffer, "b")
        let yAway = fixture.rowY(buffer, "d")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yOrigin))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yAway))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yOrigin))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yOrigin))
        fixture.render()

        #expect(fixture.rows == ["a", "b", "c", "d", "e"], "back where it started")
    }

    /// `.dimmed` draws the row itself, faint, at the slot it would land in — and
    /// it must be faint ALL the way along. A Table row is several styled runs
    /// (starting with the one-cell selection gutter) and each carries its own
    /// reset, so a `dim … reset` wrapper used to die before the first character
    /// and the row drew at full intensity. Asserting `contains(dim)` cannot see
    /// that; asserting that no reset is left un-reopened can.
    @Test("The dimmed slot stays faint past the row's own resets")
    func dimmedSlotIsFaintThroughout() {
        let fixture = Fixture(feedback: .dimmed)
        let buffer = fixture.render()
        let ySource = fixture.rowY(buffer, "b")
        let yTarget = fixture.rowY(buffer, "d")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        let dragging = fixture.render()

        guard let slot = dragging.lines.first(where: { $0.contains(ANSIRenderer.dim) }) else {
            Issue.record("expected a dimmed slot line"); return
        }
        guard let column = slot.stripped.firstIndex(of: "b").map({ slot.stripped.distance(from: slot.stripped.startIndex, to: $0) })
        else {
            Issue.record("the slot should hold a copy of the dragged row: \(slot.stripped)"); return
        }
        // The state in force AT the row's text — not merely somewhere on the
        // line. Everything before the last reset has been cancelled by it.
        let state = slot.ansiStateBefore(visibleColumn: column)
        let live = state.components(separatedBy: ANSIRenderer.reset).last ?? ""
        #expect(
            live.contains(ANSIRenderer.dim),
            "the dim was cancelled before the text: \(state.debugDescription)")

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
    }

    /// The grabbed cell must stay under the pointer, so with the pointer held
    /// still the float must sit exactly on the row's own left edge. Measuring
    /// the grab from the first CLICKABLE column instead of the first ROW cell
    /// put it a cell out — and because the preview was the full-interior-width
    /// styled line, the overhang painted over the scrollbar and the border.
    @Test("The floating row lands on the row's own left edge")
    func cursorPreviewAnchorsToTheRow() {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        let y = fixture.rowY(buffer, "b")
        guard let line = buffer.lines.first(where: { $0.stripped.contains("b") }),
            let textColumn = line.stripped.firstIndex(of: "b").map({
                line.stripped.distance(from: line.stripped.startIndex, to: $0)
            })
        else {
            Issue.record("expected a row line holding \"b\""); return
        }
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: textColumn, y: y))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: textColumn, y: y + 2))
        fixture.render()

        guard let frame = fixture.tui.dragAndDropSession.previewFrame(),
            let preview = fixture.tui.dragAndDropSession.active?.preview
        else {
            Issue.record("expected a floating row"); return
        }
        let previewText = preview.lines[0].stripped
        guard let inPreview = previewText.firstIndex(of: "b").map({
            previewText.distance(from: previewText.startIndex, to: $0)
        }) else {
            Issue.record("the float should be the row: \(previewText.debugDescription)"); return
        }
        #expect(
            frame.x + inPreview == textColumn,
            "the grabbed cell drifted off the pointer: float x \(frame.x) + \(inPreview)")
        #expect(
            frame.x + preview.width <= buffer.width - 1,
            "and the float stays inside the table's own frame, off the border and scrollbar")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: textColumn, y: y + 2))
    }

    /// What floats is the ROW, not the row as the grid drew it. The drawn line
    /// carries the focus/selection background and is padded out to the grid's
    /// interior — floating that painted a bar of highlight across the scrollbar
    /// column and the right border, because a styled blank is real content and
    /// the preview trim (rightly) keeps it.
    @Test("The floating row is the row itself, not its line in the grid")
    func cursorPreviewIsUnstyled() {
        let fixture = Fixture(feedback: .cursor, scrollbar: .visible)
        var buffer = fixture.render()
        let y = fixture.rowY(buffer, "b")
        // Select it first: the row you drag is normally the row you are on.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: y))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: y))
        buffer = fixture.render()

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: y))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: y + 2))
        fixture.render()

        guard let frame = fixture.tui.dragAndDropSession.previewFrame(),
            let preview = fixture.tui.dragAndDropSession.active?.preview
        else {
            Issue.record("expected a floating row"); return
        }
        #expect(
            preview.lines[0].stripped.trimmingCharacters(in: .whitespaces) == "b",
            "the float is one row's content: \(preview.lines[0].stripped.debugDescription)")
        #expect(
            frame.x + preview.width <= buffer.width - 2,
            "it clears the scrollbar column and the border: x \(frame.x) w \(preview.width)")

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: y + 2))
    }

    /// A table with a wrapping column publishes no row bands at all until now,
    /// so the drag had nothing to hit-test: the row never moved AND the click
    /// was swallowed. Multi-line tables force `.live` feedback (no slot), so a
    /// successful drag is visible in the data.
    @Test("A multi-line table reorders by drag too")
    func multiLineDragReorders() {
        let rows = ["alpha beta gamma", "delta epsilon", "zeta eta"]
        let holder = MultiLineFixture(rows: rows)
        let buffer = holder.render()
        let ySource = holder.rowY(buffer, "alpha")
        let yTarget = holder.rowY(buffer, "zeta")
        #expect(ySource >= 0 && yTarget > ySource, "both rows on screen")

        holder.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: ySource))
        holder.render()
        holder.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 4, y: yTarget))
        holder.render()
        holder.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: yTarget))
        holder.render()

        #expect(holder.rows.first != rows[0], "the dragged row left the top: \(holder.rows)")
        #expect(Set(holder.rows) == Set(rows), "and nothing was lost")
    }

    /// A table whose column wraps — rows are taller than one line, so the band
    /// heights are what a click maps through.
    @MainActor
    private final class MultiLineFixture {
        var rows: [String]
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(rows: [String]) {
            self.rows = rows
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let view = Table(rows.map(Row.init), selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.name).lineLimit(2)
            }
            .onMove { self.rows.move(fromOffsets: $0, toOffset: $1) }
            .frame(width: 14, height: 12)
            var context = RenderContext(
                availableWidth: 14, availableHeight: 14, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
            buffer.lines.firstIndex { $0.stripped.contains(label) } ?? -1
        }
    }
}
