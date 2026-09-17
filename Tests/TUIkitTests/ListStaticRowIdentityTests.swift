//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListStaticRowIdentityTests.swift
//
//  A static List row has no identity of its own, so the only id it can be
//  given is its index — and an index cannot be cast into a String, a UUID or a
//  Set of either. The extraction used to `continue` past a row whose index
//  would not cast, so a whole list of static rows rendered as the EMPTY
//  PLACEHOLDER: the content vanished, and which selection type you happened to
//  bind decided whether it did.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("list static row identity", .rendersEnglishUI)
struct ListStaticRowIdentityTests {
    private struct Row: Identifiable, Hashable {
        let id = UUID()
        let name: String
    }

    private func lines<V: View>(_ view: V) -> [String] {
        let context = makeRenderContext(width: 30, height: 10)
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    private func shows<V: View>(_ view: V, _ text: String) -> Bool {
        lines(view).contains { $0.contains(text) }
    }

    @Test("Static rows draw whatever the selection type is")
    func staticRowsSurviveEverySelectionType() {
        #expect(shows(List { Text("alpha"); Text("beta") }, "alpha"), "no selection at all")
        #expect(
            shows(List(selection: .constant(Int?.none)) { Text("alpha"); Text("beta") }, "alpha"),
            "an Int selection, which CAN hold an index")
        #expect(
            shows(List(selection: .constant(String?.none)) { Text("alpha"); Text("beta") }, "beta"),
            "a String selection, which cannot — the rows must still draw")
        #expect(
            shows(List(selection: .constant(UUID?.none)) { Text("alpha"); Text("beta") }, "beta"),
            "nor can a UUID")
        #expect(
            shows(List(selection: .constant(Set<UUID>())) { Text("alpha"); Text("beta") }, "beta"),
            "nor a Set of them")
    }

    @Test("A row the selection cannot name is drawn but not selectable")
    func unnameableRowsAreNotSelectable() {
        // The placeholder must not come back for a list that has content, and
        // the rows must not be pretending to an identity they do not have.
        #expect(
            !shows(List(selection: .constant(String?.none)) { Text("alpha") }, "No items"),
            "content is content: \(lines(List(selection: .constant(String?.none)) { Text("alpha") }))")
    }

    @Test("An empty list still shows its placeholder")
    func emptyListIsStillEmpty() {
        // The old behaviour got this right by accident — the id cast failed,
        // so nothing was a row. Now emptiness is decided by the buffer, which
        // means it no longer depends on which selection type was bound.
        #expect(shows(List(selection: .constant(String?.none)) { EmptyView() }, "No items"))
        #expect(shows(List(selection: .constant(Int?.none)) { EmptyView() }, "No items"))
        #expect(shows(List { EmptyView() }, "No items"))
    }

    @Test("Identified rows are unaffected")
    func identifiedRowsStillSelectable() {
        // The control: a ForEach over Identifiable data carries real ids, and
        // this path must be untouched by any of the above.
        let rows = [Row(name: "one"), Row(name: "two")]
        let list = List(selection: .constant(rows[0].id)) {
            ForEach(rows) { Text($0.name) }
        }
        #expect(shows(list, "one"))
        #expect(shows(list, "two"))
    }
}
