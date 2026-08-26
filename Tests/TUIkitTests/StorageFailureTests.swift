//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StorageFailureTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// A value whose encoding always fails, for exercising the encode path.
private struct Unencodable: Codable {
    struct Nope: Error {}

    func encode(to encoder: any Encoder) throws {
        throw Nope()
    }

    init() {}
    init(from decoder: any Decoder) throws { self.init() }
}

/// `@AppStorage`'s file backend used to drop every failure at its `catch`, so an
/// app reported "Saved" for a write that never reached the disk. These pin each
/// reporting path — and each one fails on the pre-fix code, where nothing at all
/// arrives at the handler.
///
/// Serialized because ``StorageDiagnostics`` is a process-wide channel (the same
/// shape as `StorageDefaults.backend` beside it). `.serialized` orders this
/// suite internally but not against the others, which run in parallel and now
/// also report — so every assertion below is scoped to *this* test's own
/// unique temporary directory or key, never to the global counters. A shared
/// mutable default is exactly how the render-cache flakes happened.
@Suite("Storage failure reporting", .serialized)
struct StorageFailureTests {

    /// Runs `body` against a private temporary directory with a capturing
    /// handler installed, restoring whatever was there before.
    ///
    /// Returns only the failures raised *under that directory*: another suite's
    /// storage work reaches this handler too, and counting it would make these
    /// assertions depend on unrelated tests.
    private func capturingFailures(_ body: (URL) throws -> Void) rethrows -> [StorageFailure] {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tuikit-storage-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let box = Lock(initialState: [StorageFailure]())
        let previous = StorageDiagnostics.onFailure
        StorageDiagnostics.onFailure = { failure in
            guard failure.path?.hasPrefix(root.path) == true else { return }
            box.withLock { $0.append(failure) }
        }
        defer { StorageDiagnostics.onFailure = previous }

        try body(root)
        return box.withLock { $0 }
    }

    @Test("A write to an unwritable path is reported, not dropped")
    func unwritablePathReportsSave() {
        let failures = capturingFailures { root in
            // A *file* where the storage file's parent directory should be, so
            // every write below it fails with ENOTDIR. More portable than
            // relying on a permission mode, which root ignores.
            let blocker = root.appendingPathComponent("blocked")
            FileManager.default.createFile(atPath: blocker.path, contents: Data())

            let storage = JSONFileStorage(fileURL: blocker.appendingPathComponent("settings.json"))
            storage.setValue(42, forKey: "answer")
            storage.synchronize()
        }

        #expect(failures.contains { $0.operation == .save })
        #expect(failures.allSatisfy { $0.path?.contains("blocked") == true })
    }

    @Test("A corrupt settings file is reported at load")
    func corruptFileReportsLoad() {
        let failures = capturingFailures { root in
            let file = root.appendingPathComponent("settings.json")
            try? Data("this is not JSON".utf8).write(to: file)
            _ = JSONFileStorage(fileURL: file)
        }

        #expect(failures.count == 1)
        #expect(failures.first?.operation == .load)
    }

    @Test("A value that cannot be encoded is reported with its key")
    func encodeFailureCarriesKey() {
        let failures = capturingFailures { root in
            let storage = JSONFileStorage(fileURL: root.appendingPathComponent("settings.json"))
            storage.setValue(Unencodable(), forKey: "doomed")
        }

        #expect(failures.count == 1)
        #expect(failures.first?.operation == .encode)
        #expect(failures.first?.key == "doomed")
    }

    @Test("A failure is recorded even with no handler installed")
    func failureRecordedWithoutHandler() {
        let previous = StorageDiagnostics.onFailure
        StorageDiagnostics.onFailure = nil
        defer { StorageDiagnostics.onFailure = previous }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tuikit-storage-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A key no other suite can produce, so `lastFailure` is identifiable
        // even if a parallel suite reports in the same instant.
        let key = "doomed-\(UUID().uuidString)"
        let storage = JSONFileStorage(fileURL: root.appendingPathComponent("settings.json"))
        storage.setValue(Unencodable(), forKey: key)

        // The whole point of retaining it: silence at the handler is not the
        // same as losing the failure.
        #expect(StorageDiagnostics.lastFailure?.key == key)
        #expect(StorageDiagnostics.lastFailure?.operation == .encode)

        // And `reset()` clears it. Asserted as "no longer mine" rather than
        // "nil", which a concurrent suite's report would falsify.
        StorageDiagnostics.reset()
        #expect(StorageDiagnostics.lastFailure?.key != key)
    }

    @Test("Reading back an undecodable value stays silent")
    func decodeOnReadIsNotReported() {
        let failures = capturingFailures { root in
            let file = root.appendingPathComponent("settings.json")
            let storage = JSONFileStorage(fileURL: file)
            storage.setValue("a string", forKey: "mixed")

            // Read it back as the wrong type: `@AppStorage` falls back to its
            // default, which is defined behaviour, on a per-frame path.
            let read: Int? = storage.value(forKey: "mixed")
            #expect(read == nil)
        }

        #expect(failures.isEmpty)
    }
}
