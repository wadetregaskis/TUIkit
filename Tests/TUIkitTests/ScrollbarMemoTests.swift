//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarMemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A focused scroll view's bar pulses, and its animated runs were one
/// scrollbar render per pulse frame on every frame. The bar and its runs are
/// kept on the handler with the inputs they were drawn from, and drawn again
/// only when one of those moves.
@MainActor
@Suite("The vertical scrollbar is drawn again only when its inputs move", .serialized)
struct ScrollbarMemoTests {

    @MainActor
    private struct Harness {
        let tui = TUIContext()
        let focusManager = FocusManager()

        func frame() -> FrameBuffer {
            let view = ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<60, id: \.self) { index in Text("row \(index)") }
                }
            }
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            return buffer
        }

        var handler: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    @Test("Same inputs: the second frame's bar comes from the memo and matches the first")
    func memoAnswersUnchangedInputs() {
        let harness = Harness()
        let first = harness.frame()
        guard let handler = harness.handler else {
            Issue.record("no scroll handler registered")
            return
        }
        let hitsAfterFirst = handler.verticalScrollbarMemoHits
        let second = harness.frame()
        #expect(handler.verticalScrollbarMemoHits > hitsAfterFirst, "the memo answered: \(handler.verticalScrollbarMemoHits)")
        #expect(first.lines == second.lines)
    }

    @Test("A scrolled offset draws a new bar")
    func offsetInvalidates() {
        let harness = Harness()
        let first = harness.frame()
        guard let handler = harness.handler else {
            Issue.record("no scroll handler registered")
            return
        }
        _ = harness.frame()
        let hitsBefore = handler.verticalScrollbarMemoHits
        handler.scrollOffset = 20
        let scrolled = harness.frame()
        #expect(handler.verticalScrollbarMemoHits == hitsBefore, "moved inputs are not served: \(handler.verticalScrollbarMemoHits) vs \(hitsBefore)")
        #expect(first.lines.map(\.stripped) != scrolled.lines.map(\.stripped))
    }
}
