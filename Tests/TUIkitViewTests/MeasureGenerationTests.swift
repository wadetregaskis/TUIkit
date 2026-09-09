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
private struct HintedLeaf: View, Renderable, Layoutable, Equatable {
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
        // Through the installer, which also mirrors it onto the cache — that
        // mirror is what `measureChild` gates on, so a bare assignment leaves
        // this whole suite measuring a memo that is switched off.
        environment.installVolatileReadTracker(VolatileReadTracker())
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

    /// The same two asks with the leaf behind the VALUE memo. `.equatable()`
    /// here; the production shape is `_MemoizedRow`, which every `ForEach` row
    /// over an `Equatable` element becomes — same `measureValueMemoized`, same
    /// `RenderCache.SizeKey`.
    ///
    /// The `beginRenderPass()` between the asks is LOAD-BEARING, and not for the
    /// reason a pass boundary usually is. Without it the second ask never
    /// reaches the value memo at all: `measureChild`'s own per-pass `MeasureKey`
    /// table answers it first, and that memo is live here because `liveContext`
    /// installs the `VolatileReadTracker` it gates on. The boundary drops that
    /// table and KEEPS `sizeEntries`, which is the cross-frame asymmetry this
    /// case is about. `RenderCacheContractTests`'
    /// `incomparableEnvironmentDeclinesStoredSizes` does the same thing for the
    /// same reason.
    private func askTwiceMemoized(bumping: Bool) -> (hugged: Int, hinted: Int) {
        let context = liveContext(width: 12)
        let cache = context.renderCache!
        let hugged = measureChild(
            HintedLeaf().equatable(), proposal: .unspecified, context: context)
        var hinted = context
        hinted.environment.widthHint = 9
        if bumping { hinted = hinted.invalidatingMeasureMemo() }
        cache.beginRenderPass()
        let second = measureChild(
            HintedLeaf().equatable(), proposal: .unspecified, context: hinted)
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

    /// The half of the mechanism this suite did not cover. `RenderCache.SizeKey`
    /// carried no generation, so `measureValueMemoized` answered the post-bump
    /// ask out of the pre-bump entry — 3 cells where the hinted leaf is 9 — even
    /// though the outer `measureChild` had correctly missed and re-entered the
    /// wrapper. And `sizeEntries` is the cross-frame table, so that answer stood
    /// for as long as the row kept being marked active.
    @Test("The generation reaches the value memo's size half too")
    func generationReachesTheValueMemo() {
        let (hugged, hinted) = askTwiceMemoized(bumping: true)
        #expect(hugged == 3, "the hug should be the leaf's own width")
        #expect(
            hinted == 9,
            """
            the value memo served the pre-change size (\(hinted)) through a \
            bumped generation — its SizeKey cannot see the generation.
            """)
    }

    /// The hazard at the wrapper, so the case above is known to guard something.
    /// Note what makes this the VALUE memo's hazard and not the one
    /// `hazardIsReal` already pins: the pass boundary inside
    /// `askTwiceMemoized` has dropped `measureChild`'s per-pass table, so the
    /// only thing that can answer the second ask is `sizeEntries`.
    @Test("Without the generation, the value memo is blind to the change too")
    func memoizedHazardIsReal() {
        let (hugged, hinted) = askTwiceMemoized(bumping: false)
        #expect(hugged == 3)
        #expect(
            hinted == 3,
            "the value memo answered correctly without being told (\(hinted))")
    }

    /// And the memo must still pay for itself under a bumped generation: two
    /// asks that share one generation are one question at the wrapper too, or
    /// every container that opts in walks its whole subtree twice.
    @Test("Two memoized asks in one generation still share an answer")
    func memoizedSameGenerationStillMemoizes() {
        var context = liveContext(width: 12)
        context.environment.widthHint = 9
        context = context.invalidatingMeasureMemo()
        let cache = context.renderCache!
        _ = measureChild(
            HintedLeaf().equatable(), proposal: .unspecified, context: context)
        // Same boundary, same reason as `askTwiceMemoized`: without it the
        // per-pass `MeasureKey` memo answers the second ask before the value
        // memo sees it, and ITS hits land in `measureMemoTotals` rather than
        // `stats` — so this would read a delta of zero and fail while the memo
        // it is about worked perfectly.
        cache.beginRenderPass()
        let before = cache.stats
        _ = measureChild(
            HintedLeaf().equatable(), proposal: .unspecified, context: context)
        #expect(
            cache.stats.delta(since: before).hits >= 1,
            "the second ask in one generation missed the value memo")
    }
}
