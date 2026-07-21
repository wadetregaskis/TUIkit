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
}
