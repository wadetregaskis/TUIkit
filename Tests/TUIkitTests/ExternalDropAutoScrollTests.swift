//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ExternalDropAutoScrollTests.swift
//
//  Where a drag from ANOTHER view lands while the receiving list is
//  auto-scrolling under a motionless pointer — the twin of
//  `ReorderAutoScrollSlotTests`, which covers a list reordering its own rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Incoming drop while auto-scrolling")
struct ExternalDropAutoScrollTests {
    /// Any type will do: a drop destination accepts by payload type, and the
    /// app defines the type.
    private struct Track: Sendable {
        let name: String
    }

    /// A list with more rows than it can show and a drop destination, so an
    /// incoming drag can hold at its bottom edge and make it scroll.
    @MainActor
    private final class Fixture {
        var rows: [String]
        var dropped: (slot: Int, count: Int)?
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(rows: [String]) {
            self.rows = rows
            env.focusManager = FocusManager()
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

        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            session.beginFrame()
            let list = List(selection: .constant(String?.none)) {
                ForEach(rows, id: \.self) { Text($0) }
                    .dropDestination(for: Track.self) { index, drops in
                        self.dropped = (index, drops.count)
                    }
            }
            .frame(width: 20, height: 9)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(list, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        func label(_ buffer: FrameBuffer, onLine line: Int) -> String? {
            guard buffer.lines.indices.contains(line) else { return nil }
            let letters = String(buffer.lines[line].stripped.filter(\.isLetter))
            return rows.contains(letters) ? letters : nil
        }

        func lastRowLine(_ buffer: FrameBuffer) -> Int? {
            buffer.lines.indices.last { self.label(buffer, onLine: $0) != nil }
        }

        /// The one blank line among the drawn content: the gap the incoming
        /// drop would land in.
        func slotLine(_ buffer: FrameBuffer) -> Int? {
            buffer.lines.indices.first { line in
                let content = buffer.lines[line].stripped.filter { !" \u{2502}".contains($0) }
                return content.isEmpty && line > 0 && line < buffer.lines.count - 1
            }
        }

        /// Starts a drag from somewhere else and parks the pointer in the
        /// list's bottom hot margin, where auto-scroll engages.
        func dragToBottomEdge(of buffer: FrameBuffer) {
            let edge = max(0, buffer.lines.count - 2)
            dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: edge))
            session.begin(payload: Track(name: "incoming"), preview: FrameBuffer(text: "x"))
            dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: edge))
            session.dragMoved()
        }
    }

    @Test("The incoming slot follows the pointer while the list scrolls under it")
    func slotRidesThePointer() {
        let names = "abcdefghijklmnopqrst".map(String.init)
        let fixture = Fixture(rows: names)
        var buffer = fixture.render()
        fixture.dragToBottomEdge(of: buffer)
        buffer = fixture.render()

        var offenders: [String] = []
        var scrolled = false
        var lastBottomRow: String?
        for tick in 0...8 {
            fixture.session.driveAutoScroll(nowNanos: UInt64(tick) &* 1_000_000_000)
            buffer = fixture.render()
            let bottom = fixture.lastRowLine(buffer).flatMap { fixture.label(buffer, onLine: $0) }
            if let bottom, let lastBottomRow, bottom != lastBottomRow { scrolled = true }
            lastBottomRow = bottom
            guard tick >= 2 else { continue }
            // The pointer is in the bottom margin, on the "more rows below"
            // chrome, where no row can go, so the gap rides the viewport's
            // leading edge: directly above the last row drawn, whichever row
            // that now is. What matters is that it MOVES with the rows rather
            // than being carried away by them.
            let slot = fixture.slotLine(buffer)
            let lastRow = fixture.lastRowLine(buffer)
            if slot != lastRow.map({ $0 - 1 }) {
                offenders.append(
                    "t=\(tick) slot=\(slot.map(String.init) ?? "\u{2014}") "
                        + "lastRow=\(lastRow.map(String.init) ?? "\u{2014}")")
            }
        }
        #expect(scrolled, "the fixture actually auto-scrolled")
        #expect(offenders.isEmpty, "the gap follows the pointer every frame: \(offenders)")
    }

    @Test("The drop lands where the pointer is, not where the rows started")
    func dropLandsUnderThePointer() {
        let names = "abcdefghijklmnopqrst".map(String.init)
        let fixture = Fixture(rows: names)
        var buffer = fixture.render()
        fixture.dragToBottomEdge(of: buffer)
        buffer = fixture.render()
        for tick in 0...6 {
            fixture.session.driveAutoScroll(nowNanos: UInt64(tick) &* 1_000_000_000)
            buffer = fixture.render()
        }
        // The drop belongs among the rows now under the pointer — not at the
        // index the first hover named, which was the end of the list (the
        // pointer started on the "N rows below" chrome, where no row is).
        let visible = buffer.lines.indices
            .compactMap { fixture.label(buffer, onLine: $0) }
            .compactMap { names.firstIndex(of: $0) }
        guard let firstVisible = visible.min(), let lastVisible = visible.max() else {
            Issue.record("no rows drawn: \(buffer.lines.map(\.stripped))")
            return
        }
        #expect(firstVisible > 0, "the list scrolled before the drop")
        fixture.session.performDrop()
        guard let landed = fixture.dropped?.slot else {
            Issue.record("nothing was dropped")
            return
        }
        #expect(
            (firstVisible...lastVisible + 1).contains(landed),
            "landed at \(landed), outside the visible \(firstVisible)…\(lastVisible)")
    }

    /// A drop index is only ever handed to the app, and the documented use of
    /// it is `insert(contentsOf:at:)` — which traps rather than clamping. So it
    /// has to be in range at the moment of the drop, not merely at the moment
    /// of the hover.
    ///
    /// Between the two the data can shrink with no pointer event to re-clamp
    /// on: a filter narrowing, a sibling view taking the item, the drag's own
    /// source removing it. Here the list simply loses rows while the pointer
    /// holds still past the end of it — the hover named the old count, and
    /// nothing else asks the question again.
    @Test("A list that shrinks under a held pointer still yields a usable index")
    func slotIsClampedWhenTheListShrinksBeforeTheDrop() {
        let fixture = Fixture(rows: ["a", "b", "c", "d", "e", "f", "g", "h"])
        let buffer = fixture.render()
        fixture.dragToBottomEdge(of: buffer)
        // Past every row: the conventional "append" answer, which is exactly
        // the index that a shrinking list strands.
        fixture.handler?.hoverExternalDrop(atContentY: 999)
        #expect(fixture.handler?.externalDropSlot == 8, "the hover named the end")

        fixture.rows = ["a", "b", "c"]
        _ = fixture.render()
        fixture.session.performDrop()

        guard let landed = fixture.dropped?.slot else {
            Issue.record("nothing was dropped")
            return
        }
        #expect(
            (0...fixture.rows.count).contains(landed),
            "landed at \(landed), outside 0…\(fixture.rows.count)")
    }
}
