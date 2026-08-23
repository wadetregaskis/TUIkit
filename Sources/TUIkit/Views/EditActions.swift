//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditActions.swift
//
//  Which edits a `ForEach` performs on its own collection.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// The edits a ``ForEach`` will make to the collection it is bound to.
///
/// The alternative to writing `.onMove` and `.onDelete` closures that do the
/// obvious thing. `ForEach($items, editActions: .all)` moves and removes
/// elements through the binding itself, which is the same code every such
/// closure would have contained.
///
/// Generic over the collection, as SwiftUI's is, because the cases are not
/// always available: a `MutableCollection` can reorder but an `Array` is needed
/// to remove, so ``move`` and ``delete`` are constrained separately and
/// ``all`` requires both. That is what stops `.delete` being offered for a
/// collection that cannot shrink.
public struct EditActions<Data>: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

extension EditActions where Data: MutableCollection {
    /// Rows can be reordered.
    public static var move: EditActions<Data> { EditActions(rawValue: 1 << 0) }
}

extension EditActions where Data: RangeReplaceableCollection {
    /// Rows can be removed.
    public static var delete: EditActions<Data> { EditActions(rawValue: 1 << 1) }
}

extension EditActions where Data: MutableCollection, Data: RangeReplaceableCollection {
    /// Rows can be reordered and removed.
    public static var all: EditActions<Data> { [.move, .delete] }
}

// MARK: - ForEach

extension ForEach where Content: View {
    /// Creates a `ForEach` over a binding to a collection, performing the named
    /// edits on that collection itself.
    ///
    /// ```swift
    /// List {
    ///     ForEach($items, editActions: .all) { $item in
    ///         TextField("", text: $item.name)
    ///     }
    /// }
    /// ```
    ///
    /// Exactly ``onMove(perform:)`` and ``onDelete(perform:)`` with the closures
    /// filled in — the collection is right there in the binding, so the two
    /// obvious implementations (`move(fromOffsets:toOffset:)` and
    /// `remove(atOffsets:)`) are what they would have been. Stating an action
    /// this way and writing the closure yourself are the same thing; state the
    /// closure when the model needs to hear about the edit.
    ///
    /// An action NOT in the set is not merely inert: the `List` is never told
    /// the rows can move or be deleted, so no drag-reorder gesture arms and no
    /// delete key is claimed.
    ///
    /// - Parameters:
    /// **One deviation:** the collection must be `Int`-indexed (an `Array`,
    /// `ContiguousArray` or `ArraySlice` — what backs a `List` in practice).
    /// That is not a choice about editing; it is the constraint TUIkit's
    /// `move(fromOffsets:toOffset:)` and `remove(atOffsets:)` already carry, so
    /// that they out-specialise SwiftUI's overlay versions of the same names on
    /// Apple platforms and link. See `Collection+Offsets.swift` — without it
    /// this compiles and then fails to LINK, which is how the constraint was
    /// found.
    ///
    /// - Parameters:
    ///   - data: The collection to iterate and edit.
    ///   - editActions: Which edits to perform.
    ///   - content: Builds a row from a binding to its element.
    public init<C>(
        _ data: Binding<C>,
        editActions: EditActions<C>,
        @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
    )
    where
        C: MutableCollection, C: RandomAccessCollection, C: RangeReplaceableCollection,
        C.Index == Int, C.Element: Identifiable, Data == [Binding<C.Element>],
        ID == C.Element.ID
    {
        self.init(data, content: content)
        applyEditActions(editActions, to: data)
    }

    /// Creates a `ForEach` over a binding to a collection whose elements are
    /// identified by a key path, performing the named edits on that collection.
    ///
    /// The key path names a property of the ELEMENT, as it does in SwiftUI.
    ///
    /// - Parameters:
    ///   - data: The collection to iterate and edit.
    ///   - id: The property identifying each element.
    ///   - editActions: Which edits to perform.
    ///   - content: Builds a row from a binding to its element.
    public init<C>(
        _ data: Binding<C>,
        id: KeyPath<C.Element, ID>,
        editActions: EditActions<C>,
        @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
    )
    where
        C: MutableCollection, C: RandomAccessCollection, C: RangeReplaceableCollection,
        C.Index == Int, Data == [Binding<C.Element>]
    {
        self.init(data, id: id, content: content)
        applyEditActions(editActions, to: data)
    }

    /// Fills in the move / delete closures for whichever actions were named.
    ///
    /// Written against the raw values rather than `contains(.move)` so it needs
    /// neither of the constraints those statics carry — the two initializers
    /// above already require both, and duplicating the requirement here to ask
    /// a question about a bit pattern would be the constraint spreading for no
    /// reason.
    private mutating func applyEditActions<C>(_ actions: EditActions<C>, to data: Binding<C>)
    where C: MutableCollection, C: RangeReplaceableCollection, C.Index == Int {
        if actions.rawValue & 1 != 0 {
            onMoveAction = { source, destination in
                data.wrappedValue.move(fromOffsets: source, toOffset: destination)
            }
        }
        if actions.rawValue & 2 != 0 {
            onDeleteAction = { offsets in
                data.wrappedValue.remove(atOffsets: offsets)
            }
        }
    }
}
