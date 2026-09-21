//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// Renders one frame the way the loop does — the cache's pass boundary
    /// first — and answers how many subtree clears that boundary applied.
    ///
    /// That count is the oracle, in place of `AppState.shared.needsRender`.
    /// Two reasons, and the second is why it is the DRAIN rather than the
    /// total:
    ///
    /// - `needsRender` is process-wide. A `@State` write in any test running
    ///   beside this one sets it, so a NEGATIVE assertion on it fails for
    ///   someone else's reason — which is what happened here under a parallel
    ///   run. (A positive assertion is merely weakened by the same pollution,
    ///   which is why the other readers in this directory are left alone.)
    ///   `StatePropertyTests` says the same thing about the same flag.
    /// - The total number of subtree clears grows by one every frame for
    ///   reasons that are not this bug: a tint, a focus registration, a theme
    ///   and an environment write all clear DURING a render, by design.
    ///   A `@State` write does not — it enqueues, and `beginRenderPass` applies
    ///   it at the next boundary. So measuring across that boundary with no
    ///   render in between isolates exactly the writes a frame made.
    @discardableResult
    private func frame(_ view: some View, tui: TUIContext, width: Int) -> Int {
        let before = tui.renderCache.stats.subtreeClears
        tui.renderCache.beginRenderPass()
        let drained = tui.renderCache.stats.subtreeClears - before
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: 12, environment: env, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        return drained
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

        // Two frames to settle: the first fills the memo and builds the
        // TabView's own `@State`, and the second is where that write is
        // applied. Each later frame's boundary reports what the frame BEFORE
        // it wrote, so the two assertions below are about frames two and three.
        frame(view, tui: tui, width: 60)
        frame(view, tui: tui, width: 60)

        #expect(
            frame(view, tui: tui, width: 60) == 0,
            "a settled TabView dirtied state, so the loop would render again")
        #expect(
            frame(view, tui: tui, width: 60) == 0,
            "...and it is still doing it on the frame after that")
    }
}
