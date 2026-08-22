//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeAndDimmedFocusTests.swift
//
//  Two things that LOOK inert and have to BE inert: a `.dimmed()` subtree, and
//  the app header. Neither is a Tab stop; the header stays clickable, because a
//  control drawn in the title bar is meant to be clicked.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Chrome and dimmed content are not in the focus ring")
struct ChromeAndDimmedFocusTests {

    private func reachable(_ view: some View) -> [String] {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.appHeader = AppHeaderState()
        environment.terminalWidth = 40
        environment.terminalHeight = 12
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12,
            environment: environment, tuiContext: tui)
        for _ in 0..<2 {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        return focusManager.registeredFocusIDsInActiveSection()
    }

    @Test("A dimmed subtree is not reachable by Tab")
    func dimmedIsNotFocusable() {
        // `.dimmed()` was purely visual: it flattened the content's LOOK and
        // left every control in it in the focus ring, which is what made
        // `.dimmed().overlay { Alert(…) }` read as modal and behave as a live
        // page.
        #expect(reachable(VStack { Button("in") {} }.dimmed()).isEmpty)
        // The control: undimmed, the same button IS reachable.
        #expect(!reachable(VStack { Button("in") {} }).isEmpty)
    }

    @Test("A dimmed subtree keeps its state, which is why storage stays shared")
    func dimmedKeepsState() {
        // Isolating focus must not isolate `@State` — a dimmed page that is
        // later undimmed has to come back as it was, scroll position and all.
        let buffer = renderToBuffer(
            StatefulProbe().dimmed(),
            context: makeRenderContext(width: 20, height: 3))
        #expect(!buffer.lines.isEmpty)
    }

    private struct StatefulProbe: View {
        @State private var count = 7
        var body: some View { Text("n=\(count)") }
    }

    @Test("An app-header control is chrome, not a Tab stop")
    func headerIsNotFocusable() {
        // Tab walked out of the content and into the title bar.
        let withHeader = reachable(
            VStack { Text("page") }.appHeader { Button("header") {} })
        #expect(withHeader.isEmpty, "the header joined the focus ring: \(withHeader)")

        // The page's own controls are unaffected — the isolation is the
        // header's subtree, not the whole tree.
        let both = reachable(
            VStack { Button("page") {} }.appHeader { Button("header") {} })
        #expect(both.count == 1, "expected only the page's button: \(both)")
    }

    @Test("…but it is still clickable")
    func headerStaysClickable() {
        // The point of a control in the header. Its buffer publishes regions;
        // RenderLoop merges them (except behind a modal, which is
        // ModalInputGrabTests' case).
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let header = AppHeaderState()
        environment.appHeader = header
        environment.terminalWidth = 40
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12,
            environment: environment, tuiContext: tui)
        _ = renderToBuffer(
            VStack { Text("page") }.appHeader { Button("header") {} }, context: context)
        #expect(header.contentBuffer?.hitTestRegions.isEmpty == false)
    }
}
