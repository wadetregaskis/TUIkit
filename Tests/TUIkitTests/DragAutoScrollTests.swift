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

        /// A drop destination sharing a zone's rectangle — what makes that zone
        /// somewhere the drag could actually land, and so somewhere allowed to
        /// scroll under it. Real trees get this from the app's own
        /// `dropDestination`; the tests state it explicitly.
        func addTarget(_ handlerID: HitTestRegion.HandlerID, accepts: Bool = true) {
            session.registerTarget(
                DragAndDropSession.Target(
                    handlerID: handlerID, accepts: { _ in accepts },
                    perform: { _, _ in true }, setTargeted: { _ in }))
        }

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
        cursorX: Int, cursorY: Int, delayNanos: UInt64 = 0,
        accepts: Bool = true
    ) -> Harness {
        let harness = Harness()
        harness.setRegions([Self.viewport])
        harness.addZone(
            Self.zoneID, vertical: vertical, horizontal: horizontal, delayNanos: delayNanos)
        harness.addTarget(Self.zoneID, accepts: accepts)
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

    // MARK: - The return flight

    /// A cancelled drag walks its preview home rather than having it vanish
    /// mid-air. Cell-stepped and derived from the clock, so a slow frame
    /// shortens the flight instead of stretching it.
    @Test("A cancelled drag returns the preview to where it started")
    func cancelledDragFliesHome() {
        let harness = Harness()
        harness.setRegions([Self.viewport])
        harness.session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .pressed, x: 4, y: 2)
        harness.session.begin(payload: "x", preview: FrameBuffer(text: "ROW"))
        // Drag away: the preview follows the cursor.
        harness.session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 20, y: 8)
        harness.session.dragMoved()
        let away = harness.session.previewFrame()
        #expect(away?.x == 20 && away?.y == 8, "carried to the cursor")

        harness.session.cancelReturningToOrigin()
        #expect(harness.session.active == nil, "the drag is over immediately")

        var seen: [(x: Int, y: Int)] = []
        for step in 0...5 {
            guard let frame = harness.session.driveReturnFlight(
                nowNanos: UInt64(step) * 40_000_000)
            else { break }
            seen.append((frame.x, frame.y))
        }
        #expect(seen.first?.x == 20 && seen.first?.y == 8, "starts where it was let go")
        #expect(seen.count > 1, "and takes more than one frame about it")
        #expect(
            zip(seen, seen.dropFirst()).allSatisfy { $0.x >= $1.x && $0.y >= $1.y },
            "moving only homeward: \(seen)")

        // Past the duration it is done, and draws nothing more.
        #expect(harness.session.driveReturnFlight(nowNanos: 500_000_000) == nil)
        #expect(harness.session.returnFlightFrame == nil)
    }

    /// A drag cancelled without having moved has nowhere to fly, and must not
    /// leave a stray overlay behind for a frame.
    @Test("A cancel at the origin ends without a flight")
    func cancelAtOriginDoesNotFly() {
        let harness = Harness()
        harness.setRegions([Self.viewport])
        harness.session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .pressed, x: 4, y: 2)
        harness.session.begin(payload: "x", preview: FrameBuffer(text: "ROW"))
        harness.session.cancelReturningToOrigin()
        #expect(harness.session.driveReturnFlight(nowNanos: 0) == nil)
    }

    /// A row reorder carries no payload, so `.live` and `.dimmed` never open a
    /// drag — and the driver's "is a drag in flight" gate silently excluded the
    /// two feedback modes people actually use. `armAutoScroll()` is how a
    /// gesture with nothing to float says it wants the edges anyway.
    @Test("An armed gesture with no payload scrolls at the edge")
    func armedGestureWithoutAPayloadScrolls() {
        let harness = Harness()
        harness.setRegions([Self.viewport])
        let vertical = scrollHandler(offset: 0, content: 100, viewport: 10)
        harness.addZone(Self.zoneID, vertical: vertical)
        // No `begin`: exactly what a `.live` reorder does.
        harness.session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 5, y: 9)
        #expect(!harness.drive(nowNanos: 0), "unarmed, the driver does nothing")
        #expect(vertical.scrollOffset == 0)

        harness.session.armAutoScroll(owner: vertical)
        harness.run(ticks: 3)
        #expect(vertical.scrollOffset > 0, "armed, the edge scrolls it")

        let reached = vertical.scrollOffset
        harness.session.disarmAutoScroll()
        harness.run(ticks: 3)
        #expect(vertical.scrollOffset == reached, "and disarming stops it")
    }

    /// A page that scrolls away under a payload it would refuse is just the
    /// view running off: the drag can't land there, so there is nothing to
    /// reveal. What entitles a scrollable to move is containing a destination
    /// that would take THIS payload.
    @Test("A scrollable that would refuse the payload never scrolls")
    func refusingZoneDoesNotScroll() {
        let handler = scrollHandler(offset: 0, content: 100, viewport: 10)
        let harness = oneZone(vertical: handler, cursorX: 20, cursorY: 9, accepts: false)
        #expect(!harness.drive(nowNanos: 0), "nowhere to land here, so no engagement")
        harness.run(ticks: 3)
        #expect(handler.scrollOffset == 0)
    }

    /// A reorder can only land in the list it came from, so the enclosing page
    /// must hold still — even though the cursor is at ITS edge too.
    @Test("A reorder scrolls its own list, not the page around it")
    func reorderScrollsOnlyItsOwnList() {
        let page = scrollHandler(offset: 30, content: 100, viewport: 20)
        let list = scrollHandler(offset: 30, content: 100, viewport: 8)
        let harness = Harness()
        let pageRect = HitTestRegion(
            offsetX: 0, offsetY: 0, width: 40, height: 20, handlerID: HitTestRegion.HandlerID(1))
        let listRect = HitTestRegion(
            offsetX: 0, offsetY: 12, width: 40, height: 8, handlerID: HitTestRegion.HandlerID(2))
        harness.setRegions([pageRect, listRect])
        harness.addZone(pageRect.handlerID, vertical: page)
        harness.addZone(listRect.handlerID, vertical: list)
        // No drop destination anywhere: a reorder payload is private and
        // unnameable, so nothing could register one.
        harness.session.armAutoScroll(owner: list)
        // The last row of both the list and the page — inside both hot margins.
        harness.session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 20, y: 19)
        harness.run(ticks: 3)
        #expect(list.scrollOffset > 30, "the list the row came from scrolls")
        #expect(page.scrollOffset == 30, "the page it sits in does not")
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
        harness.addTarget(outerRect.handlerID)
        harness.addTarget(innerRect.handlerID)
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

    @Test("A list's cursor-row region does not shrink the zone it measures")
    func cursorRowRegionDoesNotShrinkTheZone() {
        // A `List` stamps an extra ONE-ROW region over its keyboard cursor,
        // carrying the container's own handler id (that is how an enclosing
        // ScrollView finds the row to reveal), and inserts it AHEAD of the
        // container. Measuring the zone against the first match therefore
        // measured a single row: with the cursor at the top of the list, every
        // row below it read as "dragged past the bottom", so a drag anywhere in
        // the list armed auto-scroll — and by the time the cursor reached the
        // real hot margin the dwell had already elapsed and it scrolled at once.
        // Exactly the reported symptom, and exactly why it only happened while
        // the list was scrolled to the top (elsewhere the cursor row is off
        // screen and no extra region exists).
        let handler = scrollHandler(offset: 0, content: 100, viewport: 10)
        let harness = Harness()
        harness.setRegions([
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: 40, height: 1, handlerID: Self.zoneID),
            Self.viewport,
        ])
        harness.addZone(Self.zoneID, vertical: handler)
        harness.beginDrag(x: 20, y: 5)  // mid-viewport: clear of both hot margins
        #expect(
            !harness.drive(nowNanos: 0),
            "the middle of the list is not an edge, whatever the cursor row's region says")
        harness.run(ticks: 3)
        #expect(handler.scrollOffset == 0)
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

// MARK: - Against a real render

/// The tests above drive the session against fabricated region rects and a
/// bare handler, so they never run the code a real frame runs *after* the
/// tick: the view's own render, which re-resolves its handler and may move the
/// offset back. That is the gap #401 fell through — the scroll and the thing
/// that undoes it live in different files, and only a real render puts them in
/// the same frame.
///
/// The loop below is the run loop's order (`RenderLoop.render`): drive one
/// auto-scroll tick, then render, then publish the regions the next tick
/// resolves against.
@MainActor
@Suite("drag auto-scroll through a render")
struct DragAutoScrollRenderTests {

    private struct Row: Identifiable {
        let id: Int
        var name: String { "row-\(id)" }
    }

    private static let rows = (0..<40).map(Row.init(id:))

    /// Renders `view` frame by frame with an auto-scroll tick ahead of each,
    /// returning the first data row visible after every frame.
    private func topRows(_ view: some View, frames: Int, height: Int) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: height, environment: environment,
            tuiContext: tui)
        let session = tui.dragAndDropSession
        session.dispatcher = tui.mouseEventDispatcher

        func frame() -> [String] {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            session.beginFrame()
            let buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            tui.stateStorage.endRenderPass()
            return buffer.lines.map(\.stripped)
        }

        _ = frame()  // register the zone and publish its region
        // A row reorder: the gesture belongs to the control's own scrollable,
        // which is what entitles it to scroll (nothing else would accept a
        // reorder payload). The real press does this in `_ListCore` / `Table`.
        session.armAutoScroll(owner: session.autoScrollZones.first?.vertical)
        // Park the drag on the control's last line: inside the bottom hot
        // margin, at the base rate — the rate that lands exactly on offset 1.
        session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 10, y: height - 1)
        session.begin(payload: "x", preview: FrameBuffer(text: "x"))

        var tops: [String] = []
        for tick in 0...frames {
            session.driveAutoScroll(nowNanos: UInt64(tick) &* 1_000_000_000)
            let lines = frame()
            tops.append(lines.first { $0.contains("row-") } ?? "— \(lines)")
        }
        return tops
    }

    /// The first data row of each frame, as an integer, for compact assertions.
    private func topIndices(_ view: some View, frames: Int, height: Int) -> [Int] {
        topRows(view, frames: frames, height: height).map { line in
            guard let range = line.range(of: "row-") else { return -1 }
            return Int(line[range.upperBound...].prefix { $0.isNumber }) ?? -1
        }
    }

    @Test("A Table auto-scrolls away from its top instead of stalling at offset 1")
    func tableEscapesTheRestingSnap() {
        let table = Table(Self.rows, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Row.name)
        }
        .frame(height: 10)

        let tops = topIndices(table, frames: 5, height: 10)
        #expect(
            tops == tops.sorted() && tops.last! > tops.first!,
            """
            the viewport must advance one row per tick, not flip 0↔1 — \
            got \(tops)
            """)
    }

    /// The List is the twin that already had the guard (7f9fc5b4); it is here
    /// so the two are asserted together and cannot drift apart again.
    @Test("A List auto-scrolls away from its top instead of stalling at offset 1")
    func listEscapesTheRestingSnap() {
        let list = List {
            ForEach(Self.rows) { Text($0.name) }
        }
        .frame(height: 10)

        let tops = topIndices(list, frames: 5, height: 10)
        #expect(
            tops == tops.sorted() && tops.last! > tops.first!,
            "the list advances one row per tick — got \(tops)")
    }
}
