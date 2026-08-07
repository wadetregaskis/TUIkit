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
        // Whether a reorder gesture was in flight AT ALL — set at
        // `beginReorder` and cleared below. Asked before the handler lookups
        // because the handler can be gone while the gesture is not: the
        // session holds it weakly, so a control that left the page, came back
        // (adopting the reorder onto a replacement) and left again takes the
        // replacement with it. That release still ends the gesture.
        let wasReordering = reorderFocusID != nil
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
            if let orphan = reorderHandler, orphan.reorder?.active == true {
                orphan.cancelReorder()
            }
            // Even with NO handler left to tell, the gesture is over and the
            // session's drag has to end: returning `false` here left the
            // floating preview painted at the last cursor position for the
            // rest of the session (only a new drag ever replaced it) and let
            // the release fall through to the click path, which selects
            // through press-frame geometry belonging to a list that is no
            // longer on screen.
            guard wasReordering else { return false }
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
        //
        // Latched on the SESSION as well as the handler. The handler latch
        // alone is unreliable the moment a reorder has been adopted after a
        // page round-trip: it lands on whichever handler the session holds
        // (the replacement), and the release path — which falls back to the
        // press-captured handler once the session forgets its own — then
        // consults an object that was never flagged, so the cancelled gesture
        // fell through to the click path anyway.
        reorderCancelledPendingRelease = true
        reorderHandler?.reorderCancelled = true
        reorderFocusID = nil
        reorderHandler = nil
        cancelReturningToOrigin()
    }

    /// Reads and clears the session's cancel latch — "the release now arriving
    /// is the tail of a cancelled gesture, not a click". One-shot, like the
    /// handler-level flag it backstops.
    func consumeReorderCancellation() -> Bool {
        defer { reorderCancelledPendingRelease = false }
        return reorderCancelledPendingRelease
    }

    /// The scrollable a navigator pressed mid-drag should move: the innermost
    /// registered zone under the cursor that this gesture could actually land
    /// in, or `nil` when the pointer is over nothing that qualifies.
    ///
    /// The same zones, the same "could this drag land here" rule and the same
    /// innermost-wins tiebreak the edge auto-scroll uses — deliberately, so the
    /// keys and the edges can never disagree about which view is in play. What
    /// differs is only the geometry: auto-scroll asks whether the cursor is near
    /// an EDGE, this asks whether it is inside at all.
    func zoneUnderCursor() -> AutoScrollZone? {
        guard let dispatcher, let cursor = lastAbsoluteEvent else { return nil }
        var best: (zone: AutoScrollZone, area: Int)?
        for zone in autoScrollZones {
            guard let rect = dispatcher.regionRect(for: zone.handlerID),
                cursor.x >= rect.offsetX, cursor.x < rect.offsetX + rect.width,
                cursor.y >= rect.offsetY, cursor.y < rect.offsetY + rect.height,
                canReceiveDrag(zone, rect: rect, dispatcher: dispatcher)
            else { continue }
            let area = rect.width * rect.height
            if best == nil || area <= best!.area { best = (zone, area) }
        }
        return best?.zone
    }

    /// Just the scroll state of ``zoneUnderCursor()``.
    func scrollableUnderCursor() -> (any ScrollableOffsetState)? {
        zoneUnderCursor()?.vertical
    }

    /// Answers a navigator key pressed while a drag gesture is in flight, by
    /// scrolling the view under the pointer. Reports whether it did.
    ///
    /// This runs ahead of the focus system deliberately. The keys have to reach
    /// the view the payload is OVER, and that view is usually not the focused
    /// one — a drag starts by focusing its source, and the whole point of
    /// carrying a payload somewhere else is that "somewhere else" is where you
    /// need to scroll. Left to the focus system these keys would move the source
    /// list's own selection instead, mid-drag, which is both useless and
    /// destructive.
    ///
    /// Declines when the pointer is over nothing this drag could land in, so a
    /// gesture held over inert chrome leaves the keys to mean what they usually
    /// mean; a scrollable that registered no zone (`.scrollDisabled`) is not a
    /// candidate either, and a reorder inside it still falls through to
    /// ``ItemListHandler/handleDragScrollKey(_:)``.
    func handleDragNavigator(_ event: KeyEvent) -> Bool {
        guard active != nil || autoScrollArmed, let zone = zoneUnderCursor() else { return false }
        let target = zone.vertical
        let step = event.shift ? max(1, zone.shiftStep) : 1
        // One screenful of the view under the pointer, in its own stepping
        // unit and measured from where it is NOW — see
        // `ScrollableOffsetState.pageDistance`, which is the only place a
        // page is defined.
        let page = target.pageDistance
        switch event.key {
        case .up: target.scrollFine(by: -step)
        case .down: target.scrollFine(by: step)
        // Re-based on what the target DREW, not on where its offset stands:
        // near the top edge a viewport at offset 1 draws from 0, and mid-drag
        // that duplicate is reachable (Home leaves you on 0, Page Up on 1), so
        // one Page Down from two identical-looking screens used to go two rows
        // or three. The steps above must NOT be re-based — stepping is how the
        // offset gets past the duplicate. See
        // `ScrollableOffsetState.pageDelta(_:)`, and the twin of this switch in
        // `ItemListHandler.handleDragScrollKey`, which follows the same rules.
        case .pageUp: target.scrollFine(by: target.pageDelta(-page))
        case .pageDown: target.scrollFine(by: target.pageDelta(page))
        case .home: target.scrollToOffset(0)
        case .end: target.scrollToOffset(target.settledMaxOffset)
        default: return false
        }
        target.releaseAnchorOnUserScroll()
        return true
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
