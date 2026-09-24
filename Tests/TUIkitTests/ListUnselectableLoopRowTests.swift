//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListUnselectableLoopRowTests.swift
//
//  A `ForEach` whose ids the list's selection cannot hold — `Int` ids in a
//  `String`-selection list — draws its rows, unselectable. SwiftUI does; a
//  static row without a usable tag already did here. A loop's rows used to be
//  DROPPED, which showed a section of them as its bare header and a list of
//  nothing else as the empty placeholder — and once a `Group` or an `if`/`else`
//  around a loop was looked through, the same drop reached the wrapped loops
//  that had escaped it by being drawn through the child walk.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A loop whose ids the selection cannot hold", .rendersEnglishUI)
struct ListUnselectableLoopRowTests {

    /// The lines `view` draws, stripped of styling.
    private func lines(_ view: some View) -> [String] {
        ListSectionEditingFixture().render(view.frame(height: 10)).lines.map(\.stripped)
    }

    /// Whether a line shows `label` as a whole word — "n1" but not "n10".
    private func shows(_ label: String, in lines: [String]) -> Bool {
        lines.contains { $0.split(separator: " ").contains { $0.contains(label) } }
    }

    @Test("A bare loop is drawn")
    func bareLoopIsDrawn() {
        let drawn = lines(
            List(selection: .constant(String?.none)) {
                ForEach(1...3, id: \.self) { Text("n\($0)") }
            })
        for label in ["n1", "n2", "n3"] {
            #expect(shows(label, in: drawn), "\(label) is missing: \(drawn)")
        }
    }

    @Test("A loop in a Group in a Section is drawn beside a selectable one")
    func groupedLoopInASectionIsDrawn() {
        let drawn = lines(
            List(selection: .constant(String?.none)) {
                Section("Fruit") { ForEach(["apple", "pear"], id: \.self) { Text($0) } }
                Section("Counts") { Group { ForEach(1...3, id: \.self) { Text("n\($0)") } } }
            })
        for label in ["apple", "pear", "n1", "n2", "n3"] {
            #expect(shows(label, in: drawn), "\(label) is missing: \(drawn)")
        }
    }

    @Test("A loop in a Group as the List's content is drawn")
    func groupedLoopAsTheListsContentIsDrawn() {
        let drawn = lines(
            List(selection: .constant(String?.none)) {
                Group { ForEach(1...3, id: \.self) { Text("n\($0)") } }
            })
        for label in ["n1", "n2", "n3"] {
            #expect(shows(label, in: drawn), "\(label) is missing: \(drawn)")
        }
    }

    @Test("A loop in the else of an empty-state if is drawn")
    func loopInAnElseIsDrawn() {
        let counts = [1, 2, 3]
        let drawn = lines(
            List(selection: .constant(String?.none)) {
                Section("Counts") {
                    if counts.isEmpty {
                        Text("none")
                    } else {
                        ForEach(counts, id: \.self) { Text("n\($0)") }
                    }
                }
            })
        for label in ["n1", "n2", "n3"] {
            #expect(shows(label, in: drawn), "\(label) is missing: \(drawn)")
        }
    }

    @Test("Its rows take no selection")
    func rowsTakeNoSelection() {
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                ForEach(1...3, id: \.self) { Text("n\($0)") }
            }
            .frame(height: 10))
        let handler = fixture.handler
        #expect(handler != nil, "the list did not take the focus")
        #expect(handler?.id(at: 0) == nil, "a row answered to an id the selection cannot hold")
    }
}
