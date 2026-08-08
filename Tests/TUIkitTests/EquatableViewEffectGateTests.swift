//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EquatableViewEffectGateTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A memoizable leaf whose body is built by a closure, so each case can put a
/// different effect **inside** the subtree the cache would serve.
///
/// That placement is the whole point. `Leaf().equatable().onAppear {}` puts the
/// effect *above* the boundary, where it re-runs every frame and caching the
/// inert leaf below it is perfectly correct. The dangerous shape is the effect
/// *below* the boundary, where a cache hit skips the body that registers it.
///
/// Equality is by label alone — the closure is the view's construction, not its
/// content — which is what lets two separately-built values compare equal and
/// hit.
private struct EffectLeaf<Content: View>: View, @MainActor Equatable {
    let label: String
    let build: @MainActor (Text) -> Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.label == rhs.label }

    var body: some View {
        build(Text(label))
    }
}

private struct CountKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

/// A subtree that registers an effect must never be served from cache: the frame
/// the cache answers is a frame on which the effect was never registered, so
/// `onAppear` never fires, a key handler is not in the dispatcher, focus is not
/// in the ring.
///
/// Every effect site declares itself through
/// `VolatileReadTracker.recordRenderSideEffect()`, and `EquatableView` refuses
/// to *store* any buffer whose render tripped it. That is a single contract with
/// many call sites, so it is exactly the kind of thing that rots quietly: a new
/// effect modifier that forgets to declare itself is invisible until someone's
/// `onAppear` stops firing on the second frame.
///
/// Upstream pinned the same contract from the other side (`d4f7d3aa`,
/// characterizing the effects that vanish when it is missing).
@MainActor
@Suite("EquatableView effect gate", .serialized)
struct EquatableViewEffectGateTests {

    private func context() -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.focusManager = FocusManager()
        environment.renderCache = RenderCache()
        environment.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: 40,
            availableHeight: 10,
            environment: environment,
            identity: ViewIdentity(path: "Root")
        )
    }

    /// Renders `view` through one cache lifecycle and reports whether anything
    /// was stored.
    private func storesBuffer(_ build: () -> some View) -> Bool {
        let context = self.context()
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        _ = renderToBuffer(build(), context: context)
        cache.removeInactive()
        return !cache.isEmpty
    }

    @Test("An inert subtree is cached — the control")
    func inertSubtreeIsCached() {
        // If this ever fails, every expectation below passes vacuously.
        #expect(storesBuffer { EffectLeaf(label: "inert") { $0 }.equatable() })
    }

    @Test("An effect ABOVE the boundary does not stop the subtree caching")
    func effectAboveTheBoundaryStillCaches() {
        // The distinction the rest of this suite turns on: here the effect
        // re-registers every frame regardless, because the cache is not what
        // answers for it.
        #expect(storesBuffer { EffectLeaf(label: "x") { $0 }.equatable().onAppear {} })
    }

    @Test("onAppear inside the subtree declines the cache")
    func onAppearDeclines() {
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.onAppear {} }.equatable() })
    }

    @Test("task inside the subtree declines the cache")
    func taskDeclines() {
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.task {} }.equatable() })
    }

    @Test("onChange inside the subtree declines the cache")
    func onChangeDeclines() {
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.onChange(of: 1) { _, _ in } }.equatable() })
    }

    @Test("A key handler inside the subtree declines the cache")
    func keyPressDeclines() {
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.onKeyPress { _ in false } }.equatable() })
    }

    @Test("Focus registration inside the subtree declines the cache")
    func focusableDeclines() {
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.focusable() }.equatable() })
    }

    @Test("A preference write inside the subtree declines the cache")
    func preferenceDeclines() {
        #expect(
            !storesBuffer {
                EffectLeaf(label: "x") { $0.preference(key: CountKey.self, value: 1) }.equatable()
            })
    }

    @Test("A measure pass never stores")
    func measurePassNeverStores() {
        // The buffer a measure pass produces is incomplete — interactive
        // controls suppress their hit-test regions while measuring — and it is
        // produced at a different size. Storing it would let the same frame's
        // render walk hit on it, which is how upstream's first-frame effect loss
        // happened: the subtree's effects never mounted at all.
        var context = self.context()
        context.isMeasuring = true
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        _ = renderToBuffer(EffectLeaf(label: "inert") { $0 }.equatable(), context: context)
        cache.removeInactive()
        #expect(cache.isEmpty)
    }
}
