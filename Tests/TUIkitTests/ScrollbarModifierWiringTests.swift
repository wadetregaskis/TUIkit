//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        .scrollIndicators(.visible)
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

    /// `.scrollIndicators` is an ENVIRONMENT value, so it reaches nested
    /// scrollables too — SwiftUI-parity behaviour, matching `.scrollIndicators`.
    ///
    /// This is deliberate, and it is worth pinning: it was mistaken for a bug
    /// when a demo page's page-level `.automatic` gave every scrollable inside
    /// it a bar, including one whose whole point was to be chrome-free. The
    /// wrapper was at fault, not the propagation. Both halves are asserted —
    /// that an inner scrollable inherits an outer setting, and that its own
    /// explicit setting still wins.
    @Test("scrollIndicators reaches nested scrollables, and the inner one wins")
    func visibilityPropagatesButInnerWins() {
        func innerHasBar(outer: ScrollIndicatorVisibility, inner: ScrollIndicatorVisibility?) -> Bool {
            let tui = TUIContext()
            var content: any View = ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<60, id: \.self) { Text("row \($0)") }
                }
            }
            .frame(height: 6)
            if let inner { content = AnyView(content).scrollIndicators(inner) }
            let view = AnyView(content).scrollIndicators(outer)

            let buffer = renderToBuffer(view, context: makeContext(tui: tui))
            // A bar draws its arrows in the last column; the indicators instead
            // replace a whole line with "N more ... below" text.
            return buffer.lines.contains { $0.stripped.hasSuffix("\u{25B2}") }
                || buffer.lines.contains { $0.stripped.hasSuffix("\u{25BC}") }
        }

        #expect(
            innerHasBar(outer: .automatic, inner: nil),
            "an inner scrollable inherits the ancestor's .automatic")
        // `ScrollIndicatorVisibility.hidden` spelled out, not `.hidden`. The `inner`
        // parameter is an Optional, and inside a `#expect` expansion an
        // implicit member in an Optional position can bind to `View.hidden()`
        // — reachable because `Optional` conforms to `View` — instead of to
        // the enum case. It compiles clean and the expectation then fails on a
        // render that is perfectly correct. See HitTestingModifier.swift.
        #expect(
            !innerHasBar(outer: .automatic, inner: ScrollIndicatorVisibility.hidden),
            "its own .hidden overrides the ancestor")
        #expect(
            innerHasBar(outer: .hidden, inner: .visible),
            "and its own .visible overrides an ancestor's .hidden")
    }

    // MARK: - .never, and the axes: argument

    /// Whether a vertical bar and a horizontal bar were drawn.
    ///
    /// Both are read off one render of a view that overflows BOTH ways, so a
    /// per-axis setting has something to be wrong about in either direction.
    private func bars(
        overflowing: Bool = true, _ apply: (AnyView) -> any View
    ) -> (vertical: Bool, horizontal: Bool) {
        let tui = TUIContext()
        let rows = overflowing ? 60 : 2
        let rule = overflowing ? " ————————————————————————————" : ""
        let content = AnyView(
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { Text("row \($0)\(rule)") }
                }
            }
            .frame(width: 20, height: 6))
        let buffer = renderToBuffer(AnyView(apply(content)), context: makeContext(tui: tui))
        let lines = buffer.lines.map(\.stripped)
        return (
            vertical: lines.contains { $0.hasSuffix("\u{25B2}") || $0.hasSuffix("\u{25BC}") },
            horizontal: lines.contains { $0.contains("\u{25C0}") || $0.contains("\u{25B6}") })
    }

    @Test("Both bars are automatic by default — drawn only when overflowing")
    func automaticByDefault() {
        // SwiftUI's default, and reachable here since #555 split the question
        // in two: `.automatic` decides WHETHER, the style decides WHAT. Only
        // the bar style measures, so the automatic default costs nothing in a
        // subtree that asked for the "N more" text or for no indicator at all.
        let fitting = bars(overflowing: false) { $0 }
        #expect(!fitting.vertical && !fitting.horizontal, "nothing to indicate: \(fitting)")

        let drawn = bars { $0 }
        #expect(drawn.vertical && drawn.horizontal, "both axes overflow: \(drawn)")
    }

    @Test(".never draws no bar, exactly as .hidden does")
    func neverIsHidden() {
        // SwiftUI distinguishes them — `.hidden` is a request a platform
        // convention may override, `.never` is unconditional — and nothing here
        // can override a hidden bar, so the two must agree. The case exists so
        // that source written against SwiftUI compiles and means what it says.
        let never = bars { $0.scrollIndicators(ScrollIndicatorVisibility.never) }
        #expect(!never.vertical && !never.horizontal, "\(never)")

        // …and it overrides an ancestor that asked for one, which is the half
        // that would pass by accident if `.never` simply did nothing.
        let overridden = bars {
            AnyView($0.scrollIndicators(ScrollIndicatorVisibility.never).scrollIndicators(.visible))
        }
        #expect(!overridden.vertical && !overridden.horizontal, "\(overridden)")
    }

    @Test("axes: names which bar the setting is about")
    func axesSelectsTheBar() {
        // Both axes are automatic by default and this content overflows both
        // ways, so the argument shows in what it takes AWAY: hiding one axis
        // must leave the other's bar standing.
        let horizontalOnly = bars { $0.scrollIndicators(.hidden, axes: .vertical) }
        #expect(!horizontalOnly.vertical, "hid the named axis: \(horizontalOnly)")
        #expect(horizontalOnly.horizontal, "and only that one: \(horizontalOnly)")

        let verticalOnly = bars { $0.scrollIndicators(.hidden, axes: .horizontal) }
        #expect(!verticalOnly.horizontal, "hid the named axis: \(verticalOnly)")
        #expect(verticalOnly.vertical, "and only that one: \(verticalOnly)")
    }

    /// The point of splitting the question in two (#555): `.hidden` used to
    /// mean "no BAR", and an overflowing view fell back to the "N more lines"
    /// text — so there was no way to ask for no indicator at all, and no way
    /// to ask for the text form without also giving up automatic visibility.
    @Test("Hidden draws neither indicator, whichever style is selected")
    func hiddenDrawsNeitherIndicator() {
        func screen(_ apply: (AnyView) -> any View) -> String {
            let tui = TUIContext()
            let content = AnyView(
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<60, id: \.self) { Text("row \($0)") }
                    }
                }
                .frame(width: 20, height: 6))
            return renderToBuffer(AnyView(apply(content)), context: makeContext(tui: tui))
                .lines.map(\.stripped).joined()
        }
        for style in [ScrollIndicatorStyle.scrollbar, .text] {
            let drawn = screen { $0.scrollIndicatorStyle(style).scrollIndicators(.hidden) }
            #expect(!drawn.contains("\u{25B2}"), "no ▲ under \(style): \(drawn)")
            #expect(!drawn.contains("\u{25BC}"), "no ▼ under \(style): \(drawn)")
            #expect(!drawn.contains("more rows"), "and no text either under \(style): \(drawn)")
        }
        // The same content DOES indicate itself when nothing hides it, so the
        // expectations above are not passing on a view that simply fits.
        let byDefault = screen { $0 }
        #expect(byDefault.contains("\u{25B2}") || byDefault.contains("\u{25BC}"))
    }

    @Test("Two axis-specific calls compose rather than clobbering")
    func axisCallsCompose() {
        // The reason the modifier TRANSFORMS the environment instead of setting
        // it: an unnamed axis has to keep what it inherited, and a plain
        // `.environment` write would reset it to the default. Written as two
        // calls precisely because that is the shape a caller reaches for.
        let neither = bars {
            AnyView(
                $0.scrollIndicators(.hidden, axes: .horizontal)
                    .scrollIndicators(.hidden, axes: .vertical))
        }
        #expect(
            !neither.vertical && !neither.horizontal,
            "each call kept the other's axis hidden: \(neither)")
    }
}
