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
            ("Grid", { child in AnyView(Grid { GridRow { child } }) }),
            ("LazyVStack", { child in AnyView(ScrollView { LazyVStack { child } }) }),
            ("DisclosureGroup", { child in
                AnyView(DisclosureGroup("g", isExpanded: .constant(true)) { child })
            }),
            ("NavigationSplitView", { child in
                AnyView(NavigationSplitView(sidebar: { child }, detail: { Text("d") }))
            }),
            // A control's LABEL is a full view slot, and `_ControlLabel` rebuilt
            // its buffer by hand — so this is the same question `Section` failed.
            ("a Slider's label", { child in
                AnyView(Slider(value: .constant(0.5), in: 0...1, label: { child }))
            }),
            ("a Stepper's label", { child in
                AnyView(Stepper(value: .constant(5), in: 0...10, label: { child }))
            }),
            ("a Dialog's footer", { child in
                AnyView(Dialog(title: "d", content: { Text("c") }, footer: { child }))
            }),
        ]
    }

    // MARK: - The three audits

    /// Something with no payload of its own, to measure the container against.
    ///
    /// The count has to be a DIFFERENCE: several of these containers carry
    /// payload of their own — a `Slider` publishes its track's hit region
    /// whether or not its label has one — so "at least one came out" passes
    /// while the child's is being dropped. That is exactly how a `Slider`
    /// label's overlay stayed lost.
    private func inert() -> some View { Text("x") }

    @Test("Every container carries its children's animated runs")
    func containersCarryRuns() {
        for (what, wrap) in containers() {
            let base = render(wrap(AnyView(inert()))).animatedCells.count
            let found = render(wrap(AnyView(blinker()))).animatedCells.count
            #expect(found > base, "\(what) dropped the child's run (\(base) → \(found))")
        }
    }

    @Test("Every container carries its children's hit-test regions")
    func containersCarryHitRegions() {
        // A control that cannot be clicked still draws its focus ring and its
        // hover lift, so nothing about the screen says the region is missing.
        for (what, wrap) in containers() {
            let base = render(wrap(AnyView(inert()))).hitTestRegions.count
            let found = render(wrap(AnyView(clickable()))).hitTestRegions.count
            #expect(found > base, "\(what) dropped the child's region (\(base) → \(found))")
        }
    }

    @Test("A disabled container still lets a presentation float to the root")
    func disabledContainersFloatOverlays() {
        // Disabling a container is a statement about INTERACTION. It is not a
        // reason to stop compositing, and the presentation does not know it has
        // happened — it activates its focus section and grabs the keyboard
        // either way, so a swallowed overlay is an invisible dialog holding the
        // app rather than a dialog that politely declined to appear.
        //
        // `List` had exactly that: its row-overlay carry lived inside the
        // mouse-handler attachment, which returns early for a disabled list, so
        // every row's presentation was dropped — visible rows included.
        for (what, wrap) in containers() {
            let overlays = render(wrap(AnyView(presenter())).disabled(true)).overlays
            #expect(
                overlays.contains { $0.level == .modal && $0.centered && $0.dimsBackground },
                "\(what), disabled, swallowed the modal's overlay")
        }
    }

    @Test("A disabled List still floats a presentation from a row")
    func disabledListFloatsRowOverlays() {
        // The specific shape, pinned separately from the sweep above because
        // the sweep does not reach it: `List`'s row-overlay carry lived inside
        // its mouse-handler attachment, which returns early for a disabled
        // list. So every row's presentation was dropped — visible rows
        // included, no scrolling involved — while the presentation went on
        // activating its focus section and grabbing the keyboard.
        // Written WITHOUT the `AnyView` the sweep's container list needs: the
        // erasure changes when `List` resolves `@Environment(\.isDisabled)`,
        // so an erased list does not see the flag and the case silently stops
        // testing anything. That is why this is a test of its own.
        let direct = render(List { presenter() }.disabled(true)).overlays
        #expect(
            direct.contains { $0.level == .modal },
            "a disabled List swallowed its row's dialog")

        let rows = render(
            List { ForEach([1], id: \.self) { _ in presenter() } }.disabled(true)
        ).overlays
        #expect(
            rows.contains { $0.level == .modal },
            "a disabled List of ForEach rows swallowed its row's dialog")
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
