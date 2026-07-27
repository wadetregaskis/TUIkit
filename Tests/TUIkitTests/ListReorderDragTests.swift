//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListReorderDragTests.swift
//
//  Mouse drag-to-reorder for an editable `List { ForEach(...).onMove }`: a
//  press picks up a row, the drag shows where it would land, and the row ends
//  up there. What the drag SHOWS is ``RowReorderFeedback``'s business — the
//  default `.live` reorders as the cursor moves, `.ghost` floats a copy of the
//  row at the cursor, `.cursor` marks the target and moves nothing until the
//  drop — so the tests below cover the common gestures once and then each
//  mode's own contract. Driven end-to-end through the real mouse dispatcher,
//  like the run loop.
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
        var dragSession: DragAndDropSession { tui.dragAndDropSession }

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

    @Test("A ghost drag floats the row itself at the cursor")
    func ghostFloatsTheRow() throws {
        let fixture = Fixture(feedback: .ghost)
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        // The column the row's own content starts at — where a correctly
        // anchored ghost's left edge sits, whatever cell within the row was
        // grabbed.
        let rowContentLeft = buffer.lines[yA].stripped.distance(
            from: buffer.lines[yA].stripped.startIndex,
            to: buffer.lines[yA].stripped.firstIndex(of: "a")!)
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: yA))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 4, y: fixture.rowY(buffer, "c")))

        let drag = try #require(fixture.dragSession.active)
        #expect(
            drag.preview.lines.contains { $0.stripped.contains("a") },
            "the floating copy is the grabbed row")
        #expect(drag.preview.hitTestRegions.isEmpty, "a copy riding the cursor must not be clickable")
        let frame = try #require(fixture.dragSession.previewFrame())
        #expect(
            frame.x == rowContentLeft,
            """
            grab-point anchoring: the pressed cell stays under the cursor, so a \
            press 2 cells into the row leaves the ghost's left edge 2 cells left \
            of the cursor — still lined up with the column it came from.
            """)
        #expect(fixture.items == ["a", "b", "c", "d", "e"], "and the list itself has not moved")
    }

    @Test("Dropping a ghost commits the move and stops floating it")
    func ghostDropEndsTheDrag() {
        let fixture = Fixture(feedback: .ghost)
        let buffer = fixture.render()
        fixture.drag(from: "a", to: "c")
        _ = buffer
        #expect(fixture.items == ["b", "c", "a", "d", "e"])
        #expect(fixture.moves == 1)
        #expect(
            fixture.dragSession.active == nil,
            "a ghost left floating after the drop would sit over the app forever")
    }

    @Test("A ghost is only raised once a drag actually begins")
    func ghostNeedsMotion() {
        let fixture = Fixture(feedback: .ghost)
        let buffer = fixture.render()
        let yA = fixture.rowY(buffer, "a")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yA))
        #expect(
            fixture.dragSession.active == nil,
            "a press alone might still turn out to be a click")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yA))
        #expect(fixture.dragSession.active == nil)
        #expect(fixture.items == ["a", "b", "c", "d", "e"])
    }
}
