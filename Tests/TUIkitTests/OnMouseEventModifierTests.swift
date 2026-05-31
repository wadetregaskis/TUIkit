//  🖥️ TUIKit — Terminal UI Kit for Swift
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
            environment.stateStorage = tui.stateStorage
            environment.lifecycle = tui.lifecycle
            environment.keyEventDispatcher = tui.keyEventDispatcher
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.renderCache = tui.renderCache
            environment.preferenceStorage = tui.preferences
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
}
