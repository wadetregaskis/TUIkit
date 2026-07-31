//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListReorderMultiRowTests.swift
//
//  Reordering SEVERAL rows at once: grabbing any row of a multi-selection takes
//  the whole selection, the rows travel as a block and land as one, and what
//  that looks like depends on the feedback mode — `.live` shuffles them through
//  the data, `.dimmed` shows a faint copy of each at the slot, `.cursor` floats
//  them all on the pointer.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("List drag-to-reorder: several rows")
struct ListReorderMultiRowTests {

    /// Every row in hand has to be visible and moving. The slot stands for the
    /// whole block, so it is as tall as the rows it holds — showing only the
    /// grabbed one looked exactly like the rest had been deleted.
    @Test("A dimmed multi-row drag shows every row it is carrying")
    func dimmedMultiRowShowsThemAll() {
        let fixture = ListReorderFixture(feedback: .dimmed)
        fixture.selection = ["a", "b"]
        let buffer = fixture.render()
        let height = buffer.height
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "d")))
        let dragging = fixture.render()
        #expect(fixture.handler?.heldRowCount == 2, "the whole selection came")

        let lines = dragging.lines.map(\.stripped)
        #expect(lines.contains { $0.contains("a") }, "the grabbed row is on screen")
        #expect(lines.contains { $0.contains("b") }, "and so is the one travelling with it")
        #expect(dragging.height == height, "and the list is no taller for it")
    }

    /// `.cursor` carries the block on the pointer, so the float is as tall as
    /// the block: one line per row, not just the row that was grabbed.
    @Test("A cursor multi-row drag floats every row it is carrying")
    func cursorMultiRowFloatsThemAll() {
        let fixture = ListReorderFixture(feedback: .cursor)
        fixture.selection = ["a", "b"]
        let buffer = fixture.render()
        let session = fixture.tui.dragAndDropSession
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "d")))
        fixture.render()

        let preview = session.active?.preview
        #expect(preview?.height == 2, "both rows ride the pointer")
        let floating = (preview?.lines ?? []).map(\.stripped)
        #expect(floating.first?.contains("a") == true)
        #expect(floating.last?.contains("b") == true)
        // Grabbed by its SECOND row, so the block hangs one line higher than
        // its top — otherwise it jumps up under the pointer as the drag starts.
        #expect(session.active?.grabY == 1, "the grabbed row stays under the cursor")
    }

    /// The mode a drag was drawn in has to be the mode its drop commits in.
    /// `effectiveReorderFeedback` is DERIVED from the reorder state, so reading
    /// it after that state is torn down answered a different question: a
    /// multi-row `.live` drag previewed with a slot (several rows in hand never
    /// shuffle live) and then dropped as though `.live` had already moved the
    /// data — which it never had. The gesture did nothing at all.
    @Test("A multi-row drop commits in the mode the drag was drawn in")
    func multiRowLiveDropActuallyMoves() {
        let fixture = ListReorderFixture(feedback: .live)
        fixture.selection = ["a", "b"]
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.render()
        #expect(fixture.handler?.heldRowCount == 2, "the whole selection came")
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "d")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(buffer, "d")))
        fixture.render()
        #expect(fixture.items != ["a", "b", "c", "d", "e"], "the rows actually moved")
    }

    /// `.live` means the list itself is the preview, and that has to hold for a
    /// block as much as for one row: the rows shuffle as the pointer crosses
    /// slots, staying together and staying in their own order. (A keyboard move
    /// still previews with a slot — it has a cancel, and one `onMove` cannot
    /// scatter a gathered block back.)
    @Test("A live multi-row mouse drag shuffles the block as it goes")
    func liveMultiRowShufflesAsItGoes() {
        let fixture = ListReorderFixture(feedback: .live)
        fixture.selection = ["a", "b"]
        var buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.render()
        #expect(fixture.handler?.effectiveReorderFeedback == .live, "the mouse keeps live")

        // Onto "c": the block lands after it, as a single-row drag would.
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        buffer = fixture.render()
        #expect(fixture.items == ["c", "a", "b", "d", "e"], "no release needed — that is `.live`")

        // And again, from where the rows are NOW.
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "d")))
        buffer = fixture.render()
        #expect(fixture.items == ["c", "d", "a", "b", "e"], "the block moves as one")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        #expect(
            fixture.items == ["c", "d", "a", "b", "e"],
            "and the drop commits nothing further — live already arrived")
    }

    /// Back up the way it came: dragging the block upward lands it BEFORE the
    /// row under the pointer, which is the same asymmetry one row has.
    @Test("A live multi-row drag upward lands before the row it is over")
    func liveMultiRowDragsUpward() {
        let fixture = ListReorderFixture(feedback: .live)
        fixture.selection = ["d", "e"]
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "e")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        #expect(fixture.items == ["a", "d", "e", "b", "c"])
    }

    /// Dragging a row straight DOWN out of the list is the ordinary way to
    /// abandon a `.cursor` reorder — and it keeps the pointer inside the
    /// content columns the whole way, which is what the old "nowhere to land"
    /// test actually measured. So the row vanished under the pointer instead of
    /// walking home.
    @Test("A cursor reorder released below the last row flies home")
    func reorderReleasedPastTheRowsFliesHome() {
        let fixture = ListReorderFixture(feedback: .cursor)
        let buffer = fixture.render()
        let session = fixture.tui.dragAndDropSession
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        fixture.render()
        // Straight down, past the last row, still in the content columns.
        let belowTheRows = buffer.height + 4
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: belowTheRows))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: belowTheRows))
        fixture.render()

        #expect(fixture.items == ["a", "b", "c", "d", "e"], "nothing moved")
        #expect(session.returnFlight != nil, "and the row walks back to its place")
    }
    /// The slot's "you are steering this" emphasis is painted by the ROW
    /// renderer, not baked into the slot's buffer. Baked in, it began one cell
    /// late — the selection gutter is added AROUND the buffer — so the row's
    /// first cell stayed at the terminal's default colours while the rest of the
    /// line was highlighted.
    @Test("The held slot's emphasis covers the row's first cell")
    func heldSlotEmphasisReachesTheFirstCell() {
        let fixture = ListReorderFixture(feedback: .dimmed)
        _ = fixture.render()
        // Focus the list and pick a row up from the KEYBOARD — the only gesture
        // that emphasises the slot (a mouse drag has the pointer to say where
        // the row is).
        _ = fixture.env.focusManager?.dispatchKeyEvent(KeyEvent(key: .down))
        _ = fixture.env.focusManager?.dispatchKeyEvent(
            KeyEvent(key: .character("r"), ctrl: true))
        let held = fixture.render()

        let slotLine = try? #require(
            held.lines.first { $0.contains("\u{1b}[48;") && !$0.stripped.isEmpty })
        // Everything before the highlight starts is the list's own BORDER. The
        // row's first cell — the selection gutter — must be inside it; it used
        // to be the one cell left unpainted.
        let ahead = (slotLine?.components(separatedBy: "\u{1b}[48;").first ?? "?").stripped
        #expect(
            ahead.allSatisfy { "│┃|".contains($0) },
            "only the border precedes the highlight: \(ahead.debugDescription)")
    }

    @Test("A block in hand still shows which row the cursor is on")
    func multiRowKeyboardMoveKeepsTheCursorRow() {
        let fixture = ListReorderFixture(feedback: .dimmed)
        fixture.selection = ["a", "b", "c"]
        _ = fixture.render()
        // Focus the list, then pick the whole selection up from the keyboard.
        _ = fixture.env.focusManager?.dispatchKeyEvent(KeyEvent(key: .down))
        _ = fixture.env.focusManager?.dispatchKeyEvent(
            KeyEvent(key: .character("r"), ctrl: true))
        let grabbed = try? #require(fixture.handler?.reorder?.grabbedOffset)
        let held = fixture.render()

        // The three rows have left the list and are drawn as one slot, which
        // carries the focus pulse across its whole height. The row the cursor is
        // on has to stay picked out inside it: before Ctrl-R it was plainly
        // distinguishable from its selected neighbours, and picking the block up
        // must not take that away. Faint everywhere = an indicator on all three
        // = an indicator on none.
        let faint = ["a", "b", "c"].map { label -> Bool in
            let line = held.lines.first { $0.stripped.contains(label) } ?? ""
            return line.contains("\u{1b}[2m")
        }
        #expect(faint.filter { !$0 }.count == 1, "exactly one row is at full strength")
        #expect(faint[grabbed ?? 0] == false, "and it is the row that was grabbed")
    }
}
