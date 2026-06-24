//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Helpers

@MainActor
private func makeContext(width: Int = 40, height: Int = 8) -> RenderContext {
    let tuiContext = TUIContext()
    var environment = EnvironmentValues()
    environment.focusManager = FocusManager()
    environment.stateStorage = tuiContext.stateStorage
    environment.lifecycle = tuiContext.lifecycle
    environment.keyEventDispatcher = tuiContext.keyEventDispatcher
    environment.mouseEventDispatcher = tuiContext.mouseEventDispatcher
    environment.renderCache = tuiContext.renderCache
    environment.preferenceStorage = tuiContext.preferences
    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: tuiContext
    )
}

// MARK: - ScrollViewHandler

@MainActor
@Suite("ScrollViewHandler")
struct ScrollViewHandlerTests {

    @Test("scroll(by:) moves scrollOffset within bounds")
    func scrollMovesWithinBounds() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10

        handler.scroll(by: 5)
        #expect(handler.scrollOffset == 5)
        handler.scroll(by: 3)
        #expect(handler.scrollOffset == 8)
    }

    @Test("scroll(by:) clamps at the top")
    func scrollClampsAtTop() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.scrollOffset = 3

        handler.scroll(by: -10)
        #expect(handler.scrollOffset == 0)
    }

    @Test("scroll(by:) clamps at the bottom")
    func scrollClampsAtBottom() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        // maxOffset = 100 - 10 = 90
        handler.scrollOffset = 80

        handler.scroll(by: 100)
        #expect(handler.scrollOffset == 90)
    }

    @Test("scroll(by:) is a no-op when content fits viewport")
    func scrollNoOpWhenContentFits() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 5
        handler.viewportHeight = 10

        handler.scroll(by: 5)
        #expect(handler.scrollOffset == 0)
    }

    @Test("PageDown scrolls by one viewport")
    func pageDownScrollsByViewport() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 20

        let consumed = handler.handleKeyEvent(KeyEvent(key: .pageDown))
        #expect(consumed)
        #expect(handler.scrollOffset == 20)
    }

    @Test("PageUp scrolls back by one viewport")
    func pageUpScrollsBackByViewport() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 20
        handler.scrollOffset = 50

        _ = handler.handleKeyEvent(KeyEvent(key: .pageUp))
        #expect(handler.scrollOffset == 30)
    }

    @Test("Left/Right keys scroll the horizontal axis")
    func leftRightScrollsHorizontally() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.horizontal.extent = 50
        handler.horizontal.viewportHeight = 10  // viewport width in columns

        #expect(handler.handleKeyEvent(KeyEvent(key: .right)))
        #expect(handler.horizontal.scrollOffset == 1)
        #expect(handler.handleKeyEvent(KeyEvent(key: .left)))
        #expect(handler.horizontal.scrollOffset == 0)
        // At the left edge Left can't move, so it isn't consumed (key bubbles).
        #expect(!handler.handleKeyEvent(KeyEvent(key: .left)))
    }

    @Test("Left/Right are not consumed when content fits horizontally")
    func leftRightNoOpWhenContentFits() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.horizontal.extent = 5
        handler.horizontal.viewportHeight = 10  // content narrower than viewport

        #expect(!handler.handleKeyEvent(KeyEvent(key: .right)))
        #expect(!handler.handleKeyEvent(KeyEvent(key: .left)))
    }

    @Test("End jumps to maxOffset, Home jumps back to zero")
    func endThenHome() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10

        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        #expect(handler.scrollOffset == 90)
        _ = handler.handleKeyEvent(KeyEvent(key: .home))
        #expect(handler.scrollOffset == 0)
    }

    @Test("Arrow keys scroll one line each")
    func arrowKeysOneLineEach() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10

        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.scrollOffset == 3)
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.scrollOffset == 2)
    }

    @Test("Unrelated keys are not consumed")
    func unrelatedKeysNotConsumed() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10

        #expect(!handler.handleKeyEvent(KeyEvent(key: .character("a"))))
        #expect(!handler.handleKeyEvent(KeyEvent(key: .enter)))
        #expect(!handler.handleKeyEvent(KeyEvent(key: .tab)))
    }

    @Test("hasContentAbove / hasContentBelow reflect position")
    func hasContentAboveBelow() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10

        #expect(!handler.hasContentAbove)
        #expect(handler.hasContentBelow)

        handler.scrollOffset = 50
        #expect(handler.hasContentAbove)
        #expect(handler.hasContentBelow)

        handler.scrollOffset = 90
        #expect(handler.hasContentAbove)
        #expect(!handler.hasContentBelow)
    }

    @Test("Wheel is consumed only when it actually moves the viewport (scroll chaining)")
    func wheelConsumedOnlyWhenItMoves() {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10

        // Mid-content: a wheel tick moves the viewport → consumed.
        handler.scrollOffset = 50
        #expect(handler.handleWheelEvent(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0)))

        // At the bottom, scrolling down can't move → NOT consumed, so the
        // dispatcher bubbles the wheel to the enclosing scroller (chaining).
        handler.scrollOffset = handler.maxOffset
        #expect(!handler.handleWheelEvent(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0)))
        #expect(handler.scrollOffset == handler.maxOffset, "offset must be unchanged")

        // At the top, scrolling up can't move → NOT consumed.
        handler.scrollOffset = 0
        #expect(!handler.handleWheelEvent(
            MouseEvent(button: .scrollUp, phase: .scrolled, x: 0, y: 0)))

        // Content that fits the viewport entirely never consumes the wheel.
        let fits = ScrollViewHandler(focusID: "fits")
        fits.contentHeight = 5
        fits.viewportHeight = 10
        #expect(!fits.handleWheelEvent(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0)))
    }
}

// MARK: - ScrollView rendering

@MainActor
@Suite("ScrollView Rendering")
struct ScrollViewRenderingTests {

    @Test("Renders to its viewport height even when content is taller")
    func rendersToViewport() {
        let view = ScrollView {
            VStack(alignment: .leading) {
                ForEach(0..<50, id: \.self) { Text("Row \($0)") }
            }
        }
        let buffer = renderToBuffer(view, context: makeContext(width: 30, height: 6))
        #expect(buffer.height == 6, "ScrollView should fill viewport height; got \(buffer.height)")
    }

    @Test("Horizontal ScrollView windows wide content and the horizontal wheel scrolls it")
    func horizontalWheelScrolls() {
        let view = ScrollView(.horizontal) {
            Text("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")  // 36 columns, one line
        }
        let context = makeContext(width: 10, height: 3)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        let before = buffer.lines.map(\.stripped)
        #expect(before[0].hasPrefix("0123456789"), "shows the left edge first: \(before[0])")
        #expect(!before.joined().contains("Z"), "the right end is off-screen")
        // Content does NOT wrap onto the next line — it scrolls instead.
        #expect(
            before.count > 1 && before[1].trimmingCharacters(in: .whitespaces).isEmpty,
            "wide content is one line, not wrapped: \(before)")

        // Scroll right via the horizontal wheel.
        for _ in 0..<5 {
            _ = dispatcher.dispatch(MouseEvent(button: .scrollRight, phase: .scrolled, x: 5, y: 0))
        }
        let after = renderToBuffer(view, context: context).lines.map(\.stripped).joined()
        #expect(!after.contains("0"), "after scrolling right, the left edge is off-screen: \(after)")
        #expect(after.contains("F"), "a later column is now visible: \(after)")
    }

    @Test("A horizontal ScrollView shows the ◀▶ scrollbar when content overflows")
    func horizontalScrollbarAppears() {
        let view = ScrollView(.horizontal) {
            Text("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")  // 36 columns
        }
        .scrollbarVisibility(.automatic)
        let context = makeContext(width: 10, height: 4)
        _ = renderToBuffer(view, context: context)  // settle the lazily-measured extent
        let text = renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
        #expect(
            text.contains("◀") || text.contains("▶"),
            "the bottom horizontal scrollbar should be drawn: \(text)")
    }

    @Test("A horizontal ScrollView whose content fits shows no scrollbar")
    func horizontalScrollbarHiddenWhenFits() {
        let view = ScrollView(.horizontal) {
            Text("short")
        }
        .scrollbarVisibility(.automatic)
        let context = makeContext(width: 20, height: 4)
        _ = renderToBuffer(view, context: context)
        let text = renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
        #expect(
            !text.contains("◀") && !text.contains("▶"),
            "no horizontal scrollbar when the content fits: \(text)")
    }

    @Test("Clicking the horizontal scrollbar's right arrow scrolls the content")
    func horizontalScrollbarClickScrolls() {
        let view = ScrollView(.horizontal) {
            Text("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")  // 36 columns
        }
        .scrollbarVisibility(.automatic)
        let context = makeContext(width: 12, height: 4)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        _ = renderToBuffer(view, context: context)  // settle the extent so the bar shows next frame
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        #expect(buffer.lines.map(\.stripped).joined().contains("0"), "left edge visible first")

        // The bar is the bottom row; its ▶ arrow is the last content column (x = 11).
        let barRow = buffer.height - 1
        for _ in 0..<3 {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 11, y: barRow))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 11, y: barRow))
        }
        let after = renderToBuffer(view, context: context).lines.map(\.stripped).joined()
        #expect(!after.contains("0"), "clicking ▶ scrolled the left edge off-screen: \(after)")
    }

    @Test("Wheel down then up restores the original viewport")
    func wheelRoundTripRestoresViewport() {
        let view = ScrollView {
            VStack(alignment: .leading) {
                ForEach(0..<100, id: \.self) { Text("Row \($0)") }
            }
        }
        let context = makeContext(width: 30, height: 8)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        // First render to register the wheel handler
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        let beforeText = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(beforeText.contains("Row 0"))

        // Scroll down a few ticks, render again, then scroll back
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 5))
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 5))

        let scrolled = renderToBuffer(view, context: context)
        dispatcher.setRegions(scrolled.hitTestRegions)
        let scrolledText = scrolled.lines.map(\.stripped).joined(separator: "\n")
        #expect(
            !scrolledText.contains("Row 0"),
            "After scrolling, Row 0 should be off-screen; got:\n\(scrolledText)"
        )

        // Scroll back to the top
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 5, y: 5))
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 5, y: 5))
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 5, y: 5))

        let restored = renderToBuffer(view, context: context)
        let restoredText = restored.lines.map(\.stripped).joined(separator: "\n")
        #expect(
            restoredText.contains("Row 0"),
            "After scrolling back, Row 0 should be visible again; got:\n\(restoredText)"
        )
    }

    /// Regression: a `ScrollView` that shares vertical space with a flexible
    /// sibling (here a trailing `Spacer`) is *measured* with the full available
    /// height — taller than the height it renders into. A measure-pass
    /// `clampScrollOffset()` then clamped the persistent offset against too large
    /// a viewport, pulling it back every frame so the last screenful was
    /// unreachable ("N more below"). The fix gates the clamp on `!isMeasuring`.
    /// Mirrors `ListTests.listWithFlexibleSiblingScrollsToBottom`.
    @Test("A ScrollView sharing space with a flexible sibling scrolls fully to the bottom")
    func scrollViewWithFlexibleSiblingScrollsToBottom() {
        var context = makeContext(width: 30, height: 24)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let view = VStack(spacing: 1) {
            Text("header").border()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<100, id: \.self) { Text("Row \($0)") }
                }
            }
            Spacer()
        }

        let initial = renderToBuffer(view, context: context)
        dispatcher.setRegions(initial.hitTestRegions)
        guard let region = initial.hitTestRegions.max(by: { $0.height < $1.height }) else {
            Issue.record("expected a ScrollView hit-test region"); return
        }
        // Precondition: the ScrollView really renders into a sub-region (else the
        // bug can't reproduce and the test would be vacuous).
        #expect(region.height < context.availableHeight - 2,
            "ScrollView should render into a sub-region for this test to be meaningful")

        let cx = region.offsetX + region.width / 2
        let cy = region.offsetY + region.height / 2
        var joined = ""
        for _ in 0..<80 {  // 80 wheel ticks * 3 lines >> 100 rows: reaches the end
            _ = dispatcher.dispatch(
                MouseEvent(button: .scrollDown, phase: .scrolled, x: cx, y: cy))
            let b = renderToBuffer(view, context: context)
            dispatcher.setRegions(b.hitTestRegions)
            joined = b.lines.map(\.stripped).joined(separator: "\n")
        }

        #expect(joined.contains("Row 99"), "wheel-scrolling to the end must reveal the last row")
        #expect(!joined.contains("more below"), "nothing should remain below once at the bottom")
    }

    /// Scroll chaining: a nested scroller that has reached its own limit must
    /// pass further wheel ticks up to its parent `ScrollView`, so the parent's
    /// content *below* the nested scroller stays reachable by wheel. Regression
    /// for the example List page's "can't scroll past the inner lists" trap —
    /// previously the inner scroller swallowed every wheel tick (its handler
    /// returned `true` unconditionally), so the outer viewport never moved while
    /// the cursor was over it.
    @Test("A nested scroller at its limit chains the wheel to its parent")
    func nestedScrollerChainsWheelToParent() {
        var context = makeContext(width: 30, height: 10)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        // A short inner ScrollView at the top, then a tall run of outer rows.
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<40, id: \.self) { Text("Inner \($0)") }
                    }
                }
                .frame(height: 4)
                ForEach(0..<60, id: \.self) { Text("Outer \($0)") }
            }
        }

        let initial = renderToBuffer(view, context: context)
        dispatcher.setRegions(initial.hitTestRegions)
        // The cursor sits over the inner scroller (top of the viewport). It
        // never moves, so every tick is delivered to the inner region first.
        guard let outer = initial.hitTestRegions.max(by: { $0.height < $1.height }) else {
            Issue.record("expected a ScrollView hit-test region"); return
        }
        let cx = outer.offsetX + 2
        let cy = outer.offsetY + 1

        // One tick scrolls the *inner* list; the outer hasn't moved yet, so the
        // last outer row is still far below.
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: cx, y: cy))
        let afterOne = renderToBuffer(view, context: context)
        dispatcher.setRegions(afterOne.hitTestRegions)
        #expect(
            !afterOne.lines.map(\.stripped).joined().contains("Outer 59"),
            "the outer viewport should not have reached its end after a single tick")

        // Keep scrolling over the same (inner) spot. Once the inner hits its
        // limit the wheel must chain to the outer, revealing the last outer row.
        var joined = ""
        for _ in 0..<60 {
            _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: cx, y: cy))
            let b = renderToBuffer(view, context: context)
            dispatcher.setRegions(b.hitTestRegions)
            joined = b.lines.map(\.stripped).joined(separator: "\n")
        }
        #expect(
            joined.contains("Outer 59"),
            "wheel over a maxed-out inner scroller must chain to the parent and reach its end; got:\n\(joined)")
    }

    @Test("Emits a viewport-wide mouse hit-test region")
    func emitsHitTestRegion() {
        let view = ScrollView {
            VStack { ForEach(0..<50, id: \.self) { Text("Row \($0)") } }
        }
        let context = makeContext(width: 30, height: 8)
        let buffer = renderToBuffer(view, context: context)
        let regions = buffer.hitTestRegions

        // At least one region should cover the viewport (the
        // wheel handler). Inner content may add more — but the
        // viewport region must be present.
        let viewportRegion = regions.first { region in
            region.offsetX == 0
                && region.offsetY == 0
                && region.width == 30
                && region.height == 8
        }
        #expect(
            viewportRegion != nil,
            "Expected a viewport-spanning hit-test region; got \(regions.count) regions"
        )
    }

    @Test("Shows down-indicator when content overflows below")
    func showsDownIndicatorWhenOverflowing() {
        let view = ScrollView {
            VStack(alignment: .leading) {
                ForEach(0..<50, id: \.self) { Text("Row \($0)") }
            }
        }
        let buffer = renderToBuffer(view, context: makeContext(width: 30, height: 6))
        let text = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(text.contains("more below"), "Expected a 'more below' indicator; got:\n\(text)")
    }

    @Test("Hides indicators when content fits")
    func hidesIndicatorsWhenContentFits() {
        let view = ScrollView {
            VStack { Text("Row 0"); Text("Row 1") }
        }
        let buffer = renderToBuffer(view, context: makeContext(width: 30, height: 10))
        let text = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(!text.contains("more below"))
        #expect(!text.contains("more above"))
    }

    @Test("showsIndicators: false suppresses the chrome")
    func showsIndicatorsFalseSuppresses() {
        let view = ScrollView(showsIndicators: false) {
            VStack { ForEach(0..<50, id: \.self) { Text("Row \($0)") } }
        }
        let buffer = renderToBuffer(view, context: makeContext(width: 30, height: 6))
        let text = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(!text.contains("more below"))
        #expect(!text.contains("more above"))
    }

    /// Regression test for "the Mixed-widget ScrollView won't scroll to the
    /// focused control". When a ScrollView is nested in a layout that
    /// render-to-measures it (here a VStack with a flexible `Spacer` sibling),
    /// its `renderToBuffer` runs several times per frame in measuring mode.
    /// Inner controls don't emit hit-test regions while measuring, so the
    /// "follow the focused control" detection — if it ran during a measure
    /// pass — would consume the focus-change signal (update its last-seen
    /// focus) WITHOUT being able to scroll, leaving the real render with
    /// nothing to act on. The control below the fold then never scrolled into
    /// view. The fix gates the whole snap step on `!isMeasuring`.
    @Test("Nested ScrollView still scrolls a below-fold focused control into view")
    func nestedScrollViewFollowsFocusBelowFold() {
        var context = makeContext(width: 40, height: 24)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        let fm = context.environment.focusManager

        let view = VStack(alignment: .leading, spacing: 1) {
            Text("preceding content")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        Button("btn-\(i)") {}.focusID("btn-\(i)")
                    }
                }
            }
            .frame(height: 5)
            .border()
            Spacer()
        }

        _ = renderToBuffer(view, context: context)
        fm.focus(id: "btn-0")
        let top = renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
        #expect(top.contains("btn-0"))

        fm.focus(id: "btn-9")
        let moved = renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
        #expect(moved.contains("btn-9"),
            "a nested ScrollView must scroll a below-fold focused control into view")
    }
}

// MARK: - Content @State isolation

/// A view with its own `@State`, bumped via a click, reporting the held value —
/// so a test can verify the value persists across renders rather than resetting.
private final class StateSink: @unchecked Sendable { var value = -1 }

private struct StatefulContent: View {
    @State private var count = 0
    let sink: StateSink
    var body: some View {
        Button("count \(count)") {
            count += 1
            sink.value = count
        }
    }
}

@MainActor
@Suite("ScrollView — content @State isolation")
struct ScrollViewContentStateTests {

    @Test("A ScrollView preserves directly-stateful content's @State (no key collision)")
    func preservesContentState() {
        // The content's `@State` (property index 0) must not collide with the
        // ScrollView's own state keys (handler index 0, …) at the same identity —
        // it lives under a distinct child identity. If it collided, the content's
        // state would be clobbered each frame and the count would never climb.
        let sink = StateSink()
        let tui = TUIContext()
        let fm = FocusManager()
        let view = ScrollView { StatefulContent(sink: sink) }

        func click() {
            var env = EnvironmentValues()
            env.focusManager = fm
            env.stateStorage = tui.stateStorage
            env.mouseEventDispatcher = tui.mouseEventDispatcher
            let ctx = RenderContext(
                availableWidth: 24, availableHeight: 6, environment: env, tuiContext: tui)
            fm.beginRenderPass()
            let buffer = renderToBuffer(view, context: ctx)
            fm.endRenderPass()
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            // The button's region is the short one (height 1); the ScrollView's
            // viewport region (taller) rejects the click and falls through to it.
            guard let button = buffer.hitTestRegions.min(by: { $0.height < $1.height }) else { return }
            let x = button.offsetX + button.width / 2
            let y = button.offsetY
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }

        click()  // count: 0 → 1
        click()  // count: 1 → 2 (only if the @State persisted across the ScrollView)
        #expect(sink.value == 2,
                "content @State persisted across renders inside the ScrollView, got \(sink.value)")
    }
}
