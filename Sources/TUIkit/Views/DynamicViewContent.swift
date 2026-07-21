//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DynamicViewContent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Dynamic row actions

/// The row-mutation actions a `ForEach` carries so an enclosing editable
/// `List` can discover and wire them — the internal seam behind SwiftUI's
/// `DynamicViewContent` (whose `onMove`/`onDelete` this mirrors).
///
/// The list looks its content up as one of these; a `nil` action means that
/// gesture is unavailable (a delete key does nothing, a row can't be dragged).
@MainActor
protocol DynamicViewContentActions {
    /// The `.onMove(perform:)` reorder action: `(source offsets, destination
    /// offset)`, both measured from the data's start. `nil` if not reorderable.
    var moveAction: ((IndexSet, Int) -> Void)? { get }

    /// The `.onDelete(perform:)` action: the offsets to delete. `nil` if the
    /// rows can't be deleted.
    var deleteAction: ((IndexSet) -> Void)? { get }
}

extension ForEach: DynamicViewContentActions {
    var moveAction: ((IndexSet, Int) -> Void)? { onMoveAction }
    var deleteAction: ((IndexSet) -> Void)? { onDeleteAction }
}

// MARK: - ForEach modifiers

extension ForEach {
    /// Sets the deletion action for the dynamic view's rows — mirrors SwiftUI's
    /// `onDelete(perform:)`.
    ///
    /// Inside an editable `List`, pressing **Delete** (or Backspace) on the
    /// focused row calls this action with that row's offset; the closure mutates
    /// the backing collection (typically via ``remove(atOffsets:)``). Passing
    /// `nil` makes the rows non-deletable again.
    ///
    /// ```swift
    /// List {
    ///     ForEach(items, id: \.self) { Text($0) }
    ///         .onDelete { items.remove(atOffsets: $0) }
    /// }
    /// ```
    ///
    /// - Note: SwiftUI returns `some DynamicViewContent`; TUIkit returns the
    ///   concrete `ForEach` (it has no `DynamicViewContent` protocol), which
    ///   still chains with ``onMove(perform:)`` since both live on `ForEach`.
    ///
    /// - Parameter action: The delete action, or `nil` to disable deletion.
    /// - Returns: A `ForEach` that reports the delete action to its `List`.
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> ForEach {
        var copy = self
        copy.onDeleteAction = action
        return copy
    }

    /// Sets the move (reorder) action for the dynamic view's rows — mirrors
    /// SwiftUI's `onMove(perform:)`.
    ///
    /// Inside an editable `List`, dragging a row with the mouse reorders it,
    /// committing through this action with the dragged row's source offset and
    /// the destination offset; the closure mutates the backing collection
    /// (typically via ``move(fromOffsets:toOffset:)``).
    ///
    /// ```swift
    /// List {
    ///     ForEach(items, id: \.self) { Text($0) }
    ///         .onMove { items.move(fromOffsets: $0, toOffset: $1) }
    /// }
    /// ```
    ///
    /// - Note: As with ``onDelete(perform:)``, TUIkit returns the concrete
    ///   `ForEach` rather than SwiftUI's `some DynamicViewContent`.
    ///
    /// - Parameter action: The reorder action `(source, destination)`.
    /// - Returns: A `ForEach` that reports the move action to its `List`.
    public func onMove(perform action: @escaping (IndexSet, Int) -> Void) -> ForEach {
        var copy = self
        copy.onMoveAction = action
        return copy
    }
}
