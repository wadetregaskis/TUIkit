//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContextMenuTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("contextMenu")
struct ContextMenuTests {

    // MARK: - Dispatch: right-clicks bubble to an ancestor (the core change)

    @Test("A right-click bubbles past a non-consuming child; a left-click stops")
    func rightClickBubbles() {
        let dispatcher = MouseEventDispatcher()
        var outerFired = false
        let outerID = dispatcher.register { _ in outerFired = true; return true }
        let innerID = dispatcher.register { _ in false }  // never consumes
        // Inner region registered LAST → checked FIRST (dispatch's outside-in
        // order); both cover the same cell.
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: outerID),
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: innerID),
        ])

        // Right-click: inner returns false → BUBBLES → outer fires.
        _ = dispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 5, y: 5))
        #expect(outerFired == true, "the right-click bubbled past the inner region")

        // Left-click: inner returns false → STOPS at the first region (no bubble).
        outerFired = false
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 5, y: 5))
        #expect(outerFired == false, "a left click does not bubble")
    }

    // MARK: - Harness

    private func context(_ tui: TUIContext, focusManager: FocusManager) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
    }

    /// Renders `view` and arms the mouse dispatcher with the resulting regions.
    private func renderArmed(
        _ view: some View, tui: TUIContext, focusManager: FocusManager, context: RenderContext
    ) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    /// The modifier's persisted state box (it renders at the root identity).
    private func menuState(_ tui: TUIContext, _ context: RenderContext) -> ContextMenuState {
        tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: ContextMenuState()
        ).value
    }

    private func targetView() -> some View {
        Text("Right-click me").contextMenu {
            Button("Cut") {}
            Button("Copy") {}
        }
    }

    // MARK: - Trigger

    @Test("A right-click opens the menu at the click cell")
    func rightClickOpens() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        let view = targetView()

        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .released, x: 3, y: 0))

        let state = menuState(tui, context)
        #expect(state.isOpen == true)
        #expect(state.anchorX == 3 && state.anchorY == 0, "the menu anchors at the click cell")

        // Re-render: the open menu floats as a popover overlay.
        let opened = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        #expect(!opened.overlays.isEmpty, "the open menu renders a popover overlay")
    }

    @Test("The menu hugs its widest item — a Divider does not stretch it to the screen")
    func menuHugsItsContent() throws {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        // A separator is the case that broke: `Divider` measures as one cell but
        // renders at whatever width it is offered, and a VStack takes its width
        // from what its children DREW — so a menu laid out against the screen
        // came back screen-wide, however short its items.
        let view = Text("Right-click me").contextMenu {
            Button("Cut") {}
            Button("Copy") {}
            Divider()
            Button("Delete") {}
        }
        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .released, x: 3, y: 0))
        let opened = renderArmed(view, tui: tui, focusManager: focusManager, context: context)

        let popover = try #require(opened.overlays.first).content
        #expect(
            popover.width < context.availableWidth,
            """
            the menu must hug its items, not fill the terminal — got \(popover.width) \
            of \(context.availableWidth) cells for "Cut"/"Copy"/"Delete"
            """)
        // …and the separator still spans the menu's own interior.
        let rule = try #require(popover.lines.first { $0.stripped.contains("─") && !$0.stripped.contains("╭") })
        #expect(rule.strippedLength == popover.width, "the divider fills the menu's width")
    }

    @Test("Items render as menu rows, not as buttons")
    func itemsRenderAsMenuRows() throws {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        let view = targetView()
        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .released, x: 3, y: 0))
        let opened = renderArmed(view, tui: tui, focusManager: focusManager, context: context)

        let popover = try #require(opened.overlays.first).content
        let rows = popover.lines.map(\.stripped).filter { $0.contains("Cut") || $0.contains("Copy") }
        #expect(rows.count == 2, "both items render")
        for row in rows {
            // The default button chrome is half-block caps around the label; a
            // menu row is the bare label on a highlight bar.
            #expect(
                !row.contains("▐") && !row.contains("▌") && !row.contains("["),
                "a menu row carries no button chrome, got \(row.debugDescription)")
        }
    }

    @Test("Ctrl-click opens the menu (fallback where right-click is swallowed)")
    func ctrlClickOpens() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        let view = targetView()

        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: 0, ctrl: true))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: 0, ctrl: true))
        #expect(menuState(tui, context).isOpen == true)
    }

    @Test("A plain left-click does NOT open the menu")
    func leftClickDoesNotOpen() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        let view = targetView()

        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 0))
        #expect(menuState(tui, context).isOpen == false)
    }

    @Test("Closed, no popover overlay is drawn")
    func closedHasNoOverlay() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        let buffer = renderArmed(targetView(), tui: tui, focusManager: focusManager, context: context)
        #expect(buffer.overlays.isEmpty)
    }

    // MARK: - Dismiss

    @Test("Escape dismisses an open menu and restores the page's focus section")
    func escapeDismisses() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        let view = targetView()

        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 1, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .released, x: 1, y: 0))
        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)  // open frame
        #expect(menuState(tui, context).isOpen == true)

        // Escape reaches the menu's registered key handler.
        _ = tui.keyEventDispatcher.dispatch(KeyEvent(key: .escape))
        #expect(menuState(tui, context).isOpen == false)

        // The next (closed) render tears the menu's focus section down.
        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        #expect(
            focusManager.section(id: "contextmenu-\(context.identity.path)") == nil,
            "the menu's focus section is removed when it closes")
    }

    // MARK: - Measure isolation

    @Test("Measuring the modifier opens nothing and registers no section")
    func measureIsolation() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        _ = measureChild(
            targetView(), proposal: ProposedSize(width: 40, height: 3), context: context)
        #expect(menuState(tui, context).isOpen == false, "a measure never opens the menu")
        #expect(
            focusManager.section(id: "contextmenu-\(context.identity.path)") == nil,
            "a measure registers no focus section")
    }

    // MARK: - Button auto-dismiss compose (dismissMenu)

    @Test("A Button inside a menu runs its action AND closes the menu")
    func buttonDismissesMenu() {
        let tui = TUIContext()
        var ran = false
        var dismissed = false
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.dismissMenu = DismissMenuAction { dismissed = true }
        let context = RenderContext(
            availableWidth: 20, availableHeight: 1, environment: environment, tuiContext: tui)

        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        let buffer = renderToBuffer(Button("Go") { ran = true }, context: context)
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: 0))

        #expect(ran == true, "the button's action ran")
        #expect(dismissed == true, "and the enclosing menu was told to close")
    }

    @Test("A Button OUTSIDE any menu runs its action without dismissing (nil-safe)")
    func buttonWithoutMenuIsNilSafe() {
        let tui = TUIContext()
        var ran = false
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        // No dismissMenu in scope.
        let context = RenderContext(
            availableWidth: 20, availableHeight: 1, environment: environment, tuiContext: tui)

        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        let buffer = renderToBuffer(Button("Go") { ran = true }, context: context)
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        #expect(ran == true, "the button still works with no menu to dismiss")
    }

    // MARK: - The open menu owns the keyboard

    /// The composition the owner hit: a page with BOTH a combo `Menu` and a
    /// context-menu target. `Menu` registers a global arrow handler that answers
    /// `true` to Up/Down unconditionally, and a context menu hangs off a leaf, so
    /// it cannot isolate its siblings the way a root-attached modal can. The
    /// arrows moved the combo menu's selection instead of the open pop-up — while
    /// Tab, which goes through the focus system and WAS captured, worked.
    @Test("An open context menu takes the arrows from a sibling Menu")
    func openMenuOwnsTheArrows() {
        final class Selection { var index = 0 }
        let selection = Selection()
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        // Leading-aligned so the target's cells are where the click aims.
        let page = VStack(alignment: .leading) {
            // A greedy sibling: an `.onKeyPress` handler that answers Down
            // unconditionally, wherever it sits in the tree. `Menu`'s own
            // arrow handler used to be exactly this.
            Text("Somewhere else on the page")
                .onKeyPress { event in
                    guard event.key == .down else { return false }
                    selection.index += 1
                    return true
                }
            Text("Right-click me").contextMenu {
                Button("Cut") {}
                Button("Copy") {}
            }
        }

        _ = renderArmed(page, tui: tui, focusManager: focusManager, context: context)
        // The Menu's handler is live while nothing is presented.
        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .down)))
        #expect(selection.index == 1, "sanity: the sibling does follow Down normally")

        // Open the context menu by right-clicking the Text, then re-render so the
        // pop-up is up and the grab is in force.
        let first = renderArmed(page, tui: tui, focusManager: focusManager, context: context)
        let targetRow = first.lines.firstIndex { $0.stripped.contains("Right-click me") } ?? 0
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .right, phase: .pressed, x: 3, y: targetRow))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .right, phase: .released, x: 3, y: targetRow))
        let opened = renderArmed(page, tui: tui, focusManager: focusManager, context: context)
        #expect(!opened.overlays.isEmpty, "sanity: the pop-up is actually up")

        let before = selection.index
        _ = tui.keyEventDispatcher.dispatch(KeyEvent(key: .down))
        #expect(
            selection.index == before,
            """
            with the pop-up up, Down must not reach the sibling handler behind it \
            (was \(before), now \(selection.index))
            """)
    }

    /// The open menu holds the focus and the keyboard, so it has to say so —
    /// but on its whole FRAME, not with the top-border ● that a titled
    /// container uses. A context menu has no title, and a lone dot floating in
    /// an otherwise dead frame reads as debris rather than as focus.
    @Test("The open menu's border pulses, and shows no ● where a title would go")
    func openMenuBorderPulses() throws {
        /// The presented menu, rendered at a given point in the pulse cycle.
        func popup(pulsePhase: Double) -> FrameBuffer? {
            let tui = TUIContext()
            let focusManager = FocusManager()
            var context = context(tui, focusManager: focusManager)
            context.environment.pulsePhase = pulsePhase
            let view = targetView()

            _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .right, phase: .released, x: 3, y: 0))
            return renderArmed(view, tui: tui, focusManager: focusManager, context: context)
                .overlays.first?.content
        }

        let dim = try #require(popup(pulsePhase: 0))
        let bright = try #require(popup(pulsePhase: 1))
        #expect(
            !dim.lines.contains { $0.stripped.contains("●") },
            """
            an untitled menu shows nothing in its top border: \
            \(dim.lines.map(\.stripped).joined(separator: "\n"))
            """)
        // The colour, not the glyphs: the frame is the same box either way.
        #expect(
            dim.lines.map(\.stripped) == bright.lines.map(\.stripped),
            "the pulse must not move any glyph")
        #expect(
            dim.lines[0] != bright.lines[0],
            "…only recolour the border, which must breathe: \(dim.lines[0].debugDescription)")
    }

    /// The measure pass has to see the shortcuts too, or the menu is sized for
    /// the labels alone and the render then has to eat into them to fit the
    /// hints. (`⌘X` resolves to Ctrl-X here — see `CommandKeyBinding`.)
    @Test("Menu rows print their key equivalents in an aligned trailing column")
    func rowsPrintTheirShortcuts() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        let view = Text("Right-click me").contextMenu {
            Button("Cut") {}.keyboardShortcut("x")
            Button("Duplicate") {}.keyboardShortcut("v")
        }

        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .right, phase: .released, x: 3, y: 0))
        let opened = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        let lines = (opened.overlays.first?.content.lines ?? []).map(\.stripped)
        let rendered = lines.joined(separator: "\n")

        let cut = try? #require(lines.first { $0.contains("Cut") })
        let duplicate = try? #require(lines.first { $0.contains("Duplicate") })
        #expect(cut?.contains("^X") == true, "the shortcut is printed:\n\(rendered)")
        #expect(duplicate?.contains("^V") == true, "…on every row:\n\(rendered)")
        // Aligned: each row pads its own label so the hints share a column,
        // and the longest label is intact rather than squeezed by its hint.
        #expect(
            cut?.range(of: "^X")?.lowerBound.utf16Offset(in: cut ?? "")
                == duplicate?.range(of: "^V")?.lowerBound.utf16Offset(in: duplicate ?? ""),
            "the hints line up in one column:\n\(rendered)")
    }

    @Test("Shift+F10 opens the menu on the focused target")
    func keyboardOpens() {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let context = context(tui, focusManager: focusManager)
        let view = targetView()

        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        // The target is a focus stop, so Tab can reach it — without that there
        // is no keyboard route to a menu at all.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .tab))
        let state = menuState(tui, context)
        #expect(state.isOpen == false, "sanity: focusing alone does not open it")

        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .f10, shift: true)))
        #expect(state.isOpen == true, "Shift+F10 on the focused target opens the menu")

        // Plain F10 is somebody else's business.
        state.isOpen = false
        _ = renderArmed(view, tui: tui, focusManager: focusManager, context: context)
        #expect(!tui.keyEventDispatcher.dispatch(KeyEvent(key: .f10)))
        #expect(state.isOpen == false)
    }
}
