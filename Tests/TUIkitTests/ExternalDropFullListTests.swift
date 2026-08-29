//  🖥️ TUIkit — Terminal UI Kit for Swift
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

        /// The gap's line, found by what is NOT on it.
        ///
        /// ``slotLine(_:)`` asks for a line that is blank to the last cell, and
        /// the gap is often not: the scroll indicator rides the interior's last
        /// column, and at the bottom of an overflowing list that is the very
        /// line the gap is on. Every row here is a single letter, so "an
        /// interior line with no letter on it" names the gap without having to
        /// enumerate the chrome that may share it.
        func gapLine(_ buffer: FrameBuffer) -> Int? {
            buffer.lines.indices.first { line in
                guard line > 0, line < buffer.lines.count - 1 else { return false }
                return !buffer.lines[line].stripped.contains(where: \.isLetter)
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

    /// One pointer position gets ONE answer — the invariant the flip broke.
    ///
    /// A held pointer keeps reporting: a trackpad sends many events a second
    /// without moving a cell. Each report ran `hoverExternalDrop`, which reads
    /// the gap's own band and keeps the gap where the pointer is; each render
    /// then re-armed and ran the auto-scroll retarget, whose past-the-rows rule
    /// pulls the gap onto the last row instead. Both answers are defensible and
    /// they are not the same, so the gap flipped between two lines for as long
    /// as the drag was held — measured live at up to 3.6 kB of repaint per
    /// half-second against a settled 0.
    ///
    /// So the assertion is not "it settles eventually" (the case below already
    /// covers that, and passed throughout) but "a render does not change the
    /// answer the pointer just gave". That is what tells the two rules apart.
    @Test("A repeated report at the same cell is not a new pointer position")
    func aHeldPointerGetsOneAnswer() {
        for rowCount in 3...6 {
            let names = Array("abcdefgh".map(String.init).prefix(rowCount))
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
                // Let auto-scroll do whatever it is going to do first: the
                // question is about the STEADY state, where the rows have
                // stopped and only the pointer is still talking.
                for tick in 0..<12 {
                    fixture.tui.dragAndDropSession.driveAutoScroll(
                        nowNanos: UInt64(tick) &* 120_000_000)
                    fixture.move(to: target)
                    _ = fixture.render()
                }
                for report in 0..<6 {
                    fixture.move(to: target)
                    let answered = fixture.handler?.externalDropSlot
                    buffer = fixture.render()
                    #expect(
                        fixture.handler?.externalDropSlot == answered,
                        """
                        \(rowCount) rows, held on line \(target), report \(report): \
                        the render moved the gap from \
                        \(answered.map(String.init) ?? "-") to \
                        \(fixture.handler?.externalDropSlot.map(String.init) ?? "-")
                        """)
                }
                fixture.tui.dragAndDropSession.cancelReturningToOrigin()
                fixture.tui.dragAndDropSession.end()
                _ = fixture.render()
            }
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

    /// Moving the pointer is a new position, and the answer it gives has to
    /// survive the render that follows it.
    ///
    /// The 2026-08-24 fix stopped the gap flipping every frame, and left it
    /// flipping once per mouse movement: a hover re-armed the auto-scroll
    /// retarget whenever the pointer named a different line, so the render after
    /// each movement still overrode the pointer's own answer with the retarget's
    /// past-the-rows one. On the bottom row of a list whose rows exactly fill
    /// it, that pulled the gap one line UP off the cursor and pushed the last
    /// row down under it — reported as "sometimes under the cursor, sometimes
    /// one row above".
    ///
    /// Auto-scroll is deliberately not driven during the wiggle: with the rows
    /// standing still there is nothing for the retarget to correct, so anything
    /// it changes is the bug. `isAutoScrolling` is still set from the settling
    /// phase above, so the path under test is live.
    @Test("A moved pointer keeps the gap on its own line")
    func gapFollowsAMovedPointer() {
        for rowCount in 3...6 {
            let names = Array("abcdefgh".map(String.init).prefix(rowCount))
            let fixture = Fixture(rows: names, height: rowCount + 2)
            var buffer = fixture.render()
            guard let bottom = fixture.rowLines(buffer).last,
                let top = fixture.rowLines(buffer).first
            else {
                Issue.record("\(rowCount): no rows drawn")
                continue
            }
            fixture.hold(at: bottom)
            // Let the rows finish moving first: the steady state is what the
            // report is about.
            for tick in 0..<12 {
                fixture.tui.dragAndDropSession.driveAutoScroll(
                    nowNanos: UInt64(tick) &* 120_000_000)
                fixture.move(to: bottom)
                _ = fixture.render()
            }
            for target in [top, bottom, top, bottom] {
                fixture.move(to: target)
                let answered = fixture.handler?.externalDropSlot
                for frame in 0..<4 {
                    buffer = fixture.render()
                    #expect(
                        fixture.handler?.externalDropSlot == answered,
                        """
                        \(rowCount) rows, moved to line \(target), frame \(frame): \
                        the render moved the gap from \
                        \(answered.map(String.init) ?? "-") to \
                        \(fixture.handler?.externalDropSlot.map(String.init) ?? "-")
                        """)
                }
                #expect(
                    fixture.gapLine(buffer) == target,
                    """
                    \(rowCount) rows: the pointer is on line \(target) and the gap \
                    settled on \(fixture.gapLine(buffer).map(String.init) ?? "-")
                    """)
            }
            fixture.tui.dragAndDropSession.cancelReturningToOrigin()
            fixture.tui.dragAndDropSession.end()
            _ = fixture.render()
        }
    }
}
