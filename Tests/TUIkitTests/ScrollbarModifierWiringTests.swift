//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollbarModifierWiringTests.swift
//
//  The public scrollbar option modifiers — .scrollbarArrows(_:),
//  .scrollbarClickBehavior(_:), .scrollbarProportionalThumb(_:) — are wired
//  through the ENVIRONMENT into the rendered gutter and the click routing.
//  ScrollbarInteractionTests exercises the behaviours via direct handler
//  parameters; these tests cover the modifier → environment → render seam
//  (the documented "test passed while the app broke" failure mode).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scrollbar option modifiers wire through the environment")
struct ScrollbarModifierWiringTests {

    private func makeContext(tui: TUIContext, width: Int = 24, height: Int = 10) -> RenderContext {
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui
        ).isolatingRenderCache()
    }

    private func overflowingScrollView() -> some View {
        ScrollView {
            VStack {
                ForEach(0..<100, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollbarVisibility(.visible)
    }

    /// Counts arrow glyphs in the rendered buffer's gutter.
    private func arrowCount(_ buffer: FrameBuffer) -> Int {
        buffer.lines.reduce(0) { count, line in
            count + line.stripped.filter { $0 == "▲" || $0 == "▼" }.count
        }
    }

    @Test(".scrollbarArrows(.double) draws both arrows at each end (4 total)")
    func doubleArrowsRender() {
        let tui = TUIContext()
        let single = renderToBuffer(
            overflowingScrollView().scrollbarArrows(.single),
            context: makeContext(tui: tui))
        #expect(arrowCount(single) == 2, "single: ▲ … ▼, got \(arrowCount(single))")

        let tui2 = TUIContext()
        let double = renderToBuffer(
            overflowingScrollView().scrollbarArrows(.double),
            context: makeContext(tui: tui2))
        #expect(arrowCount(double) == 4, "double: ▲▼ … ▲▼, got \(arrowCount(double))")
    }

    @Test(".scrollbarClickBehavior selects jump-to-position vs page-by-page")
    func clickBehaviorRoutesThroughModifier() {
        /// Renders an overflowing ScrollView with the given behaviour, clicks
        /// low on the scrollbar track, and returns the first visible row
        /// index after the resulting scroll.
        func firstRowAfterTrackClick(_ behavior: ScrollbarClickBehavior) -> Int? {
            let tui = TUIContext()
            let dispatcher = tui.mouseEventDispatcher
            dispatcher.setActiveSupport(.full)
            dispatcher.beginRenderPass()
            let context = makeContext(tui: tui)
            let view = overflowingScrollView().scrollbarClickBehavior(behavior)

            // Two renders settle the handler's lazily-measured content height.
            _ = renderToBuffer(view, context: context)
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)

            // Click low on the track: the rightmost column, one row above the
            // bottom arrow.
            let x = buffer.width - 1
            let y = buffer.height - 2
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

            let after = renderToBuffer(view, context: context)
            for line in after.lines {
                let stripped = line.stripped
                if let range = stripped.range(of: #"row (\d+)"#, options: .regularExpression),
                    let n = Int(stripped[range].dropFirst(4)) {
                    return n
                }
            }
            return nil
        }

        guard let jumped = firstRowAfterTrackClick(.jump),
            let paged = firstRowAfterTrackClick(.page)
        else {
            Issue.record("scroll content not rendered")
            return
        }
        // A jump lands proportionally near the click (~80% down a 100-row
        // list); a page moves roughly one viewport from the top.
        #expect(jumped > 50, ".jump lands near the click position, got row \(jumped)")
        #expect(paged < 30, ".page moves about one viewport, got row \(paged)")
        #expect(jumped > paged, "the two behaviours are distinct")
    }

    /// `.scrollbarVisibility` is an ENVIRONMENT value, so it reaches nested
    /// scrollables too — SwiftUI-parity behaviour, matching `.scrollIndicators`.
    ///
    /// This is deliberate, and it is worth pinning: it was mistaken for a bug
    /// when a demo page's page-level `.automatic` gave every scrollable inside
    /// it a bar, including one whose whole point was to be chrome-free. The
    /// wrapper was at fault, not the propagation. Both halves are asserted —
    /// that an inner scrollable inherits an outer setting, and that its own
    /// explicit setting still wins.
    @Test("scrollbarVisibility reaches nested scrollables, and the inner one wins")
    func visibilityPropagatesButInnerWins() {
        func innerHasBar(outer: ScrollbarVisibility, inner: ScrollbarVisibility?) -> Bool {
            let tui = TUIContext()
            var content: any View = ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<60, id: \.self) { Text("row \($0)") }
                }
            }
            .frame(height: 6)
            if let inner { content = AnyView(content).scrollbarVisibility(inner) }
            let view = AnyView(content).scrollbarVisibility(outer)

            let buffer = renderToBuffer(view, context: makeContext(tui: tui))
            // A bar draws its arrows in the last column; the indicators instead
            // replace a whole line with "N more ... below" text.
            return buffer.lines.contains { $0.stripped.hasSuffix("\u{25B2}") }
                || buffer.lines.contains { $0.stripped.hasSuffix("\u{25BC}") }
        }

        #expect(
            innerHasBar(outer: .automatic, inner: nil),
            "an inner scrollable inherits the ancestor's .automatic")
        #expect(
            !innerHasBar(outer: .automatic, inner: .hidden),
            "its own .hidden overrides the ancestor")
        #expect(
            innerHasBar(outer: .hidden, inner: .visible),
            "and its own .visible overrides an ancestor's .hidden")
    }
}
