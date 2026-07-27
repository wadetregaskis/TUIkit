//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListReorderDragTests.swift
//
//  Mouse drag-to-reorder for an editable `List { ForEach(...).onMove }`: a
//  press picks up a row, the drag shows where it would land, and the row ends
//  up there. What the drag SHOWS is ``RowReorderFeedback``'s business — the
//  default `.live` reorders as the cursor moves, while `.ghost` and `.cursor`
//  open a slot where the row would land (a faint copy of it, and an empty gap,
//  respectively) and move nothing until the drop — so the tests below cover the
//  common gestures once and then each mode's own contract. Driven end-to-end
//  through the real mouse dispatcher, like the run loop.
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

    // MARK: - .cursor and .ghost: the drop is the move

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

    @Test("A ghost drag shows a FAINT copy at the drop slot, leaving the row itself alone")
    func ghostShowsAFaintCopyAtTheDropSlot() throws {
        let fixture = Fixture(feedback: .ghost)
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        let dragging = fixture.render()

        let rows = dragging.lines.filter { $0.stripped.contains("a") }
        #expect(rows.count == 2, "the row appears twice mid-drag: where it is, and where it'd land")
        // WHICH one is faint is the whole change: the ghost is the preview, so
        // it is the faint one, and the row you picked up is untouched. (An
        // assertion that merely counted a dim line either way passed before and
        // after — position and brightness both have to be pinned.)
        #expect(
            rows.first?.contains(ANSIRenderer.dim) == false,
            "the row itself stays as it was")
        #expect(rows.last?.contains(ANSIRenderer.dim) == true, "…and the copy below is the ghost")
        #expect(
            rowLabels(dragging, of: fixture.items) == ["a", "b", "c", "a", "d", "e"],
            "the ghost sits at the slot the drop would use")
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "the data has not moved yet")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(buffer, "c")))
        #expect(fixture.items == ["b", "c", "a", "d", "e"], "and the drop commits it")
    }

    @Test("A cursor drag leaves an EMPTY gap at the drop slot and dims the row it holds")
    func cursorLeavesAGapAtTheDropSlot() throws {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        let yE = fixture.rowY(buffer, "e")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: yA))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 4, y: fixture.rowY(buffer, "c")))
        let dragging = fixture.render()

        #expect(
            dragging.lines.filter { $0.stripped.contains("a") }.count == 1,
            "no copy of the row anywhere — the gap is what marks the drop")
        #expect(
            dragging.lines.first { $0.stripped.contains("a") }?.contains(ANSIRenderer.dim) == true,
            "…so the dim in place is what says which row is moving")
        #expect(
            rowLabels(dragging, of: fixture.items) == ["a", "b", "c", "d", "e"],
            "the gap carries no label, so the labels themselves are undisturbed")
        #expect(fixture.rowY(dragging, "e") == yE + 1, "…and it pushed the rows below it down")
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

    @Test("A ghost dragged downward sits after the row under the cursor")
    func ghostDownSitsAfterTheTarget() {
        let fixture = Fixture(feedback: .ghost)
        let labels = fixture.items
        let (dragging, y) = midDrag(fixture, from: "a", to: "c")
        #expect(
            rowLabels(dragging, of: labels) == ["a", "b", "c", "a", "d", "e"],
            "dropping on 'c' from above puts the row past it, so that is where the copy goes")
        // And the preview is the promise: what it shows, minus the place the
        // row is going to vacate, is the order the drop produces.
        let promised = ghostPromise(dragging, labels: labels, source: "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: y))
        #expect(rowLabels(fixture.render(), of: labels) == promised)
    }

    @Test("A ghost dragged upward sits before the row under the cursor")
    func ghostUpSitsBeforeTheTarget() {
        let fixture = Fixture(feedback: .ghost)
        let labels = fixture.items
        let (dragging, y) = midDrag(fixture, from: "e", to: "b")
        #expect(
            rowLabels(dragging, of: labels) == ["a", "e", "b", "c", "d", "e"],
            "dropping on 'b' from below puts the row before it")
        let promised = ghostPromise(dragging, labels: labels, source: "e")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: y))
        #expect(rowLabels(fixture.render(), of: labels) == promised)
    }

    /// What a mid-drag `.ghost` frame promises: the order it shows, minus the
    /// row's OLD place. That is the FULL-BRIGHTNESS occurrence — the faint one
    /// is the ghost, and the ghost is where the row ends up.
    private func ghostPromise(
        _ frame: FrameBuffer, labels: [String], source: String
    ) -> [String] {
        var removedOldPlace = false
        return frame.lines.compactMap { line -> String? in
            guard let label = labels.first(where: { line.stripped.contains($0) }) else { return nil }
            guard label == source, !line.contains(ANSIRenderer.dim), !removedOldPlace
            else { return label }
            removedOldPlace = true
            return nil
        }
    }

    @Test(
        "Hovering the row it picked up shows no placeholder",
        arguments: [RowReorderFeedback.ghost, .cursor])
    func noPlaceholderOverTheSourceRow(feedback: RowReorderFeedback) {
        let fixture = Fixture(feedback: feedback)
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        let yE = fixture.rowY(buffer, "e")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        // Out to another row — which DOES earn a placeholder — and back again.
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yA))
        let dragging = fixture.render()

        #expect(
            dragging.lines.filter { $0.stripped.contains("a") }.count == 1,
            "releasing here would move nothing, so there is nothing to preview")
        #expect(
            fixture.rowY(dragging, "e") == yE,
            "…and no gap either: a placeholder of any kind would have pushed 'e' down a line")
        #expect(
            dragging.lines.contains { $0.contains(ANSIRenderer.dim) } == (feedback == .cursor),
            """
            `.cursor` still dims the row it holds — that outlives any drop slot — \
            while `.ghost` says everything with the ghost, and there is no ghost here
            """)
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

    @Test("A ghost is only raised once a drag actually begins")
    func ghostNeedsMotion() {
        let fixture = Fixture(feedback: .ghost)
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
