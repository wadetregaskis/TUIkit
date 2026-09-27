//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservationCacheLifetimeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A body evaluated under observation arms a registration on each property it
/// read, and the registration lives until one of them is written — for a
/// property nothing writes, for as long as the model does. Its `onChange`
/// captured the render cache strongly, so a model that outlived the app kept
/// the app's whole render cache alive: every buffer and size in it.
@MainActor
@Suite("An observed body does not keep the render cache alive")
struct ObservationCacheLifetimeTests {
    @Observable
    final class Model {
        var count = 0
    }

    private struct Reader: View {
        let model: Model
        var body: some View { Text(verbatim: "count \(model.count)") }
    }

    /// Draws `Reader` once in a fresh `TUIContext` and returns a weak probe of
    /// its cache, the context and everything else that held the cache gone.
    private static func drawAndRelease(_ model: Model) -> () -> RenderCache? {
        weak var probe: RenderCache?
        do {
            let tui = TUIContext()
            probe = tui.renderCache
            let context = RenderContext(availableWidth: 20, availableHeight: 2, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let buffer = renderToBuffer(Reader(model: model), context: context)
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            #expect(buffer.lines.first?.stripped.hasPrefix("count 0") == true)
        }
        return { probe }
    }

    @Test("A cache is freed with its owner, though a body it drew read a model nothing writes")
    func cacheFreedWithItsOwner() {
        let model = Model()
        let probe = Self.drawAndRelease(model)
        #expect(probe() == nil, "the registration the body armed kept the cache alive")
        // The registration is still armed: writing the model fires it, with
        // its cache gone, and that does nothing.
        model.count = 1
        withExtendedLifetime(model) {}
    }

    @Test("A change reaches the cache the body was drawn with, at the body's identity")
    func liveCacheInvalidated() {
        let cache = RenderCache()
        let identity = ViewIdentity(rootType: Model.self)
        cache.store(identity: identity, view: 0, buffer: FrameBuffer(text: "x"), contextWidth: 1, contextHeight: 1)
        var fellBack = false
        reportObservedChange(at: identity, to: cache, hadCache: true) { fellBack = true }
        cache.beginRenderPass()
        #expect(cache.isEmpty, "the entry at the reader's identity was dropped")
        #expect(!fellBack, "a live cache takes the change itself")
    }

    @Test("A change drawn with a cache that has gone does nothing")
    func deadCacheIsANoOp() {
        var fellBack = false
        reportObservedChange(at: ViewIdentity(rootType: Model.self), to: nil, hadCache: true) { fellBack = true }
        #expect(!fellBack, "a cache that has gone must not clear another app's")
    }

    @Test("A change drawn with no cache at all still clears everything")
    func noCacheFallsBack() {
        var fellBack = false
        reportObservedChange(at: ViewIdentity(rootType: Model.self), to: nil, hadCache: false) { fellBack = true }
        #expect(fellBack, "a render with no cache to scope to falls back to the whole-cache clear")
    }
}
