//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowTagTests.swift
//
//  `.tag(_:)` on a `List` row. In SwiftUI it is the only way to give a
//  statically-built selectable `List` per-row selection values; here the tag
//  was read by `Picker` alone, and `_ListCore`'s static-child extraction keyed
//  every row by its ordinal without ever looking for one. So a tagged row
//  either could not be selected at all (the ordinal does not cast into a
//  `String` selection) or selected as 0, 1, 2 …
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("List row tags", .rendersEnglishUI)
struct ListRowTagTests {

    @MainActor
    private final class Fixture<Value: Hashable> {
        let tui = TUIContext()
        var env = EnvironmentValues()

        init() {
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
        }

        var handler: ItemListHandler<Value>? {
            env.focusManager?.currentFocused as? ItemListHandler<Value>
        }

        @discardableResult
        func render(_ view: some View) -> FrameBuffer {
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            let context = RenderContext(
                availableWidth: 30, availableHeight: 12, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
            return buffer
        }
    }

    @Test("A tagged static row selects by its tag, not by its position")
    func taggedRowsSelectByTag() {
        let fixture = Fixture<String>()
        var selection: String?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            Text("alpha").tag("a")
            Text("beta").tag("b")
        }
        .frame(height: 8)

        let buffer = fixture.render(list)
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.contains { $0.contains("alpha") }, "the rows must draw: \(lines)")

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        // The id each row is keyed by — asked through `id(at:)`, which is the
        // accessor that answers on both of the handler's id paths.
        //
        // NOT `selectableIndices`: it is empty when EVERY row is selectable
        // (the all-content shortcut documented on the property) and equally
        // empty when NONE is, which is precisely the broken state, so it
        // cannot tell the two apart here.
        #expect(
            handler.id(at: 0) == "a",
            "the first row is keyed by its tag: \(String(describing: handler.id(at: 0)))")
        #expect(
            handler.id(at: 1) == "b",
            "the second row is keyed by its tag: \(String(describing: handler.id(at: 1)))")

        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(selection == "b", "the second row's tag, got \(String(describing: selection))")
    }

    @Test("An explicit tag wins over the ordinal for an Int selection too")
    func tagWinsOverOrdinal() {
        let fixture = Fixture<Int>()
        var selection: Int?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            Text("alpha").tag(10)
            Text("beta").tag(20)
        }
        .frame(height: 8)

        fixture.render(list)
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(selection == 10, "the first row's tag, not its ordinal 0")
    }

    @Test("An untagged row still falls back to its ordinal")
    func untaggedRowsKeepTheOrdinal() {
        let fixture = Fixture<Int>()
        var selection: Int?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            Text("alpha")
            Text("beta")
        }
        .frame(height: 8)

        fixture.render(list)
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(selection == 1, "no tag, so the ordinal — got \(String(describing: selection))")
    }

    /// The well-typed neighbour is what makes this falsifiable, and it is here
    /// deliberately. A list of ONLY mistyped rows behaves identically with and
    /// without the fix — no row can be keyed either way — so a test watching
    /// just the mistyped row asserts nothing about `.tag(_:)` being read at
    /// all. With a sibling the selection CAN hold, the two states differ: the
    /// mistyped row is skipped and its neighbour is keyed by its tag.
    @Test("A tag of the wrong type leaves that row unselectable, not absent, and does not cost its neighbour")
    func mistypedTagIsUnselectable() {
        let fixture = Fixture<String>()
        var selection: String?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            Text("alpha").tag(1)  // an `Int` a `String` selection cannot hold
            Text("beta").tag("b")
        }
        .frame(height: 8)

        let lines = fixture.render(list).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("alpha") }, "the rows still draw: \(lines)")
        #expect(!lines.contains { $0.contains("No items") }, "not the empty placeholder: \(lines)")

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.itemCount == 2, "both rows are still rows: \(handler.itemCount)")
        #expect(
            handler.id(at: 0) == nil,
            "an Int tag names nothing a String selection can hold: \(String(describing: handler.id(at: 0)))")
        #expect(
            handler.id(at: 1) == "b",
            "the sibling's tag still keys it: \(String(describing: handler.id(at: 1)))")
        #expect(
            handler.selectableIndices == [1],
            "only the row the selection can name: \(handler.selectableIndices.sorted())")

        // And the unselectable row selects nothing when driven, rather than
        // falling back to something the app never named.
        handler.focusedIndex = 0
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(
            selection == nil,
            "the mistyped row writes nothing: \(String(describing: selection))")
    }

    /// A lone row is not a `TupleView`, so it reaches neither child walk — it
    /// is the List's whole content and takes the single-row fallback, which
    /// keyed it `0` and nothing else.
    @Test("A List of one tagged row selects by that tag")
    func aSingleTaggedRow() {
        let fixture = Fixture<String>()
        var selection: String?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            Text("only").tag("solo")
        }
        .frame(height: 6)

        fixture.render(list)
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(selection == "solo", "got \(String(describing: selection))")
    }

    /// The same fallback, one level in: a `Section` whose content is a single
    /// view rather than a `TupleView` of them.
    @Test("A Section of one tagged row selects by that tag")
    func aSingleTaggedRowInASection() {
        let fixture = Fixture<String>()
        var selection: String?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            Section("Letters") {
                Text("only").tag("solo")
            }
        }
        .frame(height: 6)

        fixture.render(list)
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        guard let row = handler.itemIDs.firstIndex(of: "solo") else {
            Issue.record("no row carries the tag: \(handler.itemIDs)")
            return
        }
        handler.focusedIndex = row
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(selection == "solo", "got \(String(describing: selection))")
    }

    @Test("A tagged row inside a Section selects by its tag")
    func taggedRowsInASection() {
        let fixture = Fixture<String>()
        var selection: String?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            Section("Letters") {
                Text("alpha").tag("a")
                Text("beta").tag("b")
            }
        }
        .frame(height: 8)

        fixture.render(list)
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        for _ in 0..<4 { _ = handler.handleKeyEvent(KeyEvent(key: .down)) }
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(selection == "b", "the last row's tag, got \(String(describing: selection))")
    }
}
