//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewReaderTests.swift
//
//  ScrollViewReader / ScrollViewProxy.scrollTo(_:anchor:) — SwiftUI-parity
//  programmatic scrolling over the seek machinery of "Locating things
//  without drawing them": the request rides the ScrollContentWindow
//  handshake, the stack that finds the key renders its band AT the resolved
//  offset (same-frame, O(window)), and the ScrollView adopts the answer.
//  Covers all three seek paths (uniform arithmetic, anchored walk, exact
//  slots), the reveal-snap suppression that keeps the triggering Button
//  from yanking the viewport back, and the bottom-glue release.
//
//  Created by Wade Tregaskis
//  License: MIT

// The `let _ = box.proxy = proxy` captures below are inside @ViewBuilder
// closures, where a bare `_ = …` statement doesn't compile (result builders
// accept declarations, not Void expression statements) — `let _` is the
// standard SwiftUI idiom for side effects in a builder.
// swiftlint:disable redundant_discardable_let

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Captures the proxy handed to the reader's content so the test can call
/// `scrollTo` at "event time", exactly as an app closure would.
private final class ProxyBox: @unchecked Sendable {
    var proxy: ScrollViewProxy?
}

@MainActor
@Suite("ScrollViewReader / scrollTo")
struct ScrollViewReaderTests {
    private static let viewport = 6

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

    private func makeUniformView(box: ProxyBox, rows: Int = 100_000) -> some View {
        ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { i in Text("row \(i)") }
                }
            }
            .frame(height: Self.viewport)
        }
    }

    @Test("scrollTo(anchor: .top) puts the row on the first line (uniform, exact)")
    func uniformTopAnchor() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = makeUniformView(box: box)

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("row 0") }, "starts at the top: \(first)")
        #expect(box.proxy != nil, "the reader hands its content the proxy")

        box.proxy?.scrollTo(50_000, anchor: .top)
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        // Viewport 6 with edge indicators: [▲ indicator, target, +3 rows, ▼].
        #expect(jumped[1].contains("row 50000"), "exact top alignment: \(jumped)")
        #expect(jumped.contains { $0.contains("row 50003") }, "…viewport fills below: \(jumped)")
    }

    @Test("scrollTo anchors: .bottom and .center land exactly (uniform)")
    func uniformBottomAndCenterAnchors() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = makeUniformView(box: box)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        box.proxy?.scrollTo(99_999, anchor: .bottom)
        let tail = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(tail.last?.contains("row 99999") == true, "bottom alignment: \(tail)")

        box.proxy?.scrollTo(500, anchor: .center)
        let centred = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        // Centred between the edge indicators: neighbours visible both sides.
        #expect(centred.contains { $0.contains("row 499") }, "centre alignment: \(centred)")
        #expect(centred.contains { $0.contains("row 500") }, "centre alignment: \(centred)")
        #expect(centred.contains { $0.contains("row 501") }, "centre alignment: \(centred)")
    }

    @Test("scrollTo(nil anchor): minimal movement, none when already visible")
    func nilAnchorMinimalMovement() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = makeUniformView(box: box)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        // Below the viewport → scrolls just enough: the row bottom-aligns.
        box.proxy?.scrollTo(1_000)
        let revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        // Bottom-aligned above the "▼ more below" indicator row.
        #expect(revealed[4].contains("row 1000"), "bottom-aligned reveal: \(revealed)")

        // Already visible → no movement at all.
        box.proxy?.scrollTo(997)
        let unmoved = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(unmoved == revealed, "already visible is a no-op: \(unmoved)")

        // Above the viewport → top-aligns.
        box.proxy?.scrollTo(100)
        let upward = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(upward[1].contains("row 100"), "top-aligned upward reveal: \(upward)")
    }

    @Test("Unknown id is a no-op, and the request doesn't linger")
    func unknownIDNoOp() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = makeUniformView(box: box)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        box.proxy?.scrollTo(500, anchor: .top)
        let at500 = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        box.proxy?.scrollTo("no such row", anchor: .top)
        let after = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(after == at500, "unknown id moves nothing: \(after)")
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled == at500, "…and is not a standing intent: \(settled)")
    }

    @Test("scrollTo works on the anchored path (variable heights)")
    func anchoredPathScrollTo() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
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

        // The anchor is pinned to the target row's IDENTITY, so .top is
        // exact even though the absolute offset is an estimate.
        box.proxy?.scrollTo(70_000, anchor: .top)
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(jumped[1].contains("row 70000"), "anchored top: \(jumped)")

        // Upward jump too (well above the current window).
        box.proxy?.scrollTo(10, anchor: .top)
        let upward = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(upward[1].contains("row 10"), "anchored upward: \(upward)")
    }

    @Test("scrollTo works on the exact path (small, variable, eager)")
    func exactPathScrollTo() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<50, id: \.self) { i in
                        Text("row \(i)").frame(height: i % 2 + 1)
                    }
                }
            }
            .frame(height: Self.viewport)
        }
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        box.proxy?.scrollTo(30, anchor: .top)
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(jumped[1].contains("row 30"), "exact-path top: \(jumped)")
    }

    @Test("A Button-triggered jump wins over the reveal snap — and sticks")
    func buttonTriggeredJumpIsNotYankedBack() {
        // The classic composition: the trigger is a focused Button INSIDE
        // the scroll view. Activating it bumps the interaction generation —
        // the reveal snap's own fire condition — and the button stays both
        // focused and off-band after the jump. Without suppression (this
        // frame) and baseline advance (every later frame), the snap would
        // scroll straight back to the button.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<100_000, id: \.self) { i in
                        Button("row \(i)") { box.proxy?.scrollTo(99_999, anchor: .bottom) }
                    }
                }
            }
            .frame(height: Self.viewport)
        }
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let focusedID = focusManager.currentFocusedID
        #expect(focusedID != nil, "the first button auto-focuses")

        // Enter activates the focused button → its action calls scrollTo.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(jumped.last?.contains("row 99999") == true, "the jump lands: \(jumped)")
        #expect(focusManager.currentFocusedID == focusedID, "the trigger keeps focus")

        // And STICKS: later frames must not snap back to the focused
        // trigger (baselines advanced despite the suppressed snap).
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled.last?.contains("row 99999") == true, "no yank-back: \(settled)")
        #expect(!settled.contains { $0.contains("row 0 ") }, "the trigger stays off-screen")
    }

    @Test("scrollTo releases the bottom glue (follow mode)")
    func scrollToReleasesBottomGlue() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        func makeView(lines: Int) -> some View {
            ScrollViewReader { proxy in
                let _ = box.proxy = proxy
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<lines, id: \.self) { i in Text("line \(i)") }
                    }
                }
                .frame(height: Self.viewport)
                .defaultScrollAnchor(.bottom)
            }
        }
        let first = renderFrame(
            makeView(lines: 1_000), tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("line 999") }, "starts glued to the tail: \(first)")

        box.proxy?.scrollTo(0, anchor: .top)
        let top = renderFrame(
            makeView(lines: 1_000), tuiContext: tuiContext, focusManager: focusManager)
        #expect(top.first?.contains("line 0") == true, "the jump beats the glue: \(top)")  // offset 0: no top indicator

        // Appends must not pull the view back down: the programmatic
        // scroll released the follow, exactly like scrolling up by hand.
        let grown = renderFrame(
            makeView(lines: 1_200), tuiContext: tuiContext, focusManager: focusManager)
        #expect(grown.first?.contains("line 0") == true, "the glue stays released: \(grown)")
    }

    @Test("The registry sweeps dead scroll views and reaches live ones")
    func registryLifecycle() {
        let registry = ScrollToRegistry()
        var handler: ScrollViewHandler? = ScrollViewHandler(focusID: "sv-live")
        let identity = ViewIdentity(path: "Root/ScrollView")
        registry.register(handler: handler!, identity: identity, renderCache: nil)

        registry.scrollTo(key: "42", anchor: .top)
        #expect(
            handler?.pendingScrollTo == ScrollToRequest(key: "42", anchor: .top),
            "a live handler receives the parked request")

        handler = nil
        registry.scrollTo(key: "43", anchor: nil)  // sweeps the dead entry, no crash
    }
}

// swiftlint:enable redundant_discardable_let
