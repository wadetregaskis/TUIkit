//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ReorderAutoScrollSlotTests.swift
//
//  Where a row-reorder LANDS while drag auto-scroll is running under a
//  motionless pointer.
//
//  The drop position is re-resolved from the drawn row bands, and
//  `publishRowBands` defers that retarget until after the rows are composed, so
//  the SLOT each frame draws is the previous frame's answer. That ordering is
//  real — but it does not cost the landing, which is what this pins down: the
//  release resolves against the newest target, so the row goes where the
//  pointer is however long the rows have been streaming.
//
//  Asserted on the DROP, never on the drawn slot's line. At the control's edge
//  — the only place auto-scroll runs — the pointer is on the "N more rows
//  below" chrome, where no row can go, so the slot clamps onto the last
//  droppable row and sits one line above the pointer. That is
//  `clampedToDroppableRows` working as designed, and it is what a report of
//  "the blank line stays one behind" describes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Reorder auto-scroll landing")
struct ReorderAutoScrollSlotTests {

    private struct Row: Identifiable, Sendable {
        let id: String
        var name: String { id }
    }

    /// A reorderable Table tall enough to overflow, so auto-scroll has
    /// somewhere to go. (The Example's own reorder demos are six rows in a
    /// five-line viewport, and in `.cursor` mode the carried row LEAVES — so
    /// the rest fit exactly and nothing can scroll. They cannot show this.)
    @MainActor
    private final class Fixture {
        var rows: [String]
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(rows: [String], feedback: RowReorderFeedback) {
            self.rows = rows
            env.focusManager = FocusManager()
            env.rowReorderFeedback = feedback
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }
        var session: DragAndDropSession { tui.dragAndDropSession }

        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            session.beginFrame()
            let table = Table(rows.map(Row.init), selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.name)
            }
            .onMove { self.rows.move(fromOffsets: $0, toOffset: $1) }
            .frame(width: 20, height: 9)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(table, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        /// The single-letter row label drawn on `line`, or `nil` for chrome —
        /// the header, a border, an "N more rows below" indicator.
        func label(_ buffer: FrameBuffer, onLine line: Int) -> String? {
            guard buffer.lines.indices.contains(line) else { return nil }
            let letters = String(buffer.lines[line].stripped.filter(\.isLetter))
            return rows.contains(letters) ? letters : nil
        }

        func lineOf(_ buffer: FrameBuffer, _ label: String) -> Int? {
            buffer.lines.indices.first { self.label(buffer, onLine: $0) == label }
        }

        func lastRowLine(_ buffer: FrameBuffer) -> Int? {
            buffer.lines.indices.last { self.label(buffer, onLine: $0) != nil }
        }
    }

    @Test("Auto-scrolling under a held pointer still drops where the pointer is")
    func autoScrollKeepsTheDropUnderThePointer() {
        let names = "abcdefghijklmnopqrst".map(String.init)
        let fixture = Fixture(rows: names, feedback: .cursor)

        var buffer = fixture.render()
        guard let start = fixture.lineOf(buffer, "a") else {
            Issue.record("row a is drawn: \(buffer.lines.map(\.stripped))")
            return
        }

        // Pick "a" up and carry it to the bottom edge.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: start))
        buffer = fixture.render()

        // The bottom hot margin is the control's LAST content line — the "N
        // more rows below" indicator, one above the border. Aiming at the last
        // ROW instead leaves the pointer outside the margin and nothing
        // auto-scrolls at all.
        let edge = max(0, buffer.lines.count - 2)
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: edge))
        buffer = fixture.render()
        guard let before = fixture.lastRowLine(buffer).flatMap({ fixture.label(buffer, onLine: $0) })
        else {
            Issue.record("a last row before scrolling: \(buffer.lines.map(\.stripped))")
            return
        }

        // Auto-scroll ticks, each followed by a full frame, as the run loop
        // drives it. The pointer never moves again.
        for tick in 0...6 {
            fixture.session.driveAutoScroll(nowNanos: UInt64(tick) &* 1_000_000_000)
            buffer = fixture.render()
        }

        // The pointer sits on chrome, so the slot clamps onto the last
        // droppable row — that row is what the drop names.
        guard let lastLine = fixture.lastRowLine(buffer),
            let underPointer = fixture.label(buffer, onLine: lastLine)
        else {
            Issue.record("a last row after scrolling: \(buffer.lines.map(\.stripped))")
            return
        }
        #expect(underPointer != before, "the rows actually streamed past: \(before)")

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: edge))
        fixture.render()

        // Dragging downward drops AFTER the target, so "a" must sit directly
        // after the last row on screen at release. One place earlier is the
        // lag: the drop resolved against the frame before the final scroll.
        guard let landed = fixture.rows.firstIndex(of: "a"),
            let target = fixture.rows.firstIndex(of: underPointer)
        else {
            Issue.record("both rows survive the move: \(fixture.rows)")
            return
        }
        let detail = "a landed at \(landed), \(underPointer) (under the pointer) at \(target)"
        #expect(landed == target + 1, "\(detail): \(fixture.rows)")
    }
}
