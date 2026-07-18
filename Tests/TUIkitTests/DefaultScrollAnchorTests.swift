//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DefaultScrollAnchorTests.swift
//
//  defaultScrollAnchor(.bottom) — §5c edge affinity, §6c "follow the log":
//  a bottom-anchored ScrollView starts at the tail and stays glued to it as
//  content grows; scrolling up releases the glue (the classic scroll-lock
//  every terminal user expects); returning to the bottom re-engages it.
//  Being at the bottom IS the engagement — no mode flag to desync.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("defaultScrollAnchor(.bottom)")
struct DefaultScrollAnchorTests {
    private static let viewport = 6

    private func makeView(lines: Int, variable: Bool = false) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<lines, id: \.self) { i in
                    Text("line \(i)")
                        .frame(height: variable ? i % 3 + 1 : 1)
                }
            }
        }
        .frame(height: Self.viewport)
        .defaultScrollAnchor(.bottom)
    }

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
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

    @Test("Starts at the tail and follows appends")
    func startsAtTailAndFollows() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        let first = renderFrame(
            makeView(lines: 100), tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("line 99") }, "starts at the tail: \(first)")
        #expect(!first.contains { $0.contains("line 0 ") })

        // The log grows; the view stays glued to the new tail.
        let grown = renderFrame(
            makeView(lines: 120), tuiContext: tuiContext, focusManager: focusManager)
        #expect(grown.contains { $0.contains("line 119") }, "follows the append: \(grown)")
    }

    @Test("Scrolling up releases the glue; End re-engages it")
    func scrollUpHoldsEndResumes() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        renderFrame(makeView(lines: 100), tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(makeView(lines: 100), tuiContext: tuiContext, focusManager: focusManager)

        // The ScrollView is the only focusable; scroll up a few lines.
        for _ in 0..<3 {
            _ = focusManager.dispatchKeyEvent(KeyEvent(key: .up))
        }
        let held = renderFrame(
            makeView(lines: 100), tuiContext: tuiContext, focusManager: focusManager)
        #expect(!held.contains { $0.contains("line 99") }, "scrolled away from the tail: \(held)")

        // Appends must NOT yank the view back down (the scroll-lock). The
        // "N more lines below" indicator count legitimately grows; the CONTENT
        // rows must be identical.
        let heldAfterAppend = renderFrame(
            makeView(lines: 140), tuiContext: tuiContext, focusManager: focusManager)
        let contentRows = { (lines: [String]) in lines.filter { $0.hasPrefix("line ") } }
        #expect(
            contentRows(heldAfterAppend) == contentRows(held),
            "appends move nothing while scrolled away: \(heldAfterAppend) vs \(held)")

        // End returns to the bottom and re-engages follow.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .end))
        let back = renderFrame(
            makeView(lines: 140), tuiContext: tuiContext, focusManager: focusManager)
        #expect(back.contains { $0.contains("line 139") }, "End reaches the tail: \(back)")
        let followed = renderFrame(
            makeView(lines: 160), tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            followed.contains { $0.contains("line 159") },
            "follow re-engaged after End: \(followed)")
    }

    @Test("Variable heights: starts at the tail and follows (anchored path)")
    func variableHeightsFollow() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        renderFrame(
            makeView(lines: 400, variable: true), tuiContext: tuiContext,
            focusManager: focusManager)
        let settled = renderFrame(
            makeView(lines: 400, variable: true), tuiContext: tuiContext,
            focusManager: focusManager)
        #expect(settled.contains { $0.contains("line 399") }, "tail on the anchored path: \(settled)")

        var grown = renderFrame(
            makeView(lines: 440, variable: true), tuiContext: tuiContext,
            focusManager: focusManager)
        if grown.contains(where: { $0.contains("line 439") }) == false {
            grown = renderFrame(
                makeView(lines: 440, variable: true), tuiContext: tuiContext,
                focusManager: focusManager)
        }
        #expect(grown.contains { $0.contains("line 439") }, "follows on estimates: \(grown)")
    }

    @Test("Without the anchor, the view starts at the top (unchanged default)")
    func defaultRemainsTop() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<100, id: \.self) { i in Text("line \(i)") }
            }
        }
        .frame(height: Self.viewport)

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("line 0") }, "top by default: \(first)")
    }
}
