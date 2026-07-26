//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DialogMeasuresRenderedTreeTests.swift
//
//  A dialog must be sized from the tree it actually renders.
//
//  `ContainerView.scrollableBody` renders its body inside an always-present
//  `ScrollView` but used to MEASURE the body bare. The ScrollView adds identity
//  components, and `@State` binds by identity — so the measure resolved every
//  `@State` in the body to a *different* box than the render, and therefore saw
//  every one of them at its INITIAL value. A body that had grown since (a
//  colour picker switched to its 256-swatch tab, a disclosure opened) was
//  measured at its original size, so the dialog was built too short and scrolled
//  its content even with most of the screen still free.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A dialog is sized from the tree it renders")
struct DialogMeasuresRenderedTreeTests {

    /// A body that grows on its first appearance: 3 rows initially, 25 after.
    /// The growth lives in `@State`, so a measure that binds state to the wrong
    /// identity keeps reporting the initial 3 rows forever.
    private struct GrowingBody: View {
        @State private var grown = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("HEADER")
                ForEach(0..<(grown ? 24 : 2), id: \.self) { Text("row \($0)") }
            }
            .onAppear { grown = true }
        }
    }

    private func render(tui: TUIContext, height: Int) -> [String] {
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = focus
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: height, environment: env, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(Dialog(title: "T") { GrowingBody() }, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map(\.stripped)
    }

    @Test("A body that grew is measured at its grown size, not its initial one")
    func grownBodyIsMeasuredGrown() {
        let tui = TUIContext()
        // Ample height: 25 body rows plus chrome fit easily in 40.
        _ = render(tui: tui, height: 40)  // frame 1: .onAppear grows it
        let lines = render(tui: tui, height: 40)  // frame 2: renders grown

        #expect(
            lines.contains { $0.contains("row 23") },
            "the whole grown body is visible:\n\(lines.joined(separator: "\n"))")
        #expect(
            !lines.contains { $0.contains("more line") },
            """
            The dialog must be built tall enough for the body it renders — it has \
            40 rows to work with and needs ~27. Scroll chrome here means it was \
            sized from a measure that still saw the body's INITIAL state:
            \(lines.joined(separator: "\n"))
            """)
    }
}
