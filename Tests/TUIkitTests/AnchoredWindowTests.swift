//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnchoredWindowTests.swift
//
//  §5e/§6a of "Locating things without drawing them", for VARIABLE-height
//  content: the scroll position is a persisted anchor (row ordinal + cells
//  hidden above the viewport top), scroll input is a delta walked in row
//  space, and a frame measures only the rows it draws. Estimates cover only
//  the never-measured suffix (the scrollbar), never the content: the anchor
//  row is pinned to the offset the clip shows, so what's on screen is
//  stable by construction even while estimates refine.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Counts row-builder invocations. @unchecked: driven on the main actor.
private final class BuildCounter: @unchecked Sendable {
    var calls = 0
}

@MainActor
@Suite("anchored windowing (variable heights)")
struct AnchoredWindowTests {
    private static let rows = 10_000
    private static let viewport = 6

    /// Row k is k%3+1 lines tall (average pitch exactly 2), far above the
    /// anchored-path threshold, keyed — and NOT uniform, so the uniform
    /// hypothesis falsifies on the very first frame and the anchored walk
    /// takes over.
    @discardableResult
    private func renderFrame(
        counter: BuildCounter, tuiContext: TUIContext, offset: Int
    ) -> [String] {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Self.rows, id: \.self) { i in
                counter.calls += 1
                return Text("row \(i)").frame(height: i % 3 + 1)
            }
        }
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: Self.viewport)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.rows * 3,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The visible slice: what the ScrollView's clip would show.
    private func window(_ lines: [String], at offset: Int) -> [String] {
        guard lines.count >= offset + Self.viewport else { return [] }
        return Array(lines[offset..<(offset + Self.viewport)])
    }

    @Test("Frames build O(window) rows; line scrolling shifts content by exactly one line")
    func lineScrollingIsExactAndCheap() {
        let counter = BuildCounter()
        let tuiContext = TUIContext()

        // Frame 1 at the top: the uniform hypothesis (row 0 is 1 line) is
        // falsified by row 1 (2 lines) in the same frame; the anchored walk
        // takes over. Row 0 must sit at the very top — the endpoint is exact.
        let first = renderFrame(counter: counter, tuiContext: tuiContext, offset: 0)
        #expect(first[0] == "row 0")
        #expect(counter.calls < 40, "frame 1 builds O(window) rows, built \(counter.calls)")

        // Scroll down one line at a time: each frame is cheap, and the
        // visible slice shifts by EXACTLY one line — the anchor walk is
        // line-exact even though heights vary.
        var previous = window(first, at: 0)
        for offset in 1...8 {
            let before = counter.calls
            let lines = renderFrame(counter: counter, tuiContext: tuiContext, offset: offset)
            let visible = window(lines, at: offset)
            #expect(
                Array(previous.dropFirst()) == Array(visible.dropLast()),
                "offset \(offset): the slice must shift by one line, not jump")
            #expect(counter.calls - before < 30, "one-line scroll builds a handful of rows")
            previous = visible
        }
    }

    @Test("A far jump lands near the target, cheaply, and is stable on repeat")
    func farJumpIsCheapAndStable() {
        let counter = BuildCounter()
        let tuiContext = TUIContext()

        renderFrame(counter: counter, tuiContext: tuiContext, offset: 0)
        renderFrame(counter: counter, tuiContext: tuiContext, offset: 1)

        // Scrollbar-drag-sized jump: ~half way through ~20k cells of content.
        let before = counter.calls
        let jumped = renderFrame(counter: counter, tuiContext: tuiContext, offset: 9_000)
        #expect(counter.calls - before < 40, "a jump must not walk 4,500 rows")
        let visible = window(jumped, at: 9_000)
        let shownRows = visible.compactMap { line -> Int? in
            guard line.hasPrefix("row ") else { return nil }
            return Int(line.dropFirst(4))
        }
        #expect(!shownRows.isEmpty, "the jump landed on content: \(visible)")
        // Approximate landing is the contract (the estimate seeds the seek);
        // it must be deep in the list — nowhere near either end.
        #expect(shownRows.allSatisfy { $0 > 1_000 && $0 < 9_500 }, "landed mid-list: \(shownRows)")

        // Stability: the same offset shows the same content — estimates
        // refining must never move what's on screen.
        let again = renderFrame(counter: counter, tuiContext: tuiContext, offset: 9_000)
        #expect(window(again, at: 9_000) == visible, "no jitter at a fixed offset")

        // And back to the top: the endpoint is exact again.
        let home = renderFrame(counter: counter, tuiContext: tuiContext, offset: 0)
        #expect(home[0] == "row 0", "offset 0 is exactly row 0")
    }
}
