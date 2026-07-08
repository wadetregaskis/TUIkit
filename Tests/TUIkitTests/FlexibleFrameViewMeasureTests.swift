//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FlexibleFrameViewMeasureTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Pins `FlexibleFrameView`'s analytic `sizeThatFits` to the real layout
/// contract: the measured size must equal what the frame actually renders at
/// the same availability, and the flexibility flags must follow the `ViewSize`
/// contract.
///
/// History: `FlexibleFrameView` was originally measured through the
/// render-to-measure fallback (render the subtree, then again 8 cells wider to
/// probe width growth), and this suite once pinned the `Layoutable` measure to
/// byte-match that probe. The probe is now fully retired — rendering to
/// measure made every nested `.frame` measure a pair of full subtree renders,
/// which compounded multiplicatively through nested stacks (issue #7) — and
/// two of its answers were wrong per the documented contract: it reported
/// *wrapping* content as width-flexible (reflow is not flexibility), and it
/// could never report height-flexibility at all (`maxHeight: .infinity`
/// frames measured as fixed). The ground truth here is therefore the render
/// itself, not the probe.
@MainActor
@Suite("FlexibleFrameView measure parity")
struct FlexibleFrameViewMeasureTests {
    /// A render context with the state storage the composite render path needs.
    private func ctx(width: Int = 80, height: Int = 24) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()).isolatingRenderCache()
    }

    /// What the frame actually draws under `proposal` — the ground truth the
    /// measure must match. Applies the proposal to the context the same way
    /// `renderChild` applies an allocation.
    private func renderedSize<V: View>(
        _ view: V, proposal: ProposedSize, context: RenderContext
    ) -> (width: Int, height: Int) {
        var renderContext = context
        if let width = proposal.width { renderContext.availableWidth = width }
        if let height = proposal.height { renderContext.availableHeight = height }
        let buffer = renderToBuffer(view, context: renderContext)
        return (buffer.width, buffer.height)
    }

    /// The proposals × contexts to measure each framed view under. Includes a
    /// roomy width, a mid squeeze, and a width narrow enough to force wrapping
    /// and content overflow.
    private var scenarios: [(label: String, proposal: ProposedSize, context: RenderContext)] {
        [
            ("unspecified@80", .unspecified, ctx(width: 80)),
            ("propW40@80", ProposedSize(width: 40, height: nil), ctx(width: 80)),
            ("propW12@80", ProposedSize(width: 12, height: nil), ctx(width: 80)),
            ("unspecified@30", .unspecified, ctx(width: 30)),
            ("propWH@80", ProposedSize(width: 24, height: 6), ctx(width: 80, height: 24)),
        ]
    }

    /// Asserts the `Layoutable` measure reports exactly the size the frame
    /// renders, for `view` across every scenario.
    ///
    /// Height is only compared for height-*fixed* reports: a height-flexible
    /// report is a minimum, and the render fills whatever the context offers
    /// (`maxHeight: .infinity` at 24 rows renders 24 tall however little it
    /// needs). Width reports always coincide with the rendered width — even
    /// flexible ones report the filled width at this availability.
    private func expectRenderParity<V: View>(
        _ view: V, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for scenario in scenarios {
            let measured = measureChild(view, proposal: scenario.proposal, context: scenario.context)
            let rendered = renderedSize(view, proposal: scenario.proposal, context: scenario.context)
            #expect(
                measured.width == rendered.width,
                "\(label) @ \(scenario.label): measured width \(measured.width) != rendered \(rendered.width)",
                sourceLocation: sourceLocation)
            if !measured.isHeightFlexible {
                #expect(
                    measured.height == rendered.height,
                    "\(label) @ \(scenario.label): measured height \(measured.height) != rendered \(rendered.height)",
                    sourceLocation: sourceLocation)
            }
        }
    }

    @Test("Fixed single-line content, every width shape")
    func fixedContentWidthShapes() {
        let text = Text("Hello world")
        expectRenderParity(text.frame(maxWidth: .infinity), "Text.frame(maxWidth: .infinity)")
        expectRenderParity(text.frame(width: 20), "Text.frame(width: 20)")
        expectRenderParity(text.frame(minWidth: 10), "Text.frame(minWidth: 10)")
        expectRenderParity(text.frame(minWidth: 10, maxWidth: .infinity), "Text.frame(minWidth: 10, maxWidth: .infinity)")
        expectRenderParity(text.frame(idealWidth: 15), "Text.frame(idealWidth: 15)")
        expectRenderParity(text.frame(maxWidth: .fixed(30)), "Text.frame(maxWidth: .fixed(30))")
        expectRenderParity(text.frame(minWidth: 40), "Text.frame(minWidth: 40)")  // min exceeds content
    }

    @Test("Height constraints")
    func heightShapes() {
        let text = Text("Hello")
        expectRenderParity(text.frame(height: 5), "Text.frame(height: 5)")
        expectRenderParity(text.frame(minHeight: 4), "Text.frame(minHeight: 4)")
        expectRenderParity(text.frame(maxHeight: .infinity), "Text.frame(maxHeight: .infinity)")
        expectRenderParity(text.frame(width: 20, height: 5), "Text.frame(width: 20, height: 5)")
        expectRenderParity(
            text.frame(maxWidth: .infinity, maxHeight: .infinity),
            "Text.frame(maxWidth: .infinity, maxHeight: .infinity)")
    }

    @Test("Multi-line / wrapping content")
    func multiLineContent() {
        let stack = VStack(alignment: .leading) {
            Text("First line")
            Text("A noticeably longer second line that can wrap")
        }
        expectRenderParity(stack.frame(maxWidth: .infinity), "VStack.frame(maxWidth: .infinity)")
        expectRenderParity(stack.frame(width: 18), "VStack.frame(width: 18)")
        expectRenderParity(stack.frame(minWidth: 12), "VStack.frame(minWidth: 12)")
        expectRenderParity(stack.frame(maxWidth: .infinity, alignment: .center), "VStack.frame(maxWidth: .infinity, .center)")
    }

    @Test("Flexible content (nested frame fills)")
    func flexibleContent() {
        // The inner frame makes the content itself width-flexible, exercising
        // the `isWidthFlexible ? fill : keep` branch of the structural measure.
        let flexible = Text("inner").frame(maxWidth: .infinity)
        expectRenderParity(flexible.frame(maxWidth: .infinity), "flex.frame(maxWidth: .infinity)")
        expectRenderParity(flexible.frame(width: 25), "flex.frame(width: 25)")
        expectRenderParity(flexible.frame(minWidth: 10), "flex.frame(minWidth: 10)")
        expectRenderParity(flexible.frame(maxWidth: .fixed(30)), "flex.frame(maxWidth: .fixed(30))")
    }

    @Test("Bordered flexible content")
    func borderedContent() {
        let box = VStack { Text("A"); Text("B") }.border()
        expectRenderParity(box.frame(maxWidth: .infinity), "box.frame(maxWidth: .infinity)")
        expectRenderParity(box.frame(width: 16), "box.frame(width: 16)")
    }

    // MARK: - Flexibility flags (the ViewSize contract)

    @Test("Flexibility flags follow the contract")
    func flexibilityFlags() {
        let context = ctx(width: 80, height: 24)
        func flags<V: View>(_ view: V, proposal: ProposedSize = .unspecified) -> (w: Bool, h: Bool) {
            let size = measureChild(view, proposal: proposal, context: context)
            return (size.isWidthFlexible, size.isHeightFlexible)
        }

        // An `.infinity` max fills whatever is offered: always flexible. (The
        // retired probe could never report height-flexibility at all.)
        #expect(flags(Text("x").frame(maxWidth: .infinity)).w)
        #expect(flags(Text("x").frame(maxHeight: .infinity)).h)

        // A fixed-size frame with room for its size is rigid.
        #expect(!flags(Text("x").frame(width: 20)).w)
        #expect(!flags(Text("x").frame(height: 5)).h)

        // A fixed-size frame squeezed below its size renders clamped and grows
        // back when offered more: flexible, reporting the clamped minimum.
        let squeezed = measureChild(
            Text("Hello world").frame(width: 20),
            proposal: ProposedSize(width: 12, height: nil), context: context)
        #expect(squeezed.width == 12 && squeezed.isWidthFlexible)

        // Wrapping content reflows up to its ideal width but never grows past
        // it: fixed, per the ViewSize contract. (The retired probe wrongly
        // called this flexible — its +8 render grew while below the ideal.)
        let wrapping = VStack(alignment: .leading) {
            Text("A noticeably longer line that can wrap")
        }
        #expect(!flags(wrapping.frame(minWidth: 12), proposal: ProposedSize(width: 20, height: nil)).w)

        // Width-flexible content under a fixed max grows until the cap…
        let flexible = Text("inner").frame(maxWidth: .infinity)
        let belowCap = measureChild(
            flexible.frame(maxWidth: .fixed(30)),
            proposal: ProposedSize(width: 12, height: nil), context: context)
        #expect(belowCap.width == 12 && belowCap.isWidthFlexible)

        // …and is rigid once the cap is reached.
        let atCap = measureChild(
            flexible.frame(maxWidth: .fixed(30)), proposal: .unspecified, context: context)
        #expect(atCap.width == 30 && !atCap.isWidthFlexible)
    }
}
