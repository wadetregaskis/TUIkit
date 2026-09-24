//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListGroupEditingTests.swift
//
//  `.onDelete` and `.onMove` on a `ForEach` with a `Group` or an `if`/`else`
//  between it and its container — a `Section`, or the `List` itself. Either
//  contributes exactly its content's rows, so the loop inside one is still its
//  container's whole content and every row is still that loop's: SwiftUI
//  deletes the element a row draws in all of these arrangements, and so does
//  TUIkit now. It used to claim the gesture on no row at all, and key the rows
//  by position rather than by element, so a `String` selection could not reach
//  any of them.
//
//  Not to be confused with the arrangements that ARE refused, which are in
//  `ListUnownedEditActionTests` — a `Group` holding a hand-written row beside
//  the loop is one of them, because what refuses there is the flattening, not
//  the `Group`. The shared harness is `ListSectionEditingFixture`.
//
//  Every assertion is on the collection afterwards, never on a count of
//  callbacks, and every gesture first checks that its row answers to the
//  element it draws — the element id the rows under a wrapper used to lack.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Editing a ForEach behind a Group or an if/else", .rendersEnglishUI)
struct ListGroupEditingTests {

    // MARK: - Delete

    @Test("A Group in a Section: Delete removes the element the row draws")
    func groupInASectionDeletes() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Items") {
                    Group {
                        ForEach(items.value, id: \.self) { Text($0) }
                            .onDelete { items.value.remove(atOffsets: $0) }
                    }
                }
            }
            .frame(height: 10))

        // header, alpha, beta, gamma — "beta" is row 2 and data offset 1.
        #expect(fixture.pressDelete(onRow: 2, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    @Test("A Group as the List's content: Delete removes the element the row draws")
    func groupAsTheListsContentDeletes() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Group {
                    ForEach(items.value, id: \.self) { Text($0) }
                        .onDelete { items.value.remove(atOffsets: $0) }
                }
            }
            .frame(height: 10))

        #expect(fixture.pressDelete(onRow: 1, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    /// Two sections, so an offset is measured from the right section's first
    /// item and not the list's — and the second holds its loop two `Group`s
    /// deep, because the list looks through any number of them.
    @Test("Nested Groups in the second Section delete from THAT section's collection")
    func nestedGroupsInTheSecondSectionDelete() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Alpha") {
                    Group {
                        ForEach(alpha.value, id: \.self) { Text($0) }
                            .onDelete { alpha.value.remove(atOffsets: $0) }
                    }
                }
                Section("Beta") {
                    Group {
                        Group {
                            ForEach(beta.value, id: \.self) { Text($0) }
                                .onDelete { beta.value.remove(atOffsets: $0) }
                        }
                    }
                }
            }
            .frame(height: 12))

        // header, a1, a2, a3, header, b1, b2, b3 — "b2" is row 6, data offset 1.
        #expect(fixture.pressDelete(onRow: 6, named: "b2") == true)
        #expect(beta.value == ["b1", "b3"], "got \(beta.value)")
        #expect(alpha.value == ["a1", "a2", "a3"], "the other section is untouched: \(alpha.value)")
    }

    // MARK: - Move

    @Test("A Group in a Section: the pick-up reorders the section's own collection")
    func groupInASectionReorders() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Items") {
                    Group {
                        ForEach(items.value, id: \.self) { Text($0) }
                            .onMove { items.value.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .frame(height: 10))

        // header, alpha, beta, gamma — "alpha" is row 1 and data offset 0.
        #expect(fixture.pickUpMoveAndPlace(row: 1, named: "alpha", by: 1))
        #expect(items.value == ["beta", "alpha", "gamma"], "got \(items.value)")
    }

    @Test("A Group as the List's content: the pick-up reorders its collection")
    func groupAsTheListsContentReorders() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Group {
                    ForEach(items.value, id: \.self) { Text($0) }
                        .onMove { items.value.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .frame(height: 10))

        #expect(fixture.pickUpMoveAndPlace(row: 0, named: "alpha", by: 2))
        #expect(items.value == ["beta", "gamma", "alpha"], "got \(items.value)")
    }

    // MARK: - An if/else

    /// The commonest way to reach the same hole: an empty state in one arm,
    /// the loop in the other. The list looks through an `if`/`else` as it does
    /// a `Group`, taking the arm's branch step on the way in.
    @Test("An if/else in a Section: Delete removes the element the row draws")
    func ifElseInASectionDeletes() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Items") {
                    if items.value.isEmpty {
                        Text("Nothing here")
                    } else {
                        ForEach(items.value, id: \.self) { Text($0) }
                            .onDelete { items.value.remove(atOffsets: $0) }
                    }
                }
            }
            .frame(height: 10))

        #expect(fixture.pressDelete(onRow: 2, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    @Test("An if/else as the List's content: the pick-up reorders its collection")
    func ifElseAsTheListsContentReorders() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                if items.value.isEmpty {
                    Text("Nothing here")
                } else {
                    ForEach(items.value, id: \.self) { Text($0) }
                        .onMove { items.value.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .frame(height: 10))

        #expect(fixture.pickUpMoveAndPlace(row: 1, named: "beta", by: 1))
        #expect(items.value == ["alpha", "gamma", "beta"], "got \(items.value)")
    }

    // MARK: - Selection

    /// The half of the same hole that has nothing to do with editing: a row
    /// the child walk produced is keyed by its ordinal, which no `String`
    /// selection can hold, so Space on it selected nothing.
    @Test("Space on a row behind a Group selects that row's element")
    func groupRowSelectsByElementID() {
        let selection = MainActorBox<String?>(nil)
        let binding = Binding(get: { selection.value }, set: { selection.value = $0 })
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: binding) {
                Group {
                    ForEach(["alpha", "beta", "gamma"], id: \.self) { Text($0) }
                }
            }
            .frame(height: 10))
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        handler.focusedIndex = 1
        _ = handler.handleKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "beta", "got \(String(describing: selection.value))")
    }
}
