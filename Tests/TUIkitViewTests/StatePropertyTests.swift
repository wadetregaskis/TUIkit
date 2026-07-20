//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatePropertyTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

#if os(Linux)
    private let isLinux = true
#else
    private let isLinux = false
#endif

@MainActor
@Suite(
    "State Property Wrapper Tests",
    .disabled(if: isLinux, "Skipped on Linux due to Swift runtime race condition in StateStorage")
)
struct StatePropertyWrapperTests {

    @Test("State can be mutated")
    func stateMutation() {
        let state = State(wrappedValue: 0)
        state.wrappedValue = 10
        #expect(state.wrappedValue == 10)
    }

    @Test("A bound State's mutation invalidates its render cache")
    func stateTriggerRender() {
        // A @State is bound to its context's StateStorage/RenderCache at render
        // time; mutating it routes `StateBox.didSet` through that cache (its
        // `RenderInvalidationSink`), which drops the affected subtree's cached
        // buffers at the next frame and requests a render. We assert on the
        // per-context cache — deterministic — rather than the process-wide
        // `AppState.shared.needsRender` flag, which parallel tests pollute.
        let storage = StateStorage()
        let cache = RenderCache()
        storage.renderCache = cache
        let identity = ViewIdentity(path: "Root/State")

        let state = State(wrappedValue: "initial")
        state.bindState(to: storage, identity: identity, propertyIndex: 0)

        // Seed a cached buffer at the state's identity, then mutate it.
        cache.store(
            identity: identity, view: 0, buffer: FrameBuffer(text: "cached"),
            contextWidth: 80, contextHeight: 24)
        state.wrappedValue = "changed"
        cache.beginRenderPass()  // drains the deferred invalidation

        #expect(
            cache.lookup(identity: identity, view: 0, contextWidth: 80, contextHeight: 24) == nil,
            "mutating the bound state invalidates its cached subtree")
    }

    @Test("Binding from State updates original")
    func stateBindingUpdates() {
        let state = State(wrappedValue: 0)
        let binding = state.projectedValue
        binding.wrappedValue = 77
        #expect(state.wrappedValue == 77)
    }
}
