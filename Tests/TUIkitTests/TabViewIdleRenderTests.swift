//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewIdleRenderTests.swift
//
//  A settled TabView must not ask for another frame. Its per-width size memo
//  is written during the MEASURE pass, and writing a StateBox invalidates the
//  render cache and requests a render — so a memo that compares unequal to
//  itself is a render loop, not a slow path.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("TabView idle renders")
struct TabViewIdleRenderTests {

    private func frame(_ view: some View, tui: TUIContext, width: Int) {
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: 12, environment: env, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
    }

    @Test("A settled TabView asks for no further frames")
    func settledTabViewIsQuiet() {
        // The bug: the size memo's LRU order moves on every `set`, and a
        // TabView measures at more than one width per frame (the panel sizes to
        // its widest tab, then renders at the panel's width). So the memo
        // compared unequal to itself every frame, the guarded write fired, the
        // write asked for another render — and a page with a TabView on it
        // rendered forever, drawing an identical picture. 14% of a core on the
        // Example's Tab Views page with nothing animating.
        let tui = TUIContext()
        // Bordered, because that style measures its content at the interior
        // width while the view is measured at the full one — two widths per
        // frame, which is what makes the LRU order flip.
        // Inside a ScrollView that overflows, which is how the Example's pages
        // are built: the bar takes a column, so the tabs are measured at one
        // width and rendered at another — two entries in the memo per frame,
        // and that is what makes the LRU order flip.
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TabView(selection: .constant(0)) {
                    Tab("One", value: 0) { Text("a short tab") }
                    Tab("Two", value: 1) { Text("a considerably wider tab body") }
                }
                .tabViewStyle(.bordered)
                ForEach(0..<30, id: \.self) { Text("filler \($0)") }
            }
        }

        // Two frames to settle (the first fills the memo).
        frame(view, tui: tui, width: 60)
        frame(view, tui: tui, width: 60)

        AppState.shared.didRender()
        frame(view, tui: tui, width: 60)
        #expect(
            !AppState.shared.needsRender,
            "a settled TabView dirtied state, so the loop would render again")
    }
}
