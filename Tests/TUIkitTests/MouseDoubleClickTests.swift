//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseDoubleClickTests.swift
//
//  MouseEventDispatcher synthesises MouseEvent.clickCount by timing successive
//  clicks (terminals never report double-clicks). These drive an injected clock
//  so the timing is deterministic.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Mouse double-click synthesis")
struct MouseDoubleClickTests {
    /// A dispatcher whose clock reads `now`, so tests advance time explicitly.
    private func makeDispatcher(now: @escaping () -> UInt64) -> MouseEventDispatcher {
        let dispatcher = MouseEventDispatcher()
        dispatcher.nowNanos = now
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        return dispatcher
    }

    /// Registers a full-width region and returns the release click-counts it sees.
    private func recordingDispatcher(now: @escaping () -> UInt64) -> (
        MouseEventDispatcher, () -> [Int]
    ) {
        let dispatcher = makeDispatcher(now: now)
        final class Box { var counts: [Int] = [] }
        let box = Box()
        let id = dispatcher.register { event in
            if event.phase == .released { box.counts.append(event.clickCount) }
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 3, handlerID: id)
        ])
        return (dispatcher, { box.counts })
    }

    private func click(_ dispatcher: MouseEventDispatcher, x: Int = 2, y: Int = 1) {
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
    }

    @Test("Two quick clicks at the same cell escalate to clickCount 2")
    func doubleClick() {
        var now: UInt64 = 0
        let (dispatcher, counts) = recordingDispatcher(now: { now })
        click(dispatcher)
        now += 100_000_000  // 100 ms — within the 400 ms window
        click(dispatcher)
        #expect(counts() == [1, 2])
    }

    @Test("Three quick clicks reach clickCount 3 (triple-click)")
    func tripleClick() {
        var now: UInt64 = 0
        let (dispatcher, counts) = recordingDispatcher(now: { now })
        click(dispatcher); now += 90_000_000
        click(dispatcher); now += 90_000_000
        click(dispatcher)
        #expect(counts() == [1, 2, 3])
    }

    @Test("A slow second click resets the count to 1")
    func slowClickResets() {
        var now: UInt64 = 0
        let (dispatcher, counts) = recordingDispatcher(now: { now })
        click(dispatcher)
        now += 600_000_000  // 600 ms — past the window
        click(dispatcher)
        #expect(counts() == [1, 1])
    }

    @Test("A second click at a distant cell resets the count to 1")
    func distantClickResets() {
        var now: UInt64 = 0
        let (dispatcher, counts) = recordingDispatcher(now: { now })
        click(dispatcher, x: 1, y: 1)
        now += 100_000_000
        click(dispatcher, x: 8, y: 2)  // more than one cell away
        #expect(counts() == [1, 1])
    }

    @Test("onTapGesture(count: 2) fires only on the double-click")
    func tapGestureCountTwo() {
        var now: UInt64 = 0
        final class Box { var opened = 0 }
        let box = Box()
        let view = Text("Folder").onTapGesture(count: 2) { box.opened += 1 }

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.nowNanos = { now }
        dispatcher.setActiveSupport(.full)

        func frameAndClick(x: Int, y: Int) {
            dispatcher.beginRenderPass()
            var env = EnvironmentValues()
            env.mouseEventDispatcher = dispatcher
            let context = RenderContext(
                availableWidth: 20, availableHeight: 3, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }

        frameAndClick(x: 1, y: 0)  // single click — no fire
        #expect(box.opened == 0)
        now += 120_000_000
        frameAndClick(x: 1, y: 0)  // second click → clickCount 2 → fires once
        #expect(box.opened == 1)
    }
}
