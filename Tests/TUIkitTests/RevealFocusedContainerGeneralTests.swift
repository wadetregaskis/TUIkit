//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RevealFocusedContainerGeneralTests.swift
//
//  The container-reveal rule generalized past Table/List (4e00168d): EVERY
//  focusable container must stamp its focusID onto a hit region, or an
//  enclosing ScrollView cannot scroll it into view when it takes focus.
//  The live sightings: an embedded ScrollView on the Layout System page
//  (Tab reached it; the page never scrolled) and a TabView below the fold
//  on the TabView Demo page (focus landed fully off screen).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("reveal focused containers (generalized)")
struct RevealFocusedContainerGeneralTests {
    private static let viewport = 8

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("Tabbing to an off-screen embedded ScrollView reveals it")
    func embeddedScrollViewIsRevealed() {
        // The Layout System page shape: a page ScrollView whose content
        // includes, below the fold, an inner ScrollView (its own Tab stop
        // because its content overflows its frame).
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("top") {}.focusID("top-button")
                ForEach(0..<20, id: \.self) { i in Text("filler \(i)") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<30, id: \.self) { i in Text("inner \(i)") }
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(height: Self.viewport)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("filler 0") }, "starts at the top: \(first)")
        #expect(!first.contains { $0.contains("inner") }, "the inner ScrollView starts off screen")

        // Both ScrollViews are Tab stops. Walk until the INNER one holds
        // focus; the outer must scroll it into view on that same frame.
        var revealed: [String] = []
        for _ in 0..<3 {
            focusManager.focusNext()
            revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            let focused = focusManager.currentFocusedID ?? ""
            if focused.hasPrefix("scrollview-"), focused.contains("filler") == false,
                focused != first.first
            {
                // Heuristic: two scrollview- ids exist; the inner one's
                // identity path is strictly longer (nested deeper).
                let ids = focusManager.registeredFocusIDsInActiveSection()
                    .filter { $0.hasPrefix("scrollview-") }
                if ids.count == 2, focused == ids.max(by: { $0.count < $1.count }) {
                    break
                }
            }
        }
        #expect(
            revealed.contains { $0.contains("inner") },
            "focusing the embedded ScrollView scrolled it into view: \(revealed)")
    }

    @Test("Tabbing to an off-screen TabView reveals its headers")
    func offScreenTabViewIsRevealed() {
        // The TabView Demo shape: a TabView below the fold. When its tab
        // strip takes focus the page must scroll — and because the TabView
        // is taller than the viewport, top-align so the HEADERS show.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("top") {}.focusID("top-button")
                ForEach(0..<20, id: \.self) { i in Text("filler \(i)") }
                TabView(selection: .constant(0)) {
                    Tab("Alpha", value: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<6, id: \.self) { i in Text("alpha \(i)") }
                        }
                    }
                    Tab("Beta", value: 1) { Text("beta content") }
                }
            }
        }
        .frame(height: Self.viewport)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(!first.contains { $0.contains("Alpha") }, "the TabView starts off screen: \(first)")

        // Walk focus to the TabView (its tab strip registers as a stop).
        var revealed: [String] = []
        for _ in 0..<4 {
            focusManager.focusNext()
            revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            if focusManager.currentFocusedID?.hasPrefix("tabview") == true { break }
        }
        #expect(
            focusManager.currentFocusedID?.hasPrefix("tabview") == true,
            "the TabView took focus: \(focusManager.currentFocusedID ?? "nil")")
        #expect(
            revealed.contains { $0.contains("Alpha") },
            "focusing the TabView revealed its tab strip: \(revealed)")
    }
}
