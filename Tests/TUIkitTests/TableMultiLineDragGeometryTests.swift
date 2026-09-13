//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableMultiLineDragGeometryTests.swift
//
//  Where a drag lands on a MULTI-LINE table that is scrolled by a LINE rather
//  than by a row.
//
//  That combination is the one place the table's two answers to "is an 'N more
//  above' line drawn?" disagree. The drawing condition is `window.showAbove`
//  (`scrollOffset > 0 || topClip > 0`); the mouse closure's is the handler's
//  `hasContentAbove` (`scrollOffset > 0` alone). Scroll one line into row 0 and
//  the first is true while the second is false — the indicator is on screen and
//  the click map does not know it. Nothing else in the suite reaches it: the
//  single-line paths cannot have a top clip, and row-granularity scrolling
//  moves both conditions together.
//
//  And the bottom edge, unscrolled: the row straddling the line budget is drawn
//  short so that the "▼ N more rows below" line fits under it, and its band has
//  to stop where its lines do, not at the end of the content area.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Multi-line table drag geometry")
struct TableMultiLineDragGeometryTests {

    private struct Row: Identifiable, Sendable {
        let id: String
        /// FOUR lines' worth at the width below. One repeated letter per row,
        /// so a drawn line names the row it came from whichever part of the
        /// wrap it is.
        ///
        /// Four rather than two so a single wheel tick — three lines — lands
        /// INSIDE the first row instead of stepping past it. Two-line rows put
        /// the same tick at row 1 with a line clipped, where both conditions
        /// agree again and the case proves nothing.
        var name: String {
            (0..<8).map { _ in String(repeating: id, count: 8) }.joined(separator: " ")
        }
    }

    @MainActor
    private final class Fixture {
        var rows: [String]
        var selection: String?
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(rows: [String]) {
            self.rows = rows
            env.focusManager = FocusManager()
            env.scrollIndicatorStyle = .text
            // `.live` is what the multi-line path forces anyway (no slot is
            // drawn there); spelled out so the case does not depend on that.
            env.rowReorderFeedback = .live
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }
        var session: DragAndDropSession { tui.dragAndDropSession }
        var handler: ItemListHandler<String>? {
            env.focusManager?.currentFocused as? ItemListHandler<String>
        }

        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            session.beginFrame()
            let table = Table(
                rows.map(Row.init),
                selection: Binding(get: { self.selection }, set: { self.selection = $0 })
            ) {
                TableColumn<Row>("Name", value: \.name).lineLimit(4)
            }
            .onMove { self.rows.move(fromOffsets: $0, toOffset: $1) }
            .scrollGranularity(.line)
            .frame(width: 22, height: 11)
            var context = RenderContext(
                availableWidth: 22, availableHeight: 13, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(table, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        /// The row label a drawn line belongs to, read off its repeated letter.
        func label(_ buffer: FrameBuffer, onLine line: Int) -> String? {
            guard buffer.lines.indices.contains(line) else { return nil }
            let letters = Set(buffer.lines[line].stripped.filter(\.isLetter)).map(String.init)
            guard letters.count == 1, let only = letters.first, rows.contains(only) else {
                return nil
            }
            return only
        }
    }

    /// One line of scroll into the first row draws "▲ 1 row above" while the
    /// handler still reports nothing above it. The drag has to hit-test against
    /// what is DRAWN.
    ///
    /// It does now because the bands and the pointer share the interior's first
    /// content line as their origin: the indicator sits inside that space, so
    /// the drawing condition is the only place the question is asked. Measured
    /// from the first ROW line instead, the two conditions each had to be
    /// re-derived — and they were derived differently, so the drag resolved one
    /// row above the pointer for as long as the viewport sat mid-row.
    @Test("A line-scrolled multi-line table drags the row under the pointer")
    func lineScrolledMultiLineDragHitsThePointedRow() {
        let names = "abcdef".map(String.init)
        let fixture = Fixture(rows: names)

        var buffer = fixture.render()
        // One WHEEL tick, which under `.line` granularity clips a line off the
        // top row without advancing the row offset — the state under test.
        fixture.dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 4))
        buffer = fixture.render()
        #expect(fixture.handler?.scrollOffset == 0, "still on row 0, just clipped")
        #expect(fixture.handler.map { $0.scrollTopClipLines > 0 } == true, "a line came off")
        #expect(
            buffer.lines.count > 2 && buffer.lines[2].stripped.contains("▲"),
            "the indicator is drawn: \(buffer.lines.map(\.stripped))")

        // Two lines that belong to different rows, both below the indicator.
        guard
            let sourceLine = (3..<buffer.lines.count).first(where: {
                fixture.label(buffer, onLine: $0) != nil
            }),
            let source = fixture.label(buffer, onLine: sourceLine),
            let targetLine = (sourceLine..<buffer.lines.count).first(where: {
                let here = fixture.label(buffer, onLine: $0)
                return here != nil && here != source
            }),
            let target = fixture.label(buffer, onLine: targetLine)
        else {
            Issue.record("two rows are drawn: \(buffer.lines.map(\.stripped))")
            return
        }

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 3, y: sourceLine))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 3, y: targetLine))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 3, y: targetLine))
        fixture.render()

        // `.live` drags the row across every slot it passes, so the source ends
        // up exactly where the pointed row was. Landing anywhere else means the
        // gesture resolved against a line the row is not drawn on.
        guard let landed = fixture.rows.firstIndex(of: source),
            let pointed = fixture.rows.firstIndex(of: target)
        else {
            Issue.record("both rows survive: \(fixture.rows)")
            return
        }
        let detail = "\(source) landed at \(landed), \(target) (pointed at) at \(pointed)"
        #expect(landed == pointed + 1, "\(detail): \(fixture.rows)")
    }

    /// The click half of the same disagreement, and the one a user meets
    /// first: with the viewport a line into the first row, the "▲ 1 row above"
    /// line is drawn and the click map has to know it is there.
    ///
    /// Clicking the first drawn row line selects the row that line belongs to.
    /// It selected the NEXT one down for as long as the map counted lines from
    /// a first-row origin it worked out for itself.
    @Test("A click on a line-scrolled multi-line table selects the pointed row")
    func lineScrolledMultiLineClickSelectsThePointedRow() {
        let names = "abcdef".map(String.init)
        let fixture = Fixture(rows: names)

        var buffer = fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 4))
        buffer = fixture.render()
        #expect(
            buffer.lines.count > 2 && buffer.lines[2].stripped.contains("▲"),
            "the indicator is drawn: \(buffer.lines.map(\.stripped))")

        guard let pointed = fixture.label(buffer, onLine: 3) else {
            Issue.record("a row on the first content line: \(buffer.lines.map(\.stripped))")
            return
        }
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 3))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 3))
        fixture.render()

        #expect(fixture.selection == pointed, "clicked \(pointed), selected \(fixture.selection ?? "nothing")")
    }

    /// Unscrolled, the second row straddles the line budget: the table draws row
    /// a's four lines, three of row b's, and "▼ 4 more rows below" on the last
    /// content line. A click on that line selects no row; a click on the line
    /// above it selects row b.
    ///
    /// The first half failed for as long as the bands were built from whole row
    /// heights and trimmed only at the content area, which counts the
    /// indicator's line: row b's band ran one line past its drawing, so the
    /// indicator selected it — and in this `.onMove` table a press there grabbed
    /// it for a `.live` reorder. The second half is what fails a "fix" that just
    /// drops the cut row's band.
    @Test("A click on a multi-line table's below indicator selects no row")
    func belowIndicatorClickSelectsNoRow() {
        let names = "abcdef".map(String.init)
        let fixture = Fixture(rows: names)

        let buffer = fixture.render()
        let screen = buffer.lines.map(\.stripped)
        guard
            let indicatorLine = screen.firstIndex(where: { $0.contains("▼") && $0.contains("below") }),
            indicatorLine > 0,
            let cut = fixture.label(buffer, onLine: indicatorLine - 1)
        else {
            Issue.record("a row line sits straight above the below indicator: \(screen)")
            return
        }
        // Drawn SHORT, or there is no cut tail for a band to overrun and the case
        // proves nothing.
        let cutLineCount = (0..<indicatorLine).filter {
            fixture.label(buffer, onLine: $0) == cut
        }.count
        #expect(cutLineCount < 4, "\(cut) is cut at the budget: \(screen)")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 3, y: indicatorLine))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 3, y: indicatorLine))
        fixture.render()
        #expect(
            fixture.selection == nil,
            "clicked \"\(screen[indicatorLine])\", selected \(fixture.selection ?? "nothing")")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 3, y: indicatorLine - 1))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 3, y: indicatorLine - 1))
        fixture.render()
        #expect(
            fixture.selection == cut,
            "clicked \(cut)'s last drawn line, selected \(fixture.selection ?? "nothing")")
    }
}
