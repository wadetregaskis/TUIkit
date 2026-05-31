//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragGestureModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Tests for the `.onDragGesture(_:)` modifier (`DragGestureModifier`).
///
/// The modifier maps the dispatcher's left-button press/drag/release stream
/// onto `DragGestureEvent`s (`.began` / `.moved` / `.ended`), remembering the
/// gesture's start position so translations are reported relative to it.
/// These tests render a view, feed its hit-test region to the dispatcher,
/// and dispatch a synthetic gesture.
@MainActor
@Suite("DragGestureModifier")
struct DragGestureModifierTests {

    private final class Recorder {
        var events: [DragGestureEvent] = []
        func record(_ event: DragGestureEvent) { events.append(event) }
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

    @Test("press → drag → release yields began/moved/ended with a stable start and correct translation")
    func dragLifecycle() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("knob").onDragGesture(recorder.record)

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        let region = buffer.hitTestRegions[0]
        let startX = region.offsetX
        let startY = region.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: startX, y: startY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: startX + 5, y: startY + 2))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: startX + 7, y: startY + 3))

        #expect(recorder.events.map(\.phase) == [.began, .moved, .ended])
        // The start position is remembered across the whole gesture.
        #expect(recorder.events.allSatisfy { $0.startX == startX && $0.startY == startY })

        let moved = recorder.events[1]
        #expect(moved.x == startX + 5 && moved.y == startY + 2)
        #expect(moved.translationX == 5 && moved.translationY == 2)

        let ended = recorder.events[2]
        #expect(ended.translationX == 7 && ended.translationY == 3)
    }

    @Test("A non-left button does not start a drag gesture")
    func nonLeftButtonIgnored() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("knob").onDragGesture(recorder.record)

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        let region = buffer.hitTestRegions[0]
        _ = dispatcher.dispatch(
            MouseEvent(button: .right, phase: .pressed, x: region.offsetX, y: region.offsetY))

        #expect(recorder.events.isEmpty)
    }
}
