//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RevealOnFocusEndToEndTests.swift
//
//  The user-visible payoff of Stage 1 + Stage 0, driven through the REAL
//  ScrollView pipeline: focusing a row far outside the viewport scrolls it
//  into view. The chain under test: focus(id:) records a durable intent →
//  the windowed lazy stack routes to the target row and renders it into the
//  full-height buffer (registering it, resolving the intent) → the
//  ScrollView's snap finds the focused region and moves its offset → the
//  same frame's clip shows the row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("reveal-on-focus, end to end")
struct RevealOnFocusEndToEndTests {
    private func makeView() -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<200, id: \.self) { i in
                    Button("row \(i)") {}
                }
            }
        }
        .frame(height: 6)
    }

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 6,
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

    /// Row 199's default focus ID, derived from row 0's registered one (the
    /// two differ only in the ForEach key segment "[0]" vs "[199]").
    private func tailID(from focusManager: FocusManager) -> String {
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        return id0.replacingOccurrences(of: "[0]", with: "[199]")
    }

    @Test("Focusing row 199 scrolls it into view; focusing row 0 scrolls back")
    func revealFarRowBothDirections() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("row 0") }, "starts at the top")
        #expect(!first.contains { $0.contains("row 199") })
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        let id199 = tailID(from: focusManager)

        focusManager.focus(id: id199)
        let revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(focusManager.currentFocusedID == id199, "focus landed 193 rows off-window")
        #expect(revealed.contains { $0.contains("row 199") }, "…and the viewport scrolled to show it: \(revealed)")
        #expect(!revealed.contains { $0.contains("row 0") }, "the top scrolled away")

        // Stable: nothing jumps on the next frames (§5c: reveal only when needed).
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled.contains { $0.contains("row 199") }, "the viewport stays put: \(settled)")

        // And back up.
        focusManager.focus(id: id0)
        let back = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(focusManager.currentFocusedID == id0)
        #expect(back.contains { $0.contains("row 0") }, "revealing upward works too: \(back)")
    }

    @Test("Tab past the window edge drags the viewport along")
    func tabScrollsTheViewport() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let ring = focusManager.registeredFocusIDsInActiveSection()
        focusManager.focus(id: ring[0])
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        // Walk ten steps down; the viewport must follow the focus.
        var lines: [String] = []
        for _ in 1...10 {
            focusManager.focusNext()
            lines = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        }
        #expect(
            lines.contains { $0.contains("row 10") },
            "the viewport followed focus to row 10: \(lines)")
        #expect(!lines.contains { $0.contains("row 0") }, "the top rows scrolled away")
    }

    @Test("Reveal reaches through two nested ScrollViews")
    func revealThroughNestedScrollViews() {
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<10) { i in Text("outer \(i)") }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<50, id: \.self) { i in
                            Button("inner \(i)") {}
                        }
                    }
                }
                .frame(height: 4)
                ForEach(10..<20) { i in Text("outer \(i)") }
            }
        }
        .frame(height: 8)

        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        // The only focusables are the inner buttons, so the very first frame
        // auto-focuses inner row 0 — and reveal brings the inner ScrollView
        // into the outer viewport straight away. (Itself the feature working.)
        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("inner 0") }, "auto-focus revealed the inner list: \(first)")

        // Jump to inner row 42 by key surgery on any registered inner id.
        let ring = focusManager.registeredFocusIDsInActiveSection()
        guard let innerID = ring.last(where: { $0.contains("[") }) else {
            Issue.record("no keyed inner row registered; ring: \(ring)")
            return
        }
        let target = innerID.replacingOccurrences(
            of: innerID.slice(betweenFirst: "[", and: "]") ?? "?", with: "42")

        focusManager.focus(id: target)
        var lines = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        // Allow one extra frame: the inner reveal and the outer reveal may
        // land on separate passes depending on registration order.
        if lines.contains(where: { $0.contains("inner 42") }) == false {
            lines = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        }
        #expect(focusManager.currentFocusedID == target)
        #expect(lines.contains { $0.contains("inner 42") }, "both ScrollViews scrolled to reveal: \(lines)")
    }
}

extension String {
    /// The substring strictly between the first `open` and the next `close`
    /// after it, or `nil`.
    fileprivate func slice(betweenFirst open: Character, and close: Character) -> String? {
        guard let start = firstIndex(of: open),
            let end = self[index(after: start)...].firstIndex(of: close)
        else { return nil }
        return String(self[index(after: start)..<end])
    }
}
