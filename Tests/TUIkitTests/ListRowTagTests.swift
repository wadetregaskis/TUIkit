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
        #expect(
            handler.selectableIndices.isEmpty || handler.selectableIndices == [0, 1],
            "both tagged rows are selectable: \(handler.selectableIndices.sorted())")

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

    @Test("A tag of the wrong type leaves the row unselectable, not absent")
    func mistypedTagIsUnselectable() {
        let fixture = Fixture<String>()
        var selection: String?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            Text("alpha").tag(1)
            Text("beta").tag(2)
        }
        .frame(height: 8)

        let lines = fixture.render(list).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("alpha") }, "the rows still draw: \(lines)")
        #expect(!lines.contains { $0.contains("No items") }, "not the empty placeholder: \(lines)")
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
