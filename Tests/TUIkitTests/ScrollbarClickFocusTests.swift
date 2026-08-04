//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollbarClickFocusTests.swift
//
//  Operating a scrollbar with the mouse focuses the scrollable it belongs to.
//
//  A scrollbar is not a control of its own — it is its scrollable's handle, and
//  (via `ScrollbarColors.focusIndicating`) that scrollable's focus indicator.
//  Clicking it used to drive the view without focusing it: the arrows scrolled
//  and the thumb dragged while the bar stayed unlit, even though a click one
//  column left — on the content — lit it up.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Clicking a scrollbar focuses its scrollable")
struct ScrollbarClickFocusTests {

    /// Two side-by-side overflowing ScrollViews, so a test can focus one and
    /// then click the OTHER's bar. Asserting a MOVE — rather than "is focused"
    /// — is what makes the result meaningful: an overflowing ScrollView adopts
    /// focus on its own when nothing else holds it, so a single-view test would
    /// pass without the click having done anything.
    private func twoScrollViews() -> some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack { ForEach(0..<100, id: \.self) { Text("L\($0)") } }
            }
            .focusID("left")
            .scrollbarVisibility(.visible)
            .frame(width: 12)
            ScrollView {
                VStack { ForEach(0..<100, id: \.self) { Text("R\($0)") } }
            }
            .focusID("right")
            .scrollbarVisibility(.visible)
            .frame(width: 12)
        }
    }

    private func makeContext(
        tui: TUIContext, focusManager: FocusManager, width: Int = 24, height: Int = 10
    ) -> RenderContext {
        var env = EnvironmentValues()
        env.focusManager = focusManager
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui
        ).isolatingRenderCache()
    }

    /// Renders twice and hands the hit regions to the dispatcher.
    ///
    /// Twice because a ScrollView measures its content lazily: on the first
    /// pass extent == viewport, so its bar reports "nothing here to scroll" and
    /// every press lands on an inert gutter. The second pass is the steady
    /// state a user ever actually clicks in.
    private func settled(
        _ view: some View, tui: TUIContext, context: RenderContext
    ) -> MouseEventDispatcher {
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        return dispatcher
    }

    @Test("A press on one ScrollView's bar moves focus off the other")
    func barPressMovesFocus() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = makeContext(tui: tui, focusManager: focusManager)
        let view = twoScrollViews()
        let dispatcher = settled(view, tui: tui, context: context)

        focusManager.focus(id: "left")
        #expect(focusManager.isFocused(id: "left"), "precondition: the left view holds focus")

        // The right view spans x=12…23; its bar is that view's last column.
        // y=5 is mid-track, so this is the "click somewhere down the bar" a
        // user actually makes rather than an end arrow.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 23, y: 5))

        #expect(
            focusManager.isFocused(id: "right"),
            "pressing the right bar focuses the right ScrollView")
        #expect(!focusManager.isFocused(id: "left"), "…and takes focus off the left one")
    }

    @Test("Grabbing the thumb focuses on the press that starts the drag")
    func thumbDragFocuses() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = makeContext(tui: tui, focusManager: focusManager)
        let view = twoScrollViews()
        let dispatcher = settled(view, tui: tui, context: context)

        focusManager.focus(id: "right")

        // x=11 is the left view's last column; y=1 is just below its top arrow,
        // where the thumb sits at offset 0 — so this press grabs the thumb
        // rather than paging the track. Focus has to land on the PRESS: a drag
        // can run for seconds before the button comes up, and the bar it is
        // lighting should be lit for all of it, not from the end of it.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 11, y: 1))

        #expect(
            focusManager.isFocused(id: "left"),
            "grabbing the left thumb focuses the left ScrollView")
    }
}
