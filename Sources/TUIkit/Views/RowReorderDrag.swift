//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RowReorderDrag.swift
//
//  The two small pieces a drag-to-reorder gesture needs beyond the state machine
//  in `ItemListHandler+Reorder`. `List` and `Table` both run that machine, so
//  these live here rather than privately in either one.
//
//  Created by Wade Tregaskis
//  License: MIT

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
/// for a drop. The view places the row itself, on release.
struct RowReorderPayload {}
