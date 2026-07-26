//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollKeyFallThroughTests.swift
//
//  Page Up/Down and Home/End that the focused control does not consume scroll
//  the enclosing scrollable — even when a NON-scrollable control (a Button, a
//  text field) holds the focus.
//
//  The subtlety, and why these tests re-render between the key and the
//  assertion: the scroll was always happening. What made it look dead was the
//  reveal snapping the viewport straight back to the focused control on the
//  next render. Asserting on the handler immediately after the key press passes
//  even on the broken code — the bug only exists across a frame boundary.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scroll keys fall through to the enclosing scrollable")
struct ScrollKeyFallThroughTests {

    private static let viewport = 6

    /// A ScrollView whose content overflows and whose only focusable control is
    /// a Button near the top — the dialog shape: the control that holds focus
    /// cannot scroll, and the thing that can is its ancestor.
    private func view() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("PRESS-ME") {}
                ForEach(0..<40, id: \.self) { Text("row \($0)") }
            }
        }
        .frame(height: Self.viewport)
    }

    private func render(tui: TUIContext, fm: FocusManager) -> [String] {
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport, environment: env, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(view(), context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private func firstRow(_ lines: [String]) -> Int? {
        lines.compactMap { line -> Int? in
            guard let marker = line.range(of: "row ") else { return nil }
            return Int(line[marker.upperBound...].prefix { $0.isNumber })
        }.first
    }

    @Test("Page Down scrolls the container while a Button holds focus")
    func pageDownScrollsPastFocusedButton() {
        let tui = TUIContext()
        let fm = FocusManager()

        // Settle, with focus on the Button (the only focusable control besides
        // the ScrollView itself).
        var lines: [String] = []
        for _ in 0..<3 { lines = render(tui: tui, fm: fm) }
        let before = firstRow(lines)

        _ = fm.dispatchKeyEvent(KeyEvent(key: .pageDown))
        // THE load-bearing step. Without a re-render the reveal never runs, and
        // this test passes on the broken code.
        lines = render(tui: tui, fm: fm)
        let after = firstRow(lines)

        #expect(
            after != before,
            """
            Page Down must scroll the container the focused Button sits in. \
            before=\(String(describing: before)) after=\(String(describing: after)) \
            lines=\(lines)
            """)
    }

    @Test("Home returns to the top after the view has been scrolled away")
    func homeReturnsToTop() {
        let tui = TUIContext()
        let fm = FocusManager()
        for _ in 0..<3 { _ = render(tui: tui, fm: fm) }

        _ = fm.dispatchKeyEvent(KeyEvent(key: .pageDown))
        _ = render(tui: tui, fm: fm)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .pageDown))
        let scrolled = firstRow(render(tui: tui, fm: fm))
        #expect(scrolled != 0, "precondition: actually scrolled away, got \(String(describing: scrolled))")

        _ = fm.dispatchKeyEvent(KeyEvent(key: .home))
        let lines = render(tui: tui, fm: fm)
        #expect(
            firstRow(lines) == 0,
            "Home returns to the top: \(lines)")
    }
}
