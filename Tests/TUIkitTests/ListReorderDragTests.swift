//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListReorderDragTests.swift
//
//  Mouse drag-to-reorder for an editable `List { ForEach(...).onMove }`: a
//  press picks up a row, drag moves the focus/drop cue, and the drop commits a
//  single onMove. The list order stays put during the drag (commit-on-release),
//  so the press-frame row geometry the drag closure captured never goes stale.
//  Driven end-to-end through the real mouse dispatcher, like the run loop.
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
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(items: [String] = ["a", "b", "c", "d", "e"], reorderable: Bool = true) {
            self.items = items
            self.reorderable = reorderable
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

        /// Renders the current order and arms the dispatcher.
        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let base = ForEach(items, id: \.self) { Text($0) }
            let forEach =
                reorderable
                ? base.onMove { self.items.move(fromOffsets: $0, toOffset: $1) }
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
}
