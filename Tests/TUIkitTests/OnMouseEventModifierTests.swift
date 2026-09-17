//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnMouseEventModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Tests for the `.onMouseEvent(_:)` modifier (`OnMouseEventModifier`).
///
/// The modifier renders its content, then registers a handler with the
/// frame's `MouseEventDispatcher` and emits a `HitTestRegion` covering the
/// rendered bounds. These tests render a view, feed the regions to the
/// dispatcher (as the render loop does), dispatch synthetic mouse events,
/// and assert the handler sees them — including the drag-tracking rule
/// where, once a button-down is consumed, subsequent drag/release for that
/// button route to the same handler regardless of cursor position.
@MainActor
@Suite("OnMouseEventModifier")
struct OnMouseEventModifierTests {

    /// Collects events a handler receives (a reference type avoids any
    /// mutable-capture concerns in the escaping handler closure).
    private final class Recorder {
        var events: [MouseEvent] = []
        func record(_ event: MouseEvent) -> Bool {
            events.append(event)
            return true
        }
    }

    private func context(width: Int = 40, height: Int = 10) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, tui in
            environment.applyRuntimeServices(from: tui)
        }
    }

    @Test("Emits a hit-test region covering the rendered content")
    func emitsRegion() {
        let ctx = context()
        let view = Text("hello").onMouseEvent { _ in true }

        let buffer = renderToBuffer(view, context: ctx)

        #expect(!buffer.hitTestRegions.isEmpty)
        let region = buffer.hitTestRegions[0]
        #expect(region.width == buffer.width)
        #expect(region.height == buffer.height)
    }

    @Test("A click inside the region is delivered to the handler")
    func clickInsideRegionDelivered() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("hello").onMouseEvent(recorder.record)

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        let region = buffer.hitTestRegions[0]
        let consumed = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))

        #expect(consumed)
        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.phase == .pressed)
    }

    @Test("A click outside the region is not delivered")
    func clickOutsideRegionNotDelivered() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("hi").onMouseEvent(recorder.record)

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        let region = buffer.hitTestRegions[0]
        // Well below the region.
        let consumed = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY + region.height + 5))

        #expect(!consumed)
        #expect(recorder.events.isEmpty)
    }

    @Test("After a consumed button-down, drag and release route to the same handler")
    func dragTrackingFollowsTheHandler() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("target").onMouseEvent(recorder.record)

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        let region = buffer.hitTestRegions[0]
        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))
        // Drag far outside the region — must still reach the handler that
        // claimed the button-down.
        let farX = region.offsetX + region.width + 20
        let farY = region.offsetY + region.height + 20
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: farX, y: farY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: farX, y: farY))

        #expect(recorder.events.map(\.phase) == [.pressed, .dragged, .released])
    }

    @Test("A release reaches the press handler even when its id resolves elsewhere")
    func releaseSurvivesReRenderBetweenPressAndRelease() {
        // Regression test for the "first menu click always opens item 0" bug.
        // A consumed press requests a render, so a render routinely happens
        // BETWEEN a click's press and its release, and `beginRenderPass` clears
        // the handler table: what an id resolves to by the release is whatever
        // registered under it on the frame in between. The drag/press capture
        // must therefore hold the handler itself, not its id.
        //
        // Ids are interned per control now, so no control can inherit another's
        // by accident — which is what this bug WAS, a menu page renumbering
        // every row from zero. The decoy below is put under the target's id
        // deliberately, because the property the capture has to keep is the
        // stronger one: the release goes to the handler that TOOK the press,
        // whatever the table says by then.
        let ctx = context()
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let target = Recorder()
        let decoy = Recorder()

        // Frame 0: only the target is registered; it claims the press.
        dispatcher.beginRenderPass()
        let targetID0 = dispatcher.register(target.record)
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 3, handlerID: targetID0)
        ])
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 1))
        #expect(target.events.map(\.phase) == [.pressed])

        // Frame 1 (the render the press triggered): the target's id now resolves
        // to a DECOY, and the target answers to a different one.
        dispatcher.beginRenderPass()
        let decoyID = dispatcher.register(id: targetID0, decoy.record)
        let targetID1 = dispatcher.register(target.record)
        #expect(decoyID == targetID0, "decoy must sit under the target's frame-0 id")
        #expect(targetID1 != targetID0, "an id is never handed out twice")
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 3, handlerID: targetID1),
            HitTestRegion(offsetX: 20, offsetY: 0, width: 10, height: 3, handlerID: decoyID),
        ])

        // The release must go to the handler that took the press (target),
        // never to the decoy sitting under its old id.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 1, y: 1))

        #expect(decoy.events.isEmpty, "release leaked to the handler under the stale id")
        #expect(target.events.map(\.phase) == [.pressed, .released])
    }
}
