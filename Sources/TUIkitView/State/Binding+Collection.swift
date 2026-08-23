//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Binding+Collection.swift
//
//  A binding to a collection IS a collection — of bindings.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Binding: Identifiable where Value: Identifiable {
    /// The identity of the value behind the binding.
    ///
    /// A binding has no identity of its own — two bindings to the same element
    /// are the same row — so it borrows the value's, which is what makes
    /// `ForEach` over a collection of bindings work without an explicit `id:`.
    public var id: Value.ID { wrappedValue.id }
}

extension Binding: Sequence, Collection where Value: MutableCollection {
    /// A binding to one element, not the element.
    public typealias Element = Binding<Value.Element>
    public typealias Index = Value.Index
    public typealias Indices = Value.Indices

    public var startIndex: Value.Index { wrappedValue.startIndex }
    public var endIndex: Value.Index { wrappedValue.endIndex }
    public var indices: Value.Indices { wrappedValue.indices }

    public func index(after index: Value.Index) -> Value.Index {
        wrappedValue.index(after: index)
    }

    public func formIndex(after index: inout Value.Index) {
        wrappedValue.formIndex(after: &index)
    }

    /// A binding to the element at `position`, writing back through this one.
    ///
    /// Both accessors re-check the index, and a read past the end answers with
    /// the value that was there when the binding was made. An element binding
    /// OUTLIVES the frame that produced it: an `onDelete`, a `.task` reload, or
    /// a sibling row's own setter can shorten the collection first, and an
    /// unguarded `collection[position]` would then trap inside a getter the
    /// caller has no way to see coming. Writes past the end are dropped.
    ///
    /// That is why this is not a one-line forward, and why
    /// `ForEach.elementBindings(_:)` is now `Array(data)` rather than a second
    /// copy of the same guard.
    public subscript(position: Value.Index) -> Binding<Value.Element> {
        let fallback = wrappedValue[position]
        return Binding<Value.Element>(
            get: {
                let collection = self.wrappedValue
                return collection.indices.contains(position) ? collection[position] : fallback
            },
            set: { newValue in
                guard self.wrappedValue.indices.contains(position) else { return }
                self.wrappedValue[position] = newValue
            })
    }
}

extension Binding: BidirectionalCollection
where Value: BidirectionalCollection, Value: MutableCollection {
    public func index(before index: Value.Index) -> Value.Index {
        wrappedValue.index(before: index)
    }

    public func formIndex(before index: inout Value.Index) {
        wrappedValue.formIndex(before: &index)
    }
}

extension Binding: RandomAccessCollection
where Value: MutableCollection, Value: RandomAccessCollection {}
