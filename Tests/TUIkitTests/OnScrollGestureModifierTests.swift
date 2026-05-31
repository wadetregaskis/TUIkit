//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OnScrollGestureModifierTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Tests for the `.onScrollGesture(_:)` modifier, built on
/// `.onMouseEvent`: it fires its action with a `ScrollDirection` for
/// each scroll-wheel tick inside the view and consumes the event, while
/// ignoring non-scroll events.
@MainActor
@Suite("onScrollGesture")
struct OnScrollGestureModifierTests {

    private final class Recorder {
        var directions: [ScrollDirection] = []
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

    @Test(
        "Each scroll-wheel button maps to its direction and is consumed",
        arguments: [
            (MouseButton.scrollUp, ScrollDirection.up),
            (.scrollDown, .down),
            (.scrollLeft, .left),
            (.scrollRight, .right),
        ])
    func mapsScrollButtonToDirection(_ button: MouseButton, _ direction: ScrollDirection) {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("x").onScrollGesture { recorder.directions.append($0) }

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        let region = buffer.hitTestRegions[0]

        let consumed = dispatcher.dispatch(
            MouseEvent(button: button, phase: .scrolled, x: region.offsetX, y: region.offsetY))

        #expect(consumed)
        #expect(recorder.directions == [direction])
    }

    @Test("A non-scroll event does not fire the scroll action")
    func ignoresNonScroll() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("x").onScrollGesture { recorder.directions.append($0) }

        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        let region = buffer.hitTestRegions[0]

        let consumed = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))

        #expect(!consumed)
        #expect(recorder.directions.isEmpty)
    }
}
