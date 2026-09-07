//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowedStackWidthTests.swift
//
//  A windowed lazy stack answers three different measure paths — the uniform
//  arithmetic seek, the anchored estimate, and the exact walk — and which one
//  answers changes as the render seeds its hypotheses. The width they report
//  is a heuristic (no path measures every row), but it must be the SAME
//  heuristic: a tree nothing has changed may not measure wider on its first
//  frame than on its second.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("windowed stack width stability")
struct WindowedStackWidthTests {

    /// A stack of one-line rows, all narrow but one.
    private func stack(count: Int, wideAt: Int) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Text(i == wideAt ? String(repeating: "W", count: 24) : "r\(i)")
            }
        }
    }

    private func context(
        _ tuiContext: TUIContext, height: Int, window: ScrollContentWindow?
    ) -> RenderContext {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = window
        return RenderContext(
            availableWidth: 40, availableHeight: height,
            environment: environment, tuiContext: tuiContext)
    }

    /// One frame in the shape a `ScrollView` drives: the enclosing column's
    /// natural-size ask at the real budget, the content-extent walk at the
    /// natural-extent ladder's budget, then the windowed render (which seeds
    /// the hypotheses the next frame's measures answer from).
    private func widthsOfFrame(
        _ view: some View, _ tuiContext: TUIContext, viewport: Int, offset: Int = 0
    ) -> (natural: Int, extent: Int) {
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let natural = measureChild(
            view, proposal: ProposedSize(width: nil, height: nil),
            context: context(tuiContext, height: viewport, window: nil))
        let extent = measureChild(
            view, proposal: ProposedSize(width: 40, height: nil),
            context: context(tuiContext, height: 4096, window: nil))
        _ = renderToBuffer(
            view,
            context: context(
                tuiContext, height: 4096,
                window: ScrollContentWindow(offset: offset, viewportHeight: viewport)))
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return (natural.width, extent.width)
    }

    private func naturalWidthOfFrame(
        _ view: some View, _ tuiContext: TUIContext, viewport: Int
    ) -> Int {
        widthsOfFrame(view, tuiContext, viewport: viewport).natural
    }

    @Test(
        "the natural-size ask reports the same width on every frame",
        arguments: [
            // Large enough for the anchored estimate (>256 rows), with the
            // wide row inside its sixteen-row sample but below the fold: the
            // sample used to widen the answer for a row the budget had no
            // room to draw, and only the first frame, because the render's
            // band-derived hypothesis answered every frame after.
            (400, 12),
            // The wide row beyond the sample as well — the answer must still
            // not move between frames.
            (400, 300),
            // Small enough for the exact walk on the first frame.
            (40, 20),
            // The wide row on screen: every path can see it, on every frame.
            (400, 3),
            (40, 3),
        ])
    func naturalWidthDoesNotDriftBetweenFrames(count: Int, wideAt: Int) {
        let tuiContext = TUIContext()
        let view = stack(count: count, wideAt: wideAt)
        let first = naturalWidthOfFrame(view, tuiContext, viewport: 8)
        let second = naturalWidthOfFrame(view, tuiContext, viewport: 8)
        let third = naturalWidthOfFrame(view, tuiContext, viewport: 8)
        #expect(
            first == second && second == third,
            "\(count) rows, wide row at \(wideAt): widths \(first)/\(second)/\(third)")
    }

    @Test("a wide row on screen still widens the stack")
    func anOnScreenWideRowIsHugged() {
        let tuiContext = TUIContext()
        // Row 3 is inside an 8-line viewport, so every frame draws it.
        #expect(naturalWidthOfFrame(stack(count: 400, wideAt: 3), tuiContext, viewport: 8) == 24)
    }

    @Test(
        "the content-extent walk reports the same width on every frame",
        arguments: [(400, 12), (400, 300), (40, 20), (400, 3), (40, 3)])
    func contentExtentWidthDoesNotDriftBetweenFrames(count: Int, wideAt: Int) {
        // The question a `ScrollView` asks its content: every row fits in the
        // ladder's budget, so the walk sees the whole stack while the seek —
        // which answers from the second frame — has only ever drawn the band.
        let tuiContext = TUIContext()
        let view = stack(count: count, wideAt: wideAt)
        let first = widthsOfFrame(view, tuiContext, viewport: 8).extent
        let second = widthsOfFrame(view, tuiContext, viewport: 8).extent
        let third = widthsOfFrame(view, tuiContext, viewport: 8).extent
        #expect(
            first == second && second == third,
            "\(count) rows, wide row at \(wideAt): widths \(first)/\(second)/\(third)")
    }

    @Test("a stack scrolled to a wide row does not report the narrow rows above it")
    func theBandIsAFloor() {
        // A prefix answer is the right one for "how wide are you in eight
        // lines" — but not when those eight lines are not what is drawn.
        let tuiContext = TUIContext()
        let view = stack(count: 400, wideAt: 300)
        _ = widthsOfFrame(view, tuiContext, viewport: 8)
        _ = widthsOfFrame(view, tuiContext, viewport: 8, offset: 300)
        let scrolled = widthsOfFrame(view, tuiContext, viewport: 8, offset: 300)
        #expect(scrolled.natural == 24, "the band on screen is 24 wide")
    }
}
