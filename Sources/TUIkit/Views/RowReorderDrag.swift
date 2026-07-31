//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RowReorderDrag.swift
//
//  The vocabulary a drag-to-reorder gesture needs outside the state machine in
//  `ItemListHandler+Reorder`: the gesture's own state, the protocol
//  `DragAndDropSession` resolves it through, and two small helper types. `List`
//  and `Table` both run that machine, so these live here rather than privately
//  in either one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Where inside the grabbed row a reorder drag was pressed, in the row's own
/// cells — the cell a ``RowReorderFeedback/cursor`` drag keeps under the pointer.
///
/// A class because the press-captured mouse closure fills it in on the press and
/// reads it back on the drags that follow: the closure IS the gesture, and it
/// outlives the render that made it.
@MainActor
final class RowReorderGrabPoint {
    var x = 0
    var y = 0
}

/// The payload a ``RowReorderFeedback/cursor`` drag carries.
///
/// Internal and empty on purpose: it exists only to satisfy
/// ``DragAndDropSession``, and no client's `dropDestination` can name — and
/// therefore accept — it, so floating a row over the app can never be mistaken
/// for a drop. The row is placed by the control it belongs to, on release.
struct RowReorderPayload {}

/// One in-flight row-reorder drag: which rows are in hand, and where they are.
///
/// Deliberately not nested inside `ItemListHandler`, which is generic over its
/// selection value: this is the state ``DragAndDropSession`` hands from the
/// control that started a gesture to the one that finishes it, and nothing in
/// it — offsets and lines — needs that parameter.
struct RowReorder: Equatable {
    /// The data offset of the row picked up on press.
    var grabbedOffset: Int
    /// Where that row sits *now*. Only ``RowReorderFeedback/live`` moves it
    /// mid-drag; the other modes leave the data alone until the drop, so
    /// this stays equal to ``grabbedOffset`` throughout.
    var currentOffset: Int
    /// Whether the cursor has actually moved since the press — a plain
    /// press/release with no motion is a click (selection), not a reorder.
    var active: Bool

    /// Where the row would land if released now, or `nil` when the cursor is
    /// off the rows entirely. `.dimmed` and `.cursor` show this slot — as a
    /// copy of the row and as a gap respectively — and `nil` is what makes a
    /// drag off the list read as "release here and nothing moves".
    var targetOffset: Int?

    /// Every row in hand, by data offset — the whole selection when the
    /// grabbed row was part of one, otherwise just that row.
    ///
    /// Disjoint sets are allowed and stay disjoint until the drop: rows 2,
    /// 4 and 5 travel as three rows and land as one block. Consolidating
    /// earlier would be a data change the user has not asked for yet, and
    /// could not be undone by a cancel (one `onMove` cannot scatter a block
    /// back to disjoint places).
    var held: IndexSet

    /// Where `grabbedOffset` sits within ``held``, so the row the pointer
    /// took hold of stays the one it is holding after the drop.
    ///
    /// Stored, not derived: a `.live` block move rewrites `held` at every
    /// step, and re-deriving the rank against a `grabbedOffset` that now
    /// names a different row would drift.
    let primaryRank: Int

    init(grabbedOffset: Int, held: IndexSet, active: Bool) {
        let held = held.isEmpty ? IndexSet(integer: grabbedOffset) : held
        self.grabbedOffset = grabbedOffset
        self.currentOffset = grabbedOffset
        self.held = held
        self.active = active
        self.primaryRank =
            held.contains(grabbedOffset) ? held.count(where: { $0 < grabbedOffset }) : 0
    }
}

/// A control that can hold a row reorder — ``List`` and ``Table``, through
/// `ItemListHandler`.
///
/// Non-generic deliberately, on the same terms as ``ScrollableOffsetState``:
/// ``DragAndDropSession`` resolves a gesture against whichever control is on
/// screen at the moment of the event, and `ItemListHandler` is generic over its
/// selection value. Everything asked here is about rows — offsets and lines —
/// so none of it needs that parameter.
protocol RowReorderHosting: AnyObject {
    /// The gesture in flight, or `nil`. Settable because a reorder outlives the
    /// control that started it: see ``DragAndDropSession/registerReorderHost(_:)``.
    var reorder: RowReorder? { get set }

    /// Whether the gesture was started from the keyboard rather than the mouse.
    var isKeyboardMove: Bool { get set }

    /// Whether a release has already been answered by a cancel, so the release
    /// that follows is the tail of a cancelled gesture rather than a click.
    var reorderCancelled: Bool { get set }

    /// Whether a gesture has actually become a reorder (the pointer moved).
    var isReordering: Bool { get }

    /// The rows drawn at the cursor rather than in place, by data offset.
    var reorderFloatingRows: [Int] { get }

    /// The held rows that sat above the one the pointer took hold of.
    var reorderHeldRowsAboveGrab: [Int] { get }

    /// Tracks the drag to a position in this control's content-line space.
    func dragReorder(toContentY contentY: Int?)

    /// Commits the drop, reporting whether this gesture was a reorder at all.
    @discardableResult
    func dropReorder(atContentY contentY: Int?) -> Bool

    /// Whether a release at `contentY` would put the rows anywhere.
    func reorderLandsNowhere(atContentY contentY: Int?) -> Bool

    /// Drops the gesture without moving anything.
    func cancelReorder()
}
