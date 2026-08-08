//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderCacheContractTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Fixtures

/// A leaf that renders its text and nothing else — safe to memoize (no
/// hit-test regions, no overlays, no volatile reads).
private struct CacheLeaf: View, Equatable {
    let text: String

    var body: some View {
        Text(text)
    }
}

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
///   is not `Equatable` cannot be compared, so it declines caching instead.
@MainActor
@Suite("RenderCache contracts", .serialized)
struct RenderCacheContractTests {

    /// A context with a fresh, test-local cache. Built by hand rather than via
    /// `makeRenderContext` because these tests assert absolute entry counts and
    /// cache statistics: nothing else may touch this cache.
    private func context(width: Int = 24, height: Int = 6) -> RenderContext {
        let tuiContext = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tuiContext)
        env.renderCache = RenderCache()
        env.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: env,
            identity: ViewIdentity(path: "Root")
        )
    }

    /// One frame of the real loop's cache lifecycle: drain invalidations, walk,
    /// then collect identities that were not visited.
    @discardableResult
    private func frame(_ context: RenderContext, _ view: some View) -> FrameBuffer {
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        cache.removeInactive()
        return buffer
    }

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

    @Test("The measure memo sees the change too")
    func scopedStyleChangeClearsTheSizeMemo() {
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

        // Measurement runs before rendering, so if only the render walk noticed,
        // a style that changed the *size* would already have been laid out wrong.
        #expect(cache.stats.delta(since: before).hits == 0)
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
}
