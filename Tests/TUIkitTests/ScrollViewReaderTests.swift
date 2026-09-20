//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        // This suite predates the visibility/style split (#555): it is about the
        // "N more above / below" arithmetic, which is now a style rather than
        // the default. Ask for it by name; the default is a scrollbar.
        environment.scrollIndicatorStyle = .text
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
        // Bottom-aligned above the "▼ more lines below" indicator row.
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

    @Test("Anchored nil-anchor scrollTo of a visible row is a strict no-op")
    func anchoredNilAnchorVisibleNoOp() {
        // Height profile chosen to poison the pitch estimate: 100 3-tall
        // rows seed pitch ≈ 3, then the visible region is 1-tall — so the
        // target's estimate-space y disagrees badly with the walked offset.
        // Judging "already visible" in estimate space then teleports the
        // view; it must be judged in walked row space and be a no-op.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<600, id: \.self) { i in
                        Text("row \(i)").frame(height: i < 100 ? 3 : 1)
                    }
                }
            }
            .frame(height: Self.viewport)
        }
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        box.proxy?.scrollTo(150, anchor: .top)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled[1].contains("row 150"), "landed on the target: \(settled)")

        // Row 152 is on screen (rows 150-153 are 1-tall in a 6-line
        // viewport with both indicators). SwiftUI parity: nil anchor +
        // visible target = no movement at all.
        box.proxy?.scrollTo(152)
        let after = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(after == settled, "visible target must not move the view: \(after) vs \(settled)")
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

    /// The registry reaches a scroll view the way a `@State` write reaches its
    /// view: an invalidation on the render cache the scroll view rendered with,
    /// which the next pass applies as it starts (`beginRenderPass`) and which is
    /// what asks the run loop for that frame. Counted as the subtree clears a
    /// pass start applies, so a clear made at request time does not count.
    @Test("The registry sweeps dead scroll views and asks each live one's render cache for a frame")
    func registryLifecycle() {
        let registry = ScrollToRegistry()
        let cache = RenderCache()
        var handler: ScrollViewHandler? = ScrollViewHandler(focusID: "sv-live")
        let identity = ViewIdentity(path: "Root/ScrollView")
        registry.register(handler: handler!, identity: identity, renderCache: cache)
        /// Starts a pass and counts the subtree clears it applied.
        func clearsAppliedByNextPass() -> Int {
            let before = cache.stats.subtreeClears
            cache.beginRenderPass()
            return cache.stats.subtreeClears - before
        }

        let beforeRequest = cache.stats.subtreeClears
        registry.scrollTo(key: "42", anchor: .top)
        #expect(
            handler?.pendingScrollTo == ScrollToRequest(key: "42", anchor: .top),
            "a live handler receives the parked request")
        #expect(cache.stats.subtreeClears == beforeRequest, "nothing is cleared until the next pass")
        #expect(clearsAppliedByNextPass() == 1, "the next pass clears the scroll view's subtree")

        handler = nil
        registry.scrollTo(key: "43", anchor: nil)  // sweeps the dead entry, no crash
        #expect(clearsAppliedByNextPass() == 0, "a dead scroll view asks for nothing")
    }

    // MARK: - .id(_:)-tagged targets

    /// The live scroll handler of the frame just rendered — the viewport's own
    /// offset, rather than the text it painted.
    private func liveHandler(_ focusManager: FocusManager) -> ScrollViewHandler? {
        focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
    }

    /// Fifty rows, the tagged target, fifty more. The target's content y is 50
    /// in a viewport of 6, so it is off-screen at rest and nowhere near the
    /// bottom clamp (max offset 95): the only way to reach it is to find it.
    /// A `.top` anchor charges the "N more above" indicator a line, landing the
    /// target on the first CONTENT line at offset 49 — the same offset and the
    /// same line the identical geometry addressed by a `ForEach` identity gets.
    private static let taggedTargetOffset = 49

    @Test("scrollTo reaches a target tagged with .id(_:) — eager VStack content")
    func idTaggedTargetInEagerStack() {
        // Apple's own ScrollViewReader documentation builds its example out of
        // `.id(_:)` tags rather than ForEach identities, so this is the shape
        // ported code arrives in. `ScrollView { VStack { … } }` takes the exact
        // eager seek (`_VStackCore.resolveEagerSeek`).
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<50, id: \.self) { i in Text("row \(i)") }
                    Text("marker").id("MARK")
                    ForEach(50..<100, id: \.self) { i in Text("row \(i)") }
                }
            }
            .frame(height: Self.viewport)
        }

        let resting = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(liveHandler(focusManager)?.scrollOffset == 0, "starts at the top")
        #expect(!resting.contains { $0.contains("marker") }, "the target starts off-screen: \(resting)")

        box.proxy?.scrollTo("MARK", anchor: .top)
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            liveHandler(focusManager)?.scrollOffset == Self.taggedTargetOffset,
            "the viewport moved onto the tag: \(jumped)")
        #expect(jumped[1].contains("marker"), "…on the first content line: \(jumped)")
        #expect(jumped[2].contains("row 50"), "…with its neighbour below it: \(jumped)")
    }

    @Test("scrollTo reaches a target tagged with .id(_:) — windowed LazyVStack content")
    func idTaggedTargetInWindowedStack() {
        // The other exact seek path: a lazy stack that is the scroll view's
        // direct content renders only the rows meeting the viewport
        // (`_VStackCore.renderViewportWindow`) and re-aims the window itself.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<50, id: \.self) { i in Text("row \(i)") }
                    Text("marker").id("MARK")
                    ForEach(50..<100, id: \.self) { i in Text("row \(i)") }
                }
            }
            .frame(height: Self.viewport)
        }

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(liveHandler(focusManager)?.scrollOffset == 0, "starts at the top")

        box.proxy?.scrollTo("MARK", anchor: .top)
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            liveHandler(focusManager)?.scrollOffset == Self.taggedTargetOffset,
            "the viewport moved onto the tag: \(jumped)")
        #expect(jumped[1].contains("marker"), "…on the first content line: \(jumped)")
    }

    @Test("A .id(_:) under further modifiers is still found")
    func idTaggedTargetUnderOuterModifier() {
        // `.id(k)` is rarely the outermost modifier in ported code, and SwiftUI
        // finds the tag wherever it sits in the chain. Horizontal padding keeps
        // the row one line tall, so the target's y — and therefore the expected
        // offset — is the same as the plain case above.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<50, id: \.self) { i in Text("row \(i)") }
                    Text("marker").id("MARK").padding(.horizontal, 1)
                    ForEach(50..<100, id: \.self) { i in Text("row \(i)") }
                }
            }
            .frame(height: Self.viewport)
        }

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        box.proxy?.scrollTo("MARK", anchor: .top)
        let jumped = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            liveHandler(focusManager)?.scrollOffset == Self.taggedTargetOffset,
            "the tag is read through the chain above it: \(jumped)")
        #expect(jumped[1].contains("marker"), "…and lands the same row: \(jumped)")
    }

    @Test("A tag nobody planted is still a no-op")
    func unknownTagIsNoOp() {
        // The matcher now consults two spellings, so the miss case is worth
        // re-pinning: a key neither a ForEach row nor a tag answers to must
        // leave the viewport exactly where it was, and not linger.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<50, id: \.self) { i in Text("row \(i)") }
                    Text("marker").id("MARK")
                    ForEach(50..<100, id: \.self) { i in Text("row \(i)") }
                }
            }
            .frame(height: Self.viewport)
        }

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        box.proxy?.scrollTo("MARK", anchor: .top)
        let landed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        box.proxy?.scrollTo("NO SUCH TAG", anchor: .top)
        let after = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(liveHandler(focusManager)?.scrollOffset == Self.taggedTargetOffset)
        #expect(after == landed, "an unmatched key moves nothing: \(after)")
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled == landed, "…and is not a standing intent: \(settled)")
    }

    @Test("A .id(_:) inside a ForEach row is not a second address for it")
    func idInsideForEachRowIsNotAnAddress() {
        // Deliberate, and the reason the matcher asks a keyed child for its
        // key and nothing else: a row is identified by its element's `id`, and
        // the seek paths that serve a whole-ForEach stack resolve from the
        // data's keys without building a row view — so a tag written inside
        // one could only ever work on some paths. `.tag(_:)` parted from this
        // rule on 2026-09-20 and is the contrast worth keeping in view: it now
        // gives a `ForEach` row its `List` SELECTION value, overriding the
        // element's `id`. Identity is untouched, which is why that is not an
        // address and this test still holds. Pinned at both sizes: 50 rows
        // takes the exact walk, 5,000 the uniform/anchored ladder.
        for rows in [50, 5_000] {
            let tuiContext = TUIContext()
            let focusManager = FocusManager()
            let box = ProxyBox()
            let view = ScrollViewReader { proxy in
                let _ = box.proxy = proxy
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<rows, id: \.self) { i in Text("row \(i)").id("tag\(i)") }
                    }
                }
                .frame(height: Self.viewport)
            }
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

            box.proxy?.scrollTo("tag30", anchor: .top)
            let tagged = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            #expect(
                liveHandler(focusManager)?.scrollOffset == 0,
                "\(rows) rows: the inner tag is no address: \(tagged)")

            // …and the element id it IS addressed by still works, so the
            // no-op above is the rule and not a broken seek.
            box.proxy?.scrollTo(30, anchor: .top)
            let byElement = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            #expect(
                liveHandler(focusManager)?.scrollOffset == 29,
                "\(rows) rows: the row's own id reaches it: \(byElement)")
        }
    }

    @Test("Seeded storm: seeks and data mutations interleave, invariants hold")
    func scrollToMutationStorm() {
        // 150 iterations of random scrollTo (any anchor, both directions,
        // sometimes unknown ids) interleaved with the row count growing and
        // shrinking — with row 0's Button focused throughout. Invariants
        // after every settle frame: the seek target is visible (when its id
        // survived the mutation), the focused row keeps registering (focus
        // is never stolen by the end-of-pass validation), and nothing traps.
        // Variable heights keep the anchored path engaged; the shrink
        // branch dips below the 256-row threshold to cross seek paths.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        func makeView(rows: Int) -> some View {
            ScrollViewReader { proxy in
                let _ = box.proxy = proxy
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<rows, id: \.self) { i in
                            Button("row \(i)") {}.frame(height: i % 3 + 1)
                        }
                    }
                }
                .frame(height: Self.viewport)
            }
        }

        var seed: UInt64 = 0x5EED_5C11
        func rand(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: seed >> 33) % bound
        }

        var rows = 5_000
        renderFrame(makeView(rows: rows), tuiContext: tuiContext, focusManager: focusManager)
        let focusedID = focusManager.currentFocusedID
        #expect(focusedID != nil, "row 0's button auto-focuses")

        let anchors: [UnitPoint?] = [.top, .center, .bottom, nil]
        for iteration in 0..<150 {
            var expectedVisible: Int?
            switch rand(5) {
            case 0:  // grow
                rows = min(20_000, rows + 1 + rand(3_000))
            case 1:  // shrink — sometimes below the anchored threshold
                rows = max(1, rows - 1 - rand(rand(10) == 0 ? 4_900 : 1_500))
            case 2:  // seek to a nonexistent id (must be a clean no-op)
                box.proxy?.scrollTo(rows + 1 + rand(1_000), anchor: anchors[rand(4)])
            default:  // seek to a live row
                let target = rand(rows)
                box.proxy?.scrollTo(target, anchor: anchors[rand(4)])
                expectedVisible = target
            }
            renderFrame(makeView(rows: rows), tuiContext: tuiContext, focusManager: focusManager)
            let settled = renderFrame(
                makeView(rows: rows), tuiContext: tuiContext, focusManager: focusManager)
            if let target = expectedVisible {
                #expect(
                    settled.contains { $0.contains("row \(target) ") || $0.hasSuffix("row \(target)") },
                    "iteration \(iteration) (seed path): row \(target) of \(rows) visible: \(settled)")
            }
            #expect(
                focusManager.currentFocusedID == focusedID,
                "iteration \(iteration): the focused row keeps registering (rows: \(rows))")
        }
    }
}

// swiftlint:enable redundant_discardable_let
