//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollDisabledTests.swift
//
//  `.scrollDisabled(_:)` — §1.2 of the scroll-anchoring spec, "whether the
//  end-user may adjust the scroll position at all. When disabled, scrollbars
//  and other scroll chrome still render, in a disabled state."
//
//  The line it draws is USER input versus everything else: gestures stop,
//  programmatic movement and the reveal that keeps a selection on screen do
//  not. A List whose cursor could walk off the viewport for good would be
//  unusable, and an app's own `scrollTo` is not the user adjusting anything.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scrolling can be disabled for the user")
struct ScrollDisabledTests {

    // MARK: - The gate itself, on both handler families

    /// The two scrollable state families, so neither can quietly drift from the
    /// other (`ItemListHandler` backs List and Table; `ScrollViewHandler` backs
    /// ScrollView, and `ScrollAxis` its horizontal axis).
    private func overflowingStates() -> [(name: String, state: any ScrollableOffsetState)] {
        let scrollView = ScrollViewHandler(focusID: "sv")
        scrollView.contentHeight = 100
        scrollView.viewportHeight = 10
        scrollView.wheelEdgeHold.delayNanos = 0

        let list = ItemListHandler<Int>(
            focusID: "list", itemCount: 100, viewportHeight: 10, selectionMode: .single)
        list.wheelEdgeHold.delayNanos = 0

        let axis = ScrollAxis()
        axis.extent = 100
        axis.viewportHeight = 10
        axis.wheelEdgeHold.delayNanos = 0

        return [("ScrollViewHandler", scrollView), ("ItemListHandler", list), ("ScrollAxis", axis)]
    }

    @Test("A disabled scroller ignores the wheel — and chains it, rather than swallowing it")
    func wheelIsIgnoredAndChains() {
        for (name, state) in overflowingStates() {
            state.scrollOffset = 20
            state.isScrollEnabled = false

            let consumed = state.handleWheelEvent(
                MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0))
            #expect(!consumed, "\(name): a blocked tick chains to the enclosing scroller")
            #expect(state.scrollOffset == 20, "\(name): the viewport did not move")

            // And re-enabling restores it — the flag is the only thing stopping it.
            state.isScrollEnabled = true
            #expect(
                state.handleWheelEvent(
                    MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0)),
                "\(name): re-enabled, the same tick is consumed")
            #expect(state.scrollOffset > 20, "\(name): and it moved")
        }
    }

    @Test("A disabled scroller still moves programmatically")
    func programmaticMovementStillWorks() {
        for (name, state) in overflowingStates() {
            state.isScrollEnabled = false
            state.scroll(by: 15)
            #expect(state.scrollOffset == 15, "\(name): scroll(by:) is not a gesture")
            state.scrollOffset = 3
            state.clampScrollOffset()
            #expect(state.scrollOffset == 3, "\(name): the clamp still runs")
        }
    }

    @Test("A disabled ScrollView consumes none of the scroll keys")
    func scrollKeysBubble() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.scrollOffset = 20
        handler.isScrollEnabled = false

        for key in [Key.up, .down, .pageUp, .pageDown, .home, .end, .left, .right] {
            #expect(
                !handler.handleKeyEvent(KeyEvent(key: key)),
                """
                \(key) is not consumed while scrolling is disabled — a view that \
                cannot scroll must not swallow keys something else could use
                """)
        }
        #expect(handler.scrollOffset == 20, "and none of them moved the viewport")
    }

    // MARK: - Through a real render

    private func makeContext(
        width: Int = 24, height: Int = 8, disabled: Bool
    ) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.isScrollEnabled = !disabled
        }
    }

    private func longScrollView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("line \($0)") }
            }
        }
    }

    @Test("The modifier reaches the scrollable's handler")
    func modifierReachesTheHandler() {
        let ctx = makeContext(disabled: false)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let buffer = renderToBuffer(longScrollView().scrollDisabled(true), context: ctx)
        dispatcher.setRegions(buffer.hitTestRegions)

        let before = buffer.lines.map(\.stripped)
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 2))
        let after = renderToBuffer(longScrollView().scrollDisabled(true), context: ctx)
            .lines.map(\.stripped)
        #expect(before == after, "the wheel moved nothing:\n\(after.joined(separator: "\n"))")
    }

    @Test("Without the modifier the very same wheel event does scroll")
    func withoutTheModifierItScrolls() {
        let ctx = makeContext(disabled: false)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let buffer = renderToBuffer(longScrollView(), context: ctx)
        dispatcher.setRegions(buffer.hitTestRegions)

        let before = buffer.lines.map(\.stripped)
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 2))
        let after = renderToBuffer(longScrollView(), context: ctx).lines.map(\.stripped)
        #expect(before != after, "the control case scrolls, so the test above means something")
    }

    @Test("A disabled ScrollView leaves the focus ring")
    func disabledScrollViewIsNotAFocusStop() {
        // Control: an ordinary overflowing ScrollView IS a Tab stop.
        let enabledCtx = makeContext(disabled: false)
        _ = renderToBuffer(longScrollView(), context: enabledCtx)
        _ = enabledCtx.environment.focusManager!.dispatchKeyEvent(KeyEvent(key: .tab))
        #expect(
            enabledCtx.environment.focusManager!.currentFocusedID != nil,
            "the control case takes focus, so the assertion below means something")

        let ctx = makeContext(disabled: true)
        _ = renderToBuffer(longScrollView().scrollDisabled(true), context: ctx)
        let focus = ctx.environment.focusManager!
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        #expect(
            focus.currentFocusedID == nil,
            """
            there is nothing to Tab to — with no scroll command left, a stop is \
            only an obstacle. Focused: \(focus.currentFocusedID ?? "nil")
            """)
    }

    @Test("The scroll chrome still renders when scrolling is disabled")
    func chromeStillRenders() {
        let enabled = renderToBuffer(longScrollView(), context: makeContext(disabled: false))
        let disabled = renderToBuffer(
            longScrollView().scrollDisabled(true), context: makeContext(disabled: true))

        func barCells(_ buffer: FrameBuffer) -> Int {
            buffer.lines.map(\.stripped).reduce(0) { total, line in
                total + line.filter { "▲▼█▓▒░▄▀".contains($0) }.count
            }
        }
        #expect(barCells(enabled) > 0, "the enabled control case draws a bar")
        #expect(
            barCells(disabled) == barCells(enabled),
            """
            §1.2: the chrome still renders, only in a disabled state — it must \
            not vanish, or the view reads as having no more content:
            \(disabled.lines.map(\.stripped).joined(separator: "\n"))
            """)
    }

    @Test("A disabled List still moves its selection, and follows it")
    func listSelectionStillWorks() {
        let selection = SelectionBox()
        let ctx = makeContext(width: 24, height: 6, disabled: true)
        let focus = ctx.environment.focusManager!
        let view = List(selection: selection.binding) {
            ForEach(0..<40, id: \.self) { Text("row \($0)") }
        }
        .scrollDisabled(true)

        _ = renderToBuffer(view, context: ctx)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        for _ in 0..<20 { _ = focus.dispatchKeyEvent(KeyEvent(key: .down)) }
        let lines = renderToBuffer(view, context: ctx).lines.map(\.stripped)

        #expect(
            lines.contains { $0.contains("row 20") },
            """
            moving a cursor is not adjusting a scroll position: the selection \
            walked down and the list revealed it, exactly as it would with \
            scrolling enabled:
            \(lines.joined(separator: "\n"))
            """)
    }
}

/// A `Set<Int>` selection with a `Binding` onto it.
@MainActor
private final class SelectionBox {
    var value: Int?
    var binding: Binding<Int?> { Binding(get: { self.value }, set: { self.value = $0 }) }
}
