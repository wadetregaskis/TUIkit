//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerPayloadAudit.swift
//
//  A rendered buffer carries three things beside its lines, and every container
//  a view can sit in has to pass all three up. Each is lost silently, and each
//  loss reads as an ordinary page:
//
//  * a dropped **animated run** freezes a spinner or a caret — and looks like a
//    performance win while doing it;
//  * a dropped **hit-test region** leaves a control that draws its hover and
//    focus states perfectly and cannot be clicked;
//  * a dropped **overlay** is a `.sheet`, `.alert`, `.popover`, `Picker`
//    drop-down or `.contextMenu` that never reaches the root compositor — for a
//    modal, one that takes the keyboard and then does not appear.
//
//  So this is a standing audit rather than a one-off: put each payload inside
//  each container in turn and require it to come out. `Section` was the
//  container that dropped them — runs first (found by the audit's earlier,
//  runs-only form) and then, for longer, the other two, because fixing the
//  instance did not close the class. That is why the three now share one list.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Container payload propagation")
struct ContainerPayloadAudit {

    private func harness() -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 40
        environment.terminalHeight = 20
        environment.overlayContentHeight = 18
        return (
            tui,
            RenderContext(
                availableWidth: 40, availableHeight: 20,
                environment: environment, tuiContext: tui)
        )
    }

    /// Renders twice — a `ScrollView` reports `extent == viewport` on its first
    /// pass, and a `List` has not built its window yet — and returns the second
    /// buffer, which is the steady state a user ever sees.
    private func render(_ view: some View) -> FrameBuffer {
        let (tui, context) = harness()
        for _ in 0..<2 {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            context.environment.focusManager?.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            context.environment.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        context.environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    // MARK: - The payloads

    /// Leaves one animated run.
    private func blinker() -> some View {
        Text("x").animatedCells([
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1, frames: ["a", "b"], clock: .cursor)
        ])
    }

    /// Leaves one hit-test region.
    private func clickable() -> some View {
        Button("b") {}
    }

    /// Leaves one screen-level overlay.
    private func presenter() -> some View {
        Text("t").modal(isPresented: .constant(true)) {
            Dialog(title: "D") { Text("x") }
        }
    }

    /// Every container a view can sit in, applied to whatever is handed in.
    ///
    /// One list for all three payloads: a container that swallows one is
    /// overwhelmingly likely to swallow the others, which is exactly how
    /// `Section`'s hit regions and overlays outlived the fix to its runs.
    private func containers() -> [(String, (AnyView) -> AnyView)] {
        [
            ("bare", { $0 }),
            ("VStack", { child in AnyView(VStack { child }) }),
            ("HStack", { child in AnyView(HStack { child }) }),
            ("ZStack", { child in AnyView(ZStack { child }) }),
            ("padding", { child in AnyView(child.padding()) }),
            ("border", { child in AnyView(child.border()) }),
            ("background", { child in AnyView(child.background(.blue)) }),
            ("frame", { child in AnyView(child.frame(width: 24, height: 5)) }),
            ("ScrollView", { child in AnyView(ScrollView { child }) }),
            ("Box", { child in AnyView(Box { child }) }),
            ("Section", { child in AnyView(Section("s") { child }) }),
            ("Section with a footer", { child in
                AnyView(Section(content: { child }, header: { Text("h") }, footer: { Text("f") }))
            }),
            ("List", { child in AnyView(List { child }) }),
            ("Form", { child in AnyView(Form { child }) }),
            ("Form of Sections", { child in
                AnyView(Form { Section("s") { child } })
            }),
            ("Group", { child in AnyView(Group { child }) }),
            ("NavigationStack", { child in AnyView(NavigationStack { child }) }),
            ("overlay", { child in AnyView(Text("under").overlay { child }) }),
            ("opacity", { child in AnyView(child.opacity(0.5)) }),
            ("nested stacks", { child in AnyView(VStack { HStack { Box { child } } }) }),
            ("ScrollView in a VStack", { child in AnyView(VStack { ScrollView { child } }) }),
            ("TabView", { child in
                AnyView(TabView(selection: .constant(0)) { Tab("A", value: 0) { child } })
            }),
        ]
    }

    // MARK: - The three audits

    @Test("Every container carries its children's animated runs")
    func containersCarryRuns() {
        for (what, wrap) in containers() {
            let found = render(wrap(AnyView(blinker()))).animatedCells.count
            #expect(found >= 1, "\(what) carried \(found) of 1 run")
        }
    }

    @Test("Every container carries its children's hit-test regions")
    func containersCarryHitRegions() {
        // A control that cannot be clicked still draws its focus ring and its
        // hover lift, so nothing about the screen says the region is missing.
        for (what, wrap) in containers() {
            let found = render(wrap(AnyView(clickable()))).hitTestRegions.count
            #expect(found >= 1, "\(what) carried \(found) of at least 1 region")
        }
    }

    @Test("Every container lets a presented modal float to the root")
    func containersFloatOverlays() {
        // The modal has already taken the keyboard by the time its overlay is
        // dropped, so a container that swallows it leaves the app looking
        // unresponsive rather than looking wrong.
        for (what, wrap) in containers() {
            let overlays = render(wrap(AnyView(presenter()))).overlays
            #expect(
                overlays.contains { $0.level == .modal && $0.centered && $0.dimsBackground },
                "\(what) swallowed the modal's overlay (carried \(overlays.count))")
        }
    }
}
