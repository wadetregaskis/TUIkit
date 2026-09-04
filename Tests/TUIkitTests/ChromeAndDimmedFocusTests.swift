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

    /// Renders `view` through fully bracketed render passes and reports both
    /// halves this suite asks about: what ended up in the focus ring, and what
    /// was drawn.
    ///
    /// The `beginRenderPass`/`endRenderPass` pairs are not ceremony. The prune
    /// in `StateStorage.endRenderPass` is exactly how an isolated subtree loses
    /// its `@State` — a single unbracketed render can never show it — so a test
    /// of state survival has to drive at least two passes with the ends run.
    /// Built by hand rather than through `makeRenderContext`, which isolates
    /// the render cache and so diverges from `@State`-driven invalidation.
    private func render(_ view: some View, passes: Int) -> (buffer: FrameBuffer, focusIDs: [String])
    {
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
        var buffer = FrameBuffer()
        for _ in 0..<passes {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        return (buffer, focusManager.registeredFocusIDsInActiveSection())
    }

    private func reachable(_ view: some View) -> [String] {
        render(view, passes: 2).focusIDs
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
        // The probe MOVES its value off the declared default, which is the
        // whole detection: a subtree handed a fresh `StateStorage` (or pruned
        // by `endRenderPass` because the dimmed render did not claim it) draws
        // the default back, and a probe that only ever renders its default
        // cannot tell the two apart.
        let text = render(StatefulProbe().dimmed(), passes: 3)
            .buffer.lines.joined(separator: "\n").stripped
        #expect(text.contains("count-7"), ".dimmed() lost its subtree's @State")
        #expect(!text.contains("count-0"), ".dimmed() re-hydrated its subtree from defaults")
    }

    /// Mutates its `@State` once, on appearing — `recordAppear` runs the action
    /// inline during the render, so pass 1 writes the box and passes 2 and 3
    /// read it back.
    private struct StatefulProbe: View {
        @State private var count = 0
        var body: some View { Text("count-\(count)").onAppear { count = 7 } }
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
