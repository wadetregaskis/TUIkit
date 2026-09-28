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
    /// what makes the diagnostics assertions below safe — ``StorageDiagnostics``
    /// is a process-wide channel that other suites report into in parallel, so
    /// every claim here is "this key's failure", never a global count.
    private func withStorage(_ body: (UserDefaultsStorage, String) -> Void) {
        let suite = "tuikit.tests.\(UUID().uuidString)"
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
            // Removing the domain empties it, but the preferences daemon leaves
            // the suite's file behind — empty, and one per test run: an old
            // development machine had collected 2,031 of them. Measured: once
            // the removal is flushed, deleting the file is final.
            CFPreferencesAppSynchronize(suite as CFString)
            try? FileManager.default.removeItem(
                at: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences/\(suite).plist"))
            #endif
        }
        body(storage, key)
    }

    @Test("A Codable value round-trips through the backend")
    func roundTrip() {
        withStorage { storage, key in
            let value = Settings(name: "hello", count: 3, enabled: true)
            storage.setValue(value, forKey: key)
            #expect(storage.value(forKey: key) == Optional(value))
            storage.synchronize()
            #expect(storage.value(forKey: key) == Optional(value), "and survives a flush")
        }
    }

    @Test("An absent key reads as nil")
    func absentKeyIsNil() {
        withStorage { storage, key in
            let absent: Settings? = storage.value(forKey: key)
            #expect(absent == nil)
        }
    }

    @Test("A value stored under one type reads back as nil under another, silently")
    func decodeFailureIsSilentAndFallsBack() {
        withStorage { storage, key in
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

    @Test("A value that cannot be encoded is reported with its key")
    func encodeFailureIsReported() {
        withStorage { storage, key in
            // The other half of the asymmetry: a write that cannot happen is
            // data the user expected to keep, so it is worth surfacing.
            storage.setValue(UnencodableSetting(), forKey: key)
            #expect(StorageDiagnostics.lastFailure?.key == key)
            #expect(StorageDiagnostics.lastFailure?.operation == .encode)
        }
    }

    @Test("Removing a key clears it, and removing one that was never set is not an error")
    func removal() {
        withStorage { storage, key in
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
        withStorage { first, key in
            withStorage { second, _ in
                first.setValue(Settings(name: "first", count: 1, enabled: true), forKey: key)
                let leaked: Settings? = second.value(forKey: key)
                #expect(leaked == nil)
            }
        }
    }
}
