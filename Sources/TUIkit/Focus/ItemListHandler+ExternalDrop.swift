//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+ExternalDrop.swift
//
//  Where a drag from ANOTHER view would land in this list, and how that answer
//  is kept true while the rows move underneath it.
//
//  The pointer's position is only reported when it MOVES, and edge auto-scroll
//  is by definition the case where it holds still: the rows stream past a
//  motionless cursor. So the line the pointer last named is remembered, and the
//  question is asked again from it every frame the rows are republished — the
//  same shape, and the same reason, as the reorder retarget next door.
//
//  Created by Wade Tregaskis
//  License: MIT

extension ItemListHandler {
    /// Points the incoming-drop slot at `contentY`, and remembers the line.
    ///
    /// The rule is one method rather than three lines at each of the two call
    /// sites (a `List`'s and a `Table`'s drop destination) because it has to
    /// stay the same rule in both: past the last row the drop appends, the slot
    /// is clamped so a list that shrank under the pointer cannot strand it, and
    /// the line is kept so ``publishRowBands(_:)`` can ask the question again
    /// against the next frame's rows.
    func hoverExternalDrop(atContentY contentY: Int) {
        // A NEW pointer position is a new situation: the auto-scroll retarget
        // gets one run against it, whatever the rows have done since.
        //
        // The SAME position repeated is not, and the difference is the whole
        // reason this is a condition rather than an assignment. A held pointer
        // keeps reporting — a trackpad reports many times a second without
        // moving a cell — and re-arming the retarget on every report let its
        // answer and this one alternate forever: on a list whose rows exactly
        // fill it, this method reads the gap's own band and keeps it where the
        // pointer is, while the retarget's past-the-rows rule pulls it onto the
        // last row. Two defensible answers, one per frame, and the gap flipped
        // between them for as long as the drag was held there.
        if lastExternalDropContentY != contentY { externalDropResolvedOffset = nil }
        lastExternalDropContentY = contentY
        // Past the rows, a pointer that is simply resting there means "append"
        // — the conventional answer, and the one a short list has always given.
        // Only the auto-scroll retarget below reads it differently, because
        // there the rows are moving and "the end of the data" is an answer about
        // somewhere the cursor is not.
        setExternalDropSlot(dropTarget(atContentY: contentY) ?? itemCount)
    }

    /// Points the slot at `contentY` WITHOUT remembering the line.
    ///
    /// Split from ``hoverExternalDrop(atContentY:)`` because the auto-scroll
    /// retarget calls it every frame with the SAME remembered line: storing
    /// what it resolves would mean storing a derivative of the pointer's
    /// position, and the true position is gone after the first tick. The same
    /// split, for the same reason, as `resolveReorderTarget` versus
    /// `dragReorder`.
    ///
    /// Past the rows drawn, the drop lands on the nearest one rather than at
    /// the end of the data: while the list scrolls under a motionless pointer
    /// that is the whole question, and "append" is an answer about a row
    /// nowhere near the cursor.
    ///
    /// Onto the last row rather than after it, which looks like the off-by-one
    /// and is not. The gap occupies a line, so where it sits decides which row
    /// is drawn last; resolving "after the last row drawn" therefore moves the
    /// row that the next frame's answer is measured from, and the gap flips
    /// above and below the bottom row on alternate frames. Landing ON it is a
    /// fixed point, and puts the gap at the viewport's leading edge — the same
    /// place a reorder's slot rides, for the same reason.
    func retargetExternalDrop(atContentY contentY: Int) {
        // Answered for THIS offset. The caller will not ask again until the
        // rows have moved — see ``ItemListHandler/externalDropResolvedOffset``.
        externalDropResolvedOffset = scrollOffset
        let rows = visibleRowBands.compactMap { band -> (band: RowBand, index: Int)? in
            guard band.isContent, let index = band.dropIndex else { return nil }
            return (band, index)
        }
        guard let first = rows.first, let last = rows.last else {
            setExternalDropSlot(dropTarget(atContentY: contentY) ?? itemCount)
            return
        }
        if contentY < first.band.yStart {
            setExternalDropSlot(first.index)
        } else if contentY >= last.band.yStart + max(1, last.band.height) {
            setExternalDropSlot(last.index)
        } else {
            setExternalDropSlot(dropTarget(atContentY: contentY) ?? itemCount)
        }
    }

    /// Consumes the slot for a drop that is happening now: the clamped index
    /// to insert at, with the hover state cleared.
    ///
    /// The clamp is here and not only in ``setExternalDropSlot(_:)`` because
    /// the two are answers to different questions. That one keeps a *hover*
    /// truthful as rows come and go; this one is read at the moment of
    /// insertion, and between the last hover and the drop the data can shrink
    /// with no pointer event to re-clamp on — a filter narrowing, a sibling
    /// view taking the item, the drag's own source removing it. The documented
    /// use of this index is `insert(contentsOf:at:)`, which traps rather than
    /// clamping, so the read side has to be sure on its own.
    func takeExternalDropSlot() -> Int {
        let slot = externalDropSlot ?? itemCount
        externalDropSlot = nil
        return min(max(0, slot), itemCount)
    }

    /// The slot, clamped to the list's own bounds — a list that shrank under
    /// the pointer must not strand it past the end.
    private func setExternalDropSlot(_ slot: Int) {
        externalDropSlot = min(max(0, slot), itemCount)
    }
}
