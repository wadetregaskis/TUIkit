//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollInteractionEdgeTests.swift
//
//  Edge interactions between programmatic scrolls, the reveal snap, and
//  extreme viewports: a scrollTo landing in the SAME frame as a focus
//  change must win over the snap on that frame AND every later one; a
//  degenerate (1-2 row) viewport must not oscillate as the focused row and
//  the indicator fight over the only line; a ScrollViewReader parked over
//  several ScrollViews broadcasts — the one holding the key moves, the
//  others stay put.
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
@Suite("scroll interaction edges")
struct ScrollInteractionEdgeTests {

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager, height: Int
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: height,
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

    @Test("scrollTo in the same frame as a focus CHANGE is not yanked back")
    func scrollToSurvivesSameFrameFocusChange() {
        // The reveal snap fires on focusJustChanged; a programmatic scroll
        // arriving in the same event turn must win on the scroll frame
        // (suppression) AND on every later frame (the lastFocusedID baseline
        // must advance to the NEW id even while suppressed — otherwise the
        // NEXT frame sees "focus just changed" and snaps back to the button).
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<100_000, id: \.self) { i in
                        Button("row \(i)") {}
                    }
                }
            }
            .frame(height: 6)
        }
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 6)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 6)

        // One event turn: Tab moves focus (row 0 → row 1) AND the app calls
        // scrollTo far away.
        focusManager.focusNext()
        box.proxy?.scrollTo(60_000, anchor: .top)
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 6)
        #expect(jumped.contains { $0.contains("row 60000") }, "the scroll won the frame: \(jumped)")

        // And it STICKS: the focused (off-band, grafted) button must not
        // yank the viewport back on any later frame.
        let later = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 6)
        #expect(
            later.contains { $0.contains("row 60000") },
            "no deferred snap-back to the focused row: \(later)")
    }

    @Test("Degenerate viewports (1-3 rows) always show content, never only chrome")
    func degenerateViewportsShowContent() {
        // Indicators REPLACE viewport lines: without a floor, a 1-2 row
        // viewport scrolled mid-content was 100% chrome — "▼ N more below"
        // as the ENTIRE view, at every offset, forever. Content must win
        // the last line(s): at h ≤ 2 no indicators render at all, and at
        // any height every frame of a scroll walk shows at least one
        // content row.
        for height in 1...3 {
            let tuiContext = TUIContext()
            let focusManager = FocusManager()
            let view = ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<20, id: \.self) { i in Text("row \(i)") }
                }
            }
            .frame(height: height)

            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: height)
            for step in 0..<8 {
                _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down))
                let frame = renderFrame(
                    view, tuiContext: tuiContext, focusManager: focusManager, height: height)
                #expect(
                    frame.contains { $0.contains("row ") },
                    "height \(height) step \(step): a frame of pure chrome: \(frame)")
            }
        }
    }

    @Test("A reader over two ScrollViews moves only the one holding the key")
    func registryBroadcastResolvesIndependently() {
        // ScrollToRegistry parks the request on EVERY live handler; each
        // resolves against its own content. The scroll view without the key
        // clears it as a no-op and must not move.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<300, id: \.self) { i in Text("a \(i)") }
                    }
                }
                .frame(height: 6)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(1_000..<1_300, id: \.self) { i in Text("b \(i)") }
                    }
                }
                .frame(height: 6)
            }
        }
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 12)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 12)

        // Key exists only in scroll view B: A stays at its top.
        box.proxy?.scrollTo(1_200, anchor: .top)
        let frame = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 12)
        #expect(frame.contains { $0.contains("b 1200") }, "B jumped to its key: \(frame)")
        #expect(frame.contains { $0.contains("a 0") }, "A did not move: \(frame)")

        // Key exists only in A: B must stay where it is now.
        box.proxy?.scrollTo(150, anchor: .top)
        let second = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 12)
        #expect(second.contains { $0.contains("a 150") }, "A jumped to its key: \(second)")
        #expect(second.contains { $0.contains("b 1200") }, "B did not move: \(second)")
    }
}
