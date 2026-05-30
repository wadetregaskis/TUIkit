//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    /// Number of times ``synchronize()`` has been called.
    private(set) var synchronizeCallCount = 0

    init() {}

    func value<T: Codable>(forKey key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = store[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setValue<T: Codable>(_ value: T, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(value) {
            store[key] = data
        }
    }

    func removeValue(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
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
