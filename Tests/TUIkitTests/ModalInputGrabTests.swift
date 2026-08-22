//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModalInputGrabTests.swift
//
//  A presented modal takes the keyboard. The focus ring and `onKeyPress` were
//  isolated for the page beneath it from the start; these are the other two
//  channels a page can still be driven through — a `.keyboardShortcut` and a
//  status-bar item — both of which reach the page BEFORE the modal check.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("A modal grabs every key channel, not just the focus ring")
struct ModalInputGrabTests {

    /// A page carrying one of each: a shortcut-bound button and a status-bar
    /// item, with a presentation over it that the caller switches on and off.
    private struct Page: View {
        let presented: Bool
        let onShortcut: () -> Void
        let onStatusItem: () -> Void

        var body: some View {
            VStack {
                Button("Delete", action: onShortcut)
                    .keyboardShortcut("d", modifiers: [])
            }
            .statusBarItems {
                StatusBarItem(shortcut: "n", label: "new", key: .character("n"), action: onStatusItem)
            }
            .modal(isPresented: .constant(presented)) {
                Dialog(title: "D") { Text("body") }
            }
        }
    }

    /// Renders the page and returns a handler wired to the same services, plus
    /// the two counters the page's actions bump.
    private func harness(presented: Bool) -> (InputHandler, () -> Int, () -> Int) {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let shortcuts = Counter()
        let statusItems = Counter()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let statusBar = StatusBarState()
        statusBar.focusManager = focusManager
        environment.statusBar = statusBar
        environment.terminalWidth = 40
        environment.terminalHeight = 20
        environment.overlayContentHeight = 18
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20,
            environment: environment, tuiContext: tui)
        let view = Page(
            presented: presented,
            onShortcut: { shortcuts.value += 1 },
            onStatusItem: { statusItems.value += 1 })

        for _ in 0..<2 {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            tui.keyboardShortcuts.beginRenderPass()
            statusBar.clearSectionItems()
            focusManager.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        let handler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tui.keyEventDispatcher,
            focusManager: focusManager,
            paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
            appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
            keyboardShortcuts: tui.keyboardShortcuts,
            dragAndDropSession: tui.dragAndDropSession,
            onQuit: {}, onSuspend: {})
        return (handler, { shortcuts.value }, { statusItems.value })
    }

    private final class Counter: @unchecked Sendable { var value = 0 }

    @Test("A page's keyboard shortcut does not fire from behind a modal")
    func shortcutIsGrabbed() {
        let (open, firedWhileOpen, _) = harness(presented: true)
        _ = open.handle(KeyEvent(key: .character("d")))
        #expect(firedWhileOpen() == 0, "the page's shortcut ran with a dialog over it")

        // The same key with nothing presented must still work, or the check
        // above passes for the wrong reason.
        let (closed, firedWhileClosed, _) = harness(presented: false)
        _ = closed.handle(KeyEvent(key: .character("d")))
        #expect(firedWhileClosed() == 1, "the page's shortcut stopped working entirely")
    }

    @Test("A page's status-bar item does not fire from behind a modal")
    func statusItemIsGrabbed() {
        let (open, _, firedWhileOpen) = harness(presented: true)
        _ = open.handle(KeyEvent(key: .character("n")))
        #expect(firedWhileOpen() == 0, "the page's status-bar item ran with a dialog over it")

        let (closed, _, firedWhileClosed) = harness(presented: false)
        _ = closed.handle(KeyEvent(key: .character("n")))
        #expect(firedWhileClosed() == 1, "the page's status-bar item stopped working entirely")
    }
}
