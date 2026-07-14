//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageCellAspectTests.swift
//
//  End-to-end coverage of `.imageCellAspect(_:)` — the modifier → environment →
//  `_ImageCore` threading past the converter math (which
//  `ImageTests.targetSizeCellAspect` already pins). The pre-load placeholder
//  box is the deterministic surface: its height is `fitWidth / cellAspect`
//  (bounded by the offer), computed from the environment value the modifier
//  sets, so a wrong or stale aspect is visible in plain buffer geometry.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Image cell-aspect threading")
struct ImageCellAspectTests {

    /// A snapshot context (lifecycle pinned so `.task` never fires — the
    /// image stays in the `.loading` placeholder phase, same rationale as
    /// `ImageRenderTests`). The offer is TALLER than any expected placeholder
    /// so the aspect-derived height is what bounds the box.
    private func makeContext(
        width: Int = 20, height: Int = 24,
        tuiContext: TUIContext? = nil,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        configure(&environment)
        let tui =
            tuiContext
            ?? TUIContext(
                lifecycle: LifecycleManager(firesEffects: false),
                keyEventDispatcher: KeyEventDispatcher(),
                preferences: PreferenceStorage()
            )
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: tui
        ).isolatingRenderCache()
    }

    /// The measured placeholder: wrap in a VStack so the parent lays the
    /// Image out at its `sizeThatFits` answer instead of the whole offer.
    private func placeholderHeight(aspect: Double?, width: Int = 20) -> Int {
        let base = Image(.file("/no/such/image.png"))
        let image = aspect.map { AnyView(base.imageCellAspect($0)) } ?? AnyView(base)
        return renderToBuffer(VStack { image }, context: makeContext(width: width)).height
    }

    @Test(
        "The placeholder box height is fitWidth / cellAspect (threaded via the modifier)",
        arguments: [
            // (aspect, expectedHeight) at fitWidth 20, offer height 24
            (1.0, 20),  // square cells: as tall as it is wide
            (2.0, 10),  // the default terminal aspect
            (4.0, 5),  // very tall cells: a quarter of the width
        ])
    func placeholderTracksAspect(aspect: Double, expected: Int) {
        #expect(placeholderHeight(aspect: aspect) == expected)
    }

    @Test("No modifier means the 2.0 default")
    func defaultAspect() {
        #expect(placeholderHeight(aspect: nil) == placeholderHeight(aspect: 2.0))
    }

    @Test("A zero or negative aspect falls back to the 2.0 default", arguments: [0.0, -1.5])
    func nonPositiveAspectFallsBack(bogus: Double) {
        #expect(placeholderHeight(aspect: bogus) == placeholderHeight(aspect: 2.0))
    }

    @Test("Changing the aspect between renders of the same identity re-renders (no stale memo)")
    func aspectChangeInvalidatesCachedRender() {
        // The staleness bug class: a render cache / memo keyed WITHOUT the
        // aspect would serve the first frame's buffer after the environment
        // value changes on the same TUIContext + view identity.
        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage()
        )
        let view = VStack { Image(.file("/no/such/image.png")) }

        // ONE context (one render cache, one state storage, one identity) —
        // only the environment's aspect differs between the two renders.
        let context1 = makeContext(tuiContext: tui) { $0.imageCellAspect = 1.0 }
        var context2 = context1
        context2.environment.imageCellAspect = 4.0

        let first = renderToBuffer(view, context: context1)
        #expect(first.height == 20, "aspect 1.0 → square box, got \(first.height)")

        let second = renderToBuffer(view, context: context2)
        #expect(second.height == 5, "aspect 4.0 re-renders (5 rows), got \(second.height)")
    }
}
