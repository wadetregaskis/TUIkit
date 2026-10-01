//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StoredEntryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// A built-in store keeps the value a key's bytes decoded to, so a read on the
/// render path does not decode JSON every time — and serves it only where the
/// fresh decode would have answered the same.
@Suite("A store's kept values answer as a fresh decode would")
struct StoredEntryTests {

    private final class Box: Codable, Equatable {
        var name: String
        init(name: String) { self.name = name }
        static func == (lhs: Box, rhs: Box) -> Bool { lhs.name == rhs.name }
    }

    private static func withStorage(_ body: (JSONFileStorage) throws -> Void) rethrows {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit.tests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = JSONFileStorage(fileURL: directory.appendingPathComponent("settings.json"))
        defer { storage.synchronize() }
        try body(storage)
    }

    @Test("A value read as another type decodes from the bytes, as it always did")
    func anotherTypeDecodesTheBytes() {
        Self.withStorage { storage in
            storage.setValue(1, forKey: "count")
            #expect(storage.value(forKey: "count") == Optional(1))
            #expect(storage.value(forKey: "count") == Optional(1.0), "an Int's bytes read as a Double")
            #expect(storage.value(forKey: "count") == String?.none, "an Int's bytes read as a String")
            #expect(storage.value(forKey: "count") == Optional(1), "and as the Int again")
        }
    }

    @Test("A stored class hands every read an instance of its own")
    func classInstancesAreNotShared() throws {
        try Self.withStorage { storage in
            storage.setValue(Box(name: "a"), forKey: "box")
            let first: Box = try #require(storage.value(forKey: "box"))
            let second: Box = try #require(storage.value(forKey: "box"))
            #expect(first == second)
            #expect(first !== second, "two reads shared one instance, so a mutation of one would change the next")
            first.name = "changed"
            #expect(storage.value(forKey: "box") == Optional(Box(name: "a")))
        }
    }

    @Test("A removed value reads as absent, and a stored one after it as itself")
    func removeThenStore() {
        Self.withStorage { storage in
            storage.setValue("first", forKey: "name")
            storage.removeValue(forKey: "name")
            #expect(storage.value(forKey: "name") == String?.none)
            storage.setValue("second", forKey: "name")
            #expect(storage.value(forKey: "name") == Optional("second"))
        }
    }
}
