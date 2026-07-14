//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OnTapGestureModifierTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Tests for the `.onTapGesture(_:)` modifier.
///
/// A tap is a left-button press followed by a release. The modifier is
/// built on `.onMouseEvent`: it claims the press (so the release routes
/// back even if the cursor leaves the view) and fires the action on the
/// release, reporting the release position. These tests render a view,
/// feed its hit-test region to the dispatcher, and dispatch synthetic
/// press/release events.
@MainActor
@Suite("onTapGesture")
struct OnTapGestureModifierTests {

    private final class Recorder {
        var taps: [(x: Int, y: Int)] = []
    }

    private func context(width: Int = 40, height: Int = 10) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, tui in
            environment.applyRuntimeServices(from: tui)
        }
    }

    private func regionAndDispatcher(
        _ view: some View, _ ctx: RenderContext
    ) -> (HitTestRegion, MouseEventDispatcher) {
        let buffer = renderToBuffer(view, context: ctx)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        return (buffer.hitTestRegions[0], dispatcher)
    }

    @Test("A press then release fires the tap once, at the release position")
    func pressReleaseFiresTap() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("btn").onTapGesture { x, y in recorder.taps.append((x, y)) }
        let (region, dispatcher) = regionAndDispatcher(view, ctx)

        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))
        // No tap on the press alone.
        #expect(recorder.taps.isEmpty)

        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: region.offsetX + 2, y: region.offsetY + 1))

        #expect(recorder.taps.count == 1)
        #expect(recorder.taps.first?.x == region.offsetX + 2)
        #expect(recorder.taps.first?.y == region.offsetY + 1)
    }

    @Test("The press claims the gesture, so a release outside the view still taps")
    func releaseOutsideStillTaps() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("btn").onTapGesture { x, y in recorder.taps.append((x, y)) }
        let (region, dispatcher) = regionAndDispatcher(view, ctx)

        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))
        let farX = region.offsetX + region.width + 20
        let farY = region.offsetY + region.height + 20
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: farX, y: farY))

        #expect(recorder.taps.count == 1)
        #expect(recorder.taps.first?.x == farX)
        #expect(recorder.taps.first?.y == farY)
    }

    @Test("A right-button click does not fire a tap")
    func rightClickIgnored() {
        let ctx = context()
        let recorder = Recorder()
        let view = Text("btn").onTapGesture { x, y in recorder.taps.append((x, y)) }
        let (region, dispatcher) = regionAndDispatcher(view, ctx)

        _ = dispatcher.dispatch(
            MouseEvent(button: .right, phase: .pressed, x: region.offsetX, y: region.offsetY))
        _ = dispatcher.dispatch(
            MouseEvent(button: .right, phase: .released, x: region.offsetX, y: region.offsetY))

        #expect(recorder.taps.isEmpty)
    }
}
