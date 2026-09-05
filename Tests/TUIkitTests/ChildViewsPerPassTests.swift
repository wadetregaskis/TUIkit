//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChildViewsPerPassTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A stack resolves its children in `sizeThatFits` and again in
/// `renderToBuffer`, and a stack inside a `ScrollView` is measured several
/// times a frame — so a `ForEach` built its rows five times per frame. A
/// provider that says its children are worth remembering is resolved once
/// per pass, and afresh on the next.
@MainActor
@Suite("A stack's children are resolved once per pass", .serialized)
struct ChildViewsPerPassTests {

    /// Twenty rows, and a count of how often they were built.
    private struct CountingRows: View, ChildViewProvider {
        var body: Never { fatalError("CountingRows provides children") }
        func childViews(context: RenderContext) -> [ChildView] {
            Counters.resolutions += 1
            return (0..<20).map { ChildView(Text("row \($0)"), identityType: Text.self, childIndex: $0) }
        }
        var childViewsAreWorthMemoising: Bool { true }
    }

    private enum Counters {
        nonisolated(unsafe) static var resolutions = 0
    }

    private static func frame<V: View>(_ view: V, tui: TUIContext) -> FrameBuffer {
        let context = RenderContext(availableWidth: 40, availableHeight: 8, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.renderCache.removeInactive()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    @Test("Inside a scroll view, one resolution per pass — and a fresh one next pass")
    func oncePerPass() {
        let tui = TUIContext()
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("heading")
            ScrollView { VStack(alignment: .leading, spacing: 0) { CountingRows() } }
        }
        Counters.resolutions = 0
        let buffer = Self.frame(view, tui: tui)
        #expect(buffer.lines.count == 8)
        #expect(buffer.lines[1].stripped.hasPrefix("row 0"), "\(buffer.lines[1])")
        #expect(Counters.resolutions == 1, "resolved once for the whole pass: \(Counters.resolutions)")
        _ = Self.frame(view, tui: tui)
        #expect(Counters.resolutions == 2, "the memo is scratch for one pass: \(Counters.resolutions)")
    }

    @Test("A ForEach opts in from sixteen rows")
    func forEachOptsIn() {
        #expect(ForEach(0..<16, id: \.self) { Text("\($0)") }.childViewsAreWorthMemoising)
        #expect(!ForEach(0..<15, id: \.self) { Text("\($0)") }.childViewsAreWorthMemoising)
    }
}
