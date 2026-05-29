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
}
