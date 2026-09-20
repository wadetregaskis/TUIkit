//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCacheContractTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Fixtures

/// An `.equatable()` view containing a *nested* `.equatable()` view. The outer
/// value can change while the inner one does not, which is the whole point:
/// the inner subtree should still be able to answer from cache.
private struct CacheOuter: View, Equatable {
    let title: String
    let leaf: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
            CacheLeaf(text: leaf).equatable()
        }
    }
}

/// The `_MemoizedRow` twin of ``CacheOuter``: `ForEach` wraps every
/// `Equatable` element row in one of these, so an outer row containing an
/// inner one is the ordinary nested-`ForEach` shape, not a contrivance.
@MainActor
private func nestedMemoizedRow(_ title: String) -> some View {
    _MemoizedRow(
        element: title,
        content: VStack(spacing: 0) {
            Text(title)
            _MemoizedRow(element: "inner", content: Text("static"))
        })
}

/// A leaf whose colour comes from the *palette accent* rather than from a
/// literal, so `.tint(_:)` applied above it changes what it renders.
private struct AccentLeaf: View, Equatable {
    let text: String

    var body: some View {
        Text(text).foregroundStyle(.palette.accent)
    }
}

/// A value with no `Equatable` conformance, so a change under it is
/// undetectable by construction.
private struct Incomparable {
    let token = 0
}

private struct IncomparableProbeKey: EnvironmentKey {
    static let defaultValue: Incomparable? = nil
}

extension EnvironmentValues {
    fileprivate var incomparableProbe: Incomparable? {
        get { self[IncomparableProbeKey.self] }
        set { self[IncomparableProbeKey.self] = newValue }
    }
}

private struct ComparableProbeKey: EnvironmentKey {
    static let defaultValue = "-"
}

extension EnvironmentValues {
    fileprivate var comparableProbe: String {
        get { self[ComparableProbeKey.self] }
        set { self[ComparableProbeKey.self] = newValue }
    }
}

/// Renders whatever `comparableProbe` holds — and compares equal to any other
/// instance, so a memo can only be broken by the environment digest.
private struct ProbeEcho: View, Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    @Environment(\.comparableProbe) private var probe

    var body: some View { Text(probe) }
}

// MARK: - Tests

/// The two `EquatableView`/`RenderCache` contracts upstream fixed in PR #64
/// (`e84738728c`, `c48e35d78d`). Both reproduced here; one is fixed.
///
/// - **Nested entry liveness** — fixed. These assert the contract, and every one
///   of them fails on the pre-fix code, where an outer hit left the cache with
///   one entry instead of two.
/// - **Environment in the cache key** — fixed, but not by putting the
///   environment in the key. `EnvironmentModifier` compares the value it applied
///   here last pass and clears the subtree when it differs, which costs one
///   comparison per modifier instead of a fingerprint per lookup. A value that
///   is not `Equatable` cannot be compared, so it declines caching instead —
///   true of this route, which is what `.environment(_:_:)` and every style
///   modifier use. A slot whose owner notes it by hand instead (the two `Paint`
///   slots, a tint, a theme) never reaches that arm: an uncomparable value there
///   is ignored and deadens the slot, so the subtree keeps what it was painted
///   with. Lost memoization on one route, stale ink on the other.
@MainActor
@Suite("RenderCache contracts", .serialized)
struct RenderCacheContractTests: RenderCacheHarness {

    // MARK: - Nested entry liveness (upstream `e84738728c`)

    @Test("A nested entry survives a cache hit at the .equatable() above it")
    func nestedEntrySurvivesOuterHit() {
        let context = self.context()
        let cache = context.environment.renderCache!

        // Frame 1 — both miss and both store.
        frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        #expect(cache.count == 2, "outer and inner should both be cached")

        // Frame 2 — the outer value is unchanged, so it hits and the inner view
        // is never walked. Nothing below reaches `markActive`, so the entry
        // survives only because the hit declared its subtree retained.
        frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        #expect(cache.count == 2, "the nested entry is still live and must not be collected")

        // Frame 3 — the outer value changes, so the subtree is walked again. The
        // inner value did not, so it answers from cache instead of re-rendering.
        let before = cache.stats
        frame(context, CacheOuter(title: "two", leaf: "static").equatable())
        let delta = cache.stats.delta(since: before)

        #expect(delta.hits >= 1, "the unchanged inner subtree is served from cache")
    }

    @Test("A nested entry survives a cache hit at the _MemoizedRow above it")
    func nestedRowEntrySurvivesOuterHit() {
        let context = self.context()
        let cache = context.environment.renderCache!

        // Frame 1 — both miss and both store.
        frame(context, nestedMemoizedRow("one"))
        #expect(cache.count == 2, "outer and inner row should both be cached")

        // Frame 2 — the outer element is unchanged, so it hits and nothing
        // below it is walked. Only the hit's subtree retention keeps the inner
        // entry alive; `sizeThatFits` deliberately marks nothing, so the
        // measure walk cannot rescue it either.
        frame(context, nestedMemoizedRow("one"))
        #expect(cache.count == 2, "the nested row entry is still live and must not be collected")

        // Frame 3 — the outer element changes, so the subtree is walked again.
        // The inner row did not change, so it answers from cache.
        let before = cache.stats
        frame(context, nestedMemoizedRow("two"))
        let delta = cache.stats.delta(since: before)

        #expect(delta.hits >= 1, "the unchanged inner row is served from cache")
    }

    @Test("The nested entry survives an arbitrary run of outer hits")
    func nestedEntrySurvivesRepeatedHits() {
        let context = self.context()
        let cache = context.environment.renderCache!

        frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        for _ in 0..<5 {
            frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        }

        // Retention is declared per pass, so it has to be re-declared on every
        // hit frame — one missed frame and the entry is gone.
        #expect(cache.count == 2)
    }

    @Test("Retention lapses when the subtree leaves the tree")
    func retentionLapsesWhenSubtreeGoes() {
        let context = self.context()
        let cache = context.environment.renderCache!

        frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        #expect(cache.count == 2)

        // Render something else at the same root: neither entry is visited and
        // nothing declares them retained, so both are collected. Retention keeps
        // live subtrees, it does not leak dead ones.
        frame(context, Text("unrelated"))
        #expect(cache.isEmpty)
    }

    // MARK: - Environment in the cache key (upstream `c48e35d78d`)

    @Test("A scoped .foregroundStyle change above an .equatable() re-renders it")
    func scopedStyleChangeIsNotServedStale() {
        let base = context()

        // The truth for each style, rendered with its own cache so neither can
        // answer for the other. If these two matched, the test below would prove
        // nothing — which is the precondition, asserted rather than assumed.
        let redTruth = frame(
            base.isolatingRenderCache(), CacheLeaf(text: "hi").equatable().foregroundStyle(.red))
        let blueTruth = frame(
            base.isolatingRenderCache(), CacheLeaf(text: "hi").equatable().foregroundStyle(.blue))
        #expect(
            redTruth.lines != blueTruth.lines,
            "precondition: .foregroundStyle must change the rendered output"
        )

        // One cache, same view value, style changed above the memoization
        // boundary. Nothing in the cache key sees the difference — the modifier
        // has to notice and clear.
        let shared = context()
        frame(shared, CacheLeaf(text: "hi").equatable().foregroundStyle(.red))
        let served = frame(shared, CacheLeaf(text: "hi").equatable().foregroundStyle(.blue))

        #expect(served.lines == blueTruth.lines, "the new style must be rendered")
        #expect(served.lines != redTruth.lines, "not the buffer from the old one")
    }

    /// `.theme(_:)` is the same environment application as the two above, and
    /// was the one that did none of the bookkeeping: it assigned the appearance,
    /// palette, tint, control styles and style cascade straight onto the child
    /// context and told the cache nothing. A memoized subtree below a theme that
    /// changed therefore served the buffer painted in the OLD palette.
    ///
    /// What it notes is the theme's INPUTS — the base palette and the tint on
    /// slots of their own — never the `TintedPalette` the two of them resolve
    /// to. The next case pins the other half, that memoization still WORKS
    /// under a theme that did not change.
    @Test("A .theme change above an .equatable() re-renders it")
    func scopedThemeChangeIsNotServedStale() {
        let base = context()
        let green = Theme(palette: SystemPalette(.green))
        let blue = Theme(palette: SystemPalette(.blue))

        let greenTruth = frame(
            base.isolatingRenderCache(), AccentLeaf(text: "hi").equatable().theme(green))
        let blueTruth = frame(
            base.isolatingRenderCache(), AccentLeaf(text: "hi").equatable().theme(blue))
        #expect(
            greenTruth.lines != blueTruth.lines,
            "precondition: the two themes must differ on screen")

        let shared = context()
        frame(shared, AccentLeaf(text: "hi").equatable().theme(green))
        let served = frame(shared, AccentLeaf(text: "hi").equatable().theme(blue))
        #expect(served.lines == blueTruth.lines, "the new theme must be rendered")
        #expect(served.lines != greenTruth.lines, "not the buffer from the old one")
    }

    /// The other half, and the one a careless fix breaks: an UNCHANGED theme
    /// must still let the subtree memoize. A comparison that answered "changed"
    /// for an equal rebuild — and `.theme(…)` rebuilds its `TintedPalette` on
    /// every frame — would clear the subtree on every frame, which no output
    /// comparison would catch, only the clear count.
    @Test("An unchanged theme does not defeat the memo below it")
    func unchangedThemeStillMemoizes() {
        let shared = context()
        // A TINTED theme: the resolved palette is the incomparable one.
        let theme = Theme(palette: SystemPalette(.green), tint: .red)
        frame(shared, AccentLeaf(text: "hi").equatable().theme(theme))
        let before = shared.renderCache?.stats.subtreeClears ?? 0
        frame(shared, AccentLeaf(text: "hi").equatable().theme(theme))
        let after = shared.renderCache?.stats.subtreeClears ?? 0
        #expect(after == before, "an unchanged theme cleared the subtree anyway")
    }

    /// `.tint(_:)` swaps the environment palette for a `TintedPalette`, which is
    /// an environment application like any other: a memoized subtree below it
    /// keys on the view value, which does not change when the tint above it
    /// does. Same mechanism as `.foregroundStyle` above, different modifier.
    @Test("A scoped .tint change above an .equatable() re-renders it")
    func scopedTintChangeIsNotServedStale() {
        let base = context()

        let redTruth = frame(
            base.isolatingRenderCache(), AccentLeaf(text: "hi").equatable().tint(.red))
        let blueTruth = frame(
            base.isolatingRenderCache(), AccentLeaf(text: "hi").equatable().tint(.blue))
        #expect(
            redTruth.lines != blueTruth.lines,
            "precondition: .tint must change the rendered output"
        )

        let shared = context()
        frame(shared, AccentLeaf(text: "hi").equatable().tint(.red))
        let served = frame(shared, AccentLeaf(text: "hi").equatable().tint(.blue))

        #expect(served.lines == blueTruth.lines, "the new tint must be rendered")
        #expect(served.lines != redTruth.lines, "not the buffer from the old one")
    }

    @Test("An unchanged tint still memoizes")
    func unchangedTintStillHits() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, AccentLeaf(text: "hi").equatable().tint(.red))
        let before = cache.stats
        frame(shared, AccentLeaf(text: "hi").equatable().tint(.red))

        // Noticing the *change* rather than keying the cache on the palette: a
        // stable tint must still cost a comparison, not a miss.
        #expect(cache.stats.delta(since: before).hits >= 1)
    }

    /// Two modifiers injecting the SAME key path share one identity (a
    /// `Renderable` adds no child identity). With the slot keyed only on
    /// (identity, keyPath), the outer one answered for both and the inner
    /// one's changes were never compared.
    @Test("A changed inner value is seen past an unchanged outer one, same key path")
    func chainedSameKeyPathInnerChangeIsSeen() {
        let shared = context()

        // The INNER application (closest to the view) wins, so the leaf shows
        // it; the OUTER stays constant so its comparison says "unchanged"
        // every frame.
        frame(
            shared,
            ProbeEcho().equatable()
                .environment(\.comparableProbe, "aaa")
                .environment(\.comparableProbe, "outer"))
        let served = frame(
            shared,
            ProbeEcho().equatable()
                .environment(\.comparableProbe, "bbb")
                .environment(\.comparableProbe, "outer"))

        #expect(
            served.lines.first?.stripped == "bbb",
            "the inner change was eaten by the outer slot: \(served.lines.map(\.stripped))")
    }

    @Test("An unchanged style still memoizes")
    func unchangedStyleStillHits() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, CacheLeaf(text: "hi").equatable().foregroundStyle(.red))
        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().foregroundStyle(.red))

        // The point of detecting the *change* rather than keying on the
        // environment: a stable style costs a comparison, not a miss.
        #expect(cache.stats.delta(since: before).hits >= 1)
    }

    @Test("A style change keeps the memoized sizes; any other environment change drops them")
    func scopedStyleChangeKeepsTheSizeMemo() {
        let shared = context()
        let cache = shared.environment.renderCache!
        let proposal = ProposedSize(width: nil, height: nil)

        // A pass per measurement, as the real loop does. Change detection short
        // circuits after the first visit *within* a pass — two-pass layout
        // visits one modifier many times per frame and the value it applies
        // cannot change between those visits, since structural identity gives
        // one modifier one value. Measuring twice inside a single pass would be
        // testing something that cannot happen.
        cache.beginRenderPass()
        _ = measureChild(
            CacheLeaf(text: "hi").equatable().foregroundStyle(.red),
            proposal: proposal, context: shared)
        let before = cache.stats
        cache.beginRenderPass()
        _ = measureChild(
            CacheLeaf(text: "hi").equatable().foregroundStyle(.blue),
            proposal: proposal, context: shared)

        // A paint is ink: it moves no cell, so the size measured under red is
        // the size under blue, and the measure walks keep serving it while
        // the render walk re-inks. (A ramp that rotates every frame used to
        // re-measure every row on every walk.)
        #expect(cache.stats.delta(since: before).hits >= 1, "\(cache.stats.delta(since: before))")

        // A value that CAN move cells still clears them: measurement runs
        // before rendering, so if only the render walk noticed, a change that
        // altered the size would already have been laid out wrong.
        cache.beginRenderPass()
        _ = measureChild(
            CacheLeaf(text: "hi").equatable().environment(\.comparableProbe, "one"),
            proposal: proposal, context: shared)
        let beforeProbe = cache.stats
        cache.beginRenderPass()
        _ = measureChild(
            CacheLeaf(text: "hi").equatable().environment(\.comparableProbe, "two"),
            proposal: proposal, context: shared)
        #expect(cache.stats.delta(since: beforeProbe).hits == 0, "\(cache.stats.delta(since: beforeProbe))")
    }

    @Test("A non-Equatable environment value declines caching rather than risking it")
    func incomparableEnvironmentDeclinesCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        // `Incomparable` cannot be compared, so no change can ever be detected
        // below it — the only sound answer is not to memoize there.
        frame(shared, CacheLeaf(text: "hi").equatable().environment(\.incomparableProbe, Incomparable()))
        #expect(cache.isEmpty, "nothing may be stored under an uncomparable environment value")
    }

    @Test("A ForEach row declines it too, not just an .equatable() view")
    func incomparableEnvironmentDeclinesRowCaching() {
        // The same hazard, through the other memo. `_MemoizedRow` carried the
        // same five-condition gate as `EquatableView` minus this one clause, so
        // a row under an uncomparable value cached a buffer nothing could
        // invalidate. Both go through `RenderCache.isStorable` now.
        let shared = context()
        let cache = shared.environment.renderCache!
        frame(
            shared,
            VStack(spacing: 0) {
                ForEach(["a", "b"], id: \.self) { CacheLeaf(text: $0) }
            }
            .environment(\.incomparableProbe, Incomparable()))
        #expect(cache.isEmpty, "a row cached under an uncomparable environment value")
    }

    /// The SIZE half of the same clause, on both arms, with an oracle that can
    /// see a stored size.
    ///
    /// This is the drift the two memos are now one implementation to prevent, and
    /// it went the other way: the clause was added to `EquatableView`'s size memo
    /// and MISSED on `_MemoizedRow`'s "when the buffer half was unified" — the
    /// code says so — so a Form row under an injected uncomparable value measured
    /// once and served that size forever.
    ///
    /// `cache.isEmpty` is no use as the oracle here: it and `count` inspect only
    /// the BUFFER dictionary, and `sizeEntries` has no accessor at all. A stored
    /// size shows up as a `hits` delta on the next measure of the same value, so
    /// that is what these count.
    @Test("A non-Equatable environment value declines a stored SIZE too", arguments: [false, true])
    func incomparableEnvironmentDeclinesStoredSizes(asRow: Bool) {
        let proposal = ProposedSize(width: nil, height: nil)

        // Built the same way the buffer cases above are — no `AnyView` between
        // the modifier and the wrapper, because the uncomparable flag is set
        // where the value is APPLIED and an erasure in between loses it. (The
        // first draft of this test put one there and both arms reported a stored
        // size that was not really there.)
        @MainActor func measureView(_ shared: RenderContext, uncomparable: Bool) {
            let cache = shared.environment.renderCache!
            cache.beginRenderPass()
            if uncomparable {
                _ = measureChild(
                    CacheLeaf(text: "hi").equatable()
                        .environment(\.incomparableProbe, Incomparable()),
                    proposal: proposal, context: shared)
            } else {
                _ = measureChild(
                    CacheLeaf(text: "hi").equatable(), proposal: proposal, context: shared)
            }
        }

        @MainActor func measureRow(_ shared: RenderContext, uncomparable: Bool) {
            let cache = shared.environment.renderCache!
            cache.beginRenderPass()
            let rows = VStack(spacing: 0) {
                ForEach(["a", "b"], id: \.self) { CacheLeaf(text: $0) }
            }
            if uncomparable {
                _ = measureChild(
                    rows.environment(\.incomparableProbe, Incomparable()),
                    proposal: proposal, context: shared)
            } else {
                _ = measureChild(rows, proposal: proposal, context: shared)
            }
        }

        // A FRESH cache per arm. `SizeKey` carries the identity's hash, the
        // proposal and the extents — not the environment — so a size stored by the
        // control would be served straight back to the uncomparable run, and the
        // hit counted would be the control's own entry rather than a new one.
        // (The first draft shared one cache and reported exactly that.)
        @MainActor func hitsOnSecondMeasure(uncomparable: Bool) -> Int {
            let shared = context()
            let cache = shared.environment.renderCache!
            @MainActor func measure() {
                if asRow {
                    measureRow(shared, uncomparable: uncomparable)
                } else {
                    measureView(shared, uncomparable: uncomparable)
                }
            }
            measure()
            let before = cache.stats
            measure()
            return cache.stats.delta(since: before).hits
        }

        // The control first: without it, "no hits" would pass for a memo that
        // never stores a size at all.
        #expect(
            hitsOnSecondMeasure(uncomparable: false) >= 1,
            "\(asRow ? "a row" : "an .equatable() view") stopped memoizing sizes entirely")
        #expect(
            hitsOnSecondMeasure(uncomparable: true) == 0,
            """
            a size was stored under an uncomparable environment value — nothing \
            can ever invalidate it, because the key cannot see the value
            """)
    }

    @Test("…and a ForEach row IS cached when nothing uncomparable is in force")
    func rowsAreCachedNormally() {
        // The control for the case above: without it, "cache is empty" would
        // pass for a memo that never stores anything at all.
        let shared = context()
        let cache = shared.environment.renderCache!
        frame(
            shared,
            VStack(spacing: 0) {
                ForEach(["a", "b"], id: \.self) { CacheLeaf(text: $0) }
            })
        #expect(!cache.isEmpty, "ForEach rows stopped memoizing entirely")
    }
}
