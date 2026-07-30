//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyboardRowMoveTests.swift
//
//  Reordering rows without a mouse: Ctrl-R picks the focused row up, the
//  movement keys move its landing slot, Return places it and Escape puts it
//  back. The mode exists because the obvious alternative — a modifier with the
//  arrow keys — is dead on Apple Terminal, which strips modifiers from Up/Down.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Keyboard row move")
struct KeyboardRowMoveTests {

    /// A handler over five rows, wired the way a render wires one.
    private func makeHandler(
        _ rows: RowBox, feedback: RowReorderFeedback = .live, reorderable: Bool = true
    ) -> ItemListHandler<String> {
        let handler = ItemListHandler<String>(
            focusID: "list", itemCount: rows.items.count, viewportHeight: 5,
            selectionMode: .single)
        handler.reorderFeedback = feedback
        handler.canFloatDraggedRow = true
        if reorderable {
            handler.onMove = { offsets, destination in
                rows.items.move(fromOffsets: offsets, toOffset: destination)
                handler.itemCount = rows.items.count
            }
        }
        return handler
    }

    /// The rows, in a reference type so `onMove` (which fires later, from a key
    /// event) writes back into the same array the assertions read.
    @MainActor
    private final class RowBox {
        var items = ["a", "b", "c", "d", "e"]
    }

    private func press(_ handler: ItemListHandler<String>, _ key: Key, ctrl: Bool = false) -> Bool {
        handler.handleKeyEvent(KeyEvent(key: key, ctrl: ctrl))
    }

    private func pickUp(_ handler: ItemListHandler<String>) -> Bool {
        press(handler, .character("r"), ctrl: true)
    }

    // MARK: - The gesture

    @Test("Pick up, move down twice, place")
    func moveDown() {
        let rows = RowBox()
        let handler = makeHandler(rows)
        #expect(pickUp(handler))
        #expect(press(handler, .down))
        #expect(press(handler, .down))
        #expect(press(handler, .enter))
        #expect(rows.items == ["b", "c", "a", "d", "e"])
        #expect(!handler.isKeyboardMove, "and the row is out of hand")
    }

    @Test("Escape puts the row back where it was picked up")
    func escapeRestores() {
        let rows = RowBox()
        let handler = makeHandler(rows)
        handler.focusedIndex = 1
        #expect(pickUp(handler))
        #expect(press(handler, .down))
        #expect(press(handler, .down))
        #expect(press(handler, .escape))
        #expect(rows.items == ["a", "b", "c", "d", "e"])
        #expect(handler.focusedIndex == 1, "…and the cursor goes back with it")
    }

    /// Home/End/Page are what make a long move cheap: pick up, End, Return —
    /// rather than two hundred presses of Down.
    @Test("Home and End move the slot the whole way")
    func homeAndEnd() {
        let rows = RowBox()
        let handler = makeHandler(rows)
        handler.focusedIndex = 2
        #expect(pickUp(handler))
        #expect(press(handler, .end))
        #expect(press(handler, .enter))
        #expect(rows.items == ["a", "b", "d", "e", "c"])

        #expect(pickUp(handler))
        #expect(press(handler, .home))
        #expect(press(handler, .enter))
        #expect(rows.items.first == "c")
    }

    @Test("Ctrl-R again places the row — the pick-up key is a toggle")
    func pickUpTogglesPlace() {
        let rows = RowBox()
        let handler = makeHandler(rows)
        #expect(pickUp(handler))
        #expect(press(handler, .down))
        #expect(pickUp(handler))
        #expect(!handler.isKeyboardMove)
        #expect(rows.items == ["b", "a", "c", "d", "e"])
    }

    @Test("A list with no onMove ignores the key entirely")
    func withoutOnMove() {
        let rows = RowBox()
        let handler = makeHandler(rows, reorderable: false)
        #expect(!pickUp(handler), "unhandled, so an app binding on Ctrl-R still works")
        #expect(!handler.isKeyboardMove)
    }

    /// Focus can leave at any time — Tab, a click elsewhere — and the keys that
    /// would place the row go with it.
    @Test("Losing focus abandons the move")
    func focusLossCancels() {
        let rows = RowBox()
        let handler = makeHandler(rows)
        #expect(pickUp(handler))
        #expect(press(handler, .down))
        handler.onFocusLost()
        #expect(!handler.isKeyboardMove)
        #expect(rows.items == ["a", "b", "c", "d", "e"], "put back, not left half-moved")
    }

    // MARK: - Feedback

    /// `.live` moves the data as the keys go (one `onMove` per step, as a live
    /// drag does); the slot modes leave it alone until the drop.
    @Test("Live feedback moves the data per keystroke; the slot modes do not")
    func feedbackDecidesWhenTheDataMoves() {
        let live = RowBox()
        let liveHandler = makeHandler(live, feedback: .live)
        #expect(pickUp(liveHandler))
        #expect(press(liveHandler, .down))
        #expect(live.items == ["b", "a", "c", "d", "e"], "already moved, mid-gesture")

        let dimmed = RowBox()
        let dimmedHandler = makeHandler(dimmed, feedback: .dimmed)
        #expect(pickUp(dimmedHandler))
        #expect(press(dimmedHandler, .down))
        #expect(dimmed.items == ["a", "b", "c", "d", "e"], "not yet — the slot moved")
        #expect(dimmedHandler.reorderPlaceholder?.slot == 1)
        #expect(press(dimmedHandler, .enter))
        #expect(dimmed.items == ["b", "a", "c", "d", "e"], "…now")
    }

    /// `.cursor` puts the row on the pointer, and a keyboard move has no
    /// pointer — so it shows what `.dimmed` shows instead of an empty gap and a
    /// row that is nowhere.
    @Test("Cursor feedback falls back to dimmed for a keyboard move")
    func cursorFallsBackForKeyboardMoves() {
        let rows = RowBox()
        let handler = makeHandler(rows, feedback: .cursor)
        #expect(handler.effectiveReorderFeedback == .cursor, "…while nothing is moving")
        #expect(pickUp(handler))
        #expect(handler.effectiveReorderFeedback == .dimmed)
        #expect(handler.reorderFloatingRow == nil, "nothing rides a pointer that isn't there")
    }

    /// The same fallback where there is no drag session to draw a floating row
    /// above the frame — a mouse drag in that build would otherwise show a gap
    /// and no row at all.
    @Test("Cursor feedback falls back to dimmed when no row can be floated")
    func cursorFallsBackWithoutADragSession() {
        let rows = RowBox()
        let handler = makeHandler(rows, feedback: .cursor)
        handler.canFloatDraggedRow = false
        #expect(handler.effectiveReorderFeedback == .dimmed)
    }

    // MARK: - The rest of the grammar

    /// The mode is safe to be in because nothing else changes meaning: a key it
    /// does not claim keeps its own, and the row stays in hand.
    @Test("An unclaimed key keeps its meaning and the row stays held")
    func unclaimedKeysFallThrough() {
        let rows = RowBox()
        let handler = makeHandler(rows)
        #expect(pickUp(handler))
        #expect(!press(handler, .tab), "Tab still moves focus onward")
        #expect(handler.isKeyboardMove)
    }

    /// Escape has to be CLAIMED, not merely handled: `InputHandler` routes a
    /// claimed Escape through the focus system before the status bar or a
    /// page-level handler, and without the claim the example app's "⎋ back"
    /// navigated out of the page mid-move. Only a render publishes it, which is
    /// why no amount of handler-level testing caught it.
    @Test("A held row claims Escape, and says so in the status bar")
    func heldRowClaimsEscape() {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        // Its own status bar: the default is a shared instance, so a parallel
        // test's claim ("close menu") leaks into this one's first assertion.
        env.statusBar = StatusBarState()
        let context = RenderContext(
            availableWidth: 20, availableHeight: 8, environment: env, tuiContext: tui)

        var items = ["a", "b", "c"]
        let view = List {
            ForEach(items, id: \.self) { Text($0) }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
        }
        env.focusManager?.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        env.focusManager?.endRenderPass()
        #expect(context.environment.statusBar.escapeLabelOverride == nil, "nothing held yet")

        #expect(env.focusManager?.dispatchKeyEvent(KeyEvent(key: .character("r"), ctrl: true)) == true)
        env.focusManager?.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        env.focusManager?.endRenderPass()
        #expect(context.environment.statusBar.escapeLabelOverride == "cancel move")
    }

    @Test("The pick-up chord is rebindable like any other")
    func rebindable() {
        let rows = RowBox()
        let handler = makeHandler(rows)
        handler.shortcuts = RowShortcuts([.pickUpRow: [KeyboardShortcut("g", modifiers: .control)]])
            .lookup(commandKey: .control)
        #expect(!pickUp(handler), "Ctrl-R was rebound away")
        #expect(press(handler, .character("g"), ctrl: true))
        #expect(handler.isKeyboardMove)
    }
}
