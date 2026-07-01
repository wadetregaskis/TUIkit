//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListMultiSelectTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A mutable `Set` backing a test `Binding`.
private final class StringSetSink: @unchecked Sendable {
    var value: Set<String> = []
}

/// Verifies TUIkit's multi-selection parity. SwiftUI has no multi-select
/// `Picker` — multi-selection is `List(selection: Binding<Set<...>>)`, which
/// TUIkit supports: `Enter`/`Space` on a focused row toggles its membership in
/// the bound `Set`.
@MainActor
@Suite("List multi-select (Set selection)")
struct ListMultiSelectTests {

    @Test("Enter/Space toggles Set membership on the focused row")
    func toggleMembership() {
        let sink = StringSetSink()
        let handler = ItemListHandler<String>(
            focusID: "ml", itemCount: 3, viewportHeight: 3, selectionMode: .multi)
        handler.itemIDs = ["a", "b", "c"]
        handler.multiSelection = Binding(get: { sink.value }, set: { sink.value = $0 })

        // Focused on index 0 ("a"): Enter selects it.
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(sink.value == ["a"])

        // Move to "c": Space adds it.
        handler.focusedIndex = 2
        _ = handler.handleKeyEvent(KeyEvent(key: .space))
        #expect(sink.value == ["a", "c"])

        // Back to "a": Enter removes it (toggle off).
        handler.focusedIndex = 0
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(sink.value == ["c"])
    }

    @Test("A List with a Set-selection binding renders its rows")
    func setSelectionListRenders() {
        struct Row: Identifiable { let id: Int; let name: String }
        let rows = [Row(id: 1, name: "Alpha"), Row(id: 2, name: "Beta")]
        let text = renderToBuffer(
            List(rows, selection: .constant(Set<Int>())) { Text($0.name) },
            context: makeRenderContext(width: 30, height: 8)
        ).lines.map { $0.stripped }.joined(separator: "\n")
        #expect(text.contains("Alpha"))
        #expect(text.contains("Beta"))
    }
}
