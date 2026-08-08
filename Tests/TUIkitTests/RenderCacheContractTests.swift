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

// MARK: - Tests

/// The two `EquatableView`/`RenderCache` contracts upstream fixed in PR #64
/// (`e84738728c`, `c48e35d78d`). Both reproduced here; one is fixed.
///
/// - **Nested entry liveness** — fixed. These assert the contract, and every one
///   of them fails on the pre-fix code, where an outer hit left the cache with
///   one entry instead of two.
/// - **Environment in the cache key** — *not* fixed, and the last two tests are
///   deliberate **characterizations**: they assert that a scoped style change
///   serves the wrong buffer, so they fail the day it is fixed rather than
///   passing quietly either way. See
///   `Documentation/Upstream-review/open-questions.md` for the design fork.
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

    @Test("A scoped .foregroundStyle change above an .equatable() serves a stale buffer")
    func scopedStyleChangeServesStaleBuffer() {
        let base = context()
        let red = base.withEnvironment(base.environment.setting(\.foregroundStyle, to: .red))
        let blue = base.withEnvironment(base.environment.setting(\.foregroundStyle, to: .blue))

        // Precondition: the two styles must actually render differently, or the
        // test proves nothing. Rendered with separate caches so neither can
        // answer for the other.
        let redTruth = frame(red.isolatingRenderCache(), CacheLeaf(text: "hi").equatable())
        let blueTruth = frame(blue.isolatingRenderCache(), CacheLeaf(text: "hi").equatable())
        #expect(
            redTruth.lines != blueTruth.lines,
            "precondition: .foregroundStyle must change the rendered output"
        )

        // Now the real sequence, sharing one cache: render red, then render the
        // *same view value* under blue. Identity, value and size all match, and
        // the key carries nothing else — so the red buffer is served.
        let shared = context()
        let sharedRed = shared.withEnvironment(shared.environment.setting(\.foregroundStyle, to: .red))
        let sharedBlue = shared.withEnvironment(shared.environment.setting(\.foregroundStyle, to: .blue))

        frame(sharedRed, CacheLeaf(text: "hi").equatable())
        let served = frame(sharedBlue, CacheLeaf(text: "hi").equatable())

        #expect(
            served.lines == redTruth.lines,
            "characterization: the buffer rendered under .red is served for a .blue render"
        )
        #expect(
            served.lines != blueTruth.lines,
            "which is to say: the wrong pixels. An environment component in the key would flip both expectations"
        )
    }

    @Test("The measure memo has the same environment blind spot")
    func scopedStyleChangeServesStaleSize() {
        // The size twin: `sizeThatFits` keys on identity + proposal + extent,
        // with no environment either. A style that changes *size* rather than
        // colour would therefore memoize across the change.
        let shared = context()
        let cache = shared.environment.renderCache!

        let wide = shared.withEnvironment(shared.environment.setting(\.foregroundStyle, to: .red))
        let narrow = shared.withEnvironment(shared.environment.setting(\.foregroundStyle, to: .blue))

        let view = CacheLeaf(text: "hi").equatable()
        _ = view.sizeThatFits(proposal: ProposedSize(width: nil, height: nil), context: wide)
        let before = cache.stats
        _ = view.sizeThatFits(proposal: ProposedSize(width: nil, height: nil), context: narrow)

        #expect(
            cache.stats.delta(since: before).hits == 1,
            "characterization: the memoized size answers across an environment change"
        )
    }
}
