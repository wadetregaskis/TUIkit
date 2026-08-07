//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ForEach.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// A view that generates views from a collection of data.
///
/// `ForEach` iterates over a collection and creates a view for each
/// element. The collection elements must be `Identifiable` or an
/// explicit ID key path must be provided.
///
/// ## Rendering
///
/// `ForEach` has **no standalone rendering capability**. It declares
/// `body: Never` but does *not* conform to `Renderable`. On its own,
/// it would produce an empty ``FrameBuffer``.
///
/// In practice, `ForEach` is always used inside a `@ViewBuilder` block
/// (e.g. within `VStack` or `HStack`). The builder's `buildArray`
/// method flattens it into a ``ViewArray``, which *is* `Renderable`.
/// This is the same pattern SwiftUI uses.
///
/// # Example with Identifiable
///
/// ```swift
/// struct Item: Identifiable {
///     let id: String
///     let name: String
/// }
///
/// let items = [Item(id: "1", name: "One"), Item(id: "2", name: "Two")]
///
/// VStack {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// }
/// ```
///
/// # Example with explicit ID key path
///
/// ```swift
/// let names = ["Anna", "Bob", "Clara"]
///
/// VStack {
///     ForEach(names, id: \.self) { name in
///         Text(name)
///     }
/// }
/// ```
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    /// The underlying data collection.
    let data: Data

    /// The key path to the unique ID of each element.
    let idKeyPath: KeyPath<Data.Element, ID>

    /// The closure that creates a view for each element.
    let content: (Data.Element) -> Content

    /// The `.onMove(perform:)` row-reorder action, if attached: `(source
    /// offsets, destination offset)`. `nil` unless a `.onMove` modifier set it.
    /// Read by an enclosing editable `List` (see ``DynamicViewContentActions``).
    var onMoveAction: ((IndexSet, Int) -> Void)?

    /// The `.onDelete(perform:)` row-delete action, if attached: `(offsets to
    /// delete)`. `nil` unless a `.onDelete` modifier set it.
    var onDeleteAction: ((IndexSet) -> Void)?

    /// The `.dropDestination(for:action:)` insertion action, if attached:
    /// `(insertion index, payloads)`. Type-erased so `ForEach` need not carry
    /// the payload type; the erased pair is `(accepts, perform)`.
    var dropInsertion: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)?

    /// Creates a ForEach with an explicit ID key path.
    ///
    /// - Parameters:
    ///   - data: The collection to iterate over.
    ///   - id: The key path to the unique ID of each element.
    ///   - content: The closure that creates the view for each element.
    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.idKeyPath = id
        self.content = content
    }

    /// Never called — `ForEach` is flattened into a ``ViewArray`` by
    /// `@ViewBuilder.buildArray` before rendering occurs.
    ///
    /// - Important: Accessing this property directly will crash at runtime.
    ///   Always use `ForEach` inside a `@ViewBuilder` closure (e.g., `VStack`, `HStack`).
    public var body: Never {
        fatalError("ForEach has no standalone rendering; use inside a @ViewBuilder block")
    }
}

// MARK: - ForEach as a ChildViewProvider

extension ForEach: ChildViewProvider {
    /// Emits one ``ChildView`` per element so containers (HStack/VStack/ZStack)
    /// can lay each iteration out as its own sibling.
    ///
    /// Without this conformance ``resolveChildViews(from:context:)`` falls
    /// back to wrapping the whole ForEach as a single child, then asks the
    /// universal render pipeline to draw it — and `body: Never` plus no
    /// `Renderable` conformance means the renderer reaches its silent
    /// "no rendering path" branch and returns an empty buffer. With this
    /// conformance the elements re-appear as expected.
    ///
    /// Each child's identity is keyed by its element's `id` (via
    /// ``ViewIdentity/child(erasedType:key:)``), stable across passes AND
    /// across data mutations — reordering the data moves each row's state
    /// with its element.
    public func childViews(context: RenderContext) -> [ChildView] {
        data.map(makeChild(for:))
    }

    /// One element's `ChildView` — the single constructor behind both the
    /// eager array and the lazy collection, so the two cannot drift.
    ///
    /// Identity is keyed by the element's ID — NOT its position — so a
    /// row's @State / focus / lifecycle follow the element across
    /// reorders, insertions and removals (SwiftUI's ForEach identity
    /// contract). Positional identity handed every row its neighbour's
    /// state when the data shifted.
    ///
    /// When the element is Equatable, the row is wrapped in a value-memo
    /// keyed by the element (as List does), so a container re-measuring /
    /// re-rendering its children each frame serves an unchanged row from
    /// the cache. `identityType: Content.self` keeps the per-child
    /// identity exactly what it is unwrapped — the memo is identity-
    /// transparent (the wrapper is Renderable, adds no identity).
    private func makeChild(for element: Data.Element) -> ChildView {
        let view = content(element)
        let key = String(describing: element[keyPath: idKeyPath])
        if let equatableElement = element as? any Equatable {
            return ChildView(
                _MemoizedRow(element: AnyEquatableBox(equatableElement), content: view),
                identityType: Content.self,
                key: key)
        }
        return ChildView(view, identityType: Content.self, key: key)
    }
}

// MARK: - ForEach as a LazyChildViewProvider

extension ForEach: LazyChildViewProvider {
    /// The rows as an on-demand collection (Stage 4 of "Locating things
    /// without drawing them"): count and keys come straight from `data` —
    /// O(1) and per-touch respectively, with `content` never invoked — and
    /// a row view is built only when an ordinal is actually subscripted.
    /// `RandomAccessCollection` makes the per-ordinal element access O(1).
    public func childViewCollection(context: RenderContext) -> ChildViewCollection {
        let data = self.data
        let idKeyPath = self.idKeyPath
        return ChildViewCollection(
            count: data.count,
            key: { ordinal in
                let element = data[data.index(data.startIndex, offsetBy: ordinal)]
                return String(describing: element[keyPath: idKeyPath])
            },
            build: { ordinal in
                makeChild(for: data[data.index(data.startIndex, offsetBy: ordinal)])
            })
    }
}

// MARK: - ForEach with Identifiable

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    /// Creates a ForEach for Identifiable elements.
    ///
    /// - Parameters:
    ///   - data: The collection with Identifiable elements.
    ///   - content: The closure that creates the view for each element.
    public init(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.idKeyPath = \Data.Element.id
        self.content = content
    }
}

// MARK: - ForEach with Range

extension ForEach where Data == Range<Int>, ID == Int {
    /// Creates a ForEach over an integer range.
    ///
    /// - Parameters:
    ///   - data: The range, e.g., `0..<10`.
    ///   - content: The closure that creates the view for each index.
    public init(
        _ data: Range<Int>,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.data = data
        self.idKeyPath = \.self
        self.content = content
    }
}

// MARK: - ForEach over a Binding

extension ForEach {
    /// One `Binding` per element of `data`, each writing back through the
    /// collection binding at its own index.
    ///
    /// Materialised as an array because ``ForEach`` iterates a
    /// `RandomAccessCollection` of elements, and here the ELEMENT is the
    /// binding. That is one small struct per row rather than per visible row —
    /// SwiftUI maps the indices for the same reason — so it costs a walk of the
    /// collection, not a render of it.
    ///
    /// Both accessors re-check the index. A row's binding outlives the frame it
    /// was made in: an `onDelete`, a `.task` reload, or a sibling row's own
    /// setter can shorten the collection first, and an unguarded
    /// `collection[index]` would then trap inside a getter the caller has no
    /// way to see coming. The captured `fallback` answers reads past the end
    /// with what the row last held, and writes past the end are dropped.
    static func elementBindings<C>(_ data: Binding<C>) -> [Binding<C.Element>]
    where C: MutableCollection, C: RandomAccessCollection {
        data.wrappedValue.indices.map { index in
            let fallback = data.wrappedValue[index]
            return Binding(
                get: {
                    let collection = data.wrappedValue
                    return collection.indices.contains(index) ? collection[index] : fallback
                },
                set: { newValue in
                    guard data.wrappedValue.indices.contains(index) else { return }
                    data.wrappedValue[index] = newValue
                })
        }
    }
}

extension ForEach {
    /// Creates a ForEach over a *binding* to a collection, handing each element
    /// to `content` as a `Binding` — SwiftUI's `ForEach($items) { $item in … }`.
    ///
    /// This is what a row of editable controls needs. A `Toggle` takes a
    /// `Binding<Bool>`, so a row built from a plain element value has nothing
    /// to bind to; the alternatives are an index-keyed lookup (`$flags[i]`,
    /// which works but re-couples the row to its position) or a hand-rolled
    /// `Binding(get:set:)` per row.
    ///
    /// ```swift
    /// @State private var options = [Option(name: "Verbose", enabled: false)]
    ///
    /// ForEach($options) { $option in
    ///     Toggle(option.name, isOn: $option.enabled)
    /// }
    /// ```
    ///
    /// Note what this does NOT rescue: `$dictionary[key]` is a
    /// `Binding<Value?>`, and `$dictionary[key, default: x]` cannot form a key
    /// path at all, because the `default:` parameter is an autoclosure and key
    /// path subscripts need `Hashable` arguments. Both are true of SwiftUI too,
    /// verbatim — for a dictionary, build the `Binding(get:set:)` explicitly.
    public init<C>(
        _ data: Binding<C>,
        @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
    )
    where
        C: MutableCollection, C: RandomAccessCollection, C.Element: Identifiable,
        Data == [Binding<C.Element>], ID == C.Element.ID
    {
        self.init(Self.elementBindings(data), id: \.wrappedValue.id, content: content)
    }

    /// Creates a ForEach over a binding to a collection whose elements are
    /// identified by a key path rather than `Identifiable` — SwiftUI's
    /// `ForEach($items, id: \.name) { $item in … }`.
    ///
    /// The key path names a property of the ELEMENT, as it does in SwiftUI, not
    /// of the binding; it is rebased through `wrappedValue` here so callers
    /// never write `\.wrappedValue.something`.
    public init<C>(
        _ data: Binding<C>,
        id: KeyPath<C.Element, ID>,
        @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
    )
    where C: MutableCollection, C: RandomAccessCollection, Data == [Binding<C.Element>] {
        self.init(
            Self.elementBindings(data),
            id: (\Binding<C.Element>.wrappedValue).appending(path: id),
            content: content)
    }
}
