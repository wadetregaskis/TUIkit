//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragAndDropSession+Reorder.swift
//
//  Row reordering, resolved the way `.draggable` drops already were: against
//  the control that is on screen at the moment of the event, not the one the
//  press closed over.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension DragAndDropSession {
    /// One frame's registration of a control whose rows can be reordered.
    ///
    /// The sibling of ``DragAndDropSession/Target``, and for the same reason. A
    /// reorder used to be bound at press time to the `ItemListHandler` the mouse
    /// closure captured, which is wrong twice over once anything moves: that
    /// object is not necessarily the one drawing the rows any more (leaving a
    /// page prunes its state and re-entering builds a new one), and the press
    /// frame's geometry is not where the rows are now. Registering per render
    /// answers both — the drop runs against this frame's control, through this
    /// frame's rectangle.
    struct ReorderHost {
        /// The control's focus identity — the gesture's key, because it is the
        /// one name that survives both a re-render and a trip off the page.
        let focusID: String

        /// This frame's hit region for the control. Its rect (from the
        /// dispatcher, post-composite) localises the cursor, exactly as a
        /// ``DragAndDropSession/Target``'s does.
        let handlerID: HitTestRegion.HandlerID

        /// Lines of chrome between the region's top and the first row line — a
        /// border, a title, a `Table`'s column header and scroll indicator.
        let topInset: Int

        /// The columns within the region that are rows rather than chrome; a
        /// cursor outside them is off the rows.
        let contentColumns: Range<Int>

        /// The control's reorder state machine.
        let handler: any RowReorderHosting
    }

    /// Registers a control as this frame's home for reorders of its rows, and
    /// resumes a gesture that has come back to it.
    ///
    /// The resume is the point: a `List` that left the view tree and returned
    /// comes back as a *different* `ItemListHandler` (its `StateStorage` box was
    /// pruned while it was away), and the rows in the user's hand are held by
    /// the old one — which draws nothing and whose `onMove` writes into state
    /// nothing reads. Handing them over here, before the events that follow,
    /// makes the drop land in the list actually on screen.
    func registerReorderHost(_ host: ReorderHost) {
        reorderHosts.append(host)
        guard host.focusID == reorderFocusID,
            let origin = reorderHandler, origin !== host.handler,
            let carried = origin.reorder
        else { return }
        host.handler.reorder = carried
        host.handler.isKeyboardMove = origin.isKeyboardMove
        origin.reorder = nil
        // The gesture's own scrollable is the one thing always allowed to
        // auto-scroll under it (see `canReceiveDrag`); that permission has to
        // follow the rows, or the resumed list refuses to scroll.
        adoptAutoScrollOwner(from: origin, to: host.handler)
        reorderHandler = host.handler
    }

    /// Records that a mouse gesture has picked up rows in the named control.
    ///
    /// Mouse only, deliberately: a keyboard move (<kbd>Ctrl</kbd>+<kbd>R</kbd>)
    /// is bounded by the control it started in and ends with the page, so it
    /// has nothing to resume and nothing to hand over.
    func beginReorder(focusID: String, handler: any RowReorderHosting) {
        reorderFocusID = focusID
        reorderHandler = handler
    }

    /// Advances the reorder in flight, against the control on screen now.
    ///
    /// Silently does nothing when that control is not on screen — the rows keep
    /// riding the cursor, and the gesture picks up where it left off if the user
    /// navigates back. That is the same contract a `.draggable` payload has
    /// while it is over a page that would refuse it.
    func trackReorder() {
        guard let host = currentReorderHost() else { return }
        host.handler.dragReorder(toContentY: contentY(in: host))
    }

    /// Commits the reorder in flight and takes the floating preview down the way
    /// the gesture ended, reporting whether this gesture *was* a reorder —
    /// `false` means the caller should carry on and treat it as a click.
    ///
    /// `end`, never ``performDrop()``: the payload is unnameable, so no
    /// `dropDestination` could take it, and the control has placed the rows
    /// itself.
    @discardableResult
    func performReorderDrop() -> Bool {
        defer {
            reorderFocusID = nil
            reorderHandler = nil
        }
        guard let host = currentReorderHost() else {
            // Nothing on screen owns these rows: the control was navigated away
            // from and never came back. The rows go home rather than landing in
            // a list the user cannot see — and the preview walks back rather
            // than vanishing under the pointer, which is what every other
            // "nothing happened" already does.
            guard let orphan = reorderHandler, orphan.reorder?.active == true else { return false }
            orphan.cancelReorder()
            cancelReturningToOrigin()
            return true
        }
        let contentY = contentY(in: host)
        // Asked BEFORE the drop, which clears the state it reads.
        let landsNowhere = host.handler.reorderLandsNowhere(atContentY: contentY)
        guard host.handler.dropReorder(atContentY: contentY) else { return false }
        if landsNowhere {
            cancelReturningToOrigin()
        } else {
            end()
        }
        return true
    }

    /// Abandons the reorder in flight without moving anything — the rows go back
    /// where they were picked up and the preview walks home.
    func cancelReorder() {
        reorderHandler?.cancelReorder()
        // The button is still down, so a release is still coming: without the
        // latch it falls into the click path and selects whatever row the
        // pointer happens to be over.
        reorderHandler?.reorderCancelled = true
        reorderFocusID = nil
        reorderHandler = nil
        cancelReturningToOrigin()
    }

    /// The control this frame registered for the gesture in flight, if any.
    ///
    /// Last match wins, on the same reasoning as ``autoScrollZones``:
    /// registration follows render order, so the deepest one registered last.
    private func currentReorderHost() -> ReorderHost? {
        guard let reorderFocusID else { return nil }
        return reorderHosts.last { $0.focusID == reorderFocusID }
    }

    /// Where the cursor sits in a host's content-line space — the coordinates
    /// its rows are laid out in — or `nil` when it is off the rows' columns.
    ///
    /// Derived from the ABSOLUTE cursor and this frame's rectangle, never from
    /// the coordinates the captured mouse closure was handed: the dispatcher
    /// localises a captured gesture by the offsets stamped at the *press*, which
    /// stop describing anything real the moment the control moves under it.
    private func contentY(in host: ReorderHost) -> Int? {
        guard let event = lastAbsoluteEvent,
            let rect = dispatcher?.regionRect(for: host.handlerID)
        else { return nil }
        guard host.contentColumns.contains(event.x - rect.offsetX) else { return nil }
        return event.y - rect.offsetY - host.topInset
    }
}
