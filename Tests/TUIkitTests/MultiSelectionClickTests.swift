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

    @Test("A modifier-click through the FULL dispatcher pipeline preserves selection")
    @MainActor
    func modifierClickPreservesThroughPipeline() {
        // The unit tests above call handleClickSelection directly. This drives
        // a real MouseEvent through the dispatcher → container-handler path an
        // actual terminal click takes, confirming the modifier survives every
        // hop (clickCount stamping, region hit-test, event forwarding). iTerm2
        // reports a ⌘-click with the SGR meta bit (the Mouse demo labels it
        // "Alt"), so a ⌘-click there is a meta-click here: it must ADD to the
        // selection and re-anchor, not clear it.
        var selection: Set<String> = ["Row-1", "Row-3"]
        let items = (1...6).map { "Row-\($0)" }
        let view = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            ForEach(items, id: \.self) { Text($0) }
        }
        .frame(height: 8)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 30, availableHeight: 12, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        guard let y = buffer.lines.firstIndex(where: { $0.stripped.contains("Row-5") }) else {
            Issue.record("Row-5 not rendered")
            return
        }
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: y, meta: true))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: y, meta: true))
        #expect(
            selection == ["Row-1", "Row-3", "Row-5"],
            "a meta-click adds the row and keeps the rest: \(selection.sorted())")

        // And a ctrl-click likewise (the other modifier terminals use).
        guard let y2 = buffer.lines.firstIndex(where: { $0.stripped.contains("Row-1") }) else { return }
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: y2, ctrl: true))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: y2, ctrl: true))
        #expect(
            selection == ["Row-3", "Row-5"],
            "a ctrl-click toggles just that row off, keeping the rest: \(selection.sorted())")
    }

    @Test("A modifier dropped on the RELEASE report is recovered from the press")
    @MainActor
    func modifierOnlyOnPressStillToggles() {
        // Defensive contract: a terminal that reports the SGR modifier bit on
        // the button-press (`M`) but NOT on the release (`m`) must not break
        // multi-select. List/Table select on RELEASE, so the release must
        // inherit the press's modifier or the click reads as a bare click —
        // replacing the whole selection instead of toggling one row into it.
        // (Byte captures show both macOS terminals report symmetrically — see
        // Terminal-compatibility.md — so this guards unmeasured terminals.)
        // The dispatcher carries the press's modifiers onto the matching
        // release; without that carry this test fails (selection collapses
        // to just the clicked row).
        var selection: Set<String> = ["Row-1", "Row-3"]
        let items = (1...6).map { "Row-\($0)" }
        let view = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            ForEach(items, id: \.self) { Text($0) }
        }
        .frame(height: 8)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 30, availableHeight: 12, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        guard let y = buffer.lines.firstIndex(where: { $0.stripped.contains("Row-5") }) else {
            Issue.record("Row-5 not rendered")
            return
        }
        // Press carries the modifier; release DROPS it (asymmetric terminal).
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: y, meta: true))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: y, meta: false))
        #expect(
            selection == ["Row-1", "Row-3", "Row-5"],
            "the release inherits the press's modifier and toggles Row-5 in: \(selection.sorted())")
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
