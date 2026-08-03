//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitViewResizeAnchorTests.swift
//
//  A resize — by drag or by arrow key — must step from the width the column is
//  actually SHOWING. Under a size-to-fit style nothing is stored for a column
//  until the user pins it, so a resize base read from the width store would be
//  the fallback (the minimum) and the very first interaction would collapse the
//  column instead of nudging it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("NavigationSplitView resize anchors on the displayed width")
struct NavigationSplitViewResizeAnchorTests {

    private func resizeContext(width: Int = 80, height: Int = 12) -> RenderContext {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
    }

    /// The column of the divider grip (a `◦` dot) on the centre row. Under the
    /// size-to-fit style this is exactly the sidebar's width, so it doubles as
    /// the observable "how wide is the sidebar right now".
    private func gripX(_ buffer: FrameBuffer) -> Int? {
        guard buffer.height > 0 else { return nil }
        let mid = buffer.lines[buffer.height / 2].stripped
        guard let r = mid.firstIndex(of: "◦") else { return nil }
        return mid.distance(from: mid.startIndex, to: r)
    }

    /// A size-to-fit split whose sidebar is comfortably wider than
    /// `minimumColumnWidth`, so a collapse to the minimum is unmistakable.
    private func splitView(sidebar: String = "A REASONABLY WIDE SIDEBAR") -> some View {
        NavigationSplitView {
            Text(sidebar)
        } detail: {
            Text("DETAIL")
        }
        .navigationSplitViewStyle(.sizeToFitFromLeft)
    }

    private var splitView: some View { splitView() }

    @Test("Clicking a size-to-fit divider without moving leaves the column alone")
    func clickWithoutDragKeepsWidth() {
        let context = resizeContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let first = renderToBuffer(splitView, context: context)
        let before = gripX(first)
        #expect(before != nil, "the size-to-fit divider draws a grip")
        guard let before else { return }
        dispatcher.setRegions(first.hitTestRegions)

        // Press and release on the divider with no motion in between: the
        // classic "click the handle to see what it does" gesture. `event.x` is
        // localised to the press, so both events carry a delta of zero.
        let y = first.height / 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: before, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: before, y: y))

        let after = gripX(renderToBuffer(splitView, context: context))
        #expect(
            after == before,
            "a zero-delta click must not resize: was \(before), now \(String(describing: after))")
    }

    @Test("Clicking a size-to-fit divider does not pin the column: it keeps tracking content")
    func clickWithoutDragLeavesTheColumnTracking() {
        let context = resizeContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let first = renderToBuffer(splitView, context: context)
        guard let x = gripX(first) else { Issue.record("expected a divider grip"); return }
        dispatcher.setRegions(first.hitTestRegions)

        let y = first.height / 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        // Widen the content. A column that is merely SHOWING its content width
        // grows with it; one the click has pinned stays put — which is what
        // writing the width back on a zero-delta click would have done, even
        // though the click looked harmless at the time. The yardstick is the
        // same split in a context that was never clicked.
        let wide = "A CONSIDERABLY WIDER SIDEBAR THAN BEFORE"
        let expected = gripX(renderToBuffer(splitView(sidebar: wide), context: resizeContext()))
        let wider = gripX(renderToBuffer(splitView(sidebar: wide), context: context))
        #expect(expected != x, "the yardstick must actually differ from the clicked width")
        #expect(
            wider == expected,
            "the clicked column still fits its content: \(String(describing: wider)) vs untouched \(String(describing: expected))")
    }

    @Test("The first arrow key on a size-to-fit divider steps from the shown width")
    func firstArrowKeyStepsFromShownWidth() {
        let context = resizeContext()
        let focusManager = context.environment.focusManager!

        let first = renderToBuffer(splitView, context: context)
        let before = gripX(first)
        #expect(before != nil, "the size-to-fit divider draws a grip")
        guard let before else { return }

        focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .right))

        let after = gripX(renderToBuffer(splitView, context: context))
        #expect(
            after == before + 1,
            "→ widens by one from the shown width: was \(before), now \(String(describing: after))")
    }
}
