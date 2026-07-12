//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MultiSelectionKeyboardTests.swift
//
//  The macOS keyboard-selection model for Set-bound Lists/Tables, adapted to
//  terminals: Shift+movement extends the span from the anchor (where the
//  terminal delivers Shift), `v` toggles an extend mode so plain arrows do
//  the same in ANY terminal, Ctrl+A selects all, and Escape — staged — exits
//  extend mode, clears a non-empty selection, and otherwise falls through so
//  a focused list never blocks page navigation. The claim that routes Escape
//  to the list ahead of the page is covered in InputHandlerTests; the
//  render-pass publication in EscapeClaimRenderTests below.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("macOS-style multi-selection keyboard")
struct MultiSelectionKeyboardTests {

    private final class SelectionBox {
        var selection: Set<String> = []
        var binding: Binding<Set<String>> {
            Binding(get: { self.selection }, set: { self.selection = $0 })
        }
    }

    private func makeHandler(
        _ box: SelectionBox, ids: [String] = ["a", "b", "c", "d", "e"]
    ) -> ItemListHandler<String> {
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: ids.count, viewportHeight: ids.count,
            selectionMode: .multi)
        handler.itemIDs = ids
        handler.multiSelection = box.binding
        return handler
    }

    private func click(_ handler: ItemListHandler<String>, at index: Int) {
        handler.handleClickSelection(
            at: index, event: MouseEvent(button: .left, phase: .released, x: 0, y: 0))
    }

    @discardableResult
    private func press(
        _ handler: ItemListHandler<String>, _ key: Key,
        ctrl: Bool = false, shift: Bool = false
    ) -> Bool {
        handler.handleKeyEvent(KeyEvent(key: key, ctrl: ctrl, shift: shift))
    }

    @Test("Shift+arrows extend the span from the anchor and shrink back")
    func shiftArrowExtends() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        click(handler, at: 1)  // anchor at b
        press(handler, .down, shift: true)
        press(handler, .down, shift: true)
        #expect(box.selection == ["b", "c", "d"])
        #expect(handler.focusedIndex == 3)

        // Reversing direction shrinks the span (the anchor stays put).
        press(handler, .up, shift: true)
        #expect(box.selection == ["b", "c"])

        // Crossing the anchor re-pivots to the other side.
        press(handler, .up, shift: true)
        press(handler, .up, shift: true)
        #expect(box.selection == ["a", "b"], "\(box.selection)")
    }

    @Test("The first extension anchors at the pre-move cursor")
    func firstExtensionAnchors() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        press(handler, .down)  // plain move: cursor 1, no selection
        #expect(box.selection.isEmpty)
        press(handler, .down, shift: true)
        #expect(box.selection == ["b", "c"], "anchored where the cursor stood")
    }

    @Test("Shift+Home/End extend to the ends, re-pivoting around the anchor")
    func shiftHomeEndExtend() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        click(handler, at: 2)  // anchor at c
        press(handler, .end, shift: true)
        #expect(box.selection == ["c", "d", "e"])
        #expect(handler.focusedIndex == 4)

        press(handler, .home, shift: true)
        #expect(box.selection == ["a", "b", "c"])
        #expect(handler.focusedIndex == 0)
    }

    @Test("Extension clamps at the ends instead of wrapping")
    func extensionClampsAtEnds() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        click(handler, at: 4)
        press(handler, .down, shift: true)
        #expect(box.selection == ["e"], "no wrap to the top")
        #expect(handler.focusedIndex == 4)
    }

    @Test("`v` extend mode: plain arrows extend, `v` again exits keeping the selection")
    func extendModeWalks() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        press(handler, .down)  // cursor 1
        #expect(press(handler, .character("v")))
        #expect(handler.isExtendingSelection)
        #expect(box.selection == ["b"], "entering selects the cursor row — the mode's feedback")

        press(handler, .down)
        press(handler, .down)
        #expect(box.selection == ["b", "c", "d"])

        #expect(press(handler, .character("v")))
        #expect(!handler.isExtendingSelection)
        press(handler, .down)
        #expect(box.selection == ["b", "c", "d"], "after exiting, arrows move without selecting")
        #expect(handler.focusedIndex == 4)
    }

    @Test("Inside extend mode Shift+arrow keeps its accelerated (multiplier) step")
    func extendModeShiftAccelerates() {
        let box = SelectionBox()
        let ids = (0..<20).map { "r\($0)" }
        let handler = makeHandler(box, ids: ids)

        press(handler, .character("v"))
        press(handler, .down, shift: true)
        #expect(handler.focusedIndex == 5, "the default ×5 multiplier")
        #expect(box.selection == Set(ids[0...5]))
    }

    @Test("Space toggles at the cursor and moves the anchor")
    func spaceToggleAnchors() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        press(handler, .down)
        press(handler, .down)  // cursor 2
        press(handler, .space)
        #expect(box.selection == ["c"])

        press(handler, .down, shift: true)
        #expect(box.selection == ["c", "d"], "extension pivots around the toggled row")
    }

    @Test("Ctrl+A selects all selectable rows")
    func ctrlASelectsAll() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        #expect(press(handler, .character("a"), ctrl: true))
        #expect(box.selection == ["a", "b", "c", "d", "e"])

        // With a selectable subset (headers/footers excluded), only that
        // subset is selected.
        let subsetBox = SelectionBox()
        let subsetHandler = makeHandler(subsetBox)
        subsetHandler.selectableIndices = [1, 2, 3]
        press(subsetHandler, .character("a"), ctrl: true)
        #expect(subsetBox.selection == ["b", "c", "d"])
    }

    @Test("Ctrl+A works through the windowed (lazy idAt) path")
    func ctrlASelectsAllWindowed() {
        let box = SelectionBox()
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: 1000, viewportHeight: 10, selectionMode: .multi)
        handler.idAt = { "row\($0)" }
        handler.multiSelection = box.binding

        press(handler, .character("a"), ctrl: true)
        #expect(box.selection.count == 1000)
        #expect(box.selection.contains("row999"))
    }

    @Test("Escape is staged: exit extend mode, clear the selection, then fall through")
    func escapeStaged() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        press(handler, .character("v"))
        press(handler, .down)
        #expect(box.selection == ["a", "b"])

        #expect(press(handler, .escape), "first press: consumed, exits extend mode")
        #expect(!handler.isExtendingSelection)
        #expect(box.selection == ["a", "b"], "the selection survives leaving the mode")

        #expect(press(handler, .escape), "second press: consumed, clears the selection")
        #expect(box.selection.isEmpty)

        #expect(
            !press(handler, .escape),
            "third press: NOT consumed — it must fall through to page navigation")
    }

    @Test("Single-selection mode is untouched by the multi-selection keys")
    func singleModeUntouched() {
        final class SingleBox {
            var selection: String?
        }
        let box = SingleBox()
        let ids = (0..<10).map { "r\($0)" }
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: ids.count, viewportHeight: ids.count,
            selectionMode: .single)
        handler.itemIDs = ids
        handler.singleSelection = Binding(get: { box.selection }, set: { box.selection = $0 })

        // Shift+arrow keeps its accelerated-move meaning.
        press(handler, .down, shift: true)
        #expect(handler.focusedIndex == 5)
        #expect(box.selection == nil)

        // The multi-selection keys pass through unconsumed.
        #expect(!press(handler, .character("v")))
        #expect(!press(handler, .character("a"), ctrl: true))
        box.selection = "r5"
        #expect(!press(handler, .escape), "Escape falls through even with a single selection")
        #expect(box.selection == "r5")
    }

    @Test("A stale anchor beyond freshly-shrunk data extends without trapping")
    func staleAnchorShrunkData() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        click(handler, at: 4)  // anchor at the last row
        handler.itemIDs = ["a", "b"]
        handler.itemCount = 2  // the async-reload shrink

        press(handler, .up, shift: true)
        #expect(
            box.selection.isSubset(of: ["a", "b"]) && !box.selection.isEmpty,
            "the span is clamped into the shrunken data: \(box.selection)")
    }

    @Test("Clicks and focus loss end extend mode")
    func clicksAndFocusLossEndExtendMode() {
        let box = SelectionBox()
        let handler = makeHandler(box)

        press(handler, .character("v"))
        #expect(handler.isExtendingSelection)
        click(handler, at: 3)
        #expect(!handler.isExtendingSelection, "a click ends the keyboard mode")

        press(handler, .character("v"))
        handler.onFocusLost()
        #expect(!handler.isExtendingSelection, "focus loss ends the mode")
    }
}

// MARK: - Render-pass claim publication

@MainActor
@Suite("Multi-selection Escape claim publication")
struct EscapeClaimRenderTests {

    /// A focused multi-select List with a non-empty selection publishes the
    /// lightweight Escape claim during its render pass; with nothing to
    /// clear it publishes none, leaving page navigation untouched.
    @Test("The focused list claims Escape only while it has something to clear")
    func listPublishesClaimOnlyWithSelection() {
        var selection: Set<String> = []
        let binding = Binding<Set<String>>(get: { selection }, set: { selection = $0 })
        let list = List(selection: binding) {
            ForEach(["one", "two", "three"], id: \.self) { Text($0) }
        }

        let focus = FocusManager()
        let context = makeRenderContext(width: 30, height: 8) { env, _ in
            env.focusManager = focus
        }
        let statusBar = context.environment.statusBar

        func render() {
            // What the RenderLoop's beginRenderPass does for these.
            statusBar.escapeLabelOverride = nil
            statusBar.escapeClaimGrabsInput = true
            focus.beginRenderPass()
            _ = renderToBuffer(list, context: context)
            focus.endRenderPass()
        }

        render()  // registers + auto-focuses the lone focusable
        render()
        #expect(statusBar.escapeLabelOverride == nil, "no selection → no claim")

        selection = ["two"]
        render()
        #expect(statusBar.escapeLabelOverride != nil, "a clearable selection claims ESC")
        #expect(!statusBar.escapeClaimGrabsInput, "the claim is lightweight (no input grab)")

        selection = []
        render()
        #expect(statusBar.escapeLabelOverride == nil, "clearing the selection releases the claim")
    }
}
