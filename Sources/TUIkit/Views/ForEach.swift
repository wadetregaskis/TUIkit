//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// Inside a container, `ForEach` is transparent: `resolveChildViews` asks it
/// for one ``ChildView`` per element, and the stack lays those out as its own
/// siblings, so a `ForEach` in a `VStack` is indistinguishable from writing
/// the rows out by hand.
///
/// Used as an entire `body` — which is how Apple's own `ForEach`
/// documentation writes it — it stacks its elements vertically itself, via
/// its ``Renderable`` conformance. That case is NOT reached through a
/// container, because `body` is a `@ViewBuilder` block and `buildBlock` of a
/// single element returns it unchanged; before the conformance existed the
/// renderer fell through to its empty-buffer branch and such a view drew
/// nothing at all.
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

    /// Never called — a container resolves `ForEach` into its elements, and a
    /// `ForEach` drawn on its own goes through ``renderToBuffer(context:)``.
    ///
    /// - Important: Accessing this property directly will crash at runtime.
    public var body: Never {
        fatalError("ForEach renders via Renderable, or is resolved into child views")
    }
}

// MARK: - ForEach rendered on its own

extension ForEach: Renderable, Layoutable {
    /// Stacks the elements vertically, for the case where nothing above has
    /// resolved them into siblings of their own.
    ///
    /// A container asks ``childViews(context:)`` first
    /// (``resolveChildViews(from:context:)`` tries `ChildViewProvider` before
    /// anything else), so this path is not how a `ForEach` inside a stack
    /// draws. It is how one draws when it is a view's ENTIRE body —
    ///
    /// ```swift
    /// var body: some View {
    ///     ForEach(items) { Text($0.name) }
    /// }
    /// ```
    ///
    /// — which is the shape Apple's own `ForEach` documentation uses, and
    /// which drew nothing at all here: `body` is a `@ViewBuilder` block, and
    /// `buildBlock` of a single element returns it unchanged, so no container
    /// ever saw it and the renderer fell through to its empty-buffer branch.
    /// The same hole swallowed `ForEach { … }.foregroundStyle(.red)`, a
    /// modifier being opaque to child resolution.
    ///
    /// Vertical is the right default for the same reason `TupleView` stacks
    /// that way: it is what an un-laid-out run of sibling views means here,
    /// and it is what SwiftUI's documented example produces.
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = context.availableWidth
        return FrameBuffer(
            verticallyStacking: childViews(context: context).map { child in
                let size = child.measure(
                    proposal: ProposedSize(width: width, height: nil), context: context)
                return child.render(width: width, height: size.height, context: context)
            })
    }

    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var width = 0
        var height = 0
        var widthFlexible = false
        for child in childViews(context: context) {
            let size = child.measure(proposal: proposal, context: context)
            width = max(width, size.width)
            height += size.height
            widthFlexible = widthFlexible || size.isWidthFlexible
        }
        return ViewSize(
            width: width, height: height,
            isWidthFlexible: widthFlexible, isHeightFlexible: false)
    }
}

// MARK: - ForEach as a ChildViewProvider

extension ForEach: ChildViewProvider {
    /// Emits one ``ChildView`` per element so containers (HStack/VStack/ZStack)
    /// can lay each iteration out as its own sibling.
    ///
    /// Without this conformance ``resolveChildViews(from:context:)`` falls
    /// back to wrapping the whole ForEach as a single child, which would draw
    /// through ``renderToBuffer(context:)`` — correct content, but stacked
    /// vertically whatever the surrounding container wanted. This is what
    /// makes a `ForEach` in an `HStack` a row.
    ///
    /// Each child's identity is keyed by its element's `id` (via
    /// ``ViewIdentity/child(erasedType:key:)``), stable across passes AND
    /// across data mutations — reordering the data moves each row's state
    /// with its element.
    public func childViews(context: RenderContext) -> [ChildView] {
        data.map(makeChild(for:))
    }

    /// Worth remembering for the pass from sixteen rows: below that the
    /// memo's hash and lookup cost about what building the rows does.
    public var childViewsAreWorthMemoising: Bool { data.count >= 16 }

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
        let key = identityKey(element[keyPath: idKeyPath])
        // A row carrying an explicit `.alignmentGuide` is handed over bare. The
        // memo wrapper is `Renderable` and opaque, so a container reading its
        // children's guides finds none on a wrapped row and falls back to the
        // `AlignmentID`'s default — silently un-aligning exactly the rows the
        // caller went out of their way to place. The static witness costs
        // nothing (it is `false` for every row in almost every tree) and the
        // memo is forfeited only for the rows that cannot survive it.
        // `element as? any Equatable` is a dynamic cast per row per frame, and
        // on `fanout` (2000 rows) it is the second-largest source of
        // `swift_dynamicCast` in the profile at 2.5% — behind the render path's
        // own, which became a static witness (`View._renderSelf`).
        //
        // It cannot get the same treatment, and the reason is worth writing
        // down so it is not re-derived. A static witness works when the type in
        // hand is the generic parameter of the function doing the asking; here
        // the question is about `Data.Element`, and `ForEach` is deliberately
        // unconstrained over it (SwiftUI's is too). A constrained
        // `extension ForEach where Data.Element: Equatable` would compile, but
        // extension methods dispatch STATICALLY — `childViews(context:)` lives
        // in the unconstrained extension and would bind to the unconstrained
        // overload for everyone, silently losing the memo. Caching the answer
        // per element TYPE trades the cast for a dictionary hash, which is not
        // obviously cheaper and is measurably more code.
        //
        // So it stays, and the memo it buys is worth far more than it costs:
        // building the row eagerly instead cost `fanout` 21% of its frame.
        // A row carrying z-index or spacer metadata is exempted for the same
        // reason as an alignment guide: the memo wrapper is `Renderable` and
        // opaque, reporting the DEFAULT witness (z-index 0, not-a-spacer), so
        // a `.zIndex()` row lost its ordering in a `ZStack` and a `Spacer()`
        // row lost its flexibility. Each witness is `false` for almost every
        // row in almost every tree, so the memo is forfeited only for the few
        // rows that cannot survive it — as with the guide.
        let memoisable =
            !Content._providesAlignmentGuide
            && !Content._providesZIndex
            && !Content._isSpacer
        if memoisable, let equatableElement = element as? any Equatable {
            // The row view is NOT built here. `_MemoizedRow` takes the element
            // and this `ForEach`'s content closure and builds the row only if
            // the memo misses — which, in steady state, it mostly does not.
            // Building it here instead cost `fanout` 21% of its frame in row
            // views that the very next cache hit discarded.
            return ChildView(
                _MemoizedRow(
                    element: AnyEquatableBox(equatableElement), source: element, build: content),
                identityType: Content.self,
                key: key)
        }
        return ChildView(content(element), identityType: Content.self, key: key)
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
                return identityKey(element[keyPath: idKeyPath])
            },
            anyID: { ordinal in
                let element = data[data.index(data.startIndex, offsetBy: ordinal)]
                return AnyHashable(element[keyPath: idKeyPath])
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
    /// `Array(data)` because a `Binding` to a mutable collection IS a
    /// collection of bindings now (`Binding+Collection.swift`), and that
    /// subscript already carries the out-of-date-index guard this used to spell
    /// out for itself — see it for why an element binding cannot simply
    /// subscript the collection.
    static func elementBindings<C>(_ data: Binding<C>) -> [Binding<C.Element>]
    where C: MutableCollection, C: RandomAccessCollection {
        Array(data)
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
