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

    /// The drag in flight, or `nil`.
    struct ActiveDrag {
        /// The dragged value, type-erased (drops re-match it by type).
        let payload: Any

        /// The floating preview drawn at the cursor by the root scene render.
        let preview: FrameBuffer

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
    }

    /// Registers a drop destination for this frame.
    func registerTarget(_ target: Target) {
        targets.append(target)
    }

    /// Starts a drag. The cursor position is taken from the triggering
    /// (absolute) event; targeting is resolved immediately.
    func begin(payload: Any, preview: FrameBuffer) {
        guard let event = lastAbsoluteEvent else { return }
        active = ActiveDrag(
            payload: payload, preview: preview,
            cursorX: event.x, cursorY: event.y, targetedID: nil, targeted: nil)
        dragMoved()
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
    func end() {
        active?.targeted?.setTargeted(false)
        active = nil
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
