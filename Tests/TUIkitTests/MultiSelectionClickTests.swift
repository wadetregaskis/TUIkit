//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MultiSelectionClickTests.swift
//
//  macOS mouse-selection semantics for Set-bound Lists/Tables: a plain click
//  makes the clicked row the SOLE selection, shift-click selects the range
//  from the anchor, and ctrl-/option-click toggles rows individually (the
//  command key never reaches a terminal, so both reportable modifiers stand
//  in for it). Keyboard Space keeps its toggle-at-focus behaviour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("macOS-style multi-selection clicks")
struct MultiSelectionClickTests {

    private final class SelectionBox {
        var selection: Set<String> = []
        var binding: Binding<Set<String>> {
            Binding(get: { self.selection }, set: { self.selection = $0 })
        }
    }

    private func makeHandler(_ box: SelectionBox) -> ItemListHandler<String> {
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: 5, viewportHeight: 5, selectionMode: .multi)
        handler.itemIDs = ["a", "b", "c", "d", "e"]
        handler.multiSelection = box.binding
        return handler
    }

    private func click(
        _ handler: ItemListHandler<String>, at index: Int,
        shift: Bool = false, ctrl: Bool = false, meta: Bool = false
    ) {
        handler.handleClickSelection(
            at: index,
            event: MouseEvent(
                button: .left, phase: .released, x: 0, y: 0,
                shift: shift, ctrl: ctrl, meta: meta))
    }

    @Test("A plain click makes the clicked row the sole selection")
    func plainClickReplaces() {
        let box = SelectionBox()
        box.selection = ["a", "d"]
        let handler = makeHandler(box)

        click(handler, at: 1)
        #expect(box.selection == ["b"], "plain click replaces the whole selection")
        #expect(handler.focusedIndex == 1)
    }

    @Test("Shift-click selects the range from the anchor")
    func shiftClickRange() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        click(handler, at: 1)  // anchor at b
        click(handler, at: 3, shift: true)
        #expect(box.selection == ["b", "c", "d"], "anchor..clicked span selected")

        // Re-pivoting around the SAME anchor (Finder behaviour).
        click(handler, at: 0, shift: true)
        #expect(box.selection == ["a", "b"], "shift-click re-pivots around the original anchor")
    }

    @Test("Ctrl- and option-click toggle rows individually")
    func modifierClickToggles() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        click(handler, at: 0)
        click(handler, at: 2, ctrl: true)
        #expect(box.selection == ["a", "c"], "ctrl-click adds without clearing")

        click(handler, at: 0, meta: true)
        #expect(box.selection == ["c"], "option-click toggles an already-selected row off")
    }

    @Test("A toggle-click moves the range anchor")
    func toggleMovesAnchor() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        click(handler, at: 0)
        click(handler, at: 2, ctrl: true)  // anchor now at c
        click(handler, at: 4, shift: true)
        #expect(box.selection == ["c", "d", "e"], "range extends from the toggled anchor")
    }

    @Test("Single-selection mode keeps its click-to-toggle behaviour")
    func singleModeUnchanged() {
        final class SingleBox {
            var selection: String?
        }
        let box = SingleBox()
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: 3, viewportHeight: 3, selectionMode: .single)
        handler.itemIDs = ["a", "b", "c"]
        handler.singleSelection = Binding(get: { box.selection }, set: { box.selection = $0 })

        click(handler, at: 1)
        #expect(box.selection == "b")
        click(handler, at: 1)
        #expect(box.selection == nil, "clicking the selected row again deselects (existing behaviour)")
    }
}
