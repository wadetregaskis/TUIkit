//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StateStorageIdentityTests.swift
//
//  Created by LAYERED.work
//  License: MIT  branch switches invalidate state, and nested views get independent state.
//

import Testing

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("State Storage Identity Tests", .serialized)
struct StateStorageIdentityTests {

    /// Creates a fresh StateStorage for test isolation.
    ///
    /// State mutations during tests call `setNeedsRender()` on the shared
    /// `AppState.shared` instance — that's harmless and avoids race
    /// conditions with parallel suites.
    private func testStorage() -> StateStorage {
        StateStorage()
    }

    // MARK: - Render-time @State binding

    @Test("@State binds to storage by render identity and persists across rebinds")
    func stateBindsByRenderIdentity() {
        let storage = testStorage()
        let identity = ViewIdentity(path: "TestView")

        // Bind a freshly-constructed view's @State to its render identity, then
        // mutate through it (writing to the persistent storage box).
        let first = OneStateView()
        bindStateProperties(of: first, identity: identity, storage: storage)
        first.value = 99

        // A reconstructed view bound at the SAME identity sees the persisted value
        // — even though its own default is 42.
        let second = OneStateView()
        bindStateProperties(of: second, identity: identity, storage: storage)
        #expect(second.value == 99)

        // A different identity is independent (gets its own default).
        let other = OneStateView()
        bindStateProperties(of: other, identity: ViewIdentity(path: "OtherView"), storage: storage)
        #expect(other.value == 42)
    }

    @Test("@State uses a local box until it is bound")
    func localBoxUntilBound() {
        let state = OneStateView()  // not bound to any storage
        #expect(state.value == 42)
        state.value = 7
        #expect(state.value == 7)
    }

    @Test("Multiple @State on a view bind to distinct storage slots (declaration order)")
    func multipleStateDistinctSlots() {
        let storage = testStorage()
        let identity = ViewIdentity(path: "MultiStateView")

        let first = TwoStateView()
        bindStateProperties(of: first, identity: identity, storage: storage)
        first.number = 20
        first.text = "world"

        // Reconstruct + rebind at the same identity: each @State keeps its own slot.
        let second = TwoStateView()
        bindStateProperties(of: second, identity: identity, storage: storage)
        #expect(second.number == 20)
        #expect(second.text == "world")
    }

    // MARK: - View Identity

    @Test("Child identity appends type and index")
    func childIdentityPath() {
        let root = ViewIdentity(path: "Root")
        let child = root.child(type: Int.self, index: 2)
        #expect(child.path == "Root/Int.2")
    }

    @Test("Branch identity uses hash separator")
    func branchIdentityPath() {
        let root = ViewIdentity(path: "Root")
        let branch = root.branch("true")
        #expect(branch.path == "Root#true")
    }

    @Test("isAncestor detects path descendants")
    func ancestorDetection() {
        let parent = ViewIdentity(path: "A/B")
        let child = ViewIdentity(path: "A/B/C")
        let sibling = ViewIdentity(path: "A/D")
        let branchChild = ViewIdentity(path: "A/B#true/C")

        #expect(parent.isAncestor(of: child) == true)
        #expect(parent.isAncestor(of: branchChild) == true)
        #expect(parent.isAncestor(of: sibling) == false)
        #expect(parent.isAncestor(of: parent) == false)
    }

    // MARK: - State Storage

    @Test("StateStorage returns same box for same key")
    func storageSameKey() {
        let storage = testStorage()
        let key = StateStorage.StateKey(
            identity: ViewIdentity(path: "V"),
            propertyIndex: 0
        )

        let box1: StateBox<Int> = storage.storage(for: key, default: 0)
        box1.value = 42
        let box2: StateBox<Int> = storage.storage(for: key, default: 0)

        #expect(box2.value == 42)
        #expect(box1 === box2)
    }

    @Test("StateStorage returns different boxes for different keys")
    func storageDifferentKeys() {
        let storage = testStorage()
        let key1 = StateStorage.StateKey(
            identity: ViewIdentity(path: "V"),
            propertyIndex: 0
        )
        let key2 = StateStorage.StateKey(
            identity: ViewIdentity(path: "V"),
            propertyIndex: 1
        )

        let box1: StateBox<Int> = storage.storage(for: key1, default: 10)
        let box2: StateBox<Int> = storage.storage(for: key2, default: 20)

        #expect(box1.value == 10)
        #expect(box2.value == 20)
        #expect(box1 !== box2)
    }

    // MARK: - Branch Invalidation

    @Test("invalidateDescendants removes state under a branch")
    func branchInvalidation() {
        let storage = testStorage()
        let branchIdentity = ViewIdentity(path: "Root#true")
        let childIdentity = ViewIdentity(path: "Root#true/Child")

        // Create state under the true branch
        let childKey = StateStorage.StateKey(identity: childIdentity, propertyIndex: 0)
        let box: StateBox<Int> = storage.storage(for: childKey, default: 5)
        box.value = 99

        // Invalidate the true branch
        storage.invalidateDescendants(of: branchIdentity)

        // State should be gone — new lookup returns default
        let newBox: StateBox<Int> = storage.storage(for: childKey, default: 5)
        #expect(newBox.value == 5)
        #expect(newBox !== box)
    }

    // MARK: - Render Pass GC

    @Test("endRenderPass removes state for views not marked active")
    func renderPassGarbageCollection() {
        let storage = testStorage()
        let activeIdentity = ViewIdentity(path: "Active")
        let staleIdentity = ViewIdentity(path: "Stale")

        // Create state for both
        let activeKey = StateStorage.StateKey(identity: activeIdentity, propertyIndex: 0)
        let staleKey = StateStorage.StateKey(identity: staleIdentity, propertyIndex: 0)
        let _: StateBox<Int> = storage.storage(for: activeKey, default: 1)
        let staleBox: StateBox<Int> = storage.storage(for: staleKey, default: 2)

        // Simulate render pass where only "Active" is seen
        storage.beginRenderPass()
        storage.markActive(activeIdentity)
        storage.endRenderPass()

        // Active state should survive
        let activeBox: StateBox<Int> = storage.storage(for: activeKey, default: 1)
        #expect(activeBox.value == 1)

        // Stale state should be gone — new lookup returns default
        let newStaleBox: StateBox<Int> = storage.storage(for: staleKey, default: 2)
        #expect(newStaleBox !== staleBox)
        #expect(newStaleBox.value == 2)
    }

    // MARK: - Integration: renderToBuffer with Hydration

    @Test("State survives reconstruction through renderToBuffer")
    func stateSurvivesRenderToBuffer() {
        let tuiContext = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: env,
            identity: ViewIdentity(path: "")
        )

        // First render: creates state with default 0, body sets it to 42
        let buffer1 = renderToBuffer(CounterView(), context: context)
        #expect(buffer1.lines.first?.contains("42") == true)

        // Second render: state should still be 42 even though CounterView is reconstructed
        let buffer2 = renderToBuffer(CounterView(), context: context)
        #expect(buffer2.lines.first?.contains("42") == true)
    }

    @Test("Nested views get independent state identities")
    func nestedViewsIndependentState() {
        let tuiContext = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            environment: env,
            identity: ViewIdentity(path: "")
        )

        // Render a parent with two child views that each have @State
        let buffer = renderToBuffer(ParentWithTwoCounters(), context: context)

        // Both counters should render independently
        let lines = buffer.lines.joined()
        #expect(lines.contains("A:10"))
        #expect(lines.contains("B:20"))
    }
}

// MARK: - Test Helpers

/// A view that initializes @State to 0 then immediately sets it to 42.
/// On reconstruction, the state should still be 42 (not reset to 0).
private struct CounterView: View {
    @State var countValue = 0

    var body: some View {
        if countValue == 0 {
            // First render: set to 42
            countValue = 42
        }
        return Text("Count:\(countValue)")
    }
}

/// A parent view containing two child views with independent state.
private struct ParentWithTwoCounters: View {
    var body: some View {
        VStack {
            CounterA()
            CounterB()
        }
    }
}

private struct CounterA: View {
    @State var value = 0

    var body: some View {
        if value == 0 { value = 10 }
        return Text("A:\(value)")
    }
}

private struct CounterB: View {
    @State var value = 0

    var body: some View {
        if value == 0 { value = 20 }
        return Text("B:\(value)")
    }
}

/// A view with a single `@State` (default 42), for render-time binding tests.
private struct OneStateView: View {
    @State var value = 42
    var body: some View { Text("\(value)") }
}

/// A view with two `@State` properties, for distinct-slot tests.
private struct TwoStateView: View {
    @State var number = 10
    @State var text = "hello"
    var body: some View { Text("\(number):\(text)") }
}
