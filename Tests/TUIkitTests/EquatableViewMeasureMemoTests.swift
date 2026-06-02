//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EquatableViewMeasureMemoTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Tests for the value-based measure memoization on ``EquatableView``: a
/// repeated measurement of an unchanged `Equatable` view returns the cached
/// size, a *changed* value is never served a stale size, the memoized size
/// matches what the view renders, and the shared `RenderCache` invalidation
/// drops the memo.
@MainActor
@Suite("EquatableView measure memo")
struct EquatableViewMeasureMemoTests {
    /// A minimal `Equatable` view whose size tracks its value.
    private struct Probe: View, Equatable {
        let text: String
        var body: some View { Text(text) }
    }

    private func context(_ cache: RenderCache, width: Int = 80, height: Int = 24) -> RenderContext {
        var environment = EnvironmentValues()
        environment.stateStorage = StateStorage()
        environment.renderCache = cache
        return RenderContext(availableWidth: width, availableHeight: height, environment: environment)
    }

    @Test("A repeated measure of the same value hits the memo and returns the same size")
    func memoHit() {
        let cache = RenderCache()
        let ctx = context(cache)
        let view = Probe(text: "hello").equatable()

        let first = measureChild(view, proposal: .unspecified, context: ctx)
        let hitsBefore = cache.stats.hits
        let second = measureChild(view, proposal: .unspecified, context: ctx)

        #expect(second == first)
        #expect(cache.stats.hits > hitsBefore, "the second identical measure should hit the size memo")
    }

    @Test("The memoized size matches the rendered size")
    func memoMatchesRender() {
        let cache = RenderCache()
        let ctx = context(cache)
        let view = Probe(text: "hello").equatable()

        let measured = measureChild(view, proposal: .unspecified, context: ctx)
        let rendered = renderToBuffer(view, context: ctx)

        #expect(measured.width == rendered.width)
        #expect(measured.height == rendered.height)
    }

    @Test("A different value is measured fresh, never served the cached size")
    func valueGating() {
        let cache = RenderCache()
        let ctx = context(cache)

        let short = measureChild(Probe(text: "hi").equatable(), proposal: .unspecified, context: ctx)
        // Same structural identity (root), different value: the value comparison
        // must force a miss rather than return `short`.
        let long = measureChild(
            Probe(text: "a considerably longer string").equatable(),
            proposal: .unspecified, context: ctx)

        #expect(long.width > short.width)
    }

    @Test("clearAll drops the measure memo")
    func clearAllDropsMemo() {
        let cache = RenderCache()
        let ctx = context(cache)
        let view = Probe(text: "hello").equatable()

        _ = measureChild(view, proposal: .unspecified, context: ctx)
        cache.clearAll()
        let hitsBefore = cache.stats.hits
        _ = measureChild(view, proposal: .unspecified, context: ctx)

        #expect(cache.stats.hits == hitsBefore, "after clearAll the next measure must miss")
    }

    @Test("A different proposal is a distinct memo entry")
    func proposalIsPartOfKey() {
        let cache = RenderCache()
        let ctx = context(cache)
        let view = Probe(text: "wrap me across widths if narrow").equatable()

        _ = measureChild(view, proposal: ProposedSize(width: 40, height: nil), context: ctx)
        let hitsBefore = cache.stats.hits
        // Different proposal width → different key → miss (not the width-40 entry).
        _ = measureChild(view, proposal: ProposedSize(width: 12, height: nil), context: ctx)

        #expect(cache.stats.hits == hitsBefore, "a different proposal must not hit the width-40 entry")
    }
}
