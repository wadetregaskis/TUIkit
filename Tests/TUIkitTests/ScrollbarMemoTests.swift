//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarMemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A palette edited in place: the id stays while a colour changes, as the
/// Example's Theme page does. `foregroundQuaternary` is the rung the bar's
/// track is drawn from.
private struct EditablePalette: Palette, Hashable {
    var id = "editable"
    var name = "Editable"
    var background: Color = .rgb(0, 0, 0)
    var foreground: Color = .rgb(200, 200, 200)
    var foregroundQuaternary: Color = .rgb(90, 90, 90)
    var accent: Color = .rgb(0, 200, 0)
    var success: Color = .rgb(0, 200, 0)
    var warning: Color = .rgb(200, 200, 0)
    var error: Color = .rgb(200, 0, 0)
    var info: Color = .rgb(0, 200, 200)
    var border: Color = .rgb(100, 100, 100)
}

/// A focused scroll view's bar pulses, and its animated runs were one
/// scrollbar render per pulse frame on every frame. The bar and its runs are
/// kept on the handler with the inputs they were drawn from, and drawn again
/// only when one of those moves.
@MainActor
@Suite("A scrollbar is drawn again only when its inputs move", .serialized)
struct ScrollbarMemoTests {

    @MainActor
    private struct Harness {
        let tui = TUIContext()
        let focusManager = FocusManager()

        /// Whether the content is wide as well as tall, and scrolls both ways.
        var twoAxis = false

        func frame(palette: any Palette = SystemPalette(.green)) -> FrameBuffer {
            let rows = VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<60, id: \.self) { index in
                    Text(twoAxis ? "row \(index) " + String(repeating: "=", count: 80) : "row \(index)")
                }
            }
            let view = ScrollView(twoAxis ? [.horizontal, .vertical] : .vertical) { rows }
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            environment.palette = palette
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

    @Test("Same inputs: the second frame's HORIZONTAL bar comes from the memo and matches the first")
    func horizontalMemoAnswersUnchangedInputs() {
        var harness = Harness()
        harness.twoAxis = true
        let first = harness.frame()
        guard let handler = harness.handler else {
            Issue.record("no scroll handler registered")
            return
        }
        #expect(handler.horizontal.extent > 30, "precondition: the content scrolls sideways")
        let hitsAfterFirst = handler.horizontalScrollbarMemoHits
        let second = harness.frame()
        #expect(handler.horizontalScrollbarMemoHits > hitsAfterFirst, "the memo did not answer")
        #expect(first.lines == second.lines)
    }

    @Test("A sideways offset draws a new horizontal bar")
    func horizontalOffsetInvalidates() {
        var harness = Harness()
        harness.twoAxis = true
        let first = harness.frame()
        guard let handler = harness.handler else {
            Issue.record("no scroll handler registered")
            return
        }
        _ = harness.frame()
        let hitsBefore = handler.horizontalScrollbarMemoHits
        handler.horizontal.scrollOffset = 30
        let scrolled = harness.frame()
        #expect(handler.horizontalScrollbarMemoHits == hitsBefore, "moved inputs were served")
        #expect(first.lines.last?.stripped != scrolled.lines.last?.stripped, "the bar did not move")
    }

    @Test("A palette edited under the same id draws a new bar")
    func paletteEditedInPlaceInvalidates() {
        // The key held only the palette's id, so an edit that kept it served the
        // bar drawn before the edit. The oracle is a harness that has only ever
        // seen the edited palette, rendered the same number of frames, so focus
        // and the pulse are in the same state on both sides.
        var palette = EditablePalette()
        let harness = Harness()
        _ = harness.frame(palette: palette)
        _ = harness.frame(palette: palette)
        palette.foregroundQuaternary = .rgb(90, 0, 90)
        let edited = harness.frame(palette: palette)

        let oracle = Harness()
        _ = oracle.frame(palette: palette)
        _ = oracle.frame(palette: palette)
        let expected = oracle.frame(palette: palette)
        #expect(edited.lines == expected.lines, "the bar kept the colours from before the edit")
    }
}
