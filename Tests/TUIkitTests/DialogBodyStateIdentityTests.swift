//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DialogBodyStateIdentityTests.swift
//
//  A dialog's body keeps its @State when the body grows past — or shrinks
//  back under — the height at which the container starts scrolling it.
//
//  This is the #408 regression. `scrollableBody` used to wrap the body in a
//  ScrollView only when it overflowed, so crossing that threshold swapped
//  `content` for `ScrollView { content }`. That is a STRUCTURAL change: every
//  identity path inside the body changed, so every `@State` was recreated and
//  snapped back to its initial value.
//
//  It surfaced as "the colour picker's tall tabs need two clicks". Selecting
//  the 256-swatch grid made the body overflow, which reset the picker's
//  `@State mode` back to `.rgb` — so the tab appeared not to switch at all,
//  while the short channel-editor tabs (which never crossed the threshold)
//  always worked. The click, the hit region and the binding write were all
//  correct the whole time; only the state was being thrown away.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A dialog body keeps its state across the scroll threshold")
struct DialogBodyStateIdentityTests {

    /// Counts its own appearances in `@State`. A stable identity fires
    /// `.onAppear` exactly once, so the count stays 1 no matter how many
    /// frames — or heights — follow. A recreated one starts over.
    private struct CountingBody: View {
        let rows: Int
        @State private var appearances = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("appearances=\(appearances)")
                ForEach(0..<rows, id: \.self) { Text("row \($0)") }
            }
            .onAppear { appearances += 1 }
        }
    }

    /// Renders the same dialog into `tui` at `height`, returning its lines.
    private func render(tui: TUIContext, height: Int) -> [String] {
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: height, environment: env, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(
            Dialog(title: "T") { CountingBody(rows: 12) }, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map(\.stripped)
    }

    private func appearances(_ lines: [String]) -> Int? {
        for line in lines {
            guard let r = line.range(of: "appearances=") else { continue }
            return Int(line[r.upperBound...].prefix { $0.isNumber })
        }
        return nil
    }

    @Test("state survives the body growing past the scroll threshold")
    func stateSurvivesCrossingIntoScrolling() {
        let tui = TUIContext()
        // Tall enough for a 12-row body plus chrome: no scrolling.
        _ = render(tui: tui, height: 20)
        let settled = appearances(render(tui: tui, height: 20))
        #expect(settled == 1, "precondition: one appearance while it fits, got \(String(describing: settled))")

        // Now too short: the container starts scrolling the body. The body's
        // own state must not notice.
        let scrolled = appearances(render(tui: tui, height: 8))
        #expect(
            scrolled == 1,
            """
            Crossing into the scrolling layout must not recreate the body's \
            @State — got appearances=\(String(describing: scrolled)), meaning \
            .onAppear fired again on a fresh state box.
            """)
    }

    @Test("state survives the body shrinking back out of scrolling")
    func stateSurvivesLeavingScrolling() {
        let tui = TUIContext()
        _ = render(tui: tui, height: 8)
        let settled = appearances(render(tui: tui, height: 8))
        #expect(settled == 1, "precondition: one appearance while scrolling, got \(String(describing: settled))")

        let unscrolled = appearances(render(tui: tui, height: 20))
        #expect(
            unscrolled == 1,
            "Leaving the scrolling layout must not recreate the body's @State either: \(String(describing: unscrolled))")
    }
}
