//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BindingCollectionTests.swift
//
//  A `Binding` to a mutable collection is itself a collection — of bindings to
//  its elements. `ForEach($items)` was the only consumer while the mapping was
//  private to it; as a conformance it is reachable by anything, so the rules it
//  has always kept need pinning where they can be seen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A Binding to a collection is a collection")
struct BindingCollectionTests {

    private struct Row: Identifiable, Equatable {
        let id: Int
        var enabled: Bool
    }

    /// A live array behind a binding, so a write really has to travel.
    private final class Store {
        var rows: [Row]
        init(_ rows: [Row]) { self.rows = rows }
        var binding: Binding<[Row]> {
            Binding(get: { self.rows }, set: { self.rows = $0 })
        }
    }

    @Test("It counts, indexes and iterates as the collection does")
    func mirrorsTheCollection() {
        let store = Store([Row(id: 1, enabled: false), Row(id: 2, enabled: true)])
        let binding = store.binding

        #expect(binding.count == 2)
        #expect(binding.startIndex == 0)
        #expect(binding.endIndex == 2)
        #expect(Array(binding.indices) == [0, 1])
        #expect(binding.map(\.wrappedValue) == store.rows)
        // BidirectionalCollection and RandomAccessCollection, not just Collection.
        #expect(binding.last?.wrappedValue == Row(id: 2, enabled: true))
        #expect(binding.reversed().map(\.wrappedValue.id) == [2, 1])
    }

    @Test("Writing through an element binding writes back through the collection")
    func writesTravel() {
        let store = Store([Row(id: 1, enabled: false), Row(id: 2, enabled: false)])
        let binding = store.binding

        binding[1].enabled.wrappedValue = true
        #expect(store.rows == [Row(id: 1, enabled: false), Row(id: 2, enabled: true)])

        // …and through iteration, which is the `ForEach($items)` shape.
        for row in binding { row.enabled.wrappedValue = false }
        #expect(store.rows.allSatisfy { !$0.enabled })
    }

    /// An element binding outlives the frame that made it. This is the rule
    /// that stops a row's getter trapping when the row is gone — the reason the
    /// subscript is not a one-line forward.
    @Test("An element binding whose index has gone away neither traps nor writes")
    func staleIndexIsInert() {
        let store = Store([Row(id: 1, enabled: false), Row(id: 2, enabled: true)])
        let stale = store.binding[1]

        store.rows.removeLast()

        // Reads answer with what the row last held rather than trapping.
        #expect(stale.wrappedValue == Row(id: 2, enabled: true))
        // Writes are dropped, not applied to whatever now occupies the index.
        stale.wrappedValue = Row(id: 99, enabled: false)
        #expect(store.rows == [Row(id: 1, enabled: false)])
    }

    @Test("A binding borrows its value's identity")
    func identityComesFromTheValue() {
        let store = Store([Row(id: 7, enabled: false)])
        #expect(store.binding[0].id == 7)
    }

    /// The conformance is what `ForEach.elementBindings(_:)` is built from now,
    /// so the two must not have drifted apart.
    @Test("ForEach's per-row bindings are the collection's own")
    func forEachUsesTheConformance() {
        let store = Store([Row(id: 1, enabled: false), Row(id: 2, enabled: false)])
        let rows = ForEach<[Row], Int, EmptyView>.elementBindings(store.binding)

        #expect(rows.count == 2)
        rows[0].enabled.wrappedValue = true
        #expect(store.rows[0].enabled)
    }
}
