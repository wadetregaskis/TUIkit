//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppStorage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Storage Backend Protocol

/// Protocol for persistent storage backends.
public protocol StorageBackend: Sendable {
    /// Retrieves a value for the given key.
    func value<T: Codable>(forKey key: String) -> T?

    /// Stores a value for the given key.
    func setValue<T: Codable>(_ value: T, forKey key: String)

    /// Removes the value for the given key.
    func removeValue(forKey key: String)

    /// Synchronizes changes to disk.
    func synchronize()
}

// MARK: - Process Name Sanitization

/// Sanitizes a process name for safe use as a file system path component.
///
/// Removes characters that could cause path traversal or file system issues:
/// - Forward slashes (`/`)
/// - Null bytes (`\0`)
/// - Replaces `..` sequences (path traversal)
///
/// Falls back to `"app"` if the result is empty after sanitization.
///
/// - Parameter name: The raw process name.
/// - Returns: A sanitized string safe for use as a directory name.
func sanitizedProcessName(_ name: String) -> String {
    var sanitized =
        name
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "\0", with: "")
        .replacingOccurrences(of: "..", with: "")
    sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "app" : sanitized
}

// MARK: - Config Directory

/// Returns the app-specific, platform-idiomatic configuration directory.
///
/// Each executable gets its own directory, named after the sanitized process
/// name, in the conventional per-platform location:
/// - **macOS**: `~/Library/Application Support/<appName>`
/// - **Linux / other**: `$XDG_CONFIG_HOME/<appName>`, falling back to
///   `~/.config/<appName>` (XDG Base Directory convention).
///
/// Shared by `@AppStorage`'s file backend (`JSONFileStorage`) and
/// `LocalizationService`, so all of an app's persisted configuration lives in
/// one place rather than scattered across directories.
func appConfigDirectory() -> URL {
    let appName = sanitizedProcessName(ProcessInfo.processInfo.processName)

    // Explicit override — the isolation hook for anything driving a TUIkit
    // app that must not touch the real per-app state (a PTY test harness,
    // CI). It matters most on Apple platforms, where BOTH the default
    // storage (UserDefaults) and the idiomatic directory below resolve
    // through the real user home and ignore a `$HOME` override — a
    // "sandboxed" run would otherwise read and write the developer's own
    // preferences. Setting it also switches `@AppStorage` to file-backed
    // storage under this directory (see ``StorageDefaults/backend``).
    if let override = ProcessInfo.processInfo.environment["TUIKIT_CONFIG_DIR"],
        !override.isEmpty
    {
        return URL(fileURLWithPath: override).appendingPathComponent(appName)
    }

    #if os(macOS)
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appName)
    #else
        if let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdgConfig.isEmpty {
            return URL(fileURLWithPath: xdgConfig)
                .appendingPathComponent(appName)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent(appName)
    #endif
}

// MARK: - JSON File Storage

/// A storage backend that persists data to a JSON file.
///
/// This is the default storage backend for TUIkit apps. Data is stored in the
/// app-specific configuration directory (see `appConfigDirectory()`):
/// `~/Library/Application Support/[appName]/settings.json` on macOS, or
/// `$XDG_CONFIG_HOME/[appName]/settings.json` (else `~/.config/...`) elsewhere.
public final class JSONFileStorage: StorageBackend, @unchecked Sendable {
    /// The file URL for the storage file.
    private let fileURL: URL

    /// In-memory cache of stored values.
    private var cache: [String: Data] = [:]

    /// The keys THIS instance has written or removed, guarded by `lock`.
    ///
    /// A flush merges these — and only these — over what is currently on
    /// disk. Snapshotting the whole cache instead rewrote the entire file
    /// from a copy loaded once at startup, so two instances of one app (two
    /// terminal tabs) silently clobbered each other's saved settings: the
    /// second to write anything erased everything the first had saved since
    /// launch. Merging per key narrows a lost update to a key both actually
    /// contested.
    private var dirtyKeys: Set<String> = []

    /// Lock for thread safety. Guards `cache` and `savePending` — and nothing
    /// slow: disk writes snapshot under the lock and write outside it.
    private let lock = NSLock()

    /// Serialises every disk write. A dedicated serial queue rather than
    /// `Task.detached` for three reasons: writes land in submission order (two
    /// detached saves could race and let an older snapshot win the file);
    /// `synchronize()` can flush *behind* any queued save with a plain
    /// `queue.sync`; and a slow disk never occupies a width-limited
    /// cooperative-pool thread.
    ///
    /// wasip1 has no threads, so it has no queue either, and the two properties
    /// the queue was buying — ordering and coalescing — are already the
    /// property of a single thread that does the write where it stands. The
    /// arms below say so at each of the two hops rather than pretending to a
    /// concurrency this platform does not have.
    #if !canImport(WASILibc)
        private let saveQueue = DispatchQueue(label: "TUIkit.JSONFileStorage.save", qos: .utility)
    #endif

    /// Whether a save is already queued. Writes arrive in bursts (a slider
    /// bound to storage emits one per tick); one queued flush snapshots
    /// whatever the cache holds when it runs, so the burst costs one disk
    /// write, not one per tick.
    private var savePending = false

    /// Creates a JSON file storage with default location.
    public init() {
        let configDir = appConfigDirectory()

        // Create directory if needed. A failure here is not fatal — the write
        // may still succeed if the directory already exists — but it is the
        // usual first sign that the config path is unwritable, so it is
        // reported rather than dropped.
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        } catch {
            StorageDiagnostics.report(
                StorageFailure(
                    operation: .createDirectory, path: configDir.path, underlying: error))
        }

        self.fileURL = configDir.appendingPathComponent("settings.json")
        loadFromDisk()
    }

    /// Creates a JSON file storage with a custom file URL.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        loadFromDisk()
    }
}

// MARK: - Public API

extension JSONFileStorage {
    /// The value stored for `key`, decoded from the in-memory cache, or `nil`
    /// when absent or undecodable.
    ///
    /// Served from the cache the file was loaded into at init, never from
    /// disk, because this is read on the render path. A decode failure is
    /// silent for the reason the whole family shares: falling back to the
    /// caller's default is ``AppStorage``'s defined behaviour, not an error.
    public func value<T: Codable>(forKey key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }

        guard let data = cache[key] else { return nil }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Deliberately NOT reported: falling back to the default value is
            // this API's defined behaviour, it happens legitimately whenever a
            // stored value predates a type change, and this sits on the
            // per-frame read path — reporting would fire every frame for as
            // long as the value stayed in the file. See ``StorageDiagnostics``.
            return nil
        }
    }

    /// Stores `value` for `key` and schedules a write.
    ///
    /// The cache is updated synchronously — a read straight after a write sees
    /// the new value — while the file is written on a serial queue, so a
    /// per-keystroke setting does not put file I/O in the frame. Encode
    /// failures report through ``StorageDiagnostics``; see
    /// ``synchronize()`` for the flush that makes a pending write durable.
    public func setValue<T: Codable>(_ value: T, forKey key: String) {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            // Reported before the lock is taken at all, deliberately, rather
            // than from a `catch` inside the critical section: ``report`` runs
            // the app's handler synchronously on this thread, and `lock` is a
            // plain `NSLock`. A handler that touches this backend — even just
            // `value(forKey:)`, the coalescing ``StorageDiagnostics`` invites —
            // re-entered it and hung the app for good. `flushToDisk` reports
            // after its own unlock for the same reason.
            StorageDiagnostics.report(
                StorageFailure(operation: .encode, key: key, path: fileURL.path, underlying: error))
            return
        }

        lock.lock()
        defer { lock.unlock() }

        cache[key] = data
        dirtyKeys.insert(key)
        saveToDiskAsync()
    }

    /// Removes any value stored for `key`, scheduling the write as
    /// ``setValue(_:forKey:)`` does.
    public func removeValue(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: key)
        dirtyKeys.insert(key)
        saveToDiskAsync()
    }

    /// Blocks until everything written so far is on disk.
    ///
    /// Call before exiting: writes are otherwise queued, and a terminal app
    /// can be killed by a signal between frames.
    public func synchronize() {
        // A plain sync hop onto the serial save queue: any already-queued
        // asynchronous save runs first, then this flush writes whatever the
        // cache holds now — so "synchronize then exit" cannot lose a value.
        #if canImport(WASILibc)
            flushToDisk()
        #else
            saveQueue.sync {
                self.flushToDisk()
            }
        #endif
    }
}

// MARK: - Private Helpers

extension JSONFileStorage {
    fileprivate func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            if let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                // Convert base64 strings back to Data
                for (key, base64String) in decoded {
                    if let valueData = Data(base64Encoded: base64String) {
                        cache[key] = valueData
                    }
                }
            }
        } catch {
            // Starting fresh is the right recovery, but the app has just lost
            // every stored setting and should be able to say so.
            StorageDiagnostics.report(
                StorageFailure(operation: .load, path: fileURL.path, underlying: error))
        }
    }

    /// Queues one flush (caller holds `lock`). Bursts coalesce: if a flush is
    /// already queued it will snapshot this write too, so a slider dragging a
    /// bound value costs one disk write per drain, not one per tick.
    fileprivate func saveToDiskAsync() {
        guard !savePending else { return }
        savePending = true
        #if canImport(WASILibc)
            // Inline, and therefore synchronous: the burst-coalescing above still
            // holds (`savePending` is cleared by the flush), and a write that
            // cannot be deferred to another thread is better done now than not
            // at all.
            flushToDisk()
        #else
            saveQueue.async { [weak self] in
                self?.flushToDisk()
            }
        #endif
    }

    /// Runs only on `saveQueue`. Snapshots the cache under the lock, then
    /// serialises and writes OUTSIDE it — the old detached save iterated
    /// `cache` with no lock at all, racing `setValue`'s mutation on the main
    /// thread (a CoW dictionary read overlapping a mutation of the same
    /// reference).
    fileprivate func flushToDisk() {
        lock.lock()
        savePending = false
        let snapshot = cache
        let dirty = dirtyKeys
        lock.unlock()

        // Start from what is on disk NOW — another instance may have written
        // since this one loaded — and overlay only this instance's own
        // changes. See `dirtyKeys`. A fresh read each flush rather than a
        // kept file handle: flushes are rare (bursts coalesce), and the read
        // is what makes a sibling's keys survive.
        var serializable: [String: String] = [:]
        if let data = try? Data(contentsOf: fileURL),
            let onDisk = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        {
            serializable = onDisk
        }
        for key in dirty {
            serializable[key] = snapshot[key]?.base64EncodedString()
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: serializable, options: .prettyPrinted)
            // Atomically where the platform can: a half-written settings file
            // is worse than a stale one. WASI's Foundation refuses the option
            // outright — atomic writing goes through a temporary file and a
            // rename, and wasip1 has no temporary directory to make one in — so
            // there the write is direct, and a host that cares about the
            // difference has to provide durability of its own.
            #if canImport(WASILibc)
                try data.write(to: fileURL)
            #else
                try data.write(to: fileURL, options: .atomic)
            #endif
        } catch {
            // The write that just failed is the whole point of the API: without
            // this report the app shows a saved setting that will not survive
            // the next launch.
            StorageDiagnostics.report(
                StorageFailure(operation: .save, path: fileURL.path, underlying: error))
        }
    }
}

// MARK: - Storage Defaults

/// Provides the default storage backend for ``AppStorage``.
///
/// Override the backend before creating any `@AppStorage` properties
/// if you want to use a custom storage backend.
///
/// ```swift
/// StorageDefaults.backend = MyCustomBackend()
/// ```
public enum StorageDefaults {
    /// The default storage backend used by ``AppStorage``.
    ///
    /// Matches SwiftUI's `@AppStorage`, which is backed by `UserDefaults`:
    /// - **Apple platforms**: ``UserDefaultsStorage`` over `UserDefaults.standard`,
    ///   so values land in the system preferences domain —
    ///   `~/Library/Preferences/<bundle-identifier>.plist` when the app is bundled
    ///   (the identifier comes from its `Info.plist`), else
    ///   `~/Library/Preferences/<executable-name>.plist` for a plain CLI binary.
    /// - **Linux / other**: ``JSONFileStorage``, since Foundation's `UserDefaults`
    ///   does not reliably persist there — written under `appConfigDirectory()`
    ///   (`$XDG_CONFIG_HOME/<app>/settings.json`, else `~/.config/<app>/…`).
    ///
    /// Setting `TUIKIT_CONFIG_DIR` in the environment overrides both: storage
    /// becomes file-backed under that directory on every platform. That is the
    /// isolation hook for test harnesses — on Apple platforms `UserDefaults`
    /// ignores a `$HOME` override, so without it a "sandboxed" run reads and
    /// writes the developer's real preferences domain.
    ///
    /// Override before creating any `@AppStorage` properties to use a custom backend.
    nonisolated(unsafe) public static var backend: StorageBackend = {
        if let override = ProcessInfo.processInfo.environment["TUIKIT_CONFIG_DIR"],
            !override.isEmpty
        {
            // JSONFileStorage roots itself at appConfigDirectory(), which
            // honours the same override.
            return JSONFileStorage()
        }
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            return UserDefaultsStorage()
        #else
            return JSONFileStorage()
        #endif
    }()
}

// MARK: - AppStorage Property Wrapper

/// A property wrapper that reads and writes to persistent storage.
///
/// Use `@AppStorage` to persist simple values across app launches.
/// Values must conform to `Codable`.
///
/// # Example
///
/// ```swift
/// struct SettingsView: View {
///     @AppStorage("username") var username = "Guest"
///     @AppStorage("darkMode") var darkMode = false
///     @AppStorage("fontSize") var fontSize = 14
///
///     var body: some View {
///         VStack {
///             Text("User: \(username)")
///             Text("Dark Mode: \(darkMode ? "On" : "Off")")
///         }
///     }
/// }
/// ```
///
/// # Supported Types
///
/// Any type that conforms to `Codable`:
/// - String, Int, Double, Bool
/// - Date, Data, URL
/// - Arrays and Dictionaries of Codable types
/// - Custom Codable structs and enums
@propertyWrapper
public struct AppStorage<Value: Codable>: @unchecked Sendable {
    /// The key used for storage.
    private let key: String

    /// The default value if no stored value exists.
    private let defaultValue: Value

    /// The storage backend to use.
    private let storage: StorageBackend

    /// Creates an AppStorage with the default storage backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value.
    ///   - key: The key to use for storage.
    public init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
        self.storage = StorageDefaults.backend
    }

    /// Creates an AppStorage with a custom storage backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value.
    ///   - key: The key to use for storage.
    ///   - storage: The storage backend to use.
    public init(wrappedValue: Value, _ key: String, store storage: StorageBackend) {
        self.key = key
        self.defaultValue = wrappedValue
        self.storage = storage
    }

    /// The current value.
    public var wrappedValue: Value {
        get {
            storage.value(forKey: key) ?? defaultValue
        }
        nonmutating set {
            storage.setValue(newValue, forKey: key)
            AppState.shared.setNeedsRender()
        }
    }

    /// A binding to the stored value.
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}
