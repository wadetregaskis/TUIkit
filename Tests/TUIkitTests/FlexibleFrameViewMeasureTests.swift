//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FlexibleFrameViewMeasureTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Characterization tests pinning that `FlexibleFrameView`'s `Layoutable`
/// `sizeThatFits` returns *exactly* what the render-to-measure fallback used to
/// return — for every frame-constraint shape, content shape, and proposal.
///
/// `FlexibleFrameView` was `Renderable` but not `Layoutable`, so `measureChild`
/// measured it by rendering the subtree twice (natural size, then 8 cells wider
/// to probe width-flexibility). Making it `Layoutable` replaces that with a
/// single structural measure; these tests guarantee the *result* is unchanged,
/// so the layout the stacks compute from it cannot shift.
@MainActor
@Suite("FlexibleFrameView measure parity")
struct FlexibleFrameViewMeasureTests {
    /// A render context with the state storage the composite render path needs.
    private func ctx(width: Int = 80, height: Int = 24) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext())
    }

    /// The exact render-to-measure fallback `measureChild` applied before
    /// `FlexibleFrameView` became `Layoutable` — the ground truth to match.
    private func referenceMeasure<V: View>(
        _ view: V, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        var measureContext = context
        measureContext.isMeasuring = true
        measureContext.hasExplicitWidth = false
        if let width = proposal.width { measureContext.availableWidth = width }
        if let height = proposal.height { measureContext.availableHeight = height }
        let buffer = renderToBuffer(view, context: measureContext)
        let naturalWidth = buffer.width

        var probeContext = measureContext
        probeContext.availableWidth = naturalWidth + 8
        let probedWidth = renderToBuffer(view, context: probeContext).width

        if probedWidth > naturalWidth {
            return ViewSize.flexibleWidth(minWidth: naturalWidth, height: buffer.height)
        }
        return ViewSize.fixed(naturalWidth, buffer.height)
    }

    /// The proposals × contexts to measure each framed view under. Includes a
    /// roomy width, a mid squeeze, and a width narrow enough to force wrapping
    /// and content overflow (the edge the +8 probe is fussiest about).
    private var scenarios: [(label: String, proposal: ProposedSize, context: RenderContext)] {
        [
            ("unspecified@80", .unspecified, ctx(width: 80)),
            ("propW40@80", ProposedSize(width: 40, height: nil), ctx(width: 80)),
            ("propW12@80", ProposedSize(width: 12, height: nil), ctx(width: 80)),
            ("unspecified@30", .unspecified, ctx(width: 30)),
            ("propWH@80", ProposedSize(width: 24, height: 6), ctx(width: 80, height: 24)),
        ]
    }

    /// Asserts the `Layoutable` measure equals the render-twice fallback for
    /// `view` across every scenario.
    private func expectParity<V: View>(
        _ view: V, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for scenario in scenarios {
            let viaLayoutable = measureChild(view, proposal: scenario.proposal, context: scenario.context)
            let viaFallback = referenceMeasure(view, proposal: scenario.proposal, context: scenario.context)
            #expect(
                viaLayoutable == viaFallback,
                "\(label) @ \(scenario.label): layoutable=\(viaLayoutable) fallback=\(viaFallback)",
                sourceLocation: sourceLocation)
        }
    }

    @Test("Fixed single-line content, every width shape")
    func fixedContentWidthShapes() {
        let text = Text("Hello world")
        expectParity(text.frame(maxWidth: .infinity), "Text.frame(maxWidth: .infinity)")
        expectParity(text.frame(width: 20), "Text.frame(width: 20)")
        expectParity(text.frame(minWidth: 10), "Text.frame(minWidth: 10)")
        expectParity(text.frame(minWidth: 10, maxWidth: .infinity), "Text.frame(minWidth: 10, maxWidth: .infinity)")
        expectParity(text.frame(idealWidth: 15), "Text.frame(idealWidth: 15)")
        expectParity(text.frame(maxWidth: .fixed(30)), "Text.frame(maxWidth: .fixed(30))")
        expectParity(text.frame(minWidth: 40), "Text.frame(minWidth: 40)")  // min exceeds content
    }

    @Test("Height constraints")
    func heightShapes() {
        let text = Text("Hello")
        expectParity(text.frame(height: 5), "Text.frame(height: 5)")
        expectParity(text.frame(minHeight: 4), "Text.frame(minHeight: 4)")
        expectParity(text.frame(maxHeight: .infinity), "Text.frame(maxHeight: .infinity)")
        expectParity(text.frame(width: 20, height: 5), "Text.frame(width: 20, height: 5)")
        expectParity(
            text.frame(maxWidth: .infinity, maxHeight: .infinity),
            "Text.frame(maxWidth: .infinity, maxHeight: .infinity)")
    }

    @Test("Multi-line / wrapping content")
    func multiLineContent() {
        let stack = VStack(alignment: .leading) {
            Text("First line")
            Text("A noticeably longer second line that can wrap")
        }
        expectParity(stack.frame(maxWidth: .infinity), "VStack.frame(maxWidth: .infinity)")
        expectParity(stack.frame(width: 18), "VStack.frame(width: 18)")
        expectParity(stack.frame(minWidth: 12), "VStack.frame(minWidth: 12)")
        expectParity(stack.frame(maxWidth: .infinity, alignment: .center), "VStack.frame(maxWidth: .infinity, .center)")
    }

    @Test("Flexible content (nested frame fills)")
    func flexibleContent() {
        // The inner frame makes the content itself width-flexible, exercising
        // the `isWidthFlexible ? fill : keep` branch of the structural measure.
        let flexible = Text("inner").frame(maxWidth: .infinity)
        expectParity(flexible.frame(maxWidth: .infinity), "flex.frame(maxWidth: .infinity)")
        expectParity(flexible.frame(width: 25), "flex.frame(width: 25)")
        expectParity(flexible.frame(minWidth: 10), "flex.frame(minWidth: 10)")
        expectParity(flexible.frame(maxWidth: .fixed(30)), "flex.frame(maxWidth: .fixed(30))")
    }

    @Test("Bordered flexible content")
    func borderedContent() {
        let box = VStack { Text("A"); Text("B") }.border()
        expectParity(box.frame(maxWidth: .infinity), "box.frame(maxWidth: .infinity)")
        expectParity(box.frame(width: 16), "box.frame(width: 16)")
    }
}
