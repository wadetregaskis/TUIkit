//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PreferenceStorageTests.swift
//
//  Tests for PreferenceStorage: stack behavior, setValue with reduce,
//  callbacks, beginRenderPass, and reset.
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitCore

/// String preference key for storage tests.
private struct StorageStringKey: PreferenceKey {
    static let defaultValue: String = "default"
}

/// Additive counter preference key for storage tests.
private struct StorageCounterKey: PreferenceKey {
    static let defaultValue: Int = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

@MainActor
@Suite("PreferenceStorage Tests")
struct PreferenceStorageTests {

    @Test("New storage has default values")
    func newStorageDefaults() {
        let storage = PreferenceStorage()
        #expect(storage.current[StorageStringKey.self] == "default")
    }

    @Test("setValue stores value")
    func setValueStores() {
        let storage = PreferenceStorage()
        storage.setValue("hello", forKey: StorageStringKey.self)
        #expect(storage.current[StorageStringKey.self] == "hello")
    }

    @Test("setValue with additive reduce accumulates")
    func setValueAccumulates() {
        let storage = PreferenceStorage()
        storage.setValue(5, forKey: StorageCounterKey.self)
        storage.setValue(3, forKey: StorageCounterKey.self)
        #expect(storage.current[StorageCounterKey.self] == 8)
    }

    @Test("Push creates new context")
    func pushNewContext() {
        let storage = PreferenceStorage()
        storage.setValue("outer", forKey: StorageStringKey.self)
        storage.push()
        #expect(storage.current[StorageStringKey.self] == "default")
    }

    @Test("Pop merges into parent")
    func popMerges() {
        let storage = PreferenceStorage()
        storage.push()
        storage.setValue("inner", forKey: StorageStringKey.self)
        _ = storage.pop()
        #expect(storage.current[StorageStringKey.self] == "inner")
    }

    @Test("Nested push/pop preserves outer values")
    func nestedPushPop() {
        let storage = PreferenceStorage()
        storage.setValue("outer", forKey: StorageStringKey.self)
        storage.push()
        storage.setValue("inner", forKey: StorageStringKey.self)
        _ = storage.pop()
        #expect(storage.current[StorageStringKey.self] == "inner")
    }

    /// An accumulating key accumulates ACROSS scopes, not only within one.
    ///
    /// `setValue` always folded through ``PreferenceKey/reduce``; `pop`'s merge
    /// assigned, so every scope that closed replaced its parent's running total
    /// with its own. Two nested `.onPreferenceChange` observers over a summing
    /// key reported the inner subtree's total as the whole tree's, and the
    /// contributions of everything beside it were simply gone.
    ///
    /// `!= 0` was all this asserted, which 3 satisfies as well as 6 does.
    @Test("Multiple nested levels accumulate rather than overwrite")
    func multipleNesting() {
        let storage = PreferenceStorage()
        storage.setValue(1, forKey: StorageCounterKey.self)
        storage.push()
        storage.setValue(2, forKey: StorageCounterKey.self)
        storage.push()
        storage.setValue(3, forKey: StorageCounterKey.self)
        _ = storage.pop()
        _ = storage.pop()
        #expect(storage.current[StorageCounterKey.self] == 6, "1 + 2 + 3")
    }

    /// The other half: a key with the DEFAULT reduce names a single winner, and
    /// the innermost scope is still it. Without this the fix above could be a
    /// blanket "always accumulate", which would break every ordinary key.
    @Test("A single-winner key still lets the inner scope win")
    func nestedSingleWinner() {
        let storage = PreferenceStorage()
        storage.setValue("outer", forKey: StorageStringKey.self)
        storage.push()
        storage.setValue("middle", forKey: StorageStringKey.self)
        storage.push()
        storage.setValue("inner", forKey: StorageStringKey.self)
        _ = storage.pop()
        _ = storage.pop()
        #expect(storage.current[StorageStringKey.self] == "inner")
    }

    /// A scope that says nothing about a key must not disturb it — the merge
    /// has no entry to fold, and the parent's value stands.
    @Test("An empty scope leaves the parent's value alone")
    func emptyScopeIsInert() {
        let storage = PreferenceStorage()
        storage.setValue(4, forKey: StorageCounterKey.self)
        storage.push()
        _ = storage.pop()
        #expect(storage.current[StorageCounterKey.self] == 4)
    }

    @Test("Pop on single context returns current values")
    func popSingleContext() {
        let storage = PreferenceStorage()
        storage.setValue("value", forKey: StorageStringKey.self)
        let popped = storage.pop()
        #expect(popped[StorageStringKey.self] == "value")
        #expect(storage.current[StorageStringKey.self] == "value")
    }

    @Test("onPreferenceChange callback is triggered")
    func changeCallback() {
        let storage = PreferenceStorage()
        nonisolated(unsafe) var received: String?
        storage.onPreferenceChange(StorageStringKey.self) { value in
            received = value
        }
        storage.setValue("updated", forKey: StorageStringKey.self)
        #expect(received == "updated")
    }

    @Test("Multiple callbacks for same key all fire")
    func multipleCallbacks() {
        let storage = PreferenceStorage()
        nonisolated(unsafe) var count = 0
        storage.onPreferenceChange(StorageStringKey.self) { _ in count += 1 }
        storage.onPreferenceChange(StorageStringKey.self) { _ in count += 1 }
        storage.setValue("trigger", forKey: StorageStringKey.self)
        #expect(count == 2)
    }

    @Test("beginRenderPass resets callbacks and stack")
    func beginRenderPass() {
        let storage = PreferenceStorage()
        storage.setValue("old", forKey: StorageStringKey.self)
        nonisolated(unsafe) var callbackFired = false
        storage.onPreferenceChange(StorageStringKey.self) { _ in callbackFired = true }

        storage.beginRenderPass()

        #expect(storage.current[StorageStringKey.self] == "default")
        storage.setValue("new", forKey: StorageStringKey.self)
        #expect(callbackFired == false)
    }

    @Test("reset clears everything")
    func resetClears() {
        let storage = PreferenceStorage()
        storage.setValue("data", forKey: StorageStringKey.self)
        storage.push()
        storage.setValue(42, forKey: StorageCounterKey.self)

        storage.reset()

        #expect(storage.current[StorageStringKey.self] == "default")
        #expect(storage.current[StorageCounterKey.self] == 0)
    }
}
