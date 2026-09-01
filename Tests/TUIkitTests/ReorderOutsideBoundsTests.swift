//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReorderOutsideBoundsTests.swift
//
//  Where a reorder drag can and cannot land: the rows, and nothing else. A
//  cursor carried past a control's edge is not pointing at its first or last
//  row — it is pointing at nothing — so no drop slot follows it out there.
//
//  What a release out there DOES depends on whether the rows left with the
//  pointer. Under `.cursor` they did (a copy rides it), so releasing is a
//  cancel. Under `.live` and `.dimmed` they did not — both draw the rows
//  inside the control throughout — so releasing commits to what is on screen.
//
//  Both twins, in one file: the rule is one rule, and `List` and `Table` reach
//  it through their own geometry (a title vs a column header, child buffers vs
//  lines of text).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A reorder released off the rows")
struct ReorderOutsideBoundsTests {

    /// The screen line of a control's bottom border.
    private func bottomBorder(_ buffer: FrameBuffer) -> Int {
        buffer.lines.lastIndex { $0.stripped.contains("╰") } ?? -1
    }

    // MARK: - Table

    /// Presses `source`, drags through `via`, then out to `escape` — one render
    /// between each step, as the run loop has.
    private func dragOut(
        _ fixture: TableReorderFixture, from source: String, via: String,
        escapeBy: (FrameBuffer) -> Int, release: Bool = true
    ) -> ItemListHandler<String>? {
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, source)))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, via)))
        fixture.render()
        let away = escapeBy(buffer)
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: away))
        fixture.render()
        let handler = fixture.handler
        if release {
            fixture.dispatcher.dispatch(
                MouseEvent(button: .left, phase: .released, x: 2, y: away))
            fixture.render()
        }
        return handler
    }

    @Test("Table (.cursor): the gap does not follow the cursor out of the table")
    func tableCursorGapDisappearsOutside() {
        let fixture = TableReorderFixture(feedback: .cursor)
        let handler = dragOut(
            fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) + 2 }, release: false)
        #expect(
            handler?.reorder?.targetOffset == nil,
            "a slot below the table is a slot the pointer is nowhere near")
    }

    @Test("Table (.cursor): releasing below the table leaves the order alone")
    func tableCursorReleaseOutsideCancels() {
        let fixture = TableReorderFixture(feedback: .cursor)
        _ = dragOut(fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) + 2 })
        #expect(fixture.rows == ["a", "b", "c", "d", "e"])
    }

    /// `.dimmed` keeps showing the row at the slot it was last over — it has
    /// to, since nothing else on screen is holding it — and the release
    /// commits to exactly that. Dragged from "b" through "d" and out, the
    /// promise on screen was "b after d", so that is what lands.
    @Test("Table (.dimmed): releasing below the table commits the slot it was showing")
    func tableDimmedReleaseOutsideCommits() {
        let fixture = TableReorderFixture(feedback: .dimmed)
        _ = dragOut(fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) + 2 })
        #expect(fixture.rows == ["a", "c", "d", "b", "e"])
    }

    /// `.live` has been moving the rows all along, so committing is simply not
    /// undoing them: "a" dragged through "c" is already at index 2 and stays.
    @Test("Table (.live): releasing below the table leaves the rows where the drag put them")
    func tableLiveReleaseOutsideCommits() {
        let fixture = TableReorderFixture(feedback: .live)
        _ = dragOut(fixture, from: "a", via: "c", escapeBy: { bottomBorder($0) + 2 })
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
    }

    /// The border shares a line with nothing droppable — it is chrome, exactly
    /// as it is for a click (which focuses the control without selecting a row).
    @Test("Table: the bottom border is not the last row")
    func tableBorderIsNotARow() {
        let fixture = TableReorderFixture(feedback: .cursor)
        _ = dragOut(fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) })
        #expect(fixture.rows == ["a", "b", "c", "d", "e"])
    }

    /// The gesture the border rule cost. A `.cursor` drag closes the rows up
    /// behind the row it is carrying, so once the pointer leaves the rows the
    /// row area ends in a blank line where the last row used to be drawn — and
    /// pointing back at that line is what a user does when they meant to drop
    /// on the last row and dipped below it on the way.
    ///
    /// Read as "no band here" it CANCELLED the whole gesture: the row flew home
    /// and the reorder was lost. Every other row worked, and so did the same
    /// excursion off the top, which is what made it look like a rule about the
    /// last row rather than about the line the rows had vacated.
    @Test("Table: dipping below the last row and back still drops")
    func tableDipBelowTheLastRowStillDrops() {
        let fixture = TableReorderFixture(feedback: .cursor)
        let buffer = fixture.render()
        let lastRow = fixture.rowY(buffer, "e")
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        // Below the last row, where `.cursor` forgets its gap and the rows
        // close up under the pointer…
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: bottomBorder(buffer) + 2))
        fixture.render()
        // …then back onto the line the last row was drawn on, which by now is
        // the blank the closing-up left.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: lastRow))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: lastRow))
        fixture.render()
        #expect(fixture.rows == ["a", "c", "d", "b", "e"], "b landed by the last row")
    }

    /// The `List` twin — the rule is the handler's, and the geometry that
    /// exposes it is the same on both sides.
    @Test("List: dipping below the last row and back still drops")
    func listDipBelowTheLastRowStillDrops() {
        let fixture = ListReorderFixture(feedback: .cursor)
        let buffer = fixture.render()
        let lastRow = fixture.rowY(buffer, "e")
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: bottomBorder(buffer) + 2))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: lastRow))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: lastRow))
        fixture.render()
        #expect(fixture.items == ["a", "c", "d", "b", "e"], "b landed by the last row")
    }

    /// The guard against over-correcting: an ordinary drag that never leaves the
    /// rows still lands. (The suites next door cover this at length; it is here
    /// so this file fails loudly if the bound is drawn one line too tight.)
    @Test("Table: a drag that stays on the rows still moves them")
    func tableInsideStillDrops() {
        let fixture = TableReorderFixture(feedback: .cursor)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
    }

    /// The auto-scroll case, which is where this actually bit. A drag held past
    /// an edge keeps the list scrolling, and the retarget that makes the slot
    /// ride the leading edge while the rows stream past it CLAMPS the pointer
    /// onto the rows — right for a chrome line inside the row area (the "N more"
    /// indicator the hot margin sits on), and wrong for a pointer that has left
    /// the control, where it resurrected a gap two lines below the table and let
    /// the release land the rows at the end of the list.
    ///
    /// The engaged flag is asserted too: without it this passes vacuously, on a
    /// drag that never auto-scrolled at all.
    @Test("Table: auto-scrolling past the bottom edge opens no slot out there")
    func tableAutoScrollOutsideOpensNoSlot() {
        let order = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let fixture = TableReorderFixture(rows: order, feedback: .cursor)
        var buffer = fixture.render()
        let away = bottomBorder(buffer) + 2
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        var seen: [String] = []
        for tick in 0..<10 {
            // A real pointer keeps reporting while it is held — one report and
            // the auto-scroll lapses.
            fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: away))
            fixture.tui.dragAndDropSession.driveAutoScroll(
                nowNanos: UInt64(tick) &* 200_000_000)
            buffer = fixture.render()
            seen.append(
                (fixture.handler?.reorder?.targetOffset.map(String.init) ?? "-")
                    + (fixture.handler?.isAutoScrolling == true ? "!" : ""))
        }
        #expect(seen.contains { $0.hasSuffix("!") }, "auto-scroll never engaged: \(seen)")
        #expect(seen.allSatisfy { $0.hasPrefix("-") }, "a slot opened outside: \(seen)")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: away))
        fixture.render()
        #expect(fixture.rows == order)
    }

    // MARK: - List

    private func dragOut(
        _ fixture: ListReorderFixture, from source: String, via: String,
        escapeBy: (FrameBuffer) -> Int, release: Bool = true
    ) -> ItemListHandler<String>? {
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, source)))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, via)))
        fixture.render()
        let away = escapeBy(buffer)
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: away))
        fixture.render()
        let handler = fixture.handler
        if release {
            fixture.dispatcher.dispatch(
                MouseEvent(button: .left, phase: .released, x: 2, y: away))
            fixture.render()
        }
        return handler
    }

    /// A row released over nothing walks back — and used to be back before its
    /// picture was, so for the length of the flight the same row was on screen
    /// twice: once in the list and once in the air above it.
    ///
    /// It now keeps its SPACE and draws nothing in it until the picture lands.
    /// Blank, not absent: taking the row out for the flight would change the
    /// list's length after the gesture is over, which moves the very rows the
    /// user is looking at — so the height is asserted too, and it is the half
    /// of this that a naive fix gets wrong.
    @Test("List (.cursor): a row released over nothing is blank until its picture lands")
    func listReturningRowStaysBlank() {
        let fixture = ListReorderFixture(feedback: .cursor)
        let settled = fixture.render()
        _ = dragOut(fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) + 2 })

        let flying = fixture.render()
        #expect(fixture.tui.dragAndDropSession.returnFlight != nil, "nothing is flying home")
        #expect(
            fixture.rowY(flying, "b") < 0,
            "the row was back before its picture: \(flying.lines.map(\.stripped))")
        #expect(flying.lines.count == settled.lines.count, "the list changed length mid-flight")

        // Land it, as the run loop does — once to start the clock, once past
        // the end.
        let session = fixture.tui.dragAndDropSession
        _ = session.driveReturnFlight(nowNanos: 0)
        _ = session.driveReturnFlight(
            nowNanos: DragAndDropSession.ReturnFlight.durationNanos &+ 1)
        let landed = fixture.render()
        #expect(
            fixture.rowY(landed, "b") >= 0,
            "and never came back: \(landed.lines.map(\.stripped))")
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "the order changed")
    }

    /// The same for the twin. `Table` draws its rows itself rather than from
    /// child buffers, so "blank" is a different piece of code reaching the same
    /// answer — which is exactly the pair that keeps drifting.
    @Test("Table (.cursor): a row released over nothing is blank until its picture lands")
    func tableReturningRowStaysBlank() {
        let fixture = TableReorderFixture(feedback: .cursor)
        let settled = fixture.render()
        _ = dragOut(fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) + 2 })

        let flying = fixture.render()
        #expect(fixture.tui.dragAndDropSession.returnFlight != nil, "nothing is flying home")
        #expect(
            fixture.rowY(flying, "b") < 0,
            "the row was back before its picture: \(flying.lines.map(\.stripped))")
        #expect(flying.lines.count == settled.lines.count, "the table changed height mid-flight")

        let session = fixture.tui.dragAndDropSession
        _ = session.driveReturnFlight(nowNanos: 0)
        _ = session.driveReturnFlight(
            nowNanos: DragAndDropSession.ReturnFlight.durationNanos &+ 1)
        let landed = fixture.render()
        #expect(
            fixture.rowY(landed, "b") >= 0,
            "and never came back: \(landed.lines.map(\.stripped))")
        #expect(fixture.rows == ["a", "b", "c", "d", "e"], "the order changed")
    }

    @Test("List (.cursor): the gap does not follow the cursor out of the list")
    func listCursorGapDisappearsOutside() {
        let fixture = ListReorderFixture(feedback: .cursor)
        let handler = dragOut(
            fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) + 2 }, release: false)
        #expect(handler?.reorder?.targetOffset == nil)
    }

    @Test("List (.cursor): releasing below the list leaves the order alone")
    func listCursorReleaseOutsideCancels() {
        let fixture = ListReorderFixture(feedback: .cursor)
        _ = dragOut(fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) + 2 })
        #expect(fixture.items == ["a", "b", "c", "d", "e"])
    }

    @Test("List (.dimmed): releasing below the list commits the slot it was showing")
    func listDimmedReleaseOutsideCommits() {
        let fixture = ListReorderFixture(feedback: .dimmed)
        _ = dragOut(fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) + 2 })
        #expect(fixture.items == ["a", "c", "d", "b", "e"])
    }

    @Test("List (.live): releasing below the list leaves the rows where the drag put them")
    func listLiveReleaseOutsideCommits() {
        let fixture = ListReorderFixture(feedback: .live)
        _ = dragOut(fixture, from: "a", via: "c", escapeBy: { bottomBorder($0) + 2 })
        #expect(fixture.items == ["b", "c", "a", "d", "e"])
    }

    @Test("List: the bottom border is not the last row")
    func listBorderIsNotARow() {
        let fixture = ListReorderFixture(feedback: .cursor)
        _ = dragOut(fixture, from: "b", via: "d", escapeBy: { bottomBorder($0) })
        #expect(fixture.items == ["a", "b", "c", "d", "e"])
    }

    @Test("List: a drag that stays on the rows still moves them")
    func listInsideStillDrops() {
        let fixture = ListReorderFixture(feedback: .cursor)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.items == ["b", "c", "a", "d", "e"])
    }

    /// The `Table` twin above, through a `List`'s geometry.
    @Test("List: auto-scrolling past the bottom edge opens no slot out there")
    func listAutoScrollOutsideOpensNoSlot() {
        let order = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let fixture = ListReorderFixture(items: order, feedback: .cursor)
        var buffer = fixture.render()
        let away = bottomBorder(buffer) + 2
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        var seen: [String] = []
        for tick in 0..<10 {
            fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: away))
            fixture.tui.dragAndDropSession.driveAutoScroll(
                nowNanos: UInt64(tick) &* 200_000_000)
            buffer = fixture.render()
            seen.append(
                (fixture.handler?.reorder?.targetOffset.map(String.init) ?? "-")
                    + (fixture.handler?.isAutoScrolling == true ? "!" : ""))
        }
        #expect(seen.contains { $0.hasSuffix("!") }, "auto-scroll never engaged: \(seen)")
        #expect(seen.allSatisfy { $0.hasPrefix("-") }, "a slot opened outside: \(seen)")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: away))
        fixture.render()
        #expect(fixture.items == order)
    }
}
