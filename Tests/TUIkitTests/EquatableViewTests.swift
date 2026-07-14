//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EquatableViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A minimal equatable view for testing memoization behavior.
private struct LabelView: View, Equatable {
    let text: String

    var body: some View {
        Text(text)
    }
}

@MainActor
@Suite("EquatableView Tests", .serialized)
struct EquatableViewTests {

    /// Creates a test context with a fresh environment including render cache.
    private func testContext(
        width: Int = 80,
        height: Int = 24,
        identity: ViewIdentity = ViewIdentity(path: "Root")
    ) -> RenderContext {
        let tuiContext = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tuiContext)
        // A fresh, test-local cache: these tests assert an absolute entry
        // count, so it must be touched only by this test's renders. The env is
        // built by hand here (not via RenderContext(tuiContext:)), so the cache
        // has to be set explicitly — EquatableView force-unwraps it.
        env.renderCache = RenderCache()
        env.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: env,
            identity: identity
        )
    }

    // MARK: - First Render (Cache Miss)

    @Test("First render produces correct output and populates cache")
    func firstRenderPopulatesCache() {
        let context = testContext()
        let view = EquatableView(content: LabelView(text: "Hello"))

        let buffer = renderToBuffer(view, context: context)

        #expect(buffer.lines[0].stripped == "Hello")
        #expect(context.environment.renderCache!.count == 1)
    }

    // MARK: - Cache Hit

    @Test("Second render with equal content returns cached buffer")
    func cacheHitOnEqualContent() {
        let context = testContext()

        // First render
        let view1 = EquatableView(content: LabelView(text: "Static"))
        let buffer1 = renderToBuffer(view1, context: context)

        // Second render with equal view
        let view2 = EquatableView(content: LabelView(text: "Static"))
        let buffer2 = renderToBuffer(view2, context: context)

        #expect(buffer1.lines == buffer2.lines)
        #expect(context.environment.renderCache!.count == 1)
    }

    // MARK: - Cache Miss on Changed Content

    @Test("Changed content causes cache miss and re-render")
    func cacheMissOnChangedContent() {
        let context = testContext()

        // First render
        let view1 = EquatableView(content: LabelView(text: "Before"))
        let buffer1 = renderToBuffer(view1, context: context)

        // Second render with different content
        let view2 = EquatableView(content: LabelView(text: "After"))
        let buffer2 = renderToBuffer(view2, context: context)

        #expect(buffer1.lines != buffer2.lines)
        #expect(buffer2.lines[0].stripped == "After")
    }

    // MARK: - Cache Miss on Size Change

    @Test("Changed context size causes cache miss")
    func cacheMissOnSizeChange() {
        let tuiContext = TUIContext()
        let identity = ViewIdentity(path: "Root")
        let cache = RenderCache()  // fresh, test-local (see testContext)

        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tuiContext)
        env.renderCache = cache
        env.preferenceStorage = tuiContext.preferences

        // First render at 80x24
        let context1 = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: env,
            identity: identity
        )
        let view = EquatableView(content: LabelView(text: "Size"))
        _ = renderToBuffer(view, context: context1)

        // Second render at 120x40 -- should miss
        let context2 = RenderContext(
            availableWidth: 120,
            availableHeight: 40,
            environment: env,
            identity: identity
        )
        let buffer2 = renderToBuffer(view, context: context2)

        #expect(buffer2.lines[0].stripped == "Size")
        // Cache entry was overwritten with new size
        #expect(cache.count == 1)
    }

    // MARK: - Cache Invalidation on State Change

    @Test("clearAll empties the cache (simulates state-change invalidation)")
    func clearAllEmptiesCache() {
        let cache = RenderCache()

        cache.store(
            identity: ViewIdentity(path: "Root/A"),
            view: "value",
            buffer: FrameBuffer(text: "cached"),
            contextWidth: 80,
            contextHeight: 24
        )
        #expect(cache.count == 1)

        // StateBox.didSet calls renderCache.clearAll() — test the effect directly
        cache.clearAll()

        #expect(cache.isEmpty)
    }

    // MARK: - .equatable() Modifier

    @Test("equatable() modifier wraps view in EquatableView")
    func equatableModifierCreatesWrapper() {
        let label = LabelView(text: "Test")
        let wrapped = label.equatable()

        // Verify the wrapper produces correct output
        let context = testContext()
        let buffer = renderToBuffer(wrapped, context: context)
        #expect(buffer.lines[0].stripped == "Test")
    }

    // MARK: - Integration with VStack

    @Test("EquatableView inside VStack renders correctly")
    func equatableViewInVStack() {
        let context = testContext()

        let stack = VStack {
            EquatableView(content: LabelView(text: "Top"))
            Text("Bottom")
        }

        let buffer = renderToBuffer(stack, context: context)
        #expect(buffer.height == 2)
        // VStack with default .center alignment centers shorter children
        #expect(buffer.lines[0].contains("Top"))
        #expect(buffer.lines[1].contains("Bottom"))
    }

    // MARK: - GC Integration

    @Test("Cache entries for removed views are garbage collected")
    func cacheGarbageCollection() {
        let cache = RenderCache()
        let activeId = ViewIdentity(path: "Root/Active")
        let removedId = ViewIdentity(path: "Root/Removed")

        cache.store(identity: activeId, view: "a", buffer: FrameBuffer(text: "a"), contextWidth: 80, contextHeight: 24)
        cache.store(identity: removedId, view: "r", buffer: FrameBuffer(text: "r"), contextWidth: 80, contextHeight: 24)
        #expect(cache.count == 2)

        // Simulate render pass where only activeId is visited
        cache.beginRenderPass()
        cache.markActive(activeId)
        cache.removeInactive()

        #expect(cache.count == 1)
        #expect(cache.lookup(identity: activeId, view: "a", contextWidth: 80, contextHeight: 24) != nil)
        #expect(cache.lookup(identity: removedId, view: "r", contextWidth: 80, contextHeight: 24) == nil)
    }
}

// MARK: - Cache-safety gates

/// An `Equatable` view whose render count is observable: equality is by
/// `text` only, so re-renders are attributable to the cache gates rather
/// than value changes.
@MainActor
private final class RenderTally {
    var count = 0
}

private struct TalliedLabel: View, @MainActor Equatable {
    let text: String
    let tally: RenderTally

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    var body: some View {
        tally.count += 1
        return Text(text)
    }
}

private struct TalliedButton: View, @MainActor Equatable {
    let title: String
    let tally: RenderTally

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        tally.count += 1
        return Button(title) {}
    }
}

/// `EquatableView` used to store its rendered buffer unconditionally. That
/// cached measure-pass buffers (incomplete — interactive controls suppress
/// their hit-test regions while measuring — and the measure-size entry
/// clobbered the render-size one every frame) and interactive buffers (whose
/// hit-test handlers capture per-frame state). It now applies the same gate
/// as `_MemoizedRow`; these tests pin each branch. The time-varying branch
/// (Spinner/`requestAnimation`) is pinned in `SpinnerRowAnimationTests`.
@MainActor
@Suite("EquatableView cache-safety gates", .serialized)
struct EquatableViewGateTests {
    private func context(_ tuiContext: TUIContext) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
    }

    @Test("A measure-pass render is never served as the render-pass buffer")
    func measurePassBufferNotCached() {
        let tally = RenderTally()
        let view = EquatableView(content: TalliedLabel(text: "static", tally: tally))
        let renderContext = context(TUIContext())
        var measureContext = renderContext
        measureContext.isMeasuring = true

        _ = renderToBuffer(view, context: measureContext)
        #expect(tally.count == 1)

        // The render pass must not be satisfied by the measure-pass store…
        _ = renderToBuffer(view, context: renderContext)
        #expect(tally.count == 2, "the render pass re-renders; a measure buffer is incomplete")

        // …while the render-pass buffer itself is cached as before.
        _ = renderToBuffer(view, context: renderContext)
        #expect(tally.count == 2, "the second render pass serves the cache")
    }

    @Test("An interactive subtree re-renders every frame (its regions are per-frame state)")
    func interactiveContentNotCached() {
        let tally = RenderTally()
        let view = EquatableView(content: TalliedButton(title: "Press", tally: tally))
        let renderContext = context(TUIContext())

        let first = renderToBuffer(view, context: renderContext)
        let second = renderToBuffer(view, context: renderContext)
        #expect(!first.hitTestRegions.isEmpty, "the button registers a hit region")
        #expect(!second.hitTestRegions.isEmpty)
        #expect(tally.count == 2, "interactive content declines the cache")
    }

    @Test("Static content still caches (the gates cost nothing where safe)")
    func staticContentStillCached() {
        let tally = RenderTally()
        let view = EquatableView(content: TalliedLabel(text: "static", tally: tally))
        let renderContext = context(TUIContext())

        _ = renderToBuffer(view, context: renderContext)
        _ = renderToBuffer(view, context: renderContext)
        _ = renderToBuffer(view, context: renderContext)
        #expect(tally.count == 1, "one render, two cache hits")
    }
}
