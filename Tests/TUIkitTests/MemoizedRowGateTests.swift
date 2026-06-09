//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MemoizedRowGateTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A non-interactive view that reads the per-frame-volatile pulse phase. It
/// emits no hit-test region, so the buffer gate cannot see it — only the
/// volatile-read probe can.
private struct PulseReader: View, Renderable {
    var body: Never { fatalError("PulseReader renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(text: "phase \(context.environment.pulsePhase)")
    }
}

/// Records the identity path it renders under, so a test can assert that
/// wrapping a row in `_MemoizedRow` does not leak the wrapper into the path.
private final class IdentityCapture: @unchecked Sendable { var path = "" }
private struct IdentityProbe: View, Renderable {
    let capture: IdentityCapture
    var body: Never { fatalError("IdentityProbe renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        capture.path = context.identity.path
        return FrameBuffer(text: "x")
    }
}

/// Proves the `_MemoizedRow` safety gate: an inert row is memoized, but a row
/// whose content is interactive (emits hit-test regions / overlays) is NOT —
/// because the render cache deliberately does not invalidate on the per-frame
/// pulse tick, so a cached *focused, animating* control would freeze. @State
/// changes are a separate matter: they already invalidate the cache via
/// `StateBox.didSet` → `clearAffected`, so stateful rows stay correct (covered
/// by `RenderCacheTests` / `StateBindingIdentityTests`).
@MainActor
@Suite("MemoizedRow gate", .serialized)
struct MemoizedRowGateTests {

    // A fresh RenderCache per test — TUIContext().renderCache is the shared
    // singleton, so reusing it would leak entries between serialized tests.
    private func makeContext(cache: RenderCache, width: Int = 80, height: Int = 24) -> RenderContext {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.stateStorage = tui.stateStorage
        env.lifecycle = tui.lifecycle
        env.keyEventDispatcher = tui.keyEventDispatcher
        env.renderCache = cache
        env.preferenceStorage = tui.preferences
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: env, identity: ViewIdentity(path: "Root"))
    }

    @Test("Inert row is memoized: stored once, served from cache thereafter")
    func inertRowIsMemoized() {
        let cache = RenderCache()
        let context = makeContext(cache: cache)

        let row = _MemoizedRow(element: "row-A", content: Text("hello"))
        let first = renderToBuffer(row, context: context)
        #expect(first.hitTestRegions.isEmpty)
        #expect(cache.count == 1)  // inert → stored

        let second = renderToBuffer(row, context: context)
        #expect(second.lines == first.lines)  // transparent
        #expect(cache.stats.hits >= 1)  // second render was a hit
    }

    @Test("Interactive row is NOT memoized: gate excludes hit-test regions")
    func interactiveRowIsNotMemoized() {
        let cache = RenderCache()
        let context = makeContext(cache: cache)

        let row = _MemoizedRow(element: "row-B", content: Button("Tap") {})
        let buffer = renderToBuffer(row, context: context)

        #expect(!buffer.hitTestRegions.isEmpty)  // it really is interactive
        #expect(cache.isEmpty)  // gate refused to cache it
    }

    @Test("Row that reads pulsePhase is NOT memoized (volatile-read probe)")
    func volatileReadingRowIsNotMemoized() {
        let cache = RenderCache()
        let context = makeContext(cache: cache)

        let row = _MemoizedRow(element: "row-C", content: PulseReader())
        let buffer = renderToBuffer(row, context: context)

        // The buffer gate cannot see this row — it has no regions/overlays...
        #expect(buffer.hitTestRegions.isEmpty)
        #expect(buffer.overlays.isEmpty)
        // ...but the volatile-read probe caught the pulsePhase read.
        #expect(cache.isEmpty)
    }

    @Test("ForEach rows in a stack are auto-memoized by element value")
    func stackForEachRowsAutoMemoized() {
        let cache = RenderCache()
        let context = makeContext(cache: cache)
        let items = [1, 2, 3, 4]  // Int is Equatable
        let view = VStack { ForEach(items, id: \.self) { Text("row \($0)") } }

        _ = renderToBuffer(view, context: context)
        #expect(cache.count >= items.count)  // each row stored

        let hitsBefore = cache.stats.hits
        _ = renderToBuffer(view, context: context)
        #expect(cache.stats.hits > hitsBefore)  // second render served from cache
    }

    @Test("ForEach-in-stack memo is identity-transparent (no wrapper in the path)")
    func stackForEachIdentityTransparent() {
        let cache = RenderCache()
        let context = makeContext(cache: cache)
        let capture = IdentityCapture()
        let view = VStack { ForEach([42], id: \.self) { _ in IdentityProbe(capture: capture) } }

        _ = renderToBuffer(view, context: context)

        #expect(!capture.path.isEmpty)
        // The row renders under its content's identity, not the _MemoizedRow
        // wrapper's — so @State / focus slots are exactly what they'd be unwrapped.
        #expect(!capture.path.contains("_MemoizedRow"))
        #expect(capture.path.contains("IdentityProbe"))
    }
}
