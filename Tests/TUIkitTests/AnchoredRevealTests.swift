//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnchoredRevealTests.swift
//
//  Reveal-on-focus through the REAL ScrollView for VARIABLE-height content —
//  the anchored walk (§5e), where target positions are estimates that the
//  reveal snap must converge on. The uniform path's reveal is pinned by
//  RevealOnFocusEndToEndTests; this suite closes the variable-height gap.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("reveal on the anchored path (variable heights)")
struct AnchoredRevealTests {
    private static let rows = 400

    private func makeView() -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<Self.rows, id: \.self) { i in
                    Button("row \(i)") {}
                        .frame(height: i % 3 + 1)
                }
            }
        }
        .frame(height: 8)
    }

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8,
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

    /// Renders frames until `line` appears or the budget runs out; returns
    /// (framesTaken, finalScreen) — the convergence measurement.
    private func framesUntilVisible(
        _ needle: String, view: some View, tuiContext: TUIContext,
        focusManager: FocusManager, budget: Int = 6
    ) -> (frames: Int, screen: [String]) {
        var screen: [String] = []
        for frame in 1...budget {
            screen = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            if screen.contains(where: { $0.contains(needle) }) {
                return (frame, screen)
            }
        }
        return (budget + 1, screen)
    }

    @Test("focus(id:) reveals a far variable-height row, both directions")
    func revealFarRowBothDirections() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("row 0") }, "starts at the top: \(first)")
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        let idTail = id0.replacingOccurrences(of: "[0]", with: "[399]")

        focusManager.focus(id: idTail)
        let down = framesUntilVisible(
            "row 399", view: view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(focusManager.currentFocusedID == idTail, "focus landed on the tail")
        #expect(
            down.frames <= 4,
            "reveal must converge within a few frames on estimates; took \(down.frames): \(down.screen)")

        // Stability once revealed: no oscillation (§7q's failure mode).
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled.contains { $0.contains("row 399") }, "no oscillation: \(settled)")

        focusManager.focus(id: id0)
        let up = framesUntilVisible(
            "row 0", view: view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(up.frames <= 4, "upward reveal converges; took \(up.frames): \(up.screen)")
    }

    @Test("A mid-list jump lands exactly on the target row")
    func midListJumpIsExact() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        let idMid = id0.replacingOccurrences(of: "[0]", with: "[217]")

        focusManager.focus(id: idMid)
        let result = framesUntilVisible(
            "row 217", view: view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(result.frames <= 4, "mid jump converges; took \(result.frames): \(result.screen)")
        #expect(focusManager.currentFocusedID == idMid)
    }

    @Test("Tab walks across the window edge on variable heights")
    func tabWalksTheEdge() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let ring = focusManager.registeredFocusIDsInActiveSection()
        focusManager.focus(id: ring[0])
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        var previous = focusManager.currentFocusedID
        var trace: [String] = []
        for step in 1...10 {
            focusManager.focusNext()
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            let current = focusManager.currentFocusedID
            trace.append("step \(step): \(current?.suffix(20) ?? "nil")")
            #expect(current != nil && current != previous, "step \(step) advanced focus")
            previous = current
        }
        let lines = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            lines.contains { $0.contains("row 10") },
            "the viewport followed: \(lines)\ntrace: \(trace.joined(separator: "\n"))")
    }
}
