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
    /// a section header/footer, a line no row occupies, or a list that hasn't
    /// published its geometry yet.
    ///
    /// `contentY` is in the same space as ``visibleRowBands``: lines from the
    /// first content line of the list's interior.
    func contentRowIndex(atContentY contentY: Int) -> Int? {
        visibleRowBands.first {
            $0.isContent && contentY >= $0.yStart && contentY < $0.yStart + $0.height
        }?.rowIndex
    }

    // MARK: - The drag

    /// Whether a reorder drag is in flight *and* has moved — the test that
    /// separates a reorder from a plain click.
    var isReordering: Bool { reorder?.active == true }

    /// The row a `.cursor` drag is carrying on the pointer, or `nil` when no
    /// such drag is in flight. `_ListCore` draws the floating copy from this
    /// row's buffer.
    var reorderFloatingRow: Int? {
        guard reorderFeedback == .cursor, let reorder, reorder.active else { return nil }
        return reorder.currentOffset
    }

    /// The row a non-`.live` drag has hold of — the one drawn dim in its own
    /// place, whether or not it currently has anywhere else to land. `nil` when
    /// nothing is dragging or when `.live` is moving the data instead.
    var reorderSource: Int? {
        guard reorderFeedback != .live, let reorder, reorder.active else { return nil }
        return reorder.currentOffset
    }

    /// Where the dragged row would land — what `.ghost` and `.cursor` draw in
    /// the list itself (a full-brightness copy, and a gap, respectively).
    ///
    /// `nil` when nothing is dragging, when `.live` is moving the data instead,
    /// when the cursor has left the rows (`.cursor` drops its gap then, so the
    /// list reads as "let go here and nothing moves"), or when the row would
    /// land exactly where it already is. That last case is the same statement
    /// as the others: releasing on the row you picked up moves nothing, so
    /// there is nothing to preview — and drawing a copy of the row against
    /// itself only made the list look like it had gained a duplicate.
    var reorderPlaceholder: (source: Int, slot: Int)? {
        guard let source = reorderSource, let slot = reorder?.targetOffset, slot != source
        else { return nil }
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

        guard let contentY, let target = contentRowIndex(atContentY: contentY) else {
            // Off the rows. `.cursor` forgets its slot — the gap disappears and
            // releasing there is a cancel — while the other modes hold the last
            // one, since they have nothing that says "nowhere".
            if reorderFeedback == .cursor {
                reorder.targetOffset = nil
                self.reorder = reorder
            }
            return
        }
        if reorderFeedback == .live, target != reorder.currentOffset {
            move(from: reorder.currentOffset, to: target)
            reorder.currentOffset = target
        }
        reorder.targetOffset = target
        self.reorder = reorder
        focusedIndex = target
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

        if reorderFeedback == .live {
            focusedIndex = clampedRowIndex(reorder.currentOffset)
            return true
        }
        // Released off the rows. `.cursor` shows no drop slot there, so it has
        // promised the drop would do nothing — keep that promise. `.ghost` still
        // shows one (it holds the last), so it commits to it.
        guard let target = contentY.flatMap({ contentRowIndex(atContentY: $0) })
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
    private func move(from: Int, to target: Int) -> Int {
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
