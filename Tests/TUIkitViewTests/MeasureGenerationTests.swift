//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeasureGenerationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

/// A test-local environment value, standing in for the row width a menu hands
/// its rows: assigned straight onto `context.environment`, never applied through
/// a modifier, so `noteAppliedEnvironment` never sees it.
private struct WidthHintKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    fileprivate var widthHint: Int? {
        get { self[WidthHintKey.self] }
        set { self[WidthHintKey.self] = newValue }
    }
}

/// A leaf whose SIZE comes out of the environment, which is the whole hazard in
/// one view. Hugs its own content when no hint is in force, fills the hint when
/// one is — exactly the shape of a menu row, which hugs while the menu is
/// measuring itself and fills once the width is known.
private struct HintedLeaf: View, Renderable, Layoutable {
    var body: Never { fatalError("HintedLeaf renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize.fixed(context.environment.widthHint ?? 3, 1)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: [String(repeating: "x", count: context.environment.widthHint ?? 3)])
    }
}

/// The measure memo is keyed on a view's identity, its type, its raw bytes and
/// two widths — and deliberately not on the environment. So a container that
/// ASSIGNS an environment value between two measurements of one subtree asks two
/// questions the key cannot tell apart, and the second is answered by the first.
///
/// ``RenderContext/measureGeneration`` is the opt-in by which such a container
/// says so. Both halves are pinned here: that the hazard is real without it (or
/// the remedy proves nothing) and that it is gone with it.
///
/// This was two reverted commits before it was a mechanism. A menu measures its
/// rows hugging, to learn its width, then again at that width because a row
/// drawn into the interior less its hint column can wrap where the hug did not
/// — and on the arm where the hug wanted every cell it was offered, both asks
/// are at the same width. The stale serve landed on `_ButtonCore`, whose size
/// comes from the `ButtonStyle` it reads out of the environment, so moving the
/// row width into some view's value could not separate them.
@MainActor
@Suite("The measure memo's environment generation")
struct MeasureGenerationTests {

    /// A context shaped like the render loop's, because the memo only engages
    /// when a `VolatileReadTracker` is installed alongside a cache.
    private func liveContext(width: Int) -> RenderContext {
        var environment = EnvironmentValues()
        let cache = RenderCache()
        environment.renderCache = cache
        environment.stateStorage = StateStorage()
        environment.volatileReadTracker = VolatileReadTracker()
        let context = RenderContext(
            availableWidth: width, availableHeight: 4, environment: environment,
            identity: ViewIdentity(path: "Root"))
        cache.beginRenderPass()
        return context
    }

    /// Asks the same leaf, at one identity and one width, before and after the
    /// hint is assigned — with the generation bumped or not.
    private func askTwice(bumping: Bool) -> (hugged: Int, hinted: Int) {
        let context = liveContext(width: 12)
        let hugged = measureChild(HintedLeaf(), proposal: .unspecified, context: context)
        var hinted = context
        hinted.environment.widthHint = 9
        if bumping { hinted = hinted.invalidatingMeasureMemo() }
        let second = measureChild(HintedLeaf(), proposal: .unspecified, context: hinted)
        return (hugged.width, second.width)
    }

    /// The hazard. Without the bump the second ask is answered by the first, so
    /// a container that changed the environment gets the answer from before it
    /// did. If this ever starts passing, the memo has learnt to see the
    /// environment some other way and the case below is no longer load-bearing.
    @Test("Without the generation, an environment change is invisible to the memo")
    func hazardIsReal() {
        let (hugged, hinted) = askTwice(bumping: false)
        #expect(hugged == 3, "the hug should be the leaf's own width")
        #expect(
            hinted == 3,
            """
            the memo answered the second ask correctly without being told the \
            environment changed (\(hinted)) — which would mean this suite's \
            remedy is guarding nothing.
            """)
    }

    /// The remedy.
    @Test("With the generation, the second ask is measured afresh")
    func generationSeparatesTheQuestions() {
        let (hugged, hinted) = askTwice(bumping: true)
        #expect(hugged == 3)
        #expect(
            hinted == 9,
            "the bumped generation still served the pre-change size (\(hinted))")
    }

    /// And it must not throw away the work taken AFTER the bump: two asks in the
    /// same generation are still one question, or every container that opts in
    /// pays for a second full walk of everything below it.
    @Test("Two asks in one generation still share an answer")
    func sameGenerationStillMemoizes() {
        var context = liveContext(width: 12)
        context.environment.widthHint = 9
        context = context.invalidatingMeasureMemo()
        _ = measureChild(HintedLeaf(), proposal: .unspecified, context: context)
        let before = context.renderCache?.measureMemoTotals.hits ?? 0
        _ = measureChild(HintedLeaf(), proposal: .unspecified, context: context)
        let after = context.renderCache?.measureMemoTotals.hits ?? 0
        #expect(after == before + 1, "the second ask in one generation missed the memo")
    }

    /// The generation rides on the context, so it survives the copy helpers a
    /// container reaches for between assigning the environment and measuring.
    @Test("The generation survives the context's copy helpers")
    func generationSurvivesCopies() {
        let context = liveContext(width: 12).invalidatingMeasureMemo()
        #expect(context.measureGeneration == 1)
        #expect(context.withAvailableWidth(6).measureGeneration == 1)
        #expect(context.withAvailableHeight(2).measureGeneration == 1)
        #expect(context.withChildIdentity(erasedType: HintedLeaf.self, index: 0)
            .measureGeneration == 1)
        var mutated = context
        mutated.environment.widthHint = 4
        #expect(mutated.measureGeneration == 1, "assigning the environment reset it")
    }
}
