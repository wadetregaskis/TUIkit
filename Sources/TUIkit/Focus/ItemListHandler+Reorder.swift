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
    func reorderClosedUpIndex(_ index: Int, source: Int) -> Int {
        index - (index > source ? 1 : 0)
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
        guard let source = reorderRemovedRow else { return index }
        let closedUp = reorderClosedUpIndex(index, source: source)
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
        guard reorderFeedback == .cursor else { return reorderFeedback }
        return (isKeyboardMove || !canFloatDraggedRow) ? .dimmed : .cursor
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
        reorder?.targetOffset = focusedIndex
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
            focusedIndex = clampedRowIndex(move(from: reorder.grabbedOffset, to: target))
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
    func handleRowMoveKey(_ event: KeyEvent) -> Bool? {
        if isKeyboardMove, let handled = handleKeyboardMoveKey(event) { return handled }
        // Chords, so they work in either selection mode.
        switch shortcuts.action(for: event) {
        case .pickUpRow: return beginKeyboardMove() ? true : nil
        case .moveRowUp: return nudgeFocusedRow(by: -1) ? true : nil
        case .moveRowDown: return nudgeFocusedRow(by: 1) ? true : nil
        default: return nil
        }
    }

    /// Moves the focused row one place, with no mode to enter or leave — the
    /// single-step shortcut that is most of what reordering ever is.
    ///
    /// Each press is one `onMove`, so it is undoable and repeatable in the
    /// app's own terms, and the cursor rides along with the row.
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
        switch shortcuts.action(for: event) {
        case .placeRow, .pickUpRow:
            placeHeldRow()
            return true
        case .cancelMove:
            cancelKeyboardMove()
            return true
        case .moveRowUp:
            moveHeldRow(by: -1)
            return true
        case .moveRowDown:
            moveHeldRow(by: 1)
            return true
        case .selectAll, .extendSelection, nil:
            break
        }
        let page = max(1, viewportHeight - 1)
        switch event.key {
        case .up: moveHeldRow(by: -1)
        case .down: moveHeldRow(by: 1)
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
        guard let source = reorderRemovedRow else { return visible.map { .row($0) } }
        let rows = visible.filter { $0 != source }
        guard let placeholder = reorderPlaceholder else { return rows.map { .row($0) } }
        // The slot goes at closed-up position `placeholder.slot` — before the
        // first surviving row that already numbers at or past it.
        let slot =
            rows.firstIndex { reorderClosedUpIndex($0, source: source) >= placeholder.slot }
            ?? rows.count
        var drawn = rows.map { DrawnRow.row($0) }
        drawn.insert(.slot, at: slot)
        return drawn
    }

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
                    height: band.height, isContent: false, dropIndex: placeholder?.slot)
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
        reorder = RowReorder(grabbedOffset: offset, active: false)
        focusedIndex = offset
    }

    /// Tracks a drag to `contentY` (`nil` when the cursor is off the rows —
    /// over the border, a header, or past the last row — which holds the
    /// current target rather than snapping anywhere).
    ///
    /// Under ``RowReorderFeedback/live`` this moves the row *now*, one `onMove`
    /// per slot crossed, so the list itself is the preview. The other modes
    /// only move the cursor to mark where the drop would land.
    func dragReorder(toContentY contentY: Int?) {
        guard var reorder, onMove != nil else { return }
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
        if effectiveReorderFeedback == .live, target != reorder.currentOffset {
            move(from: reorder.currentOffset, to: target)
            reorder.currentOffset = target
        }
        reorder.targetOffset = target
        self.reorder = reorder
        // The keyboard cursor follows the row the pointer is actually OVER, by
        // data offset. Over the gap there is no such row, so it stays put —
        // moving it to the drop target would light up a neighbour instead.
        if let row = contentRowIndex(atContentY: contentY) { focusedIndex = row }
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
        self.reorder = nil

        if effectiveReorderFeedback == .live {
            focusedIndex = clampedRowIndex(reorder.currentOffset)
            return true
        }
        // Released off the rows. `.cursor` shows no drop slot there, so it has
        // promised the drop would do nothing — keep that promise. `.dimmed` still
        // shows one (it holds the last), so it commits to it.
        guard let target = contentY.flatMap({ dropTarget(atContentY: $0) })
            ?? reorder.targetOffset
        else {
            focusedIndex = clampedRowIndex(reorder.grabbedOffset)
            return true
        }
        focusedIndex = clampedRowIndex(move(from: reorder.grabbedOffset, to: target))
        return true
    }

    /// Drops any in-flight reorder without moving anything.
    func cancelReorder() {
        reorder = nil
    }

    // MARK: - Moving

    /// Moves the row at `from` onto `target` through ``onMove`` and returns
    /// where it now sits. A drop onto itself is skipped, so an aimless drag
    /// doesn't churn the app's state.
    @discardableResult
    func move(from: Int, to target: Int) -> Int {
        guard let onMove, from != target else { return from }
        // `toOffset` is measured against the collection BEFORE the move, so
        // moving down inserts past the target and moving up inserts before it
        // — exactly what SwiftUI's `move(fromOffsets:toOffset:)` expects.
        let destination = from < target ? target + 1 : target
        onMove(IndexSet(integer: from), destination)
        return destination > from ? destination - 1 : destination
    }

    /// `index` clamped to the rows that exist (an empty list yields 0).
    private func clampedRowIndex(_ index: Int) -> Int {
        min(max(0, index), max(0, itemCount - 1))
    }
}
