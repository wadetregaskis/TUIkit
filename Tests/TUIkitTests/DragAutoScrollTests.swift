//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragAutoScrollTests.swift
//
//  Drag auto-scroll (macOS `NSView.autoscroll`): while a drag is in flight and
//  the cursor lingers near a registered scrollable's edge, that scrollable
//  scrolls to bring an off-screen drop target into view. The driver lives on
//  `DragAndDropSession` because it is the one place the drag cursor and the
//  dispatcher's ABSOLUTE region geometry meet — a scrollable only knows its own
//  size at render, never where the compositor placed it. These tests drive the
//  session directly against fabricated region rects, so the geometry and the
//  rate ramp are exercised deterministically.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("drag auto-scroll")
struct DragAutoScrollTests {
    /// A drag session wired to a dispatcher it OWNS. `DragAndDropSession.dispatcher`
    /// is deliberately `weak` (in production `TUIContext` retains the dispatcher);
    /// a test must therefore keep it alive itself, which is what this class is for.
    private final class Harness {
        /// Each tick advances the clock well past the repeat interval, so every
        /// post-engagement tick fires.
        static let bigTick: UInt64 = 1_000_000_000

        let dispatcher = MouseEventDispatcher()
        let session = DragAndDropSession()

        init() { session.dispatcher = dispatcher }

        func setRegions(_ regions: [HitTestRegion]) { dispatcher.setRegions(regions) }

        func addZone(
            _ handlerID: HitTestRegion.HandlerID,
            vertical: any ScrollableOffsetState,
            horizontal: (any ScrollableOffsetState)? = nil,
            delayNanos: UInt64 = 0
        ) {
            session.registerAutoScrollZone(
                DragAndDropSession.AutoScrollZone(
                    handlerID: handlerID, vertical: vertical,
                    horizontal: horizontal, delayNanos: delayNanos))
        }

        func beginDrag(x: Int, y: Int) {
            session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: x, y: y)
            session.begin(payload: "x", preview: FrameBuffer(text: "x"))
        }

        @discardableResult
        func drive(nowNanos: UInt64) -> Bool { session.driveAutoScroll(nowNanos: nowNanos) }

        /// Engages the drag at its edge, then applies `ticks` scroll ticks.
        func run(ticks: Int) {
            drive(nowNanos: 0)  // engage; arms the delay
            for tick in 1...max(1, ticks) {
                drive(nowNanos: UInt64(tick) &* Self.bigTick)
            }
        }
    }

    private static let zoneID = HitTestRegion.HandlerID(1)
    private static let viewport = HitTestRegion(
        offsetX: 0, offsetY: 0, width: 40, height: 10, handlerID: zoneID)

    private func scrollHandler(offset: Int, content: Int, viewport: Int) -> ScrollViewHandler {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = content
        handler.viewportHeight = viewport
        handler.scrollOffset = offset
        return handler
    }

    /// A one-zone harness with the standard 40×10 viewport, the drag already in
    /// flight at `(cursorX, cursorY)`.
    private func oneZone(
        vertical: any ScrollableOffsetState,
        horizontal: (any ScrollableOffsetState)? = nil,
        cursorX: Int, cursorY: Int, delayNanos: UInt64 = 0
    ) -> Harness {
        let harness = Harness()
        harness.setRegions([Self.viewport])
        harness.addZone(
            Self.zoneID, vertical: vertical, horizontal: horizontal, delayNanos: delayNanos)
        harness.beginDrag(x: cursorX, y: cursorY)
        return harness
    }

    @Test("A drag near the bottom edge scrolls the content down")
    func bottomEdgeScrollsDown() {
        let handler = scrollHandler(offset: 0, content: 100, viewport: 10)
        // Cursor on the last visible row (the bottom edge of a 0..<10 viewport).
        let harness = oneZone(vertical: handler, cursorX: 20, cursorY: 9)
        harness.run(ticks: 3)
        #expect(handler.scrollOffset > 0, "hovering the bottom edge scrolls toward the end")
    }

    @Test("A drag near the top edge scrolls the content up")
    func topEdgeScrollsUp() {
        let handler = scrollHandler(offset: 50, content: 100, viewport: 10)
        let harness = oneZone(vertical: handler, cursorX: 20, cursorY: 0)
        harness.run(ticks: 3)
        #expect(handler.scrollOffset < 50, "hovering the top edge scrolls toward the start")
    }

    @Test("A drag comfortably inside the viewport does not scroll")
    func middleDoesNotScroll() {
        let handler = scrollHandler(offset: 30, content: 100, viewport: 10)
        // Row 5 is clear of both hot margins (top 0..1, bottom 8..9).
        let harness = oneZone(vertical: handler, cursorX: 20, cursorY: 5)
        #expect(!harness.drive(nowNanos: 0), "a mid-viewport cursor engages nothing")
        harness.run(ticks: 3)
        #expect(handler.scrollOffset == 30, "and never moves the viewport")
    }

    @Test("Dragging past the edge scrolls markedly faster than dragging just inside it")
    func pastEdgeIsFaster() {
        let atEdge = scrollHandler(offset: 0, content: 1000, viewport: 10)
        let past = scrollHandler(offset: 0, content: 1000, viewport: 10)
        // Same viewport, same tick count: one cursor sits on the bottom edge, the
        // other well below it (a scrollable smaller than the screen lets the
        // cursor travel past — the macOS acceleration the owner asked for).
        oneZone(vertical: atEdge, cursorX: 20, cursorY: 9).run(ticks: 4)
        oneZone(vertical: past, cursorX: 20, cursorY: 18).run(ticks: 4)
        #expect(
            past.scrollOffset > atEdge.scrollOffset,
            "past-edge (\(past.scrollOffset)) accelerates beyond at-edge (\(atEdge.scrollOffset))")
    }

    @Test("No auto-scroll without a drag in flight")
    func noDragNoScroll() {
        let handler = scrollHandler(offset: 30, content: 100, viewport: 10)
        let harness = Harness()
        harness.setRegions([Self.viewport])
        harness.addZone(Self.zoneID, vertical: handler)
        // Cursor is at the edge, but no drag has begun.
        harness.session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .moved, x: 20, y: 9)
        #expect(!harness.drive(nowNanos: 0), "auto-scroll only runs during a drag")
        #expect(handler.scrollOffset == 30)
    }

    @Test("A scrollable already at its boundary does not engage")
    func boundaryDoesNotEngage() {
        // Already scrolled to the very bottom: nothing left below, so a cursor at
        // the bottom edge must NOT engage (and must not oscillate).
        let handler = scrollHandler(offset: 90, content: 100, viewport: 10)
        let harness = oneZone(vertical: handler, cursorX: 20, cursorY: 9)
        #expect(!harness.drive(nowNanos: 0), "no content below → no engagement")
        harness.run(ticks: 3)
        #expect(handler.scrollOffset == 90, "and the offset stays pinned at the boundary")
    }

    @Test("The initial delay holds the first scroll")
    func initialDelayHoldsFirstScroll() {
        let handler = scrollHandler(offset: 0, content: 100, viewport: 10)
        let harness = oneZone(
            vertical: handler, cursorX: 20, cursorY: 9, delayNanos: 300_000_000)
        harness.drive(nowNanos: 0)  // engage at t=0, first tick due at t=300ms
        harness.drive(nowNanos: 100_000_000)  // 100ms < 300ms
        #expect(handler.scrollOffset == 0, "no scroll before the delay elapses")
        harness.drive(nowNanos: 400_000_000)  // past the delay
        #expect(handler.scrollOffset > 0, "the first scroll fires once the delay passes")
    }

    @Test("The innermost of nested zones is the one that scrolls")
    func innermostZoneWins() {
        let outer = scrollHandler(offset: 30, content: 100, viewport: 20)
        let inner = scrollHandler(offset: 30, content: 100, viewport: 8)
        let harness = Harness()
        let outerRect = HitTestRegion(
            offsetX: 0, offsetY: 0, width: 40, height: 20, handlerID: HitTestRegion.HandlerID(1))
        let innerRect = HitTestRegion(
            offsetX: 5, offsetY: 5, width: 20, height: 8, handlerID: HitTestRegion.HandlerID(2))
        harness.setRegions([outerRect, innerRect])
        // Registered outer-first, as the render order would.
        harness.addZone(outerRect.handlerID, vertical: outer)
        harness.addZone(innerRect.handlerID, vertical: inner)
        // Cursor on the inner zone's bottom edge (row 12 = 5 + 8 - 1), inside its
        // columns.
        harness.beginDrag(x: 12, y: 12)
        harness.run(ticks: 3)
        #expect(inner.scrollOffset > 30, "the inner (smaller) zone scrolls")
        #expect(outer.scrollOffset == 30, "the outer zone is left alone")
    }

    @Test("Auto-scroll resolves against the dispatcher's live region rects")
    func needsDispatcherRegions() {
        // The driver locates each zone's on-screen rect through the dispatcher.
        // `RenderLoop.render()` empties those regions in `beginRenderPass()` (via
        // `MouseEventDispatcher.beginRenderPass()`) at the top of every frame, so
        // the drive MUST happen first — against the previous frame's geometry —
        // or every `regionRect` lookup is nil and nothing scrolls. This models
        // that ordering constraint: clear the regions the way `beginRenderPass`
        // would, and the very same edge drag becomes a no-op.
        let handler = scrollHandler(offset: 0, content: 100, viewport: 10)
        let harness = oneZone(vertical: handler, cursorX: 20, cursorY: 9)

        // With the (previous frame's) regions present, the edge drag engages.
        #expect(harness.drive(nowNanos: 0), "the edge drag engages while the rect is known")

        // Now clear the dispatcher's regions exactly as beginRenderPass does.
        harness.dispatcher.beginRenderPass()
        harness.run(ticks: 3)
        #expect(
            handler.scrollOffset == 0,
            "with no region rect the driver can't place the zone, so nothing scrolls")
    }

    @Test("A horizontal scrollable auto-scrolls toward the right edge")
    func horizontalEdgeScrolls() {
        let vertical = scrollHandler(offset: 0, content: 10, viewport: 10)  // can't move vertically
        let horizontal = ScrollAxis()
        horizontal.viewportHeight = 40  // "height" reads as width for a horizontal axis
        horizontal.extent = 200
        horizontal.scrollOffset = 0
        // Cursor at the right edge, within the rows.
        let harness = oneZone(
            vertical: vertical, horizontal: horizontal, cursorX: 39, cursorY: 5)
        harness.run(ticks: 3)
        #expect(horizontal.scrollOffset > 0, "hovering the right edge scrolls horizontally")
        #expect(vertical.scrollOffset == 0, "the un-scrollable vertical axis stays put")
    }
}
