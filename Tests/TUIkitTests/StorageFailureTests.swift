//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StorageFailureTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch
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

/// An error whose printed form is fixed, so the assertions on
/// ``StorageFailure/description`` can name the exact string a user would read.
private struct Boom: Error, CustomStringConvertible {
    var description: String { "boom" }
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

    @Test("A failure handler may localize its own message")
    func handlerMayLocalize() {
        let unwritable = LocalizationService(configDirectoryPath: "/dev/null/tuikit-unwritable")
        let observed = Lock(initialState: String?.none)
        let previous = StorageDiagnostics.onFailure
        StorageDiagnostics.onFailure = { _ in
            observed.withLock { $0 = unwritable.string(for: LocalizationKey.Button.cancel) }
        }
        defer { StorageDiagnostics.onFailure = previous }
        // The report is synchronous, from inside the language switch. It used
        // to run under the service's lock — which is not recursive — so a
        // handler that localized deadlocked the switch.
        unwritable.setLanguage(.german)
        #expect(observed.withLock { $0 } == "Abbrechen")
    }

    @Test("A failure handler may read the backend that reported")
    func handlerMayReadBackend() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tuikit-storage-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = JSONFileStorage(fileURL: root.appendingPathComponent("settings.json"))
        // Scoped to this test's own key: the parallel suites report here too.
        let key = "doomed-\(UUID().uuidString)"

        let previous = StorageDiagnostics.onFailure
        StorageDiagnostics.onFailure = { failure in
            guard failure.key == key else { return }
            // The coalescing shape ``StorageDiagnostics`` invites: consult what
            // was reported last before showing the same failure again.
            _ = storage.value(forKey: "lastStorageError") as String?
        }
        defer { StorageDiagnostics.onFailure = previous }

        // Not a plain call, and not a `Task`: `setValue` used to report the
        // encode failure while still holding its lock, so the handler's read
        // re-entered a non-recursive `NSLock` and never came back. On the test
        // thread that hangs the whole suite instead of failing this one test,
        // and a wedged cooperative-pool thread is one the suite never gets back.
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            storage.setValue(Unencodable(), forKey: key)
            done.signal()
        }

        #expect(
            done.wait(timeout: .now() + 2) == .success,
            "setValue reported the encode failure while still holding its lock")
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

    // MARK: - The reported string

    // `description` is the entire user-facing output of this subsystem — what
    // an app prints when `@AppStorage` cannot write, and the one report a user
    // can send back. Every branch of it was unexecuted: the existing cases all
    // read `lastFailure`'s FIELDS and never its rendering, so dropping the
    // `key` clause (or renaming `operation.rawValue`) would leave "storage
    // failed" with no indication of which key or which file, and nothing would
    // have failed.

    @Test("The description names the operation, and only what it has")
    func descriptionWithNothingElse() {
        #expect(StorageFailure(operation: .save).description == "storage save failed")
        #expect(StorageFailure(operation: .load).description == "storage load failed")
        #expect(StorageFailure(operation: .encode).description == "storage encode failed")
        #expect(
            StorageFailure(operation: .createDirectory).description
                == "storage createDirectory failed")
    }

    @Test("Each optional field adds its own clause")
    func descriptionClauses() {
        #expect(
            StorageFailure(operation: .encode, key: "answer").description
                == #"storage encode failed for key "answer""#)
        #expect(
            StorageFailure(operation: .load, path: "/tmp/settings.json").description
                == "storage load failed at /tmp/settings.json")
        #expect(
            StorageFailure(operation: .save, underlying: Boom()).description
                == "storage save failed: boom")
    }

    @Test("All three clauses appear together, in that order")
    func descriptionWithEverything() {
        let failure = StorageFailure(
            operation: .save, key: "answer", path: "/tmp/settings.json", underlying: Boom())

        #expect(
            failure.description
                == #"storage save failed for key "answer" at /tmp/settings.json: boom"#)
        // Through `CustomStringConvertible`, which is how the doc comment's own
        // example reaches it: `.error("Couldn't save settings: \(failure)")`.
        #expect("\(failure)" == failure.description)
    }

    // MARK: - The counter

    @Test("failureCount rises with every report and reset() clears it")
    func failureCountTracksReports() {
        // The counter is process-wide and other suites report into it while
        // this one runs (`.serialized` orders this suite internally, not
        // against the others). So the assertions are on the DELTA, and only in
        // the direction nothing else can move: a report only ever raises the
        // count, so anything concurrent can only push it further past the
        // bound. `report(_:)` is used directly rather than provoking a real
        // failure, which keeps the window between the reads as small as it can
        // be.
        let before = StorageDiagnostics.failureCount
        StorageDiagnostics.report(StorageFailure(operation: .save, key: "counted-1"))
        StorageDiagnostics.report(StorageFailure(operation: .load, path: "/counted-2"))

        #expect(StorageDiagnostics.failureCount >= before + 2)
        #expect(StorageDiagnostics.lastFailure?.path == "/counted-2", "the latest wins")

        StorageDiagnostics.reset()
        #expect(
            StorageDiagnostics.failureCount < before + 2,
            "reset() left the count where it was")
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
