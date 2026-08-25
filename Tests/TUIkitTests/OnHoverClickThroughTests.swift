//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnHoverClickThroughTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// A declined mouse event falls through to the region beneath — for every
/// button. `.onHover` wraps its content in a full-size region that declines
/// everything but hover, and with the left button stopping at the first
/// matching region, a hover-wrapped Button was unclickable.
@MainActor
@Suite("Declined clicks fall through")
struct OnHoverClickThroughTests {

    @Test("A hover-wrapped Button still takes its click")
    func hoverWrappedButtonClicks() {
        var pressed = 0
        var hovered = false
        let context = makeRenderContext(width: 20, height: 4) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.focusManager = FocusManager()
        }
        let view = Button("hit me") { pressed += 1 }
            .onHover { hovered = $0 }

        let buffer = renderToBuffer(view, context: context)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setRegions(buffer.hitTestRegions)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 0))
        #expect(pressed == 1, "the hover wrapper shielded the click")
        _ = hovered
    }
}
