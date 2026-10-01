//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UserDefaultsStorageTests.swift
//
//  `UserDefaultsStorage` is what `@AppStorage` actually writes through on
//  Apple platforms, and no test named it. `StorageFailureTests` pins the
//  read/write asymmetry — a decode failure is silent, an encode failure is
//  reported — only for `JSONFileStorage`, and `AppStorageTests` injects a mock
//  backend throughout, so the shipping path's own `catch` arms were cold: the
//  one line ever executed was the `guard` miss for an absent key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// A value whose encoding always fails, so the write path's `catch` runs.
private struct UnencodableSetting: Codable {
    struct Nope: Error {}

    func encode(to encoder: any Encoder) throws { throw Nope() }

    init() {}
    init(from decoder: any Decoder) throws { self.init() }
}

/// Something with more than one field, so a round trip proves the JSON coding
/// rather than a passthrough.
private struct Settings: Codable, Equatable {
    var name: String
    var count: Int
    var enabled: Bool
}

@Suite("UserDefaults storage backend")
struct UserDefaultsStorageTests {

    /// A backend on its own suite and a key nothing else can produce, with
    /// everything it wrote removed afterwards.
    ///
    /// A fresh suite rather than `.standard`: this runs in a real user session,
    /// and the standard domain is the user's own preferences. The unique key is
    /// what makes the "not reported" assertions below safe:
    /// ``StorageDiagnostics`` is a process-wide channel that other suites
    /// report into in parallel, and another key's report cannot make
    /// `lastFailure?.key != key` false. It CAN make `== key` false — another
    /// report lands between the write and the read — so the one test that
    /// asserts its own report is the latest runs in an exit test.
    private static func withStorage(_ body: (UserDefaultsStorage, String) -> Void) {
        withSuite { suite, key in body(UserDefaultsStorage(suiteName: suite), key) }
    }

    /// ``withStorage(_:)``'s suite and key, for a test that opens the suite
    /// more than once.
    private static func withSuite(_ body: (String, String) -> Void) {
        #if canImport(Darwin)
        // On Apple platforms a suite named by an absolute path keeps its file
        // at that path (`<path>.plist`), not in ~/Library/Preferences — so the
        // suite lives in a temporary directory of its own, and deleting the
        // directory removes whatever the preferences daemon wrote, whenever it
        // wrote it. A named suite left an empty file in ~/Library/Preferences
        // on most runs: removing the domain empties it without deleting it,
        // and deleting the file afterwards did not stick — measured, four of
        // the six tests' files came back (an old development machine had
        // collected 2,031 of them, the new one 868 in a day).
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit.tests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = directory.appendingPathComponent("defaults").path
        #else
        let suite = "tuikit.tests.\(UUID().uuidString)"
        #endif
        let key = "settings-\(UUID().uuidString)"
        let storage = UserDefaultsStorage(suiteName: suite)
        defer {
            // Both halves are needed across platforms: the Apple backend keeps
            // its values in the suite's domain, and the Linux one — which
            // stands `UserDefaults` up on a JSON file — only sees the removal.
            storage.removeValue(forKey: key)
            storage.synchronize()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            #if canImport(Darwin)
            try? FileManager.default.removeItem(at: directory)
            #endif
        }
        body(suite, key)
    }

    #if canImport(Darwin)
    /// A read keeps the value its bytes decoded to, so the bytes themselves
    /// must be read every time: another process — or here, another store on
    /// the same suite — may have written new ones, and a kept value served
    /// past them would be a stale setting. Apple platforms only: elsewhere a
    /// suite is a JSON file each store loads once, and two stores on one
    /// never saw each other's writes.
    @Test("Bytes another writer put in the suite are read, not the value kept from before")
    func anotherWritersBytesAreRead() {
        Self.withSuite { suite, key in
            let (storage, other) = (UserDefaultsStorage(suiteName: suite), UserDefaultsStorage(suiteName: suite))
            storage.setValue(1, forKey: key)
            #expect(storage.value(forKey: key) == Optional(1))
            other.setValue(2, forKey: key)
            #expect(storage.value(forKey: key) == Optional(2), "the kept 1 was served over the new bytes")
            other.removeValue(forKey: key)
            #expect(storage.value(forKey: key) == Int?.none, "the kept 2 was served after a removal")
        }
    }
    #endif

    @Test("A Codable value round-trips through the backend")
    func roundTrip() {
        Self.withStorage { storage, key in
            let value = Settings(name: "hello", count: 3, enabled: true)
            storage.setValue(value, forKey: key)
            #expect(storage.value(forKey: key) == Optional(value))
            storage.synchronize()
            #expect(storage.value(forKey: key) == Optional(value), "and survives a flush")
        }
    }

    @Test("An absent key reads as nil")
    func absentKeyIsNil() {
        Self.withStorage { storage, key in
            let absent: Settings? = storage.value(forKey: key)
            #expect(absent == nil)
        }
    }

    @Test("A value stored under one type reads back as nil under another, silently")
    func decodeFailureIsSilentAndFallsBack() {
        Self.withStorage { storage, key in
            storage.setValue("a string", forKey: key)
            // The migration case the doc comment describes: the stored shape no
            // longer matches the type asked for. `@AppStorage`'s defined
            // behaviour is the caller's default, not an error — and this is a
            // per-frame read path, so it must not report either.
            let asNumber: Int? = storage.value(forKey: key)
            #expect(asNumber == nil)
            #expect(
                StorageDiagnostics.lastFailure?.key != key,
                "a read fallback is not a failure")
        }
    }

    /// In an exit test: `lastFailure` is the process's latest report, and in
    /// the shared process another suite's report can land between this write
    /// and the read (`StorageFailureTests` makes several).
    @Test("A value that cannot be encoded is reported with its key")
    func encodeFailureIsReported() async {
        await #expect(processExitsWith: .success) {
            Self.withStorage { storage, key in
                // The other half of the asymmetry: a write that cannot happen
                // is data the user expected to keep, so it is worth surfacing.
                storage.setValue(UnencodableSetting(), forKey: key)
                #expect(StorageDiagnostics.lastFailure?.key == key)
                #expect(StorageDiagnostics.lastFailure?.operation == .encode)
            }
        }
    }

    @Test("Removing a key clears it, and removing one that was never set is not an error")
    func removal() {
        Self.withStorage { storage, key in
            storage.setValue(Settings(name: "x", count: 1, enabled: false), forKey: key)
            #expect(storage.value(forKey: key) != Optional<Settings>.none)

            storage.removeValue(forKey: key)
            storage.removeValue(forKey: key)
            let gone: Settings? = storage.value(forKey: key)
            #expect(gone == nil)
            #expect(
                StorageDiagnostics.lastFailure?.key != key,
                "a redundant removal is not a failure")
        }
    }

    @Test("Two suites do not see each other's values")
    func suitesAreSeparate() {
        // What `init(suiteName:)` is for, and the property this file's own
        // isolation rests on.
        Self.withStorage { first, key in
            Self.withStorage { second, _ in
                first.setValue(Settings(name: "first", count: 1, enabled: true), forKey: key)
                let leaked: Settings? = second.value(forKey: key)
                #expect(leaked == nil)
            }
        }
    }
}
