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

/// The "N more above / below" lines are chrome painted OVER a content row:
/// the cells change but the row's hit regions used to stay, so a click on the
/// indicator pressed whatever control was scrolled exactly under it —
/// invisible, and still clickable.
@MainActor
@Suite("Indicator line shield")
struct IndicatorLineShieldTests {
    @Test("A click on an 'N more' line pages instead of pressing the hidden row")
    func indicatorClickPages() {
        var pressed: Set<Int> = []
        let tui = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { i in
                    Button("row \(i)") { pressed.insert(i) }
                }
            }
        }
        .scrollIndicatorStyle(.text)
        .frame(height: 6)

        func frame() -> FrameBuffer {
            var env = EnvironmentValues()
            env.applyRuntimeServices(from: tui)
            env.mouseEventDispatcher = tui.mouseEventDispatcher
            env.focusManager = focusManager
            let context = RenderContext(
                availableWidth: 24, availableHeight: 6, environment: env, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            return buffer
        }

        _ = frame()
        let handler = focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler != nil)
        handler?.scrollOffset = 10
        let buffer = frame()
        #expect(
            buffer.lines.first?.stripped.contains("more") == true,
            "precondition: the top indicator is drawn: \(buffer.lines.map(\.stripped))")

        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setRegions(buffer.hitTestRegions)
        let before = handler?.scrollOffset ?? -1
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 0))
        #expect(pressed.isEmpty, "the hidden row took the indicator's click: \(pressed)")
        #expect(
            (handler?.scrollOffset ?? -1) < before,
            "the indicator click pages up: \(handler?.scrollOffset ?? -1) vs \(before)")

        // And the bottom indicator pages down.
        handler?.scrollOffset = 10
        let buffer2 = frame()
        dispatcher.setRegions(buffer2.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 5))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 5))
        #expect(pressed.isEmpty, "\(pressed)")
        #expect((handler?.scrollOffset ?? -1) > 10, "pages down: \(handler?.scrollOffset ?? -1)")

        // The wheel is NOT the shield's business: it falls through to the
        // viewport handler and scrolls as it does everywhere else.
        handler?.scrollOffset = 10
        let buffer3 = frame()
        dispatcher.setRegions(buffer3.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .pressed, x: 3, y: 0))
        #expect((handler?.scrollOffset ?? -1) < 10, "wheel over the indicator still scrolls")
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

/// Hover across a tree reshape: handler ids are per-frame numbers, so the
/// dispatcher re-resolves the resting cursor against each frame's regions by
/// the region's own identity, exiting what left and entering what arrived.
@MainActor
@Suite("Hover survives a reshape")
struct HoverReshapeTests {

    @Test("The hovered control keeps its hover when ids shift under it")
    func hoverSurvivesIDShift() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        var events: [MousePhase] = []

        func frame(withExtraSiblingFirst extra: Bool) {
            dispatcher.beginRenderPass()
            if extra {
                _ = dispatcher.register { _ in false }  // shifts every later id
            }
            let id = dispatcher.register { event in
                events.append(event.phase)
                return true
            }
            var regions: [HitTestRegion] = []
            if extra {
                regions.append(
                    HitTestRegion(offsetX: 0, offsetY: 5, width: 4, height: 1,
                                  handlerID: HitTestRegion.HandlerID(0)))
            }
            regions.append(
                HitTestRegion(offsetX: 2, offsetY: 0, width: 6, height: 2, handlerID: id))
            dispatcher.setRegions(regions)
        }

        frame(withExtraSiblingFirst: false)
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 3, y: 1))
        #expect(events == [.entered], "\(events)")

        // Next frame: an extra sibling registers first, shifting the ids.
        // The same rectangle is the same control — no exit, no re-enter.
        events = []
        frame(withExtraSiblingFirst: true)
        #expect(events.isEmpty, "a reshape must not flicker an unchanged hover: \(events)")

        // Motion inside it still routes to the RIGHT handler after the shift.
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 4, y: 1))
        #expect(events == [.moved], "\(events)")
    }

    @Test("A control that leaves the resting cursor is exited; the newcomer entered")
    func reshapeMovesHover() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        var aEvents: [MousePhase] = []
        var bEvents: [MousePhase] = []

        dispatcher.beginRenderPass()
        let aID = dispatcher.register { aEvents.append($0.phase); return true }
        dispatcher.setRegions([
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: 6, height: 1, handlerID: aID, focusID: "a")
        ])
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
        #expect(aEvents == [.entered])

        // Next frame the tree reshapes: A moved away, B sits under the cursor.
        aEvents = []
        dispatcher.beginRenderPass()
        let bID = dispatcher.register { bEvents.append($0.phase); return true }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 3, width: 6, height: 1,
                          handlerID: HitTestRegion.HandlerID(99), focusID: "a"),
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: 6, height: 1, handlerID: bID, focusID: "b"),
        ])
        #expect(aEvents == [.exited], "the control that left must be exited: \(aEvents)")
        #expect(bEvents == [.entered], "the newcomer under the cursor lights up: \(bEvents)")
    }
}
