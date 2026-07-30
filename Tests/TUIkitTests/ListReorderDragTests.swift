//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListReorderDragTests.swift
//
//  Mouse drag-to-reorder for an editable `List { ForEach(...).onMove }`: a
//  press picks up a row, the drag shows where it would land, and the row ends
//  up there. What the drag SHOWS is ``RowReorderFeedback``'s business — the
//  default `.live` reorders as the cursor moves, while `.dimmed` and `.cursor`
//  take the row OUT of the list and open a slot where it would land (holding a
//  faint copy of it, and nothing, respectively — `.cursor` puts the row on the
//  pointer instead) — so what is on screen is already the order a drop would
//  produce. The tests below cover the common gestures once and then each mode's
//  own contract, driven end-to-end through the real mouse dispatcher like the
//  run loop.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("List drag-to-reorder")
struct ListReorderDragTests {

    /// A row-order holder plus the pieces to render it — a reference type so the
    /// `onMove` closure (which fires during a later mouse dispatch, not during
    /// the render that installed it) writes straight back into `items`.
    /// `@MainActor`, so capturing it in the closure is race-free.
    @MainActor
    private final class Fixture {
        var items: [String]
        let reorderable: Bool
        /// How many times `onMove` has fired — the difference between "the list
        /// is the preview" and "the drop is the move".
        private(set) var moves = 0
        /// Rows rendered taller than one line, by label. Variable row heights
        /// are what make the drag's row geometry go stale as rows shuffle.
        var tallRows: [String: Int] = [:]
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(
            items: [String] = ["a", "b", "c", "d", "e"], reorderable: Bool = true,
            feedback: RowReorderFeedback = .live
        ) {
            self.items = items
            self.reorderable = reorderable
            env.focusManager = FocusManager()
            env.rowReorderFeedback = feedback
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

        /// Renders the current order and arms the dispatcher.
        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let tall = tallRows
            let base = ForEach(items, id: \.self) { item in
                Text(
                    tall[item].map { lines in
                        Array(repeating: item, count: lines).joined(separator: "\n")
                    } ?? item)
            }
            let forEach =
                reorderable
                ? base.onMove {
                    self.moves += 1
                    self.items.move(fromOffsets: $0, toOffset: $1)
                }
                : base
            let view = List(selection: .constant(String?.none)) { forEach }
                .frame(height: 9)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
            buffer.lines.firstIndex { $0.stripped.contains(label) } ?? -1
        }

        func drag(from source: String, to target: String) {
            let buffer = render()
            let ySource = rowY(buffer, source)
            let yTarget = rowY(buffer, target)
            dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
            dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
            dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
            render()
        }
    }

    @Test("Dragging a row downward drops it after the target")
    func dragDown() {
        let fixture = Fixture()
        fixture.drag(from: "a", to: "c")
        // "a" (0) dropped onto "c" (2) lands just after it.
        #expect(fixture.items == ["b", "c", "a", "d", "e"])
    }

    @Test("Dragging a row upward drops it before the target")
    func dragUp() {
        let fixture = Fixture()
        fixture.drag(from: "e", to: "b")
        // "e" (4) dragged up onto "b" (1) lands before it.
        #expect(fixture.items == ["a", "e", "b", "c", "d"])
    }

    @Test("A press/release with no motion selects — it does not reorder")
    func clickDoesNotReorder() {
        let fixture = Fixture()
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        // No .dragged between press and release → a plain click.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yA))
        fixture.render()
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "order is untouched by a click")
    }

    @Test("Dropping a row back onto itself is a no-op")
    func dragToSameRowIsNoOp() {
        let fixture = Fixture()
        fixture.drag(from: "c", to: "c")
        #expect(fixture.items == ["a", "b", "c", "d", "e"])
    }

    @Test("A non-reorderable list (no onMove) is never reordered by a drag")
    func noOnMoveDoesNotReorder() {
        let fixture = Fixture(reorderable: false)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "a plain list is never reordered")
    }

    // MARK: - .live: the list is the preview

    @Test("A live drag reorders as the cursor moves, before any release")
    func liveReordersDuringTheDrag() {
        let fixture = Fixture()
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        #expect(
            fixture.items == ["b", "c", "a", "d", "e"],
            "the point of `.live`: no release yet, and the row has already moved")
    }

    @Test("A live drag issues one onMove per slot crossed")
    func liveMovesOncePerSlot() {
        let fixture = Fixture()
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        for label in ["b", "c", "d"] {
            fixture.dispatcher.dispatch(
                MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, label)))
            fixture.render()
        }
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(buffer, "d")))
        #expect(fixture.items == ["b", "c", "d", "a", "e"])
        #expect(
            fixture.moves == 3,
            """
            one per slot — and NOT a fourth on release: `.live` has already \
            arrived, so committing again would move the row one slot past \
            where the user let go.
            """)
    }

    @Test("A live drag that returns to where it started leaves the order alone")
    func liveDragBackIsNetZero() {
        let fixture = Fixture()
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        let yC = fixture.rowY(buffer, "c")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yC))
        fixture.render()
        // Back to the top row — which, the rows having shuffled, is now "b".
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yA))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yA))
        #expect(fixture.items == ["a", "b", "c", "d", "e"])
    }

    @Test("A live drag hit-tests against the CURRENT rows, not the press frame")
    func liveDragReadsFreshRowGeometry() {
        // A tall first row makes the two orders disagree about which row owns a
        // given line — with press-frame geometry the second drag below reads
        // the line under the cursor as the row ABOVE the one that is really
        // drawn there, and shoves "a" straight back where it came from.
        let fixture = Fixture(items: ["a", "b", "c", "d"])
        fixture.tallRows = ["a": 3]
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        #expect(fixture.items == ["b", "a", "c", "d"], "…and now 'a' spans the three lines below 'b'")

        // Nudge back up ONE line — still within the dragged row's own (now
        // three-line) band, so nothing should move.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yA + 2))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yA + 2))
        #expect(
            fixture.items == ["b", "a", "c", "d"],
            "the cursor is still over the dragged row itself — a live drag holds still there")
    }

    // MARK: - .cursor and .dimmed: the drop is the move

    @Test("Cursor feedback leaves the order alone until the drop")
    func cursorDefersTheMove() {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "nothing has moved yet")
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(buffer, "c")))
        #expect(fixture.items == ["b", "c", "a", "d", "e"])
        #expect(fixture.moves == 1, "one move for the whole gesture")
    }

    @Test("A dimmed drag takes the row out of its place and shows it faint at the slot")
    func dimmedShowsTheRowAtTheSlotOnly() throws {
        let fixture = Fixture(feedback: .dimmed)
        let buffer = fixture.render()
        let height = buffer.height
        let yA = fixture.rowY(buffer, "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        let dragging = fixture.render()

        let rows = dragging.lines.filter { $0.stripped.contains("a") }
        #expect(rows.count == 1, "the row is drawn ONCE — at the slot, not in its old place")
        #expect(rows.first?.contains(ANSIRenderer.dim) == true, "…and it is the faint copy")
        #expect(
            rowLabels(dragging, of: fixture.items) == ["b", "c", "a", "d", "e"],
            "so the preview IS the result: this is the order the drop produces")
        #expect(dragging.height == height, "the list keeps its length — nothing was inserted")
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "the data has not moved yet")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(buffer, "c")))
        #expect(fixture.items == ["b", "c", "a", "d", "e"], "and the drop commits exactly that")
    }

    @Test("A cursor drag takes the row out and leaves an EMPTY slot")
    func cursorLeavesAnEmptySlot() throws {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        let height = buffer.height
        let yA = fixture.rowY(buffer, "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: yA))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 4, y: fixture.rowY(buffer, "c")))
        let dragging = fixture.render()

        #expect(
            !dragging.lines.contains { $0.stripped.contains("a") },
            "the row is not drawn anywhere — the gap is where it would land")
        #expect(rowLabels(dragging, of: fixture.items) == ["b", "c", "d", "e"])
        #expect(dragging.height == height, "the list keeps its length")
    }

    /// The measured `.cursor` oscillation: after each step the pointer rests on
    /// the gap, and the gap used to read as "off the rows", which made a
    /// `.cursor` drag clear its own target every other row.
    @Test("The slot advances one row per step and never vanishes")
    func slotAdvancesEveryStep() {
        for feedback in [RowReorderFeedback.dimmed, .cursor] {
            let fixture = Fixture(feedback: feedback)
            let buffer = fixture.render()
            var y = fixture.rowY(buffer, "a")
            fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: y))

            var slots: [Int] = []
            for _ in 0..<4 {
                y += 1
                fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: y))
                slots.append(slotLine(fixture.render(), feedback: feedback))
            }
            #expect(
                slots == [1, 2, 3, 4],
                "\(feedback): one row per step, monotonically — got \(slots)")
        }
    }

    /// Where the drop slot is, in list-body lines. Under `.dimmed` it is the
    /// faint copy of the row; under `.cursor` it is the one blank line.
    private func slotLine(_ frame: FrameBuffer, feedback: RowReorderFeedback) -> Int {
        let body = frame.lines.dropFirst().dropLast()  // strip the border rows
        let index: Int?
        switch feedback {
        case .dimmed:
            index = body.firstIndex { $0.contains(ANSIRenderer.dim) }
        case .cursor, .live:
            index = body.firstIndex { line in
                let inner = line.stripped.dropFirst().dropLast()  // strip │ … │
                return inner.allSatisfy { $0 == " " }
            }
        }
        return index.map { $0 - body.startIndex } ?? -1
    }

    /// The item labels down the rendered list, one per line they appear on —
    /// the drag's preview read back in visual order.
    private func rowLabels(_ buffer: FrameBuffer, of items: [String]) -> [String] {
        buffer.lines.compactMap { line in items.first { line.stripped.contains($0) } }
    }

    /// Presses `source`, drags to `target`, and returns the mid-drag frame plus
    /// the row the cursor is resting on — so the caller can release right there.
    private func midDrag(
        _ fixture: Fixture, from source: String, to target: String
    ) -> (frame: FrameBuffer, y: Int) {
        let buffer = fixture.render()
        let y = fixture.rowY(buffer, target)
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, source)))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: y))
        return (fixture.render(), y)
    }

    @Test("A row dragged downward sits after the row under the cursor")
    func dimmedDownSitsAfterTheTarget() {
        let fixture = Fixture(feedback: .dimmed)
        let labels = fixture.items
        let (dragging, y) = midDrag(fixture, from: "a", to: "c")
        #expect(
            rowLabels(dragging, of: labels) == ["b", "c", "a", "d", "e"],
            "dropping on 'c' from above puts the row past it")
        // And the preview is the promise: what it shows, minus the place the
        // row is going to vacate, is the order the drop produces.
        let promised = rowLabels(dragging, of: labels)
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: y))
        #expect(rowLabels(fixture.render(), of: labels) == promised)
    }

    @Test("A row dragged upward sits before the row under the cursor")
    func dimmedUpSitsBeforeTheTarget() {
        let fixture = Fixture(feedback: .dimmed)
        let labels = fixture.items
        let (dragging, y) = midDrag(fixture, from: "e", to: "b")
        #expect(
            rowLabels(dragging, of: labels) == ["a", "e", "b", "c", "d"],
            "dropping on 'b' from below puts the row before it")
        let promised = rowLabels(dragging, of: labels)
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: y))
        #expect(rowLabels(fixture.render(), of: labels) == promised)
    }

    /// The row's own place is a destination like any other, and the preview
    /// shows it like any other: the row leaves its place and the slot opens
    /// where it was. Putting a row back where it came from is a thing a user may
    /// want to do, and mid-drag it is the only way to change their mind — so the
    /// preview has to keep tracking the cursor across that row rather than going
    /// inert over it.
    @Test(
        "A drag over its own row previews dropping it back",
        arguments: [RowReorderFeedback.dimmed, .cursor])
    func sourceRowIsADropTarget(feedback: RowReorderFeedback) {
        let fixture = Fixture(feedback: feedback)
        let buffer = fixture.render()
        let labels = fixture.items
        let yA = fixture.rowY(buffer, "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        // Movement within the same row: a reorder gesture, targeting the row's
        // own slot.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 6, y: yA))
        let dragging = fixture.render()

        #expect(dragging.height == buffer.height, "the list keeps its height")
        switch feedback {
        case .dimmed:
            #expect(
                rowLabels(dragging, of: labels) == labels,
                "the row previews back in its own place, so the order reads unchanged")
            #expect(
                dragging.lines.contains { $0.contains(ANSIRenderer.dim) },
                "…and it is the dimmed preview, not the row itself")
        case .cursor:
            #expect(
                rowLabels(dragging, of: labels) == ["b", "c", "d", "e"],
                "the row is carried, leaving a blank slot where it would land")
        case .live:
            break
        }

        // Releasing there changes nothing, which is the point of being able to
        // do it.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 6, y: yA))
        #expect(rowLabels(fixture.render(), of: labels) == labels)
    }

    /// `.cursor`'s whole distinction from `.dimmed`: the row you have hold of is
    /// drawn ON the pointer, so the gesture reads as carrying it rather than as
    /// the list rearranging itself around an invisible hand. The list draws the
    /// gap; the drag session draws the row, above every other view.
    @Test("A cursor drag carries the row on the pointer")
    func cursorFloatsTheRowAtThePointer() throws {
        // Multi-cell labels, so the press can land in the MIDDLE of a row and
        // the grab point is something other than its corner.
        let fixture = Fixture(items: ["alpha", "bravo", "charlie", "delta"], feedback: .cursor)
        let buffer = fixture.render()
        let session = fixture.tui.dragAndDropSession
        // A row's content starts at column 2 — past the border and the gutter
        // `renderPlainLine` prefixes — so this press lands on the label's third
        // cell.
        let grabbedCell = 2
        let pressX = 2 + grabbedCell
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: pressX, y: fixture.rowY(buffer, "alpha")))
        #expect(session.active == nil, "a press alone may still be a click — nothing floats yet")

        fixture.dispatcher.dispatch(
            MouseEvent(
                button: .left, phase: .dragged, x: pressX, y: fixture.rowY(buffer, "charlie")))
        fixture.render()
        let drag = try #require(session.active, "the dragged row is riding the pointer")
        #expect(
            drag.preview.lines.contains { $0.stripped.contains("alpha") },
            "…and it is the row that was grabbed")
        #expect(drag.preview.hitTestRegions.isEmpty, "a floating copy must not be clickable")

        // It TRACKS: the preview frame follows every movement rather than
        // sitting where the drag began — and it tracks by the GRABBED cell, so
        // the row stays put under the pointer instead of jumping to align its
        // corner there.
        let first = try #require(session.previewFrame())
        #expect(first.x + grabbedCell == pressX, "the pressed cell is under the pointer")

        let movedX = pressX + 1
        fixture.dispatcher.dispatch(
            MouseEvent(
                button: .left, phase: .dragged, x: movedX, y: fixture.rowY(buffer, "delta")))
        fixture.render()
        let second = try #require(session.previewFrame())
        #expect(second.x == first.x + 1 && second.y == first.y + 1, "the row moves with the pointer")
        #expect(second.x + grabbedCell == movedX, "…and still by the cell that was grabbed")

        fixture.dispatcher.dispatch(
            MouseEvent(
                button: .left, phase: .released, x: movedX, y: fixture.rowY(buffer, "delta")))
        #expect(session.active == nil, "the drop puts the row back in the list — nothing floats on")
        #expect(fixture.items == ["bravo", "charlie", "delta", "alpha"])
    }

    /// With the pointer off the rows there is no drop slot, but the row is still
    /// in the user's hand — so it stays on the pointer, and stays out of the
    /// list. Drawn in both places it would read as a duplicate.
    @Test("A cursor drag off the rows keeps carrying the row")
    func cursorOffTheRowsStillFloats() throws {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        let session = fixture.tui.dragAndDropSession
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        fixture.render()
        // Out of the content columns entirely — the gap goes with it.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 0, y: 0))
        let dragging = fixture.render()

        #expect(session.active != nil, "still carrying it")
        #expect(
            !dragging.lines.contains { $0.stripped.contains("a") },
            "and still out of the list, so the row is never drawn twice")
        // A row in your hand is not a row hidden below the fold. The viewport
        // is sized from the DATA window, so taking the dragged row out of the
        // DRAWING must not make the List claim there is more to scroll to.
        #expect(
            !dragging.lines.contains { $0.stripped.contains("below") },
            "and no phantom overflow indicator for the row being carried")

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 0, y: 0))
        #expect(session.active == nil, "the cancelled drop ends the drag too")
        #expect(fixture.items == ["a", "b", "c", "d", "e"])
    }

    // MARK: - Edge auto-scroll

    /// Dragging a row past the last visible one has to scroll the list, or a
    /// long list can only be reordered within one screenful. The driver was
    /// gated on a payload drag, which only `.cursor` opens — so the two modes
    /// people actually use were invisible to it.
    @Test(
        "A reorder drag arms the edge auto-scroll in every feedback mode",
        arguments: [RowReorderFeedback.live, .dimmed, .cursor])
    func reorderArmsAutoScroll(feedback: RowReorderFeedback) {
        let fixture = Fixture(feedback: feedback)
        let buffer = fixture.render()
        let session = fixture.tui.dragAndDropSession
        #expect(!session.autoScrollArmed, "nothing dragging yet")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        #expect(session.autoScrollArmed, "\(feedback) must reach the auto-scroll driver")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(buffer, "a")))
        #expect(!session.autoScrollArmed, "and disarm on the drop")
    }

    /// Escape mid-drag used to fall through to the page — the Example's
    /// "⎋ back" navigated out from under a live drag while the floating
    /// preview kept compositing over the new page until the button came up.
    @Test("Escape cancels a drag in flight, and its release is not a click")
    func escapeCancelsAMouseDrag() {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        let session = fixture.tui.dragAndDropSession
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "d")))
        fixture.render()
        #expect(session.active != nil, "carrying a row")

        #expect(fixture.env.focusManager?.dispatchKeyEvent(KeyEvent(key: .escape)) == true)
        #expect(session.active == nil, "the floating row goes down at once")
        fixture.render()
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "and the row goes back")

        // The button is still down — the release must not land as a click.
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(buffer, "d")))
        fixture.render()
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "nothing moved on the way out")
    }

    @Test("Dragging a cursor-mode row out of the list cancels the drop")
    func cursorDragOutCancels() {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        // Out of the rows entirely — the gap goes, so the drop must do nothing.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 0, y: 0))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 0, y: 0))
        #expect(
            fixture.items == ["a", "b", "c", "d", "e"],
            "releasing where no slot is shown leaves the order alone")
    }

    /// The reported hole: once the row leaves its place, the line it came from is
    /// occupied by its successor — and dragging back over that line did nothing,
    /// because the successor still named its own DATA offset as the drop target.
    /// Its own place is the one destination a user is most likely to want back,
    /// and it was the only one they could not reach.
    @Test(
        "Dragging back over the row's own line previews putting it back",
        arguments: [RowReorderFeedback.dimmed, .cursor])
    func draggingBackToTheStartPutsItBack(feedback: RowReorderFeedback) {
        let fixture = Fixture(feedback: feedback)
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yA + 3))
        #expect(slotLine(fixture.render(), feedback: feedback) == 3, "sanity: the slot went with it")

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yA))
        #expect(
            slotLine(fixture.render(), feedback: feedback) == 0,
            "\(feedback): the slot comes back to the line the pointer is on")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yA))
        #expect(
            fixture.items == ["a", "b", "c", "d", "e"],
            "\(feedback): and the drop honours the preview — the row goes back where it was")
    }

    /// The general rule the above is one case of: the slot is always on the line
    /// the pointer is on, whichever way the pointer came. Walking down and back
    /// up is what separates a drop target that means "the position under the
    /// cursor" from one that means "this row's data offset", which only agree
    /// while the pointer is below the slot.
    @Test("The slot follows the pointer back up, one row per step")
    func slotFollowsThePointerBackUp() {
        for feedback in [RowReorderFeedback.dimmed, .cursor] {
            let fixture = Fixture(feedback: feedback)
            let buffer = fixture.render()
            let yA = fixture.rowY(buffer, "a")
            fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
            for step in 1...4 {
                fixture.dispatcher.dispatch(
                    MouseEvent(button: .left, phase: .dragged, x: 2, y: yA + step))
                fixture.render()
            }
            var slots: [Int] = []
            for step in stride(from: 3, through: 0, by: -1) {
                fixture.dispatcher.dispatch(
                    MouseEvent(button: .left, phase: .dragged, x: 2, y: yA + step))
                slots.append(slotLine(fixture.render(), feedback: feedback))
            }
            #expect(slots == [3, 2, 1, 0], "\(feedback): coming back up — got \(slots)")
        }
    }

    @Test("Nothing is disturbed until a drag actually begins")
    func decorationNeedsMotion() {
        let fixture = Fixture(feedback: .dimmed)
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        let pressed = fixture.render()
        #expect(
            pressed.lines.filter { $0.stripped.contains("a") }.count == 1,
            "a press alone might still turn out to be a click, so it shows nothing")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yA))
        #expect(fixture.items == ["a", "b", "c", "d", "e"])
    }
}
