//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ExternalDropFullListTests.swift
//
//  An incoming drop onto a list whose rows exactly fill it — where opening a
//  landing slot is itself enough to make the list overflow.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Incoming drop onto a list with no spare row")
struct ExternalDropFullListTests {

    private struct Track: Sendable {
        let name: String
    }

    @MainActor
    private final class Fixture {
        var rows: [String]
        let height: Int
        /// Kept across renders: reachable through the session only while a drag
        /// hovers, and the same persisted object before and after one.
        var handler: ItemListHandler<String>?
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(rows: [String], height: Int) {
            self.rows = rows
            self.height = height
            env.focusManager = FocusManager()
            // The default, and the one the reported case was seen in: a bar
            // costs no LINE, so the slot's line comes straight out of the rows
            // — which is what makes an exactly-full list overflow the moment a
            // drag arrives over it.
            env.scrollIndicatorStyle = .scrollbar
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        @discardableResult
        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let list = List(selection: .constant(String?.none)) {
                ForEach(rows, id: \.self) { Text($0) }
                    .dropDestination(for: Track.self) { _, _ in }
            }
            .frame(width: 22, height: height)
            var context = RenderContext(
                availableWidth: 22, availableHeight: height + 2, environment: env,
                tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(list, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            handler =
                tui.dragAndDropSession.scrollableUnderCursor() as? ItemListHandler<String>
                ?? handler
            return buffer
        }

        /// The line a row's text is on, or nil.
        func rowLines(_ buffer: FrameBuffer) -> [Int] {
            buffer.lines.indices.filter { line in
                let letters = String(buffer.lines[line].stripped.filter(\.isLetter))
                return rows.contains(letters)
            }
        }

        /// The one blank line among the drawn content: the gap the incoming
        /// drop would land in.
        func slotLine(_ buffer: FrameBuffer) -> Int? {
            buffer.lines.indices.first { line in
                guard line > 0, line < buffer.lines.count - 1 else { return false }
                return !buffer.lines[line].stripped
                    .contains { !" \u{2502}".contains($0) }
            }
        }

        /// Presses somewhere else, then holds the pointer on `y`.
        func hold(at y: Int) {
            tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .pressed, x: 2, y: y))
            tui.dragAndDropSession.begin(
                payload: Track(name: "incoming"), preview: FrameBuffer(text: "x"))
            move(to: y)
        }

        /// One pointer motion, as the terminal reports it — no more. Everything
        /// after this has to settle without further input.
        func move(to y: Int) {
            tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .dragged, x: 2, y: y))
            tui.dragAndDropSession.dragMoved()
        }
    }

    /// The reported case: five rows in five lines of room, a sixth dragged in
    /// and held over the bottom row.
    ///
    /// Opening the slot needs a sixth line the list does not have, so it
    /// overflows, so the pointer is in the hot margin and edge auto-scroll
    /// engages. Once the list has scrolled as far as it goes, nothing is moving
    /// — and the gap has to stop moving too. It did not: the retarget ran every
    /// frame, and the bands it read its answer off were laid out around its own
    /// previous answer, so the gap flipped between two places forever with the
    /// pointer perfectly still.
    ///
    /// A real pointer keeps reporting while it is held, which is why the
    /// motion is repeated here. One report and the auto-scroll lapses, which is
    /// exactly why the first attempt at this test passed.
    @Test("The landing slot settles while the pointer is held still")
    func slotSettlesOnAFullList() {
        for rowCount in 3...6 {
            let names = Array("abcdefgh".map(String.init).prefix(rowCount))
            // Exactly full: `height` minus the two border rows is `rowCount`.
            let fixture = Fixture(rows: names, height: rowCount + 2)
            var buffer = fixture.render()
            guard let bottom = fixture.rowLines(buffer).last,
                let top = fixture.rowLines(buffer).first
            else {
                Issue.record("\(rowCount): no rows drawn")
                continue
            }
            for target in [bottom, top] {
                fixture.hold(at: target)
                var seen: [String] = []
                for tick in 0..<14 {
                    // Time barely advances: the rate ramp has not moved the
                    // rows yet, which is the state the reported case sits in —
                    // auto-scroll engaged, offset still where it was.
                    fixture.tui.dragAndDropSession.driveAutoScroll(
                        nowNanos: UInt64(tick) &* 1_000_000)
                    fixture.move(to: target)
                    buffer = fixture.render()
                    // The INDEX, not the drawn line: two indices can put the
                    // gap on the same line while the drop lands a place apart.
                    seen.append(
                        "\(fixture.handler?.externalDropSlot.map(String.init) ?? "-")"
                            + "@\(fixture.slotLine(buffer).map(String.init) ?? "-")"
                            + "\(fixture.handler?.isAutoScrolling == true ? "!" : "")")
                }
                // The list cannot scroll for ever, so the tail must be still.
                // The head may move: that is the rows arriving under the
                // pointer, which is what auto-scroll is for.
                let tail = Set(seen.suffix(6))
                #expect(
                    tail.count == 1,
                    "\(rowCount) rows, held on line \(target): slot ended \(seen.suffix(8))")
                fixture.tui.dragAndDropSession.cancelReturningToOrigin()
                fixture.tui.dragAndDropSession.end()
                _ = fixture.render()
            }
        }
    }
}
