//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InfrastructureStateCollisionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// A composite view's `@State` binds by declaration order from index 0 at its
/// identity — and a `Renderable` wrapper that persists its own boxes at the
/// SAME identity used to land on those very keys. Same type and the two
/// aliased one box; different types and the per-frame box swap reset BOTH
/// sides to their defaults every render. Infrastructure slots now live at
/// reserved negative indices (see `StateStorage.StateKey`); this drives a
/// stateful composite view through each wrapper that shares its identity and
/// requires the state to survive.
@MainActor
@Suite("Infrastructure state does not collide with content @State")
struct InfrastructureStateCollisionTests {

    /// Mutates its Int @State once, on appearing. Int deliberately: every
    /// infrastructure slot holds some non-Int box (a focus-id String, a run
    /// state, a handler), so a collision is a TYPE mismatch, and
    /// `storage(for:)` then replaces the box each frame — the mutation is
    /// lost and the count reads 0 again. (A same-type collision is quieter
    /// and worse to pin here: the two sides silently share one box, and the
    /// damage lands on the wrapper's value — a focus id equal to user state —
    /// not on the probe's face.)
    private struct StatefulProbe: View {
        @State private var count = 0
        var body: some View {
            Text("count-\(count)").onAppear { count = 7 }
        }
    }

    private func render(_ view: some View, passes: Int = 3) -> FrameBuffer {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
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
            context.environment.focusManager?.beginRenderPass()
            buffer = renderToBuffer(view, context: context)
            context.environment.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        return buffer
    }

    private func expectStateSurvives(_ view: some View, _ what: Comment) {
        let text = render(view).lines.joined(separator: "\n").stripped
        #expect(text.contains("count-7"), what)
        #expect(!text.contains("count-0"), what)
    }

    @Test("focusable")
    func focusable() {
        expectStateSurvives(
            StatefulProbe().focusable(),
            ".focusable() clobbered the wrapped view's @State")
    }

    @Test("refreshable")
    func refreshable() {
        expectStateSurvives(
            StatefulProbe().refreshable {},
            ".refreshable clobbered the wrapped view's @State")
    }

    @Test("navigationDestination(isPresented:)")
    func navigationPresentation() {
        expectStateSurvives(
            NavigationStack {
                StatefulProbe()
                    .navigationDestination(isPresented: .constant(false)) { Text("d") }
            },
            "navigationDestination(isPresented:) clobbered the wrapped view's @State")
    }

    @Test("userResizable")
    func userResizable() {
        expectStateSurvives(
            // Framed: the resize handles draw on the content's last row and
            // column, and a one-row probe would have its text overlaid.
            StatefulProbe().frame(width: 20, height: 3).userResizable(),
            ".userResizable() clobbered the wrapped view's @State")
    }

    @Test("Toggle's label")
    func toggleLabel() {
        expectStateSurvives(
            Toggle(isOn: .constant(true)) { StatefulProbe() },
            "Toggle clobbered its composite label's @State")
    }
}
