//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MockStorageBackend.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

@testable import TUIkit

/// An in-memory ``StorageBackend`` for tests.
///
/// Mirrors ``JSONFileStorage``'s encode/decode semantics (values are
/// JSON-encoded, so a type-mismatched read returns `nil`) but stays in
/// memory, runs synchronously, and leaves nothing on disk. Also tracks a
/// few interactions so tests can assert on backend behaviour.
final class MockStorageBackend: StorageBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]

    /// One ``StoredKey`` per key asked about, as a custom store keeps them:
    /// handed back with every read and write of the key.
    private var keys: [String: StoredKey] = [:]

    /// Number of times ``synchronize()`` has been called.
    private(set) var synchronizeCallCount = 0

    init() {}

    func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey) {
        lock.lock()
        defer { lock.unlock() }
        let value = store[key].flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        return (value, storedKey(key))
    }

    func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(value) {
            store[key] = data
        }
        return storedKey(key)
    }

    func remove(forKey key: String) -> StoredKey? {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
        return keys[key]
    }

    /// The key's ``StoredKey``, made on first use (caller holds `lock`).
    private func storedKey(_ key: String) -> StoredKey {
        if let stored = keys[key] { return stored }
        let stored = StoredKey()
        keys[key] = stored
        return stored
    }

    func synchronize() {
        lock.lock()
        defer { lock.unlock() }
        synchronizeCallCount += 1
    }

    // MARK: - Test inspection helpers

    /// Whether a raw value is stored for `key` (independent of its type).
    func hasValue(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return store[key] != nil
    }

    /// The number of distinct keys currently stored.
    var storedKeyCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return store.count
    }
}
