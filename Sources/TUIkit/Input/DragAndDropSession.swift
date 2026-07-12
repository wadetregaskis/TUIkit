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

        /// The currently targeted destination, if any.
        var targetedID: HitTestRegion.HandlerID?
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
            cursorX: event.x, cursorY: event.y, targetedID: nil)
        dragMoved()
    }

    /// Advances the drag to the last stamped cursor position and updates
    /// which destination (if any) is targeted, firing `isTargeted`
    /// transitions on the way.
    func dragMoved() {
        guard var drag = active, let event = lastAbsoluteEvent else { return }
        drag.cursorX = event.x
        drag.cursorY = event.y

        // The innermost on-screen region at the cursor that is a registered,
        // payload-compatible target wins.
        let hitIDs = dispatcher?.handlerIDs(at: event.x, y: event.y) ?? []
        let newTarget = hitIDs.lazy
            .compactMap { id in
                self.targets.first { $0.handlerID == id && $0.accepts(drag.payload) }
            }
            .first

        if newTarget?.handlerID != drag.targetedID {
            if let previous = drag.targetedID {
                target(for: previous)?.setTargeted(false)
            }
            newTarget?.setTargeted(true)
            drag.targetedID = newTarget?.handlerID
        }
        active = drag
    }

    /// Drops the payload on the targeted destination (if any), ends the
    /// drag, and reports whether a destination took the payload.
    @discardableResult
    func performDrop() -> Bool {
        guard let drag = active else { return false }
        defer { end() }
        guard let targetedID = drag.targetedID,
            let target = target(for: targetedID),
            let event = lastAbsoluteEvent
        else { return false }
        return target.perform(drag.payload, event)
    }

    /// Ends the drag without dropping (or after one), clearing any targeting.
    func end() {
        if let targetedID = active?.targetedID {
            target(for: targetedID)?.setTargeted(false)
        }
        active = nil
    }

    private func target(for id: HitTestRegion.HandlerID) -> Target? {
        targets.first { $0.handlerID == id }
    }
}
