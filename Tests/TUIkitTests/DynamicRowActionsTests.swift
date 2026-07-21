//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DynamicRowActionsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("ForEach onMove / onDelete")
struct DynamicRowActionsTests {

    // MARK: - Action discovery (DynamicViewContentActions)

    @Test("A bare ForEach carries no move / delete action")
    func bareForEachHasNoActions() {
        let forEach = ForEach(["a", "b", "c"], id: \.self) { Text($0) }
        #expect(forEach.moveAction == nil)
        #expect(forEach.deleteAction == nil)
    }

    @Test(".onDelete attaches a delete action reachable through the protocol")
    func onDeleteAttaches() {
        var deleted: IndexSet?
        let forEach = ForEach(["a", "b", "c"], id: \.self) { Text($0) }
            .onDelete { deleted = $0 }
        let actions: DynamicViewContentActions = forEach
        #expect(actions.moveAction == nil)
        actions.deleteAction?(IndexSet(integer: 1))
        #expect(deleted == IndexSet(integer: 1))
    }

    @Test(".onMove attaches a move action reachable through the protocol")
    func onMoveAttaches() {
        var moved: (IndexSet, Int)?
        let forEach = ForEach(["a", "b", "c"], id: \.self) { Text($0) }
            .onMove { moved = ($0, $1) }
        let actions: DynamicViewContentActions = forEach
        #expect(actions.deleteAction == nil)
        actions.moveAction?(IndexSet(integer: 0), 2)
        #expect(moved?.0 == IndexSet(integer: 0))
        #expect(moved?.1 == 2)
    }

    @Test(".onMove and .onDelete chain (both live on ForEach)")
    func chainingBothActions() {
        let forEach = ForEach(0..<3) { Text("\($0)") }
            .onMove { _, _ in }
            .onDelete { _ in }
        #expect(forEach.moveAction != nil)
        #expect(forEach.deleteAction != nil)
    }

    @Test(".onDelete(perform: nil) makes rows non-deletable again")
    func onDeleteNilDisables() {
        let forEach = ForEach(["a"], id: \.self) { Text($0) }
            .onDelete { _ in }
            .onDelete(perform: nil)
        #expect(forEach.deleteAction == nil)
    }

    // MARK: - Delete key in the handler

    private func makeHandler(count: Int) -> ItemListHandler<Int> {
        ItemListHandler<Int>(
            focusID: "list", itemCount: count, viewportHeight: count, selectionMode: .single)
    }

    @Test("Delete on the focused row calls onDelete with that row's offset")
    func deleteKeyDeletesFocusedRow() {
        let handler = makeHandler(count: 5)
        handler.focusedIndex = 2
        var deleted: IndexSet?
        handler.onDelete = { deleted = $0 }

        let consumed = handler.handleKeyEvent(KeyEvent(key: .delete))
        #expect(consumed == true)
        #expect(deleted == IndexSet(integer: 2))
    }

    @Test("Backspace deletes too")
    func backspaceDeletes() {
        let handler = makeHandler(count: 3)
        handler.focusedIndex = 0
        var deleted: IndexSet?
        handler.onDelete = { deleted = $0 }

        #expect(handler.handleKeyEvent(KeyEvent(key: .backspace)) == true)
        #expect(deleted == IndexSet(integer: 0))
    }

    @Test("Deleting the last row clamps focus back onto the new last row")
    func deleteClampsFocus() {
        let handler = makeHandler(count: 4)
        handler.focusedIndex = 3  // last
        handler.onDelete = { _ in }

        _ = handler.handleKeyEvent(KeyEvent(key: .delete))
        // After removing row 3 the data will hold 3 rows (0…2); focus clamps.
        #expect(handler.focusedIndex == 2)
    }

    @Test("Without an onDelete action, Delete falls through (returns false)")
    func deleteInertWhenNotDeletable() {
        let handler = makeHandler(count: 3)
        handler.focusedIndex = 1
        #expect(handler.handleKeyEvent(KeyEvent(key: .delete)) == false)
        #expect(handler.handleKeyEvent(KeyEvent(key: .backspace)) == false)
    }

    // MARK: - End to end through a real editable List

    /// Renders `List { ForEach(items).onDelete { … } }`, focuses it, moves the
    /// cursor, and presses Delete — exercising `_ListCore`'s action discovery
    /// (`content as? DynamicViewContentActions`) and the focus → handler key
    /// route, not just the handler in isolation.
    @Test("An editable List deletes the focused row on Delete (end to end)")
    func listDeleteEndToEnd() {
        final class Box { var items = ["a", "b", "c", "d"] }
        let box = Box()
        let tui = TUIContext()
        let focusManager = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = focusManager
        env.applyRuntimeServices(from: tui)

        func render() {
            let view = List(selection: .constant(String?.none)) {
                ForEach(box.items, id: \.self) { Text($0) }
                    .onDelete { box.items.remove(atOffsets: $0) }
            }
            .focusID("editable-list")
            .frame(height: 8)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 10, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            _ = renderToBuffer(view, context: context)
        }

        render()
        focusManager.focus(id: "editable-list")
        // Move the cursor onto "b" (offset 1), then delete it.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        render()  // re-render so the handler's per-frame state is current
        let consumed = focusManager.dispatchKeyEvent(KeyEvent(key: .delete))
        #expect(consumed == true)
        #expect(box.items == ["a", "c", "d"], "the focused row was removed via onDelete")
    }
}
