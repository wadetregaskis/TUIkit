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

/// The three small dispatch fixes from the second hunt, pinned together:
/// taps fire on every Nth click, uncaptured drags are inert for every
/// button, and an unchanged hover answers nothing.
@MainActor
@Suite("Dispatch small print")
struct DispatchSmallPrintTests {

    @Test("onTapGesture(count: 1) fires on every click of a rapid burst")
    func rapidTapsAllFire() {
        var taps = 0
        let context = makeRenderContext(width: 20, height: 4) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let view = Text("target").onTapGesture(count: 1) { taps += 1 }
        let buffer = renderToBuffer(view, context: context)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setRegions(buffer.hitTestRegions)

        // Three quick clicks at one cell: the dispatcher stamps 1, 2, 3 —
        // an exact ==1 match dropped every release after the first.
        for _ in 0..<3 {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        }
        #expect(taps == 3, "a rapid burst dropped clicks: \(taps)")
    }

    @Test("Motion inside an already-lit tab answers nothing")
    func unchangedTabHoverIsQuiet() {
        // The tab's hover handler consumed every .moved even when the box
        // already held that tab — and a consumed event is a render request,
        // so a cursor travelling inside a tab re-rendered the app once per
        // motion drain.
        let context = makeRenderContext(width: 40, height: 8) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.focusManager = FocusManager()
        }
        let view = TabView(selection: .constant(0)) {
            Tab("Alpha", value: 0) { Text("a") }
            Tab("Beta", value: 1) { Text("b") }
        }
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let tab = buffer.hitTestRegions.first else {
            Issue.record("no tab region")
            return
        }

        let first = dispatcher.dispatch(
            MouseEvent(button: .none, phase: .moved, x: tab.offsetX, y: tab.offsetY))
        let second = dispatcher.dispatch(
            MouseEvent(button: .none, phase: .moved, x: tab.offsetX + 1, y: tab.offsetY))
        #expect(first, "the first motion lights the tab")
        #expect(!second, "an unchanged hover must not request a render")
    }

    @Test("An uncaptured right-button drag is inert, like the left's")
    func uncapturedRightDragIsInert() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var phases: [MousePhase] = []
        let id = dispatcher.register { event in
            phases.append(event.phase)
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 2, handlerID: id)
        ])

        // No press was captured (nothing consumed one); the drag must not be
        // hit-tested live into a handler that never saw a press.
        _ = dispatcher.dispatch(MouseEvent(button: .right, phase: .dragged, x: 3, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .middle, phase: .dragged, x: 3, y: 0))
        #expect(phases.isEmpty, "an uncaptured drag reached a handler: \(phases)")
    }
}

/// Regions describe in-flow cells, so every final clip trims them: the clamp
/// at a container boundary and the scroll viewport's columns. A region kept
/// for cells that were clipped away is a phantom click target sitting
/// wherever later content lands.
@MainActor
@Suite("Regions are clipped with their cells")
struct RegionClippingTests {

    private func region(x: Int, y: Int, w: Int, h: Int) -> HitTestRegion {
        HitTestRegion(
            offsetX: x, offsetY: y, width: w, height: h,
            handlerID: HitTestRegion.HandlerID(UInt64(x * 100 + y)))
    }

    @Test("clamped trims regions to the box and drops the clipped-away")
    func clampedTrimsRegions() {
        var buffer = FrameBuffer(lines: ["0123456789", "0123456789", "0123456789"])
        buffer.hitTestRegions = [
            region(x: 0, y: 0, w: 4, h: 1),  // wholly inside
            region(x: 8, y: 0, w: 4, h: 1),  // straddles the right edge
            region(x: 0, y: 2, w: 4, h: 1),  // on a clipped-away row
        ]
        let clamped = buffer.clamped(toWidth: 9, height: 2)

        #expect(clamped.hitTestRegions.count == 2, "\(clamped.hitTestRegions)")
        #expect(clamped.hitTestRegions[0].width == 4)
        #expect(clamped.hitTestRegions[1].offsetX == 8)
        #expect(clamped.hitTestRegions[1].width == 1, "trimmed to the box, not kept whole")
    }

    @Test("A horizontally scrolled region is clipped to the viewport's columns")
    func horizontalWindowClipsRegions() {
        var cache: RenderCache?
        let context = makeRenderContext(width: 8, height: 4) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.focusManager = FocusManager()
            cache = tui.renderCache
        }
        let view = ScrollView([.horizontal]) {
            HStack(spacing: 0) {
                Button("aaaa") {}
                Button("bbbb") {}
                Button("cccc") {}
            }
        }
        _ = renderToBuffer(view, context: context)
        let handler = context.environment.focusManager?.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler != nil)
        handler?.horizontal.scrollOffset = 5
        cache?.clearAll()
        let buffer = renderToBuffer(view, context: context)

        for region in buffer.hitTestRegions {
            #expect(region.offsetX >= 0, "phantom columns left of the viewport: \(region)")
            #expect(
                region.offsetX + region.width <= 8,
                "phantom columns past the viewport: \(region)")
        }
        // The straddler keeps its true origin for local coordinates.
        #expect(
            buffer.hitTestRegions.contains { $0.leftClip > 0 },
            "the clipped edge must be recorded, not forgotten")
    }
}
