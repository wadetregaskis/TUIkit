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

    /// One live-loop-shaped frame through the REAL ScrollView (the memo test
    /// needs it: the churn under test comes from the ScrollView's render
    /// canvas, which the bare-stack harness doesn't reproduce).
    private func renderScrollFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) {
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
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
    }

    @Test("Band row measures memoize across growing frames (follow mode)")
    func rowMeasuresMemoizeAcrossGrowingFrames() {
        // Through the real ScrollView, in follow mode: every frame appends a
        // row, and the band re-measures the rows it touches — including the
        // width/flexibility SAMPLE rows (0..15), which are measured but
        // never rendered. The size memo stored their sizes each frame, but
        // only renderToBuffer marked identities active, so removeInactive
        // pruned the measure-only entries at the end of EVERY pass: those
        // rows missed the memo every frame, forever, despite identical keys
        // and values (each miss re-measuring — for Text rows, re-wrapping).
        // Steady state must re-measure only what the frame genuinely
        // touches for the first time: the appended row.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let log = MeasureLog()
        func makeView(rows: Int) -> some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { i in
                        MeasureCountRow(log: log, index: i)
                    }
                }
            }
            .frame(height: Self.viewport)
            .defaultScrollAnchor(.bottom)
        }

        // Warm frames: seed the anchor, the glue, and the memo.
        for delta in 0..<3 {
            renderScrollFrame(
                makeView(rows: 5_000 + delta), tuiContext: tuiContext, focusManager: focusManager)
        }
        let before = log.measures
        renderScrollFrame(makeView(rows: 5_003), tuiContext: tuiContext, focusManager: focusManager)
        let perFrame = log.measures - before
        #expect(
            perFrame <= 8,
            "a steady append frame re-measures a handful of fresh rows, not the band + samples: \(perFrame)")
    }

    /// Renders a variable-height keyed stack with the given row count and
    /// spacing under an injected window — `rows` chooses the path (≤256 =
    /// exact full walk, above = anchored fill).
    @discardableResult
    private func renderSpacedFrame(
        rows: Int, spacing: Int, offset: Int, tuiContext: TUIContext
    ) -> [String] {
        let view = LazyVStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rows, id: \.self) { i in
                Text("row \(i)").frame(height: i % 3 + 1)
            }
        }
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: Self.viewport)
        let context = RenderContext(
            availableWidth: 30, availableHeight: rows * 4,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// Renders wrap-height rows (every 3rd wraps to 2 lines at width 30,
    /// all 1 line at width 60) at the given width and window offset.
    @discardableResult
    private func renderWrappedFrame(
        width: Int, offset: Int, tuiContext: TUIContext
    ) -> [String] {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<400, id: \.self) { i in
                Text(i.isMultiple(of: 3) ? "row \(i) " + String(repeating: "w", count: 36) : "row \(i)")
            }
        }
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: Self.viewport)
        let context = RenderContext(
            availableWidth: width, availableHeight: 400 * 3,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("A width change re-clamps the anchor's offset-within (no drift)")
    func widthChangeReclampsAnchorOffset() {
        // At width 30 every 3rd row wraps to 2 lines; scroll to offset 1 so
        // the viewport top is row 0's CONTINUATION line — the anchor is row
        // 0 with offsetWithin 1. Re-rendering the same offset at width 60
        // makes every row 1 line: a stale offsetWithin ≥ the new pitch
        // silently pushes the anchor row above the viewport (§5e violation:
        // the anchor row is pinned to the offset the clip shows). The
        // clamped anchor must keep row 0 as the viewport's top row.
        let tuiContext = TUIContext()
        renderWrappedFrame(width: 30, offset: 0, tuiContext: tuiContext)
        let narrow = renderWrappedFrame(width: 30, offset: 1, tuiContext: tuiContext)
        #expect(narrow[1].hasPrefix("www"), "viewport top is row 0's wrap line: \(narrow.prefix(3))")

        let wide = renderWrappedFrame(width: 60, offset: 1, tuiContext: tuiContext)
        #expect(
            wide[1].hasPrefix("row 0 "),
            "after widening, the anchor row stays at the viewport top: \(wide.prefix(3))")
    }

    @Test("Nonzero spacing: the anchored path's geometry matches the exact path")
    func anchoredSpacingMatchesExact() {
        // Same content prefix either side of the anchored threshold: 100
        // rows take the exact full walk, 400 the anchored fill. The first
        // rows are identical, so the head lines must be byte-identical —
        // above all the spacing line between row 0 and row 1, which the
        // anchored pitch walk is prone to dropping (spacing charged BEFORE
        // a row but applied as the advance AFTER it misses exactly one gap).
        let exact = renderSpacedFrame(
            rows: 100, spacing: 1, offset: 0, tuiContext: TUIContext())
        let anchored = renderSpacedFrame(
            rows: 400, spacing: 1, offset: 0, tuiContext: TUIContext())
        #expect(
            Array(exact.prefix(10)) == Array(anchored.prefix(10)),
            "exact \(Array(exact.prefix(10))) vs anchored \(Array(anchored.prefix(10)))")

        // And line scrolling stays line-exact WITH spacing: each one-line
        // scroll shifts the visible slice by exactly one line (spacing
        // lines included in the walk).
        let tuiContext = TUIContext()
        var previous = Array(
            renderSpacedFrame(rows: 400, spacing: 1, offset: 0, tuiContext: tuiContext)
                .prefix(Self.viewport))
        for offset in 1...8 {
            let lines = renderSpacedFrame(
                rows: 400, spacing: 1, offset: offset, tuiContext: tuiContext)
            guard lines.count >= offset + Self.viewport else {
                Issue.record("buffer too short at offset \(offset)")
                return
            }
            let visible = Array(lines[offset..<(offset + Self.viewport)])
            #expect(
                Array(previous.dropFirst()) == Array(visible.dropLast()),
                "offset \(offset): one-line shift with spacing, was \(previous) now \(visible)")
            previous = visible
        }
    }
}

// MARK: - Measure-counting probe

/// Counts `sizeThatFits` entries on the row content itself: a size-memo MISS
/// measures the content, a hit does not — the discriminator for "unchanged
/// band rows must not re-measure while the content total grows".
private final class MeasureLog: @unchecked Sendable {
    var measures = 0
}

private struct MeasureCountRow: View, Renderable, Layoutable {
    let log: MeasureLog
    let index: Int

    var body: Never { fatalError("probe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(
            lines: Array(repeating: "row \(index)", count: index % 3 + 1), width: 8)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        log.measures += 1
        return ViewSize.fixed(8, index % 3 + 1)
    }
}
