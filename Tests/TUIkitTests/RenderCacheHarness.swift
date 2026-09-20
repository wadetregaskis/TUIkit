//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCacheHarness.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// The frame-by-frame harness the render-cache contract suites drive the cache
/// with, and the one fixture they share.
///
/// A protocol rather than free functions so `context()` and `frame(_:_:)` stay
/// the unqualified calls they were when both suites lived in one file — the two
/// names read as the suite's own vocabulary, and several hundred call sites say
/// them. A suite adopts it and gains both.
@MainActor
protocol RenderCacheHarness {}

extension RenderCacheHarness {
    /// A context with a fresh, test-local cache. Built by hand rather than via
    /// `makeRenderContext` because these tests assert absolute entry counts and
    /// cache statistics: nothing else may touch this cache.
    func context(width: Int = 24, height: Int = 6) -> RenderContext {
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
    func frame(_ context: RenderContext, _ view: some View) -> FrameBuffer {
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        cache.removeInactive()
        return buffer
    }
}

/// A leaf that renders its text and nothing else — safe to memoize (no
/// hit-test regions, no overlays, no volatile reads).
///
/// Shared rather than file-private: it is the neutral subject both contract
/// suites put under the value they are testing.
struct CacheLeaf: View, Equatable {
    let text: String

    var body: some View {
        Text(text)
    }
}
