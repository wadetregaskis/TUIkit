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

    /// Clicks the cell the page's button occupies — located from a render with
    /// nothing presented — and reports whether the page's action ran.
    private func clickReachesThePage(cover: Bool, presented: Bool) -> Bool {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 40
        environment.terminalHeight = 12
        environment.overlayContentHeight = 12
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12,
            environment: environment, tuiContext: tui)
        let fired = Counter()

        func screen(presenting: Bool) -> FrameBuffer {
            let page = VStack {
                Button("page") { fired.value += 1 }
                Spacer()
            }
            let view =
                cover
                ? AnyView(
                    page.fullScreenCover(isPresented: .constant(presenting)) {
                        VStack { Text("Loading…") }
                    })
                : AnyView(
                    page.modal(isPresented: .constant(presenting)) {
                        Dialog(title: "D") { Text("body") }
                    })
            var buffer = FrameBuffer(lines: [])
            for _ in 0..<2 {
                tui.mouseEventDispatcher.beginRenderPass()
                tui.stateStorage.beginRenderPass()
                tui.renderCache.beginRenderPass()
                focusManager.beginRenderPass()
                buffer = renderToBuffer(view, context: context)
                focusManager.endRenderPass()
                tui.stateStorage.endRenderPass()
            }
            return buffer.compositingOverlays(
                maxWidth: 40, maxHeight: 12, palette: environment.palette)
        }

        // Where the page's button is when nothing covers it. Aiming there is
        // the whole question: with a presentation up, that cell belongs to the
        // presentation (or to nothing), and must not reach the page.
        guard let pageButton = screen(presenting: false).hitTestRegions.first else {
            Issue.record("the page published no region to aim at")
            return false
        }
        let target = (x: pageButton.offsetX + 1, y: pageButton.offsetY)

        let composited = screen(presenting: presented)
        tui.mouseEventDispatcher.setActiveSupport(.full)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        fired.value = 0
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: target.x, y: target.y))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: target.x, y: target.y))
        return fired.value > 0
    }

    @Test("A page behind a presentation cannot be clicked, cover or sheet")
    func pageIsNotClickable() {
        // The sheet case passed all along, but only as a side effect: the root
        // compositor's dimming pass rebuilds the buffer and drops its regions.
        // A cover does not dim, so nothing dropped them and every control under
        // it stayed live — "Loading…" over a page whose buttons still worked.
        for cover in [true, false] {
            let what = cover ? "fullScreenCover" : "modal"
            #expect(
                !clickReachesThePage(cover: cover, presented: true),
                "\(what): a click reached the page's button")
            #expect(
                clickReachesThePage(cover: cover, presented: false),
                "\(what): the page's button stopped working entirely")
        }
    }

    @Test("An app-header control does not answer a click from behind a modal")
    func headerIsGrabbed() {
        // The header is drawn OUTSIDE the composited content area, so nothing
        // the presentation does reaches it: the modifier isolates what it
        // wraps, and the compositor dims what it composites. It was the last
        // channel a page could still be operated through.
        func headerRegionsReachTheDispatcher(presented: Bool) -> Bool {
            let tui = TUIContext()
            let focusManager = FocusManager()
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            environment.terminalWidth = 40
            environment.terminalHeight = 12
            environment.overlayContentHeight = 10
            let header = AppHeaderState()
            environment.appHeader = header
            let context = RenderContext(
                availableWidth: 40, availableHeight: 10,
                environment: environment, tuiContext: tui)
            let view = VStack { Text("page") }
                .appHeader { Button("header") {} }
                .modal(isPresented: .constant(presented)) {
                    Dialog(title: "D") { Text("body") }
                }
            for _ in 0..<2 {
                tui.mouseEventDispatcher.beginRenderPass()
                tui.stateStorage.beginRenderPass()
                tui.renderCache.beginRenderPass()
                focusManager.beginRenderPass()
                _ = renderToBuffer(view, context: context)
                focusManager.endRenderPass()
                tui.stateStorage.endRenderPass()
            }
            // The header publishes its buffer through the environment; whether
            // its regions reach the dispatcher is RenderLoop's decision, and
            // `activeSectionIsModal` is the whole of it.
            // The header publishes its own buffer; whether those regions reach
            // the dispatcher is RenderLoop's decision, and
            // `activeSectionIsModal` is the whole of that decision.
            let published = header.contentBuffer?.hitTestRegions ?? []
            #expect(!published.isEmpty, "precondition: the header drew a clickable control")
            return !published.isEmpty && !focusManager.activeSectionIsModal
        }
        #expect(!headerRegionsReachTheDispatcher(presented: true),
            "the header stayed clickable behind a dialog")
        #expect(headerRegionsReachTheDispatcher(presented: false),
            "the header stopped being clickable entirely")
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
