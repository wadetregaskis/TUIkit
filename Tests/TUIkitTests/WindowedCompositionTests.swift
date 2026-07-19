//  🖥️ TUIKit — Terminal UI Kit for Swift
//  WindowedCompositionTests.swift
//
//  Compositions of the Stage-6 windowed pipeline with its neighbours —
//  the shapes real apps ship that no single-mechanism suite exercises:
//  a scrollbar over windowed content, a ScrollView nested inside a
//  windowed row (two reply channels in one pass), End pressed against an
//  ESTIMATED total that the very next frame refines, anchored .bottom /
//  .center exactness, and scrollTo against EAGER content.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

private final class ProxyBox: @unchecked Sendable {
    var proxy: ScrollViewProxy?
}

@MainActor
@Suite("windowed pipeline compositions")
struct WindowedCompositionTests {
    private static let viewport = 6

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager, width: Int = 30
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: width, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped }
    }

    @Test("A scrollbar over windowed content: geometry converges, End reaches the tail")
    func scrollbarOverWindowedContent() {
        // The composition TUIkitExample ships: .automatic scrollbar + a big
        // lazy list. The reservation loop must measure the ESTIMATED full
        // height (reserving the bar), the handshake then runs at the
        // narrowed width, and the bar column renders on every content row.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<50_000, id: \.self) { i in Text("row \(i)") }
            }
        }
        .scrollbarVisibility(.visible)
        .frame(height: Self.viewport)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled.contains { $0.contains("row 0") }, "content renders: \(settled)")
        let barGlyphs = Set("░▒▓█▲▼╵╷│")
        let rowsWithBar = settled.count { line in
            line.contains { barGlyphs.contains($0) }
        }
        // Arrows + thumb are the visible glyphs (track cells are blank),
        // so at least two rows carry bar chrome.
        #expect(rowsWithBar >= 2, "the bar chrome renders: \(settled)")

        // End against the (hypothesis-exact) uniform total lands on the
        // real last row with a full viewport.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .end))
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let tail = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(tail.contains { $0.contains("row 49999") }, "End reaches the tail: \(tail)")
        #expect(
            tail.count { $0.contains("row ") } >= Self.viewport - 1,
            "a full viewport of rows at the tail: \(tail)")
    }

    @Test("End against an ESTIMATED total settles on the real tail (anchored path)")
    func endFromEstimatedTotalSettles() {
        // Variable heights: the total is an estimate; .end sets the offset
        // from it, the next render's reply refines it, the clamp pulls the
        // offset back, and the coverage pass repairs the band. The settled
        // frame must show the real last row with no blank rows and no stuck
        // "more below".
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30_000, id: \.self) { i in
                    Text("line \(i)").frame(height: i % 3 + 1)
                }
            }
        }
        .frame(height: Self.viewport)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .end))
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled.contains { $0.contains("line 29999") }, "the real tail: \(settled)")
        #expect(!settled.contains { $0.contains("more lines below") }, "no stuck below-indicator: \(settled)")
        #expect(!settled.dropFirst().contains(""), "no blank rows at the tail: \(settled)")

        // And it STAYS settled (no oscillation as estimates refine).
        let again = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(again == settled, "the tail frame is stable: \(again)")
    }

    @Test("A ScrollView inside a windowed row keeps its own reply channel")
    func nestedScrollViewInsideWindowedRow() {
        // Two reply channels in one pass: the OUTER windowed stack reports
        // its slice to the outer ScrollView, while the INNER ScrollView
        // overwrites the window env for ITS content. Corruption here shows
        // as the outer band adopting the inner stack's slice (wrong rows on
        // screen) or the inner list rendering its full height.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<1_000, id: \.self) { i in
                    if i == 3 {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(0..<300, id: \.self) { j in Text("inner \(j)") }
                            }
                        }
                        .frame(height: 3)
                    } else {
                        Text("outer \(i)")
                    }
                }
            }
        }
        .frame(height: 8)

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
        let lines = buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }

        #expect(lines.contains { $0.contains("outer 0") }, "outer content renders: \(lines)")
        #expect(lines.contains { $0.contains("inner 0") }, "the inner list renders its head: \(lines)")
        #expect(
            !lines.contains { $0.contains("inner 200") },
            "the inner list is windowed to ITS viewport, not fully rendered: \(lines)")
        #expect(buffer.height <= 8, "the outer band stayed clipped: height \(buffer.height)")
    }

    @Test("Anchored .bottom and .center scrollTo align exactly despite estimates")
    func anchoredBottomAndCenterExactness() {
        // §5e's claim: the anchor pins to the TARGET and the alignment walk
        // measures REAL rows — so .bottom lands the target as the last
        // content line and .center puts it mid-viewport, estimates
        // notwithstanding. The storm only asserted visibility.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<100_000, id: \.self) { i in
                        Text("row \(i)").frame(height: i % 3 + 1)
                    }
                }
            }
            .frame(height: Self.viewport)
        }
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        // .bottom: the target row's LAST line is the last content row
        // (above the "more below" indicator).
        box.proxy?.scrollTo(70_000, anchor: .bottom)
        let bottom = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let bottomContent = bottom.filter { !$0.isEmpty }
        #expect(
            bottomContent.dropLast().last?.contains("row 70000") == true
                || bottomContent.last?.contains("row 70000") == true,
            ".bottom bottom-aligns the target: \(bottom)")

        // .center: the target sits mid-viewport (rows above AND below it).
        box.proxy?.scrollTo(50_001, anchor: .center)
        let centered = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let index = centered.firstIndex(where: { $0.contains("row 50001") }) else {
            Issue.record(".center target visible: \(centered)")
            return
        }
        #expect(
            (2...4).contains(index),
            ".center puts the target mid-viewport, not at an edge: index \(index) in \(centered)")
    }

    @Test("scrollTo against EAGER content (plain VStack) works on the exact path")
    func scrollToEagerContent() {
        // ScrollView { VStack { ForEach } } — the most natural SwiftUI
        // composition. The keyed rows resolve through the same windowed
        // machinery (the exact path below the threshold), so scrollTo must
        // land, and an already-visible nil-anchor target must not move.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<200, id: \.self) { i in Text("row \(i)") }
                }
            }
            .frame(height: Self.viewport)
        }
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        box.proxy?.scrollTo(150, anchor: .top)
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(jumped[1].contains("row 150"), "eager scrollTo top-aligns: \(jumped)")

        box.proxy?.scrollTo(152)
        let unmoved = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(unmoved == jumped, "visible nil-anchor target is a no-op: \(unmoved)")
    }
}
