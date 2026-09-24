//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListContentStateSlotTests.swift
//
//  A `List` draws a lone row — its whole content, when that is one view, or a
//  lone `Section`'s — at the list's OWN identity, and keeps two slots of its
//  own there: its handler and its focus id. A view of the app's own drawn
//  there binds its `@State` by declaration order from index 0, so the two had
//  to live in different index ranges or the first `@State` and the handler
//  took each other's box: different types, so each replaced the other on
//  every frame, and both came back at their defaults.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("A List's own slots and its content's @State", .rendersEnglishUI)
struct ListContentStateSlotTests {

    /// Draws its count, and hands its `@State`'s binding out through `probe`
    /// on every body, so a test can write it between frames the way an event
    /// handler would.
    private struct Counter: View {
        @State private var count = 0
        let probe: MainActorBox<Binding<Int>?>

        var body: some View {
            probe.value = $count
            return Text("n=\(count)")
        }
    }

    /// `Counter` with its count at declaration index 1 — the list's focus-id
    /// slot until it moved — behind a first `@State` that is never written.
    private struct SecondSlotCounter: View {
        @State private var first = ""
        @State private var count = 0
        let probe: MainActorBox<Binding<Int>?>

        var body: some View {
            probe.value = $count
            return Text("n=\(count)\(first)")
        }
    }

    /// Renders `view`, writes 5 into the counter's `@State`, renders again and
    /// returns what the second frame drew.
    private func countAfterAWrite(
        _ view: (MainActorBox<Binding<Int>?>) -> some View
    ) -> [String] {
        let probe = MainActorBox<Binding<Int>?>(nil)
        let fixture = ListSectionEditingFixture()
        let tree = view(probe)
        fixture.render(tree)
        probe.value?.wrappedValue = 5
        return fixture.render(tree).lines.map(\.stripped).filter { $0.contains("n=") }
    }

    @Test("A view of your own that is the List's whole content keeps its @State")
    func wholeContentKeepsItsState() {
        let drawn = countAfterAWrite { probe in
            List(selection: .constant(String?.none)) { Counter(probe: probe) }
                .frame(height: 8)
        }
        #expect(drawn.contains { $0.contains("n=5") }, "drew \(drawn)")
    }

    @Test("A view of your own that is a lone Section's content keeps its @State")
    func loneSectionContentKeepsItsState() {
        let drawn = countAfterAWrite { probe in
            List(selection: .constant(String?.none)) {
                Section("Counts") { Counter(probe: probe) }
            }
            .frame(height: 8)
        }
        #expect(drawn.contains { $0.contains("n=5") }, "drew \(drawn)")
    }

    /// The focus id's slot, which a row's SECOND `@State` shared.
    @Test("A second @State on such a row keeps its value too")
    func secondStateKeepsItsValue() {
        let drawn = countAfterAWrite { probe in
            List(selection: .constant(String?.none)) { SecondSlotCounter(probe: probe) }
                .frame(height: 8)
        }
        #expect(drawn.contains { $0.contains("n=5") }, "drew \(drawn)")
    }

    /// The other side of the same collision: the handler holds the cursor,
    /// the scroll offset and the selection's working state, and a fresh one
    /// every frame forgets all three.
    @Test("The List keeps its own handler from frame to frame under such a row")
    func listKeepsItsHandler() {
        let probe = MainActorBox<Binding<Int>?>(nil)
        let fixture = ListSectionEditingFixture()
        let tree = List(selection: .constant(String?.none)) { Counter(probe: probe) }
            .frame(height: 8)
        fixture.render(tree)
        let first = fixture.handler
        fixture.render(tree)
        let second = fixture.handler
        #expect(first != nil, "the list took the focus")
        #expect(first === second, "the list's handler was replaced between frames")
    }
}
