//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler+Reorder.swift
//
//  The drag-to-reorder state machine for `List` rows, shared by every feedback
//  mode (``RowReorderFeedback``). It lives on the handler rather than in
//  `_ListCore`'s mouse closure for two reasons: the closure is captured at
//  press time and outlives the render that made it, and the handler is what
//  survives between renders — so the drag reads the CURRENT row geometry
//  (``ItemListHandler/visibleRowBands``, republished every render) instead of a
//  press-frame copy that `.live` reordering would immediately invalidate.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension ItemListHandler {

    // MARK: - Geometry

    /// The data offset of the **content** row covering `contentY`, or `nil` for
    /// a section header, the reorder drop slot, a line no row occupies, or a
    /// list that hasn't published its geometry yet.
    ///
    /// This is the row the keyboard cursor should sit on. For where a DROP would
    /// land, ask ``dropTarget(atContentY:)`` — during a drag the two differ.
    ///
    /// `contentY` is in the same space as ``visibleRowBands``: lines from the
    /// first content line of the list's interior.
    func contentRowIndex(atContentY contentY: Int) -> Int? {
        band(atContentY: contentY).flatMap { $0.isContent ? $0.rowIndex : nil }
    }

    /// Where a drop at `contentY` would put the dragged row, or `nil` when that
    /// line is not a drop target (a section header, or nothing at all).
    ///
    /// The answer is a prospective FINAL index, not a data offset: a drag takes
    /// the row out of the list, so what is drawn is already the post-drop order
    /// and a line's position in it is exactly where a drop there lands the row.
    /// `move(from:to:)` is defined to produce that index, so the two agree by
    /// construction. Outside a drag every band's `dropIndex` is its own
    /// `rowIndex`, so `.live` and the click path are unaffected.
    func dropTarget(atContentY contentY: Int) -> Int? {
        band(atContentY: contentY)?.dropIndex
    }

    /// The published band covering `contentY`.
    private func band(atContentY contentY: Int) -> RowBand? {
        visibleRowBands.first { contentY >= $0.yStart && contentY < $0.yStart + $0.height }
    }

    /// `index` as it will be numbered once the dragged row has left its place —
    /// everything after the source shifts down one.
    ///
    /// The single piece of index arithmetic the whole feature rests on; the drop
    /// slot, the drop target and the decoration all derive from it, so it lives
    /// in one place rather than being re-derived at each site.
    func reorderClosedUpIndex(_ index: Int, removed: IndexSet) -> Int {
        index - removed.count(where: { $0 < index })
    }

    /// The data offset that a drop at closed-up position `slot` must pass to
    /// `onMove`, whose `toOffset` is measured against the collection BEFORE the
    /// move: the index of the `slot`-th row that is NOT in hand.
    ///
    /// Subsumes the single-row rule this replaced (`from < target ? target + 1
    /// : target`) — for one removed row the two agree at every position.
    func reorderInsertionOffset(forSlot slot: Int, removed: IndexSet) -> Int {
        var seen = 0
        for index in 0..<itemCount where !removed.contains(index) {
            if seen == slot { return index }
            seen += 1
        }
        return itemCount
    }

    /// The row a non-`.live` drag has taken OUT of the list, or `nil` when the
    /// list is drawn in its plain data order.
    ///
    /// The two conditions have to be asked together, and by everything that
    /// cares, or the drawing and the hit-testing disagree about what is on
    /// screen. `.dimmed` draws the row only at the drop slot, so with nowhere to
    /// drop it there is nothing to draw and the list is left exactly as it was;
    /// `.cursor` has the row on the pointer for the whole drag, so it is out of
    /// the list for the whole drag, slot or no slot.
    var reorderRemovedRow: Int? {
        guard let source = reorderSource else { return nil }
        guard effectiveReorderFeedback == .cursor || reorderPlaceholder != nil else { return nil }
        return source
    }

    /// EVERY row the drag has taken out of the list — the whole selection when
    /// one was picked up. ``reorderRemovedRow`` is the one of them the pointer
    /// grabbed, which is what the float and the faint copy show; this is what
    /// the drawing and the index arithmetic have to work from, or a multi-row
    /// drag draws rows it is carrying.
    var reorderRemovedRows: IndexSet {
        guard reorderRemovedRow != nil, let reorder else { return IndexSet() }
        return reorder.held
    }

    /// Where the row with data offset `index` sits in the order currently
    /// DRAWN: closed up behind the dragged row, then pushed past the drop slot.
    ///
    /// This is what a drop on that row has to produce. A prospective FINAL index
    /// is the same currency ``move(from:to:)`` takes, so the slot opens on the
    /// very line the pointer is on, whichever direction the pointer arrived
    /// from — and every position, including the row's own, can be named.
    ///
    /// Reading the row's DATA offset instead agrees only while the pointer is
    /// below the slot. Above it every row named the position one past itself, so
    /// dragging back up moved the slot a row late; and the source's own place —
    /// the one destination a user is most likely to want back, and mid-drag the
    /// only way to change their mind — could not be named at all, because the
    /// line it came from is occupied by its successor, which names its own
    /// offset, which is one too far.
    ///
    /// Returns `index` unchanged outside such a drag, where the list is drawn in
    /// data order and the two are the same number.
    func reorderDrawnPosition(of index: Int) -> Int {
        let removed = reorderRemovedRows
        guard !removed.isEmpty else {
            // A drag from ELSEWHERE takes no rows out of this list, but its
            // landing slot still pushes every row at or past it down a line —
            // so a row below the slot names the position after itself, exactly
            // as a reorder's does. Without this the mapping is a fixed point:
            // the row under the pointer keeps naming the index the slot is
            // already at, and the gap sits one row above the cursor for the
            // rest of the drag.
            guard let slot = externalDropSlot else { return index }
            return index >= slot ? index + 1 : index
        }
        let closedUp = reorderClosedUpIndex(index, removed: removed)
        guard let slot = reorderPlaceholder?.slot else { return closedUp }
        return closedUp >= slot ? closedUp + 1 : closedUp
    }

    // MARK: - Which feedback

    /// The feedback actually shown, which is ``reorderFeedback`` except where
    /// ``RowReorderFeedback/cursor`` has no cursor to ride.
    ///
    /// That mode's whole idea is the row travelling with the pointer, which
    /// takes two things: a pointer, and a drag session to draw the row above the
    /// frame. A move driven from the KEYBOARD has neither, and a build with no
    /// drag session has no way to draw it. Both fall back to
    /// ``RowReorderFeedback/dimmed`` — the same information (a faint copy of the
    /// row where it would land) in the one place that is left to show it. The
    /// alternative, an empty gap and a row that is nowhere at all, would just
    /// look like the row had been deleted.
    var effectiveReorderFeedback: RowReorderFeedback {
        // A move started from the KEYBOARD always previews dimmed, whatever the
        // view asked for. A mouse drag needs no mode indicator — the pointer is
        // one — but Ctrl-R puts the control into a state the user cannot see
        // otherwise, and `.live` (which just shuffles the data) shows nothing at
        // all. The faint copy at the slot IS the indicator.
        if isKeyboardMove { return .dimmed }
        guard reorderFeedback == .cursor else { return reorderFeedback }
        return canFloatDraggedRow ? .cursor : .dimmed
    }

    // MARK: - Moving a row from the keyboard

    /// Picks the focused row up, or — if one is already in hand — puts it down
    /// where it now is. Reports whether anything happened, so an unreorderable
    /// list lets the key through to whatever else wants it.
    ///
    /// From here the arrow keys (and Home/End/Page) move the row's landing SLOT
    /// rather than the cursor, ``placeHeldRow()`` commits and
    /// ``cancelKeyboardMove()`` puts it back. That is the only way this control's
    /// grammar changes, and only while a row is in hand.
    @discardableResult
    func beginKeyboardMove() -> Bool {
        guard onMove != nil, itemCount > 0 else { return false }
        if isKeyboardMove {
            placeHeldRow()
            return true
        }
        beginReorder(grabbing: focusedIndex)
        // A keyboard move is a move from the first keystroke: there is no
        // "moved far enough to not be a click" question to answer.
        reorder?.active = true
        // The slot starts where the held rows already are — as a CLOSED-UP
        // position, which for a multi-row hold is not the focused index: the
        // rows above it in the selection have already left.
        let held = reorder?.held ?? IndexSet()
        reorder?.targetOffset = reorderClosedUpIndex(focusedIndex, removed: held)
        isKeyboardMove = true
        return true
    }

    /// Moves the landing slot by `delta` rows, clamped to the list.
    func moveHeldRow(by delta: Int) {
        guard let reorder else { return }
        moveHeldRow(to: (reorder.targetOffset ?? reorder.currentOffset) + delta)
    }

    /// Moves the landing slot to `slot`, clamped to the list.
    ///
    /// Under ``RowReorderFeedback/live`` there is no slot to move: the data
    /// moves now, one `onMove` per step, exactly as a live drag does. The slot
    /// modes leave the data alone and move the gap, so the list keeps its length
    /// and one `onMove` fires at the drop.
    func moveHeldRow(to slot: Int) {
        guard var reorder, reorder.active else { return }
        let target = min(max(0, slot), max(0, itemCount - 1))
        if effectiveReorderFeedback == .live {
            let landed = move(from: reorder.currentOffset, to: target)
            reorder.currentOffset = landed
            reorder.targetOffset = landed
            focusedIndex = clampedRowIndex(landed)
        } else {
            reorder.targetOffset = target
            // Keep the cursor beside the slot so an enclosing scroller follows
            // it off-screen: the slot itself is not a row the cursor can sit on.
            focusedIndex = clampedRowIndex(target < reorder.grabbedOffset ? target : target + 1)
        }
        self.reorder = reorder
        ensureFocusedItemVisible()
    }

    /// Drops the row at the slot it is showing.
    func placeHeldRow() {
        defer { endKeyboardMove() }
        guard let reorder, reorder.active else { return }
        if effectiveReorderFeedback == .live {
            focusedIndex = clampedRowIndex(reorder.currentOffset)
        } else if let target = reorder.targetOffset {
            focusedIndex = clampedRowIndex(
                move(reorder.held, to: target) + reorder.primaryRank)
        }
        ensureFocusedItemVisible()
    }

    /// Abandons the move: the row goes back where it was picked up.
    ///
    /// Under `.live` that means moving it back — the data has been moving all
    /// along — while the slot modes never moved it, so there is only the gap to
    /// drop.
    func cancelKeyboardMove() {
        defer { endKeyboardMove() }
        guard let reorder, reorder.active else { return }
        if effectiveReorderFeedback == .live, reorder.currentOffset != reorder.grabbedOffset {
            move(from: reorder.currentOffset, to: reorder.grabbedOffset)
        }
        focusedIndex = clampedRowIndex(reorder.grabbedOffset)
        ensureFocusedItemVisible()
    }

    private func endKeyboardMove() {
        reorder = nil
        isKeyboardMove = false
    }

    /// The whole keyboard-reorder branch: the keys a held row answers, or the
    /// chord that picks one up. `nil` when neither applies, so the key goes on
    /// to mean whatever it usually means.
    /// Every key reordering claims, in one place: the chords, the held-row
    /// movement, and — while a MOUSE drag is in flight — the navigators, which
    /// scroll rather than move the cursor. `nil` means "not ours".
    func handleReorderKey(_ event: KeyEvent) -> Bool? {
        if let handled = handleRowMoveKey(event) { return handled }
        guard isReordering, !isKeyboardMove else { return nil }
        return handleDragScrollKey(event)
    }

    func handleRowMoveKey(_ event: KeyEvent) -> Bool? {
        // A mouse drag owns the gesture: it must not fall into the keyboard-move
        // keys. `.pickUpRow` there would overwrite the in-flight reorder and
        // latch `isKeyboardMove`, which the mouse release does not clear —
        // leaving the list in a mode with nothing in hand. NO key cancels it
        // either, deliberately: see ``cancelMouseDragReorder()``.
        if isReordering, !isKeyboardMove { return nil }
        if isKeyboardMove, let handled = handleKeyboardMoveKey(event) { return handled }
        // Chords, so they work in either selection mode.
        guard let (action, accelerated) = shortcuts.action(for: event) else { return nil }
        // Shift rides along as the coarse step, exactly as it does for the
        // cursor keys — same environment-configured multiplier.
        let step = accelerated ? max(1, shiftStepMultiplier) : 1
        switch action {
        case .pickUpRow: return beginKeyboardMove() ? true : nil
        case .moveRowUp: return nudgeFocusedRow(by: -step) ? true : nil
        case .moveRowDown: return nudgeFocusedRow(by: step) ? true : nil
        case .moveRowPageUp: return nudgeFocusedRow(by: -pageStep) ? true : nil
        case .moveRowPageDown: return nudgeFocusedRow(by: pageStep) ? true : nil
        case .moveRowToTop: return moveFocusedRow(to: 0) ? true : nil
        case .moveRowToBottom: return moveFocusedRow(to: itemCount - 1) ? true : nil
        case .selectAll, .extendSelection, .placeRow, .cancelMove: return nil
        }
    }

    /// Moves the focused row one place, with no mode to enter or leave — the
    /// single-step shortcut that is most of what reordering ever is.
    ///
    /// Each press is one `onMove`, so it is undoable and repeatable in the
    /// app's own terms, and the cursor rides along with the row.
    /// Applies a bound chord to the row currently in hand. Returns whether it
    /// meant anything here — a selection chord does not.
    private func heldRowChord(_ bound: (action: RowAction, accelerated: Bool)) -> Bool {
        let step = bound.accelerated ? max(1, shiftStepMultiplier) : 1
        switch bound.action {
        case .placeRow, .pickUpRow: placeHeldRow()
        case .cancelMove: cancelKeyboardMove()
        case .moveRowUp: moveHeldRow(by: -step)
        case .moveRowDown: moveHeldRow(by: step)
        case .moveRowPageUp: moveHeldRow(by: -pageStep)
        case .moveRowPageDown: moveHeldRow(by: pageStep)
        case .moveRowToTop: moveHeldRow(to: 0)
        case .moveRowToBottom: moveHeldRow(to: itemCount - 1)
        case .selectAll, .extendSelection: return false
        }
        return true
    }

    /// The navigators, while a MOUSE drag is in flight: they scroll the
    /// viewport and leave the cursor and the selection exactly where they are.
    ///
    /// Moving the focus mid-drag is confusing in a specific way — the next
    /// pointer movement snaps it back, because the drag re-points the cursor at
    /// the row under the pointer. Scrolling is what these keys are FOR here:
    /// reaching a destination that is off-screen without letting go.
    ///
    /// Every claimed key returns `true` even at an edge: an unconsumed arrow is
    /// taken by the focus system's in-section navigation and would move focus to
    /// another control mid-drag, which is worse than a no-op.
    func handleDragScrollKey(_ event: KeyEvent) -> Bool? {
        let step = event.shift ? max(1, shiftStepMultiplier) : 1
        switch event.key {
        case .up: scrollFine(by: -step)
        case .down: scrollFine(by: step)
        case .pageUp: scrollFine(by: -pageStep)
        case .pageDown: scrollFine(by: pageStep)
        case .home:
            scrollOffset = 0
            scrollTopClipLines = 0
        case .end:
            scrollOffset = maxOffset
            scrollTopClipLines = 0
        default: return nil
        }
        releaseAnchorOnUserScroll()
        return true
    }

    /// A screenful, in rows — the same unit the Page keys scroll by.
    var pageStep: Int { max(1, viewportHeight - 1) }

    /// Moves the focused row to an absolute position, with no mode to enter:
    /// the Home/End of reordering.
    @discardableResult
    func moveFocusedRow(to destination: Int) -> Bool {
        guard onMove != nil, itemCount > 1 else { return false }
        let from = clampedRowIndex(focusedIndex)
        let target = min(max(0, destination), itemCount - 1)
        guard target != from else { return false }
        focusedIndex = move(from: from, to: target)
        ensureFocusedItemVisible()
        return true
    }

    @discardableResult
    func nudgeFocusedRow(by delta: Int) -> Bool {
        guard onMove != nil, itemCount > 0 else { return false }
        let target = min(max(0, focusedIndex + delta), itemCount - 1)
        guard target != focusedIndex else { return true }
        focusedIndex = clampedRowIndex(move(from: focusedIndex, to: target))
        ensureFocusedItemVisible()
        return true
    }

    /// The keys a held row answers, or `nil` for one that keeps its usual
    /// meaning (so a chord the app bound elsewhere still works mid-move).
    private func handleKeyboardMoveKey(_ event: KeyEvent) -> Bool? {
        if let bound = shortcuts.action(for: event), heldRowChord(bound) { return true }
        let page = pageStep
        // Shift is the coarse step here too. It cannot arrive as an accelerated
        // CHORD the way a nudge does — this mode claims the BARE arrows, which
        // no binding names — so the multiplier is applied on this path as well.
        // Page/Home/End ignore it: a screenful and an end are already coarse.
        let step = event.shift ? max(1, shiftStepMultiplier) : 1
        switch event.key {
        case .up: moveHeldRow(by: -step)
        case .down: moveHeldRow(by: step)
        case .pageUp: moveHeldRow(by: -page)
        case .pageDown: moveHeldRow(by: page)
        case .home: moveHeldRow(to: 0)
        case .end: moveHeldRow(to: itemCount - 1)
        default: return nil
        }
        return true
    }

    // MARK: - What to draw

    /// One entry in the order a view actually draws during a reorder drag.
    enum DrawnRow: Equatable {
        /// A real row, by data offset.
        case row(Int)

        /// The drop slot — a gap the size of the dragged row (`.cursor`), or a
        /// faint copy of it (`.dimmed`). It has no data behind it: the keyboard
        /// cursor cannot sit on it and selection ignores it, but it IS a drop
        /// target, because after every step of the drag the pointer is on it.
        case slot
    }

    /// The rows to draw for `visible`, with the dragged row taken out and the
    /// drop slot opened where it would land.
    ///
    /// So a drag never changes how much is on screen, and what IS on screen is
    /// exactly the order a drop would produce — the preview is the result rather
    /// than the result plus a leftover.
    ///
    /// Returns `visible` unchanged (every entry a `.row`) when nothing is
    /// dragging, or when ``RowReorderFeedback/live`` is moving the data instead,
    /// or when a `.dimmed` drag has nowhere to drop — see ``reorderRemovedRow``
    /// for why those three are one question.
    ///
    /// Shared by `List` and `Table`: the index arithmetic is the same for both,
    /// and it is subtle enough (every index here is CLOSED-UP, which is also what
    /// `move(from:to:)` produces) that having it twice is how the two drift.
    func reorderDrawnRows(_ visible: some Sequence<Int>) -> [DrawnRow] {
        let removed = reorderRemovedRows
        guard !removed.isEmpty else {
            // No reorder — but a drag from another list may be hovering, and it
            // opens the same gap for the same reason.
            let rows = Array(visible)
            guard let slot = externalDropSlot else { return rows.map { .row($0) } }
            var drawn = rows.map { DrawnRow.row($0) }
            let at = rows.firstIndex { $0 >= slot } ?? drawn.count
            drawn.insert(.slot, at: min(at, drawn.count))
            return drawn
        }
        // EVERY held row leaves — a multi-row drag carries them all — but only
        // ONE slot opens: they land as a single block, so a gap per row would
        // promise something the drop does not do.
        let rows = visible.filter { !removed.contains($0) }
        guard let placeholder = reorderPlaceholder else { return rows.map { .row($0) } }
        // The slot goes at closed-up position `placeholder.slot` — before the
        // first surviving row that already numbers at or past it.
        let slot =
            rows.firstIndex { reorderClosedUpIndex($0, removed: removed) >= placeholder.slot }
            ?? rows.count
        var drawn = rows.map { DrawnRow.row($0) }
        drawn.insert(.slot, at: slot)
        return drawn
    }

    /// Re-reads the drop target from the bands just published, while edge
    /// auto-scroll is driving THIS list.
    ///
    /// The target is a DRAWN position, and it is otherwise only computed in the
    /// `.dragged` branch of the mouse handler — but auto-scroll is by
    /// definition the case where the pointer holds still and no drag event
    /// arrives. Left stale, the slot walks to the top edge as its index scrolls
    /// off, and the eventual drop lands a place out.
    private func retargetForAutoScroll() {
        guard isAutoScrolling, reorder != nil, let y = lastReorderContentY else { return }
        dragReorder(toContentY: y)
    }

    /// Whether this data row carries the keyboard cursor *right now*.
    ///
    /// While a row is out of the list — the slot feedback modes — the cursor
    /// belongs to the SLOT, which is where the row visually is. `focusedIndex`
    /// is meanwhile parked on a neighbour of the slot on purpose (see
    /// ``moveHeldRow(to:)``): the scroll-follow machinery reasons in data
    /// indices and a slot has no data behind it. Highlighting straight from
    /// `focusedIndex` is what put the cursor one row BELOW the row being moved.
    func isCursorRow(_ index: Int) -> Bool {
        reorderRemovedRow == nil && isFocused(at: index)
    }

    /// Whether the control is steering a row that has left the list, so the
    /// slot should read as "this is in your hand" rather than as a hole.
    var isHoldingRow: Bool { reorderRemovedRow != nil }

        /// The sentinel `rowIndex` the reorder drop slot is published with: it has
    /// no data behind it, so it cannot carry a real offset.
    static var reorderSlotRowIndex: Int { -1 }

    /// One drawn entry's extent on screen, as a view reports it.
    struct DrawnBand {
        /// What occupies a drawn line, for band purposes.
        enum Content {
            /// A real, selectable data row.
            case row(Int)
            /// The reorder drop slot: a drop target with no data behind it.
            case slot
            /// Chrome that shares the row area — a `List`'s section header. Not
            /// selectable, and not somewhere a row can land.
            case chrome(rowIndex: Int)
        }

        /// What is drawn there.
        var entry: Content
        /// Its first line, counted from the first CONTENT line of the interior.
        /// Must already include the "N more above" indicator's offset and any
        /// overscroll slide: this is the space the mouse handler works in.
        var yStart: Int
        /// How many lines it occupies (a clipped row counts what is shown).
        var height: Int
    }

    /// Hands this frame's drawn row geometry to the drag, applying the
    /// drop-index rules once for both `List` and `Table`.
    ///
    /// It has to come from the handler rather than a mouse closure's captured
    /// copy: a ``RowReorderFeedback/live`` drag reorders the rows underneath the
    /// cursor, so press-frame bands would describe an order that no longer
    /// exists (and a wheel tick can scroll them out from under any mode).
    func publishRowBands(_ bands: [DrawnBand]) {
        defer { retargetForAutoScroll() }
        let placeholder = reorderPlaceholder
        visibleRowBands = bands.map { band in
            switch band.entry {
            case .row(let rowIndex):
                // A real row means "put it where this row is" — as the row is
                // DRAWN, not as its data is numbered. Mid-drag the list has
                // closed up behind the dragged row and opened a slot elsewhere,
                // so the two differ, and it is the drawn position the pointer is
                // actually resting on.
                return RowBand(
                    rowIndex: rowIndex, yStart: band.yStart, height: band.height,
                    isContent: true, dropIndex: reorderDrawnPosition(of: rowIndex))
            case .slot:
                // The gap holds the target it already has. It is the line the
                // pointer rests on after every step, so reading it as "off the
                // rows" is what made a `.cursor` drag cancel its own gap.
                return RowBand(
                    rowIndex: Self.reorderSlotRowIndex, yStart: band.yStart,
                    height: band.height, isContent: false,
                    // `externalDropSlot` for a drag from elsewhere: that slot is
                    // where the pointer rests after every step too, and reading
                    // it as "off the rows" sent the gap to the end of the list
                    // and back on alternate mouse reports.
                    dropIndex: placeholder?.slot ?? externalDropSlot)
            case .chrome(let rowIndex):
                return RowBand(
                    rowIndex: rowIndex, yStart: band.yStart, height: band.height,
                    isContent: false, dropIndex: nil)
            }
        }
    }

    // MARK: - The drag

    /// Whether a reorder drag is in flight *and* has moved — the test that
    /// separates a reorder from a plain click.
    var isReordering: Bool { reorder?.active == true }

    /// The row a non-`.live` drag has hold of. `nil` when nothing is dragging
    /// or when `.live` is moving the data instead.
    ///
    /// The row LEAVES its place for the duration of the drag — the list closes
    /// up behind it, so what is on screen is the order a drop would produce.
    /// It reappears only at the drop slot, and only in `.dimmed`.
    var reorderSource: Int? {
        guard effectiveReorderFeedback != .live, let reorder, reorder.active else { return nil }
        return reorder.currentOffset
    }

    /// The row a ``RowReorderFeedback/cursor`` drag is carrying on the pointer,
    /// or `nil` when no such drag is in flight. `_ListCore` hands this row's
    /// buffer to the drag session, which floats it at the cursor.
    ///
    /// Held for the WHOLE drag, including while the cursor is off the rows and
    /// there is no drop slot: the row is in the user's hand either way, and the
    /// absent slot is what says releasing here would put it back.
    var reorderFloatingRow: Int? {
        guard effectiveReorderFeedback == .cursor else { return nil }
        return reorderSource
    }

    /// EVERY row a ``RowReorderFeedback/cursor`` drag is carrying, in data
    /// order — stacked, they are what the float shows and what the gap makes
    /// room for. One row is the ordinary case; a multi-row gesture carries the
    /// whole selection, and showing only the grabbed one of them looked exactly
    /// like the rest had been deleted.
    var reorderFloatingRows: [Int] {
        guard effectiveReorderFeedback == .cursor else { return [] }
        return Array(reorderRemovedRows)
    }

    /// The rows in hand that sit above the one the pointer grabbed — the part
    /// of the floating stack drawn before it, and so the distance the grab
    /// point moves down within the stack. Without it a multi-row drag hangs
    /// from its first row however far down the block you took hold.
    var reorderHeldRowsAboveGrab: [Int] {
        guard let reorder else { return [] }
        return reorder.held.filter { $0 < reorder.grabbedOffset }
    }

    /// Where the dragged row would land — what `.dimmed` and `.cursor` open a
    /// slot for (a faint copy of the row, and an empty gap, respectively).
    ///
    /// The slot is a CLOSED-UP index: the row's prospective final position, with
    /// the source already taken out. See ``reorderClosedUpIndex(_:source:)``.
    ///
    /// `nil` when nothing is dragging, when `.live` is moving the data instead,
    /// or when the cursor has left the rows (`.cursor` drops its gap then, so
    /// the list reads as "let go here and nothing moves").
    ///
    /// The row's OWN place is a legitimate destination, and the preview shows it
    /// like any other: putting the row back where it came from is a thing a user
    /// may want to do, and mid-drag it is the only way to change their mind. It
    /// was suppressed once, on the grounds that a copy of the row drawn against
    /// itself made the list look like it had gained a duplicate — true while the
    /// source row stayed put, and untrue since it started LEAVING its place for
    /// the duration of the drag. Suppressing it now just makes the preview stop
    /// tracking the cursor over one row for no reason the user can see.
    var reorderPlaceholder: (source: Int, slot: Int)? {
        guard let source = reorderSource, let slot = reorder?.targetOffset else { return nil }
        return (source, slot)
    }

    /// Picks up the row at `offset` for a possible reorder. Not yet a
    /// reorder — a press released without movement is a click.
    ///
    /// The row also takes the keyboard cursor, so the user can see what they
    /// have hold of before moving anything.
    func beginReorder(grabbing offset: Int) {
        reorder = RowReorder(grabbedOffset: offset, held: heldRows(grabbing: offset), active: false)
        focusedIndex = offset
    }

    /// The rows a gesture starting at `offset` picks up: the whole selection
    /// when `offset` is part of one, otherwise just that row.
    ///
    /// macOS's rule, and the one that makes a multi-row drag discoverable —
    /// grab ANY selected row and they all come. Dragging an UNselected row
    /// takes only it, which is what makes it possible to move a row out of a
    /// selection without clearing the selection first.
    private func heldRows(grabbing offset: Int) -> IndexSet {
        guard selectionMode == .multi, isSelected(at: offset) else {
            return IndexSet(integer: offset)
        }
        let selected = IndexSet((0..<itemCount).filter { isSelected(at: $0) })
        return selected.contains(offset) ? selected : IndexSet(integer: offset)
    }

    /// How many rows the drag has hold of. One outside a multi-row gesture.
    var heldRowCount: Int { reorder?.held.count ?? 0 }

    /// Tracks a drag to `contentY` (`nil` when the cursor is off the rows —
    /// over the border, a header, or past the last row — which holds the
    /// current target rather than snapping anywhere).
    ///
    /// Under ``RowReorderFeedback/live`` this moves the row *now*, one `onMove`
    /// per slot crossed, so the list itself is the preview. The other modes
    /// only move the cursor to mark where the drop would land.
    func dragReorder(toContentY contentY: Int?) {
        guard var reorder, onMove != nil else { return }
        // Kept so the target can be recomputed when the rows move under a
        // motionless pointer — see `publishRowBands`.
        lastReorderContentY = contentY
        // Any movement at all makes this a reorder rather than a click, even
        // when the cursor hasn't yet reached another row.
        reorder.active = true
        self.reorder = reorder

        guard let contentY, let target = dropTarget(atContentY: contentY) else {
            // Off the rows. `.cursor` forgets its slot — the gap disappears and
            // releasing there is a cancel — while the other modes hold the last
            // one, since they have nothing that says "nowhere".
            if effectiveReorderFeedback == .cursor {
                reorder.targetOffset = nil
                self.reorder = reorder
            }
            return
        }
        // `.live` moves the data NOW, one `onMove` per slot crossed — the whole
        // block of held rows, not just the one under the pointer. Pointing at a
        // row already in hand is not a crossing.
        if effectiveReorderFeedback == .live, !reorder.held.contains(target) {
            let landed = move(reorder.held, to: liveSlot(forTarget: target, held: reorder.held))
            // The block is contiguous from here on, wherever it started: after
            // the first move the disjoint set no longer exists, and every later
            // step has to name the rows where they NOW are.
            reorder.held = IndexSet(integersIn: landed..<(landed + reorder.held.count))
            reorder.currentOffset = landed + reorder.primaryRank
        }
        reorder.targetOffset = target
        self.reorder = reorder
        // The keyboard cursor follows the row the pointer is actually OVER, by
        // data offset. Over the gap there is no such row, so it stays put —
        // moving it to the drop target would light up a neighbour instead.
        if let row = contentRowIndex(atContentY: contentY) { focusedIndex = row }
    }

    /// The closed-up slot a `.live` step should move the held block to, given
    /// the DATA index of the row the pointer is over.
    ///
    /// Dragging down lands the block after that row, dragging up lands it
    /// before — the asymmetry a single-row drag has always had, because the row
    /// under the pointer is the one you are displacing. For one row in hand
    /// this is exactly the old `move(from:to: target)`.
    private func liveSlot(forTarget target: Int, held: IndexSet) -> Int {
        let closedUp = reorderClosedUpIndex(target, removed: held)
        let downward = held.min().map { target > $0 } ?? false
        return closedUp + (downward ? 1 : 0)
    }

    /// Commits a drop at `contentY`, and reports whether this gesture was a
    /// reorder at all — `false` means the caller should treat it as a click.
    ///
    /// ``RowReorderFeedback/live`` has already moved the row; the others move
    /// it exactly once, here.
    @discardableResult
    func dropReorder(atContentY contentY: Int?) -> Bool {
        guard let reorder, reorder.active, onMove != nil else {
            self.reorder = nil
            return false
        }
        // BEFORE the teardown below: `effectiveReorderFeedback` is derived from
        // the state this is about to clear, so reading it afterwards answers a
        // different question than the drag was answering all along.
        let feedback = effectiveReorderFeedback
        self.reorder = nil

        if feedback == .live {
            focusedIndex = clampedRowIndex(reorder.currentOffset)
            return true
        }
        // The SLOT first, and the release position only as a fallback: what is
        // on screen is the promise, and the two part company whenever the rows
        // moved without the pointer — a wheel tick, a mid-drag Page key, an
        // auto-scroll. The band under the release point then names a different
        // place than the gap the user is looking at, and the drop belongs to
        // the gap.
        //
        // Released off the rows, `.cursor` has no slot and has promised the drop
        // would do nothing — keep that promise. `.dimmed` holds its last slot,
        // so it commits to it.
        guard let target = reorder.targetOffset
            ?? contentY.flatMap({ dropTarget(atContentY: $0) })
        else {
            focusedIndex = clampedRowIndex(reorder.grabbedOffset)
            return true
        }
        focusedIndex = clampedRowIndex(
            move(reorder.held, to: target) + reorder.primaryRank)
        return true
    }

    /// Abandons a MOUSE drag: the rows go back where they were picked up and
    /// the floating preview walks home rather than vanishing under the pointer.
    ///
    /// Deliberately bound to NO key. Escape was the obvious candidate and is
    /// spoken for: a drag has to be carriable across the app — pick a row up on
    /// one page, navigate, drop it on another — and that requires the
    /// navigation keys to keep navigating while something is in hand. Releasing
    /// over nothing is the cancel, as it is on macOS. Kept whole (and covered
    /// by tests) for the day a chord is chosen for it.
    func cancelMouseDragReorder() {
        cancelReorder()
        // The button is still down, so a release is still coming: without the
        // latch it falls into the click path and selects whatever row the
        // pointer happens to be over.
        reorderCancelled = true
        dragSession?.cancelReturningToOrigin()
    }

    /// Drops any in-flight reorder without moving anything.
    func cancelReorder() {
        // `.live` has been moving the data at every step of the drag, so
        // clearing the state is not a cancel — the row is wherever the pointer
        // last left it. Put it back where it was picked up. (The slot modes
        // move nothing until the drop, so for them there is nothing to undo.)
        if let reorder, reorder.currentOffset != reorder.grabbedOffset {
            // The whole block goes back, to the slot the grabbed row came from.
            // For a selection that was DISJOINT when it was picked up that is a
            // consolidation rather than an undo — the first live step already
            // gathered it, and one `onMove` cannot scatter it again.
            move(reorder.held, to: reorder.grabbedOffset)
            focusedIndex = reorder.grabbedOffset
        }
        reorder = nil
        lastReorderContentY = nil
    }

    // MARK: - Moving

    /// Moves the row at `from` onto `target` through ``onMove`` and returns
    /// where it now sits. A drop onto itself is skipped, so an aimless drag
    /// doesn't churn the app's state.
    @discardableResult
    func move(from: Int, to target: Int) -> Int {
        move(IndexSet(integer: from), to: target)
    }

    /// Moves every row in `held` to closed-up position `target`, in ONE
    /// `onMove` — which is all it takes, because that is `(IndexSet, Int)` and
    /// `move(fromOffsets:toOffset:)` already implements the disjoint case:
    /// rows 2, 4 and 5 arrive as one block, in that order.
    ///
    /// Returns where the block starts, which for a single row is where it
    /// landed.
    @discardableResult
    func move(_ held: IndexSet, to target: Int) -> Int {
        guard let onMove, !held.isEmpty else { return target }
        let destination = reorderInsertionOffset(forSlot: target, removed: held)
        onMove(held, destination)
        // Where the block actually starts now — which is `target` except when
        // the slot was past the end and the insertion clamped, and a `.live`
        // drag that believed the clamped number would move the block again from
        // a place it is not.
        return reorderClosedUpIndex(destination, removed: held)
    }

    /// `index` clamped to the rows that exist (an empty list yields 0).
    private func clampedRowIndex(_ index: Int) -> Int {
        min(max(0, index), max(0, itemCount - 1))
    }
}
