//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StorageFailure.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Storage Failure

/// A persistent-storage operation that did not complete.
///
/// TUIkit's file-backed storage can fail in ways `UserDefaults` effectively
/// cannot: a read-only or missing configuration directory, a full disk, a
/// sandbox that denies the path. Those failures used to be swallowed at the
/// `catch` site, so an app would report "Saved" for a write that never reached
/// the disk and lose the value at the next launch.
///
/// See ``StorageDiagnostics`` for how to observe them.
public struct StorageFailure: @unchecked Sendable, CustomStringConvertible {
    /// What was being attempted.
    public enum Operation: String, Sendable {
        /// Creating the configuration directory that holds the storage file.
        case createDirectory
        /// Reading the storage file at startup.
        case load
        /// Encoding a value for storage.
        case encode
        /// Writing the storage file.
        case save
    }

    /// The operation that failed.
    public let operation: Operation

    /// The `@AppStorage` key involved, or `nil` for whole-file operations.
    public let key: String?

    /// The file or directory path involved, if the failure has one.
    public let path: String?

    /// The error the underlying API raised.
    ///
    /// Not `Sendable` — Foundation's errors are not — which is why the whole
    /// struct is `@unchecked`. It is only ever read, never mutated.
    public let underlying: (any Error)?

    /// Creates a storage failure record.
    public init(
        operation: Operation,
        key: String? = nil,
        path: String? = nil,
        underlying: (any Error)? = nil
    ) {
        self.operation = operation
        self.key = key
        self.path = path
        self.underlying = underlying
    }

    public var description: String {
        var text = "storage \(operation.rawValue) failed"
        if let key { text += " for key \"\(key)\"" }
        if let path { text += " at \(path)" }
        if let underlying { text += ": \(underlying)" }
        return text
    }
}

// MARK: - Storage Diagnostics

/// Where persistent-storage failures go.
///
/// ## Why this is not a `throws` on `@AppStorage`
///
/// ``AppStorage`` matches SwiftUI's signature exactly, and SwiftUI's
/// `wrappedValue` setter is neither `throws` nor `async` — a property wrapper
/// assignment cannot be. Making ours throw would break every call site and stop
/// it being a drop-in. So the failure surfaces *beside* the API rather than
/// through it: ``AppStorage`` stays SwiftUI-shaped, and the reporting lives on
/// the storage layer, which has no SwiftUI counterpart to match.
///
/// ## Observing failures
///
/// Install a handler to react — the natural TUI response is a notification:
///
/// ```swift
/// StorageDiagnostics.onFailure = { failure in
///     Task { @MainActor in
///         NotificationCenter.tui.post(.error("Couldn't save settings: \(failure)"))
///     }
/// }
/// ```
///
/// With no handler installed the failure is still **recorded** rather than
/// dropped: ``lastFailure`` and ``failureCount`` always reflect what happened,
/// so an app can check after a `synchronize()` and a test can assert on it.
///
/// ## What is reported, and what is not
///
/// Reported: directory creation, file loads, encode failures and file writes —
/// every path where a value the user set fails to reach the disk.
///
/// **Not** reported: a *decode* failure when reading a key back. That is the
/// defined fallback path (`@AppStorage` returns its default value), it happens
/// legitimately when a stored value predates a type change, and `value(forKey:)`
/// sits on the per-frame render path — reporting there would fire once per
/// frame for as long as the stale value sat in the file.
///
/// Note that ``AppStorage``'s setter *is* on a hot path too: a slider bound to
/// storage writes once per tick, so a persistent encode failure reports once per
/// tick. Handlers should expect repeats and coalesce.
public enum StorageDiagnostics {
    /// Guards the recorded failure state; storage writes flush on a background
    /// queue, so reports do not all arrive on the main thread.
    private static let state = Lock(initialState: State())

    private struct State: Sendable {
        var last: StorageFailure?
        var count: Int = 0
        var onFailure: (@Sendable (StorageFailure) -> Void)?
    }

    /// Called for every storage failure, on whichever thread raised it.
    ///
    /// Set to `nil` (the default) to rely on ``lastFailure`` alone.
    ///
    /// Behind the same lock as the rest of the state, and not
    /// `nonisolated(unsafe)`, because the two ends of this property are on
    /// different threads BY DESIGN: the app assigns it from the main actor
    /// (installing a handler when a screen appears, clearing it when it goes)
    /// while ``report(_:)`` reads it from the background save queue that
    /// `@AppStorage`'s flush runs on. A closure is a two-word value — context
    /// pointer and function pointer — so an unsynchronised read racing an
    /// unsynchronised write can see one word of each and call a function with
    /// another closure's context.
    public static var onFailure: (@Sendable (StorageFailure) -> Void)? {
        get { state.withLock { $0.onFailure } }
        set { state.withLock { $0.onFailure = newValue } }
    }

    /// The most recent failure, or `nil` if storage has not failed.
    public static var lastFailure: StorageFailure? {
        state.withLock { $0.last }
    }

    /// How many failures have been recorded since the last ``reset()``.
    public static var failureCount: Int {
        state.withLock { $0.count }
    }

    /// Records a failure and forwards it to ``onFailure``.
    ///
    /// Public so a custom ``StorageBackend`` reports through the same channel as
    /// the built-in ones.
    public static func report(_ failure: StorageFailure) {
        // Taken under the lock, called outside it: a handler is app code and may
        // do anything — including touching storage again, which would deadlock
        // on a non-recursive lock. The same snapshot-then-act shape `flushToDisk`
        // uses on the cache.
        let handler = state.withLock { state -> (@Sendable (StorageFailure) -> Void)? in
            state.last = failure
            state.count += 1
            return state.onFailure
        }
        handler?(failure)
    }

    /// Clears ``lastFailure`` and ``failureCount``.
    ///
    /// For an app that has shown and dismissed the error, and for tests that
    /// assert on a specific operation.
    /// The handler is deliberately NOT cleared: it is the app's installation,
    /// not part of the failure record this clears.
    public static func reset() {
        state.withLock {
            $0.last = nil
            $0.count = 0
        }
    }
}
