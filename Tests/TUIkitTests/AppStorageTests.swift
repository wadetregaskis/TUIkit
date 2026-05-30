//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AppStorageTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// MARK: - Fixtures

private struct Profile: Codable, Equatable {
    var name: String
    var age: Int
    var tags: [String]
}

private enum Theme: String, Codable, Equatable {
    case light
    case dark
}

// MARK: - sanitizedProcessName

@Suite("sanitizedProcessName")
struct SanitizedProcessNameTests {

    @Test(
        "Sanitizes process names for safe path use",
        arguments: [
            ("normal", "normal"),
            ("with/slash", "withslash"),
            ("a/b/c", "abc"),
            ("dot..dot", "dotdot"),
            ("../../etc", "etc"),
            ("a\u{0}b", "ab"),
            ("  spaced  ", "spaced"),
            ("\tleading-tab", "leading-tab"),
            ("", "app"),
            ("   ", "app"),
            ("/", "app"),
            ("..", "app"),
            ("/..", "app"),
        ]
    )
    func sanitizes(input: String, expected: String) {
        #expect(sanitizedProcessName(input) == expected)
    }

    @Test("Result never contains a path separator, null byte, or '..'")
    func resultHasNoUnsafeSequences() {
        for raw in ["a/b", "x..y", "..//..", "name\u{0}\u{0}", "/etc/passwd"] {
            let sanitized = sanitizedProcessName(raw)
            #expect(!sanitized.contains("/"))
            #expect(!sanitized.contains("\u{0}"))
            #expect(!sanitized.contains(".."))
            #expect(!sanitized.isEmpty)
        }
    }
}

// MARK: - JSONFileStorage

@Suite("JSONFileStorage")
struct JSONFileStorageTests {

    /// Runs `body` against a fresh `JSONFileStorage` backed by a unique
    /// temp file, cleaning the file up afterwards.
    private func withTempStorage(_ body: (JSONFileStorage, URL) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-appstorage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        body(JSONFileStorage(fileURL: url), url)
    }

    private func expectRoundTrip<T: Codable & Equatable>(_ value: T) {
        withTempStorage { storage, _ in
            storage.setValue(value, forKey: "key")
            let read: T? = storage.value(forKey: "key")
            #expect(read == value)
        }
    }

    // MARK: Round-trips across the documented supported types

    @Test("Round-trips a String")
    func roundTripString() { expectRoundTrip("hello world") }

    @Test("Round-trips an Int")
    func roundTripInt() { expectRoundTrip(42) }

    @Test("Round-trips a negative Int")
    func roundTripNegativeInt() { expectRoundTrip(-12_345) }

    @Test("Round-trips a Double")
    func roundTripDouble() { expectRoundTrip(3.141_592_653_589_793) }

    @Test("Round-trips a Bool")
    func roundTripBool() {
        expectRoundTrip(true)
        expectRoundTrip(false)
    }

    @Test("Round-trips a Date")
    func roundTripDate() { expectRoundTrip(Date(timeIntervalSinceReferenceDate: 1_000.5)) }

    @Test("Round-trips Data")
    func roundTripData() { expectRoundTrip(Data([0x00, 0x01, 0xFE, 0xFF])) }

    @Test("Round-trips a URL")
    func roundTripURL() { expectRoundTrip(URL(string: "https://example.com/a/b?c=d")!) }

    @Test("Round-trips an array")
    func roundTripArray() { expectRoundTrip([1, 2, 3, 4, 5]) }

    @Test("Round-trips a dictionary")
    func roundTripDictionary() { expectRoundTrip(["a": 1, "b": 2]) }

    @Test("Round-trips a custom Codable struct")
    func roundTripStruct() {
        expectRoundTrip(Profile(name: "Wade", age: 40, tags: ["swift", "tui"]))
    }

    @Test("Round-trips a custom Codable enum")
    func roundTripEnum() { expectRoundTrip(Theme.dark) }

    // MARK: Missing / removed / mismatched

    @Test("Reading an absent key returns nil")
    func absentKeyReturnsNil() {
        withTempStorage { storage, _ in
            let value: String? = storage.value(forKey: "missing")
            #expect(value == nil)
        }
    }

    @Test("removeValue clears a stored value")
    func removeClearsValue() {
        withTempStorage { storage, _ in
            storage.setValue(99, forKey: "k")
            storage.removeValue(forKey: "k")
            let value: Int? = storage.value(forKey: "k")
            #expect(value == nil)
        }
    }

    @Test("setValue overwrites an existing value")
    func overwriteValue() {
        withTempStorage { storage, _ in
            storage.setValue(1, forKey: "k")
            storage.setValue(2, forKey: "k")
            #expect(storage.value(forKey: "k") == 2)
        }
    }

    @Test("Reading a value as the wrong type returns nil")
    func typeMismatchReturnsNil() {
        withTempStorage { storage, _ in
            storage.setValue("not a number", forKey: "k")
            let asInt: Int? = storage.value(forKey: "k")
            #expect(asInt == nil)
        }
    }

    // MARK: Disk persistence

    @Test("Values persist to disk and reload in a new instance after synchronize")
    func persistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-appstorage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let writer = JSONFileStorage(fileURL: url)
            writer.setValue("hello", forKey: "greeting")
            writer.setValue(42, forKey: "answer")
            writer.setValue(Profile(name: "x", age: 1, tags: ["t"]), forKey: "profile")
            writer.synchronize()  // force a synchronous flush to disk
        }

        let reader = JSONFileStorage(fileURL: url)
        #expect(reader.value(forKey: "greeting") == "hello")
        #expect(reader.value(forKey: "answer") == 42)
        let profile: Profile? = reader.value(forKey: "profile")
        #expect(profile == Profile(name: "x", age: 1, tags: ["t"]))
    }

    @Test("A nonexistent backing file behaves as empty storage")
    func nonexistentFileIsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-appstorage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // File is never created.
        let storage = JSONFileStorage(fileURL: url)
        let value: String? = storage.value(forKey: "k")
        #expect(value == nil)
    }

    @Test("A corrupt backing file is ignored and storage starts fresh")
    func corruptFileStartsFresh() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-appstorage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try? "this is not valid json".write(to: url, atomically: true, encoding: .utf8)

        let storage = JSONFileStorage(fileURL: url)
        let value: String? = storage.value(forKey: "k")
        #expect(value == nil)  // didn't crash; treated as empty
        // …and it's still usable.
        storage.setValue("recovered", forKey: "k")
        #expect(storage.value(forKey: "k") == "recovered")
    }
}

// MARK: - AppStorage property wrapper

@Suite("AppStorage property wrapper")
struct AppStoragePropertyWrapperTests {

    @Test("Returns the default value when the key is absent")
    func defaultWhenAbsent() {
        let backend = MockStorageBackend()
        let storage = AppStorage(wrappedValue: "Guest", "username", storage: backend)
        #expect(storage.wrappedValue == "Guest")
    }

    @Test("Reading the default value does not write to the backend")
    func readingDefaultDoesNotWrite() {
        let backend = MockStorageBackend()
        let storage = AppStorage(wrappedValue: "Guest", "username", storage: backend)
        _ = storage.wrappedValue
        #expect(!backend.hasValue(forKey: "username"))
        #expect(backend.storedKeyCount == 0)
    }

    @Test("Reads a previously stored value")
    func readsStoredValue() {
        let backend = MockStorageBackend()
        backend.setValue("Wade", forKey: "username")
        let storage = AppStorage(wrappedValue: "Guest", "username", storage: backend)
        #expect(storage.wrappedValue == "Wade")
    }

    @Test("Setting wrappedValue persists to the backend")
    func setPersists() {
        let backend = MockStorageBackend()
        let storage = AppStorage(wrappedValue: 0, "count", storage: backend)
        storage.wrappedValue = 7
        #expect(storage.wrappedValue == 7)
        #expect(backend.value(forKey: "count") == 7)
    }

    @Test("projectedValue exposes a Binding that round-trips through storage")
    func projectedValueBinding() {
        let backend = MockStorageBackend()
        let storage = AppStorage(wrappedValue: false, "flag", storage: backend)
        let binding = storage.projectedValue

        #expect(binding.wrappedValue == false)
        binding.wrappedValue = true
        #expect(storage.wrappedValue == true)
        #expect(backend.value(forKey: "flag") == true)
    }

    @Test("Distinct keys are independent")
    func distinctKeysAreIndependent() {
        let backend = MockStorageBackend()
        let a = AppStorage(wrappedValue: "a", "ka", storage: backend)
        let b = AppStorage(wrappedValue: "b", "kb", storage: backend)
        a.wrappedValue = "A"
        #expect(b.wrappedValue == "b")
        #expect(a.wrappedValue == "A")
    }

    @Test("Persists a custom Codable value type")
    func customCodableValue() {
        let backend = MockStorageBackend()
        let storage = AppStorage(
            wrappedValue: Profile(name: "x", age: 1, tags: []),
            "profile",
            storage: backend
        )
        let updated = Profile(name: "y", age: 2, tags: ["t"])
        storage.wrappedValue = updated
        #expect(storage.wrappedValue == updated)
    }
}
