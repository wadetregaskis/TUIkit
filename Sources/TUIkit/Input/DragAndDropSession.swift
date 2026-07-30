//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragAndDropSession.swift
//
//  The shared state behind ``View/draggable(_:)`` and
//  ``View/dropDestination(for:action:isTargeted:)`` — TUI-internal
//  drag-and-drop (a terminal app cannot reach the system pasteboard, so
//  payloads move within the app only).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Drop Info

/// Where a drop landed and which modifier keys were held.
///
/// SwiftUI's `dropDestination` hands its action a `CGPoint`; a terminal
/// deals in character cells and — unlike SwiftUI — can meaningfully vary a
/// drop on the modifiers held at release (SGR mouse reports carry
/// shift/ctrl/meta through the whole drag), so this deliberate deviation
/// carries both. The location is in the destination view's local space —
/// `(0, 0)` is its top-left cell.
public struct DropInfo: Sendable, Equatable {
    /// The drop column, relative to the destination's left edge.
    public let x: Int

    /// The drop row, relative to the destination's top edge.
    public let y: Int

    /// Whether Shift was held when the payload was dropped.
    public let shift: Bool

    /// Whether Control was held.
    public let ctrl: Bool

    /// Whether Meta / Alt / Option was held.
    public let meta: Bool

    /// The floating drag preview's frame at the moment of the drop, in the
    /// same destination-local space as ``x``/``y`` — for effects anchored to
    /// the drag IMAGE rather than the cursor (a removal puff at its centre,
    /// an insertion marker at its edge). Where the preview sits relative to
    /// the cursor depends on the drag's ``DragPreviewAnchor``.
    public let previewX: Int

    /// The preview frame's top row (see ``previewX``).
    public let previewY: Int

    /// The preview's width in cells.
    public let previewWidth: Int

    /// The preview's height in cells.
    public let previewHeight: Int
}

// MARK: - Session

/// The app-wide drag-and-drop state: the active drag (payload, preview,
/// cursor), and the drop targets registered by the current frame.
///
/// Lifecycle per frame: the root scene render calls ``beginFrame()`` (drop
/// targets re-register during the render pass, exactly like focus
/// registration); mouse dispatch then routes the captured drag events to the
/// *source* view's handler, which drives ``begin(payload:preview:)`` /
/// ``dragMoved()`` / ``performDrop()`` here. Targeting is resolved by
/// hit-testing the dispatcher's (absolute, post-composite) regions at the
/// cursor against the registered targets, so a target's geometry is always
/// exactly what is on screen.
///
/// `@unchecked Sendable` on the same terms as ``MouseEventDispatcher``: the
/// session is only ever touched from the main run loop (render pass + input
/// dispatch), but it is created by the nonisolated ``TUIContext``
/// initializer, so it cannot be formally actor-isolated.
final class DragAndDropSession: @unchecked Sendable {
    /// One frame's registration of a drop destination.
    struct Target {
        /// The mouse-region id whose on-screen rectangle is the drop zone.
        let handlerID: HitTestRegion.HandlerID

        /// Whether this destination accepts the given payload (a type check).
        let accepts: (Any) -> Bool

        /// Performs the drop: the payload and the absolute release event.
        /// Returns whether the destination took the payload.
        let perform: (Any, MouseEvent) -> Bool

        /// The `isTargeted` callback: fired with `true` when an accepted drag
        /// moves over the destination, `false` when it leaves (or drops).
        let setTargeted: (Bool) -> Void
    }

    /// One frame's registration of a scrollable that should auto-scroll while
    /// a drag hovers near its edges — so a payload can be carried to a drop
    /// target that is currently scrolled out of view (macOS's drag
    /// auto-scroll, `NSView.autoscroll(with:)`).
    ///
    /// The zone carries the same `handlerID` as the scrollable's viewport hit
    /// region, so the driver can read the region's *absolute* on-screen rect
    /// from the dispatcher — the one place that geometry exists (a scrollable
    /// only knows its own size at render time, never where the compositor
    /// finally places it). The scroll state is held by reference (both are
    /// classes) so the driver can move the viewport and read whether there is
    /// anything left to reveal in a given direction.
    struct AutoScrollZone {
        /// The viewport region's id — its rect is the auto-scroll frame.
        let handlerID: HitTestRegion.HandlerID

        /// The vertical scroll position to drive (a `ScrollViewHandler` or an
        /// `ItemListHandler`).
        let vertical: any ScrollableOffsetState

        /// The horizontal scroll position, when the scrollable has one (a
        /// `ScrollView` with horizontal scrolling); `nil` otherwise.
        let horizontal: (any ScrollableOffsetState)?

        /// How long the cursor must dwell at this zone's edge before the first
        /// auto-scroll tick — captured from the scrollable's own environment at
        /// registration (`.dragAutoScrollDelay(_:)`), so a per-subtree override
        /// is honoured even though the driver runs at the root.
        let delayNanos: UInt64
    }

    /// The drag in flight, or `nil`.
    struct ActiveDrag {
        /// The dragged value, type-erased (drops re-match it by type).
        let payload: Any

        /// The floating preview drawn at the cursor by the root scene render.
        let preview: FrameBuffer

        /// Where the press landed WITHIN the dragged view (its local space)
        /// — the grab point ``DragPreviewAnchor/grabPoint`` keeps under the
        /// cursor.
        let grabX: Int
        let grabY: Int

        /// How the preview anchors to the cursor.
        let anchor: DragPreviewAnchor

        /// The cursor's absolute position (content-area space).
        var cursorX: Int
        var cursorY: Int

        /// The id of the currently targeted destination, if any — valid only
        /// within the frame that registered it (handler ids reset to 0 every
        /// render pass), so it is used purely to detect targeting
        /// *transitions*, never to look a target up later.
        var targetedID: HitTestRegion.HandlerID?

        /// The targeted destination itself, held by value so its
        /// `setTargeted` closure stays reachable across re-renders — the
        /// zone may re-register under a different id next frame (tree shape
        /// changed) or not re-register at all (zone removed mid-drag), and
        /// its `isTargeted` observer must still be closed out either way.
        var targeted: Target?
    }

    /// The dispatcher whose composited regions supply target geometry.
    weak var dispatcher: MouseEventDispatcher?

    /// This frame's drop targets, in registration (render) order.
    private(set) var targets: [Target] = []

    /// This frame's auto-scroll zones, in registration (render) order — outer
    /// scrollables before the inner ones they contain, so a tie at the cursor
    /// resolves to the innermost by preferring the last (deepest) match.
    private(set) var autoScrollZones: [AutoScrollZone] = []

    /// When the cursor first entered an auto-scroll zone's trigger band on the
    /// current run, or `nil` when nothing is engaged — the anchor for the
    /// configurable initial delay before the first scroll tick.
    private var autoScrollEngagedSinceNanos: UInt64?

    /// The monotonic instant the next auto-scroll tick is due; `0` before the
    /// first tick fires (see ``driveAutoScroll(nowNanos:delayNanos:)``).
    private var autoScrollNextFireNanos: UInt64 = 0

    /// The scrollable currently flagged ``ScrollableOffsetState/isAutoScrolling``.
    private var autoScrollDriven: (any ScrollableOffsetState)?

    /// The drag in flight, or `nil`.
    private(set) var active: ActiveDrag?

    /// The last press/drag/release event in ABSOLUTE coordinates, stamped by
    /// the dispatcher before it localises the event for the captured handler
    /// — drop targeting needs the on-screen cursor position, which the
    /// (region-relative) coordinates a drag handler receives can't provide.
    var lastAbsoluteEvent: MouseEvent?

    /// Clears the per-frame target registrations. Called by the root scene
    /// render before the view tree renders (and re-registers).
    func beginFrame() {
        targets.removeAll(keepingCapacity: true)
        autoScrollZones.removeAll(keepingCapacity: true)
    }

    /// Registers a drop destination for this frame.
    func registerTarget(_ target: Target) {
        targets.append(target)
    }

    /// Registers a scrollable's auto-scroll zone for this frame. Cleared and
    /// re-registered every render, exactly like a drop target — the driver
    /// only ever reads THIS frame's zones against THIS frame's geometry.
    func registerAutoScrollZone(_ zone: AutoScrollZone) {
        autoScrollZones.append(zone)
    }

    /// Starts a drag. The cursor position is taken from the triggering
    /// (absolute) event; targeting is resolved immediately.
    ///
    /// - Parameters:
    ///   - grabX: The press column within the dragged view (local space) —
    ///     the grab point `.grabPoint` keeps under the cursor.
    ///   - grabY: The press row within the dragged view.
    ///   - anchor: How the preview anchors to the cursor.
    func begin(
        payload: Any, preview: FrameBuffer,
        grabX: Int = 0, grabY: Int = 0,
        anchor: DragPreviewAnchor = .grabPoint
    ) {
        guard let event = lastAbsoluteEvent else { return }
        // The preview rides above everything and paints every cell it has, so
        // a row padded to its list's width would erase a column of the screen
        // per blank. Trimmed HERE rather than at each producer, so all three
        // (`.draggable`, and List's and Table's `.cursor` reorder) agree.
        let preview = preview.trimmingTrailingBlankCells()
        // Clamped AFTER the trim: a press in the padding must still anchor the
        // image to the cursor, not to a column the preview no longer has.
        active = ActiveDrag(
            payload: payload, preview: preview,
            grabX: min(max(0, grabX), max(0, preview.width - 1)),
            grabY: min(max(0, grabY), max(0, preview.height - 1)),
            anchor: anchor,
            cursorX: event.x, cursorY: event.y, targetedID: nil, targeted: nil)
        dragMoved()
    }

    /// The floating preview's frame for the drag in flight (absolute,
    /// content-area space), or `nil` when nothing is dragging. The single
    /// source of the anchor math: the root scene render draws the overlay
    /// here, and drops report the same frame through ``DropInfo``.
    func previewFrame() -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let drag = active else { return nil }
        let originX: Int
        let originY: Int
        switch drag.anchor {
        case .grabPoint:
            originX = drag.cursorX - drag.grabX
            originY = drag.cursorY - drag.grabY
        case .offset(let dx, let dy):
            originX = drag.cursorX + dx
            originY = drag.cursorY + dy
        }
        return (originX, originY, drag.preview.width, drag.preview.height)
    }

    /// Advances the drag to the last stamped cursor position and updates
    /// which destination (if any) is targeted, firing `isTargeted`
    /// transitions on the way.
    func dragMoved() {
        guard var drag = active, let event = lastAbsoluteEvent else { return }
        drag.cursorX = event.x
        drag.cursorY = event.y

        let newTarget = resolveTarget(atX: event.x, y: event.y, payload: drag.payload)
        if newTarget?.handlerID != drag.targetedID {
            // The transition CLOSES on the stored target's own closure, not
            // an id lookup — after a re-render the old id maps to a
            // different (or no) registration.
            drag.targeted?.setTargeted(false)
            newTarget?.setTargeted(true)
        }
        // Always refresh the stored target, even when the id is unchanged:
        // it may be this frame's re-registration of the same zone, whose
        // captured region id the drop's coordinate localisation relies on.
        drag.targetedID = newTarget?.handlerID
        drag.targeted = newTarget
        active = drag
    }

    /// Drops the payload on the destination under the cursor (if any), ends
    /// the drag, and reports whether a destination took the payload.
    @discardableResult
    func performDrop() -> Bool {
        guard let drag = active else { return false }
        defer { end() }
        // Resolve against the CURRENT frame's registrations at the release
        // position — never through the id stored at the last movement:
        // handler ids reset every render pass, and a re-render between the
        // last drag event and the release is routine (the consumed drag
        // requests one). A stale id would silently lose the drop — or, if
        // the tree shape shifted the ids, deliver it to the WRONG zone.
        guard let event = lastAbsoluteEvent,
            let target = resolveTarget(atX: event.x, y: event.y, payload: drag.payload)
        else {
            debugFocusLog(
                "performDrop: no target at (\(lastAbsoluteEvent?.x ?? -1), "
                    + "\(lastAbsoluteEvent?.y ?? -1)); \(targets.count) targets, "
                    + "hit ids \(dispatcher?.handlerIDs(at: lastAbsoluteEvent?.x ?? -1, y: lastAbsoluteEvent?.y ?? -1).map(\.raw) ?? []), "
                    + "target ids \(targets.map(\.handlerID.raw))")
            return false
        }
        return target.perform(drag.payload, event)
    }

    /// Ends the drag without dropping (or after one), clearing any targeting.
    /// Whether a gesture that carries no payload — a row reorder — has asked
    /// for the edge auto-scroll.
    ///
    /// `.live` and `.dimmed` reordering never opens a drag (there is nothing to
    /// float), so the driver's `active != nil` gate silently excluded the two
    /// modes people actually use: the zones were registered, the cursor was
    /// stamped, and the driver bailed on its first line.
    private(set) var autoScrollArmed = false

    /// Arms the edge auto-scroll for a gesture with no payload.
    func armAutoScroll() { autoScrollArmed = true }

    /// Releases the arming when the gesture ends WITHOUT having been a drag —
    /// a motionless press and release is a click, and `end()` (which disarms)
    /// only runs when the gesture actually reordered something.
    func disarmAutoScroll() {
        guard active == nil else { return }  // a real drag is still in flight
        autoScrollArmed = false
        autoScrollEngagedSinceNanos = nil
        releaseAutoScrollFlags()
    }

    func end() {
        active?.targeted?.setTargeted(false)
        active = nil
        autoScrollArmed = false
        autoScrollEngagedSinceNanos = nil
        releaseAutoScrollFlags()
    }

    /// Clears ``ScrollableOffsetState/isAutoScrolling`` on whatever this session
    /// last drove. Held as a reference rather than re-derived, because the zone
    /// that engaged may already be gone (its handler ids reset every render, and
    /// a scrollable can leave the tree mid-drag) — and a scrollable left flagged
    /// would never settle again.
    private func releaseAutoScrollFlags() {
        autoScrollDriven?.isAutoScrolling = false
        autoScrollDriven = nil
    }

    // MARK: - Auto-scroll

    /// Geometry and cadence for drag auto-scroll.
    private enum AutoScroll {
        /// Rows of "hot margin" just inside an edge where scrolling engages at
        /// the modest base rate; the rate ramps up the further past the edge
        /// the cursor is dragged.
        static let hotMarginRows = 2
        /// The fastest auto-scroll step, in lines/rows per tick.
        static let maxRate = 6
        /// The interval between ticks once engaged (~18 Hz).
        static let intervalNanos: UInt64 = 55_000_000
    }

    /// One auto-scroll zone plus the per-tick step to apply to it.
    private struct AutoScrollStep {
        let zone: AutoScrollZone
        let dy: Int
        let dx: Int
    }

    /// Drives one auto-scroll tick for the drag in flight when the cursor is
    /// near a registered scrollable's edge, returning whether auto-scroll is
    /// currently engaged. While engaged the run loop keeps ticking even if the
    /// cursor holds still, so a held-at-edge drag keeps scrolling. A no-op (and
    /// `false`) when nothing is dragging or the cursor is near no edge.
    ///
    /// This lives on the session — not on a scrollable — because deciding
    /// *which* scrollable to move and *how far past its edge* the cursor sits
    /// needs the absolute on-screen geometry (from the dispatcher) together
    /// with the drag cursor (here); a scrollable only ever knows its own size,
    /// never where the compositor placed it. The run loop calls this at the top
    /// of a frame, against the still-present previous frame's zones and region
    /// rects (a re-render re-registers both before the mutated scroll shows),
    /// so the scroll appears without a visible frame of lag.
    ///
    /// - Parameter nowNanos: This frame's monotonic timestamp.
    @discardableResult
    func driveAutoScroll(nowNanos: UInt64) -> Bool {
        guard active != nil || autoScrollArmed, let dispatcher, let cursor = lastAbsoluteEvent,
            let step = bestAutoScroll(
                cursorX: cursor.x, cursorY: cursor.y, dispatcher: dispatcher)
        else {
            autoScrollEngagedSinceNanos = nil
            releaseAutoScrollFlags()
            return false
        }

        // Mark the driven scrollable, so a view that tidies up resting scroll
        // positions leaves this one alone until the gesture ends.
        if !step.zone.vertical.isAutoScrolling {
            releaseAutoScrollFlags()
            step.zone.vertical.isAutoScrolling = true
            autoScrollDriven = step.zone.vertical
        }

        if autoScrollEngagedSinceNanos == nil {
            // Just engaged: arm the configurable initial delay before the first
            // tick, so a drag merely crossing an edge on its way elsewhere
            // doesn't yank the viewport.
            autoScrollEngagedSinceNanos = nowNanos
            autoScrollNextFireNanos = nowNanos &+ step.zone.delayNanos
        } else if nowNanos >= autoScrollNextFireNanos {
            if step.dy != 0 { step.zone.vertical.scrollFine(by: step.dy) }
            if step.dx != 0 { step.zone.horizontal?.scrollFine(by: step.dx) }
            autoScrollNextFireNanos = nowNanos &+ AutoScroll.intervalNanos
        }
        return true
    }

    /// The innermost engaged zone at the cursor and its per-tick step, or `nil`
    /// when the cursor is near no scrollable edge. Innermost wins: zones are
    /// registered outer-first, and the smallest-area match is the deepest, so a
    /// drag over a scrollable nested in another scrolls the inner one.
    private func bestAutoScroll(
        cursorX: Int, cursorY: Int, dispatcher: MouseEventDispatcher
    ) -> AutoScrollStep? {
        var best: (step: AutoScrollStep, area: Int)?
        for zone in autoScrollZones {
            guard let rect = dispatcher.regionRect(for: zone.handlerID) else { continue }
            let withinCols = cursorX >= rect.offsetX && cursorX < rect.offsetX + rect.width
            let withinRows = cursorY >= rect.offsetY && cursorY < rect.offsetY + rect.height

            // Vertical scroll needs the cursor over the zone's columns (so a
            // cursor far to the side isn't a candidate); horizontal needs it
            // within the rows. A cursor past an edge stays a candidate on the
            // OTHER axis' overlap — that is the "drag past the edge" case.
            let dy =
                withinCols
                ? Self.autoScrollDelta(
                    position: cursorY, start: rect.offsetY, extent: rect.height,
                    canBackward: zone.vertical.hasContentAbove,
                    canForward: zone.vertical.hasContentBelow)
                : 0
            let dx: Int
            if let horizontal = zone.horizontal, withinRows {
                dx = Self.autoScrollDelta(
                    position: cursorX, start: rect.offsetX, extent: rect.width,
                    canBackward: horizontal.hasContentAbove,
                    canForward: horizontal.hasContentBelow)
            } else {
                dx = 0
            }

            guard dy != 0 || dx != 0 else { continue }
            let area = rect.width * rect.height
            if best == nil || area <= best!.area {
                best = (AutoScrollStep(zone: zone, dy: dy, dx: dx), area)
            }
        }
        return best?.step
    }

    /// The signed per-tick step for one axis: negative toward the start,
    /// positive toward the end, `0` when the cursor is comfortably inside the
    /// viewport or the axis cannot move that way. The magnitude ramps from the
    /// modest base rate within the hot margin to ``AutoScroll/maxRate`` the
    /// further past the edge the cursor sits — the macOS drag-autoscroll feel
    /// (near the edge: gentle; dragged past it: markedly faster). When a
    /// scrollable butts against the screen edge the cursor clamps there and the
    /// rate tops out modestly; when it has room past its edge (a scrollable
    /// smaller than the screen) the cursor can go further and accelerate — the
    /// same distinction macOS makes.
    static func autoScrollDeltaForTesting(
        position: Int, start: Int, extent: Int, canBackward: Bool, canForward: Bool
    ) -> Int {
        autoScrollDelta(
            position: position, start: start, extent: extent,
            canBackward: canBackward, canForward: canForward)
    }

    private static func autoScrollDelta(
        position: Int, start: Int, extent: Int, canBackward: Bool, canForward: Bool
    ) -> Int {
        guard extent > 0 else { return 0 }
        let lastEdge = start + extent - 1
        // The margin is clamped so the two hot zones can never meet: on a short
        // scrollable a fixed 2-row margin is more than half the viewport, so
        // every row lands inside one zone or the other and hovering the MIDDLE
        // scrolled. Leaving at least one neutral row keeps "near an edge"
        // meaning near an edge. (A 1-row viewport gets no margin at all —
        // there is no room for one, and its only row must stay inert.)
        let margin = Swift.max(0, Swift.min(AutoScroll.hotMarginRows, (extent - 1) / 2))
        let pastStart = (start + margin) - position
        let pastEnd = position - (lastEdge - margin)
        if pastStart > 0, canBackward { return -rate(forOvershoot: pastStart) }
        if pastEnd > 0, canForward { return rate(forOvershoot: pastEnd) }
        return 0
    }

    /// Lines/rows per tick for how far the cursor is past the hot-margin
    /// trigger: the base rate within the margin, then one more per row beyond
    /// the edge, capped at ``AutoScroll/maxRate``.
    private static func rate(forOvershoot overshoot: Int) -> Int {
        Swift.min(AutoScroll.maxRate, 1 + Swift.max(0, overshoot - AutoScroll.hotMarginRows))
    }

    /// The innermost on-screen region at the given position that is a
    /// registered, payload-compatible target, from THIS frame's
    /// registrations.
    private func resolveTarget(atX x: Int, y: Int, payload: Any) -> Target? {
        let hitIDs = dispatcher?.handlerIDs(at: x, y: y) ?? []
        return hitIDs.lazy
            .compactMap { id in
                self.targets.first { $0.handlerID == id && $0.accepts(payload) }
            }
            .first
    }
}
