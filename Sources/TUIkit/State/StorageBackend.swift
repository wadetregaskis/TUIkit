//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StorageBackend.swift
//
//  Where `@AppStorage` and `@SceneStorage` keep their values, and how a view
//  that read one learns that it changed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation

// MARK: - Storage Backend Protocol

/// A store of persistent values, keyed by string: what ``AppStorage`` and
/// ``SceneStorage`` read and write.
///
/// A store implements four primitives, and is used through three methods it
/// gets for free: ``value(forKey:)``, ``setValue(_:forKey:)`` and
/// ``removeValue(forKey:)``. Those do the observation, so a store cannot
/// forget it and a write made straight through a store — not through a
/// property wrapper — reaches the views that read the key all the same.
///
/// Each key a store has been asked about has a ``StoredKey``: the key as
/// Observation sees it. A view that read the key is invalidated when it
/// changes, and nothing else is, so a write costs the views that showed the
/// value and no more. Hand back the same `StoredKey` for a key every time —
/// readers registered on it hear only of changes announced through it — and
/// keep it beside the key's value, so a read finds both in one lookup. A read
/// is on the render path: every body that shows a stored value pays it each
/// time it is evaluated.
///
/// ```swift
/// final class MemoryStorage: StorageBackend, @unchecked Sendable {
///     private let lock = NSLock()
///     private var entries: [String: (data: Data?, key: StoredKey)] = [:]
///
///     func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey) {
///         lock.withLock {
///             let entry = entries[key] ?? (nil, StoredKey())
///             entries[key] = entry
///             return (entry.data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }, entry.key)
///         }
///     }
///
///     func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey {
///         let data = try? JSONEncoder().encode(value)
///         return lock.withLock {
///             let stored = entries[key]?.key ?? StoredKey()
///             entries[key] = (data, stored)
///             return stored
///         }
///     }
///
///     func remove(forKey key: String) -> StoredKey? {
///         lock.withLock {
///             entries[key]?.data = nil
///             return entries[key]?.key
///         }
///     }
///
///     func synchronize() {}
/// }
/// ```
///
/// A store that learns of a change some other way — another process wrote
/// the file, the system reloaded its defaults — calls ``StoredKey/didChange()``
/// on the key's `StoredKey` itself.
public protocol StorageBackend: Sendable {
    /// The value stored for `key` decoded as `T`, or `nil` when there is none
    /// or it does not decode as `T`, together with the key's ``StoredKey``.
    ///
    /// Called on every read. A value that does not decode is not an error:
    /// the reader falls back to its default, which is ``AppStorage``'s defined
    /// behaviour when a stored value predates a change of type.
    func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey)

    /// Stores `value` for `key`, and returns the key's ``StoredKey``, through
    /// which the change is announced once this returns.
    func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey

    /// Removes any value stored for `key`, and returns the key's ``StoredKey``
    /// — `nil` when the store has never been asked about the key, since then
    /// no reader can be waiting on it.
    func remove(forKey key: String) -> StoredKey?

    /// Makes everything written so far durable.
    func synchronize()
}

extension StorageBackend {
    /// The value stored for `key`, or `nil` when there is none or it does not
    /// decode as `T` — noted as read, so a view whose body read it, or a kept
    /// result a control read it under, is invalidated when it changes.
    public func value<T: Codable>(forKey key: String) -> T? {
        let (value, stored) = entry(forKey: key, as: T.self)
        stored.didRead()
        return value
    }

    /// Stores `value` for `key`, and tells every view that read the key.
    public func setValue<T: Codable>(_ value: T, forKey key: String) {
        store(value, forKey: key).didChange()
    }

    /// Removes any value stored for `key`, and tells every view that read it.
    public func removeValue(forKey key: String) {
        remove(forKey: key)?.didChange()
    }
}

// MARK: - Stored Key

/// One key of a ``StorageBackend`` as Observation sees it: reading the key is
/// an access, changing it a mutation.
///
/// A store makes one per key and hands it back with every read and write (see
/// ``StorageBackend``). A view that read the key — in its body, or through a
/// control's `Binding` beneath a result the render cache keeps — is invalidated
/// at its own identity when the key changes, as it is when an `@Observable`
/// property it read changes. Nothing that did not read the key is touched.
///
/// That replaced a clear of the WHOLE render cache on every write: a stored
/// value is in no memo's key and a write carries no view identity, so dropping
/// everything was the only way to be sure, and every write — a keystroke into
/// a stored field, a `Slider` bound to `$storage` on every drag tick — paid a
/// cold frame for it.
public final class StoredKey: Observable, Sendable {
    private let registrar = ObservationRegistrar()

    /// The property a key's readers are registered on. Never read for a
    /// value: it exists so the registrar has a path to register them at.
    private var changes: Int { 0 }

    /// ``changes``'s key path, made once: a key path with no arguments is a
    /// constant, where one built per read (a subscript on the key, say) is an
    /// allocation on every read — 339 ns against 17, measured.
    private static let changesPath = \StoredKey.changes

    /// A key no reader has read yet.
    public init() {}

    /// Notes that the key was read, for the observation scope in force.
    func didRead() {
        registrar.access(self, keyPath: Self.changesPath)
    }

    /// Tells every view that read the key that it changed, and asks for a
    /// frame.
    ///
    /// ``StorageBackend/setValue(_:forKey:)`` and
    /// ``StorageBackend/removeValue(forKey:)`` call this; a store calls it
    /// itself for a change it learns of some other way. The frame is asked
    /// for whether or not any reader was observed: a control drawn every frame
    /// outside any kept result reads the key unobserved, and shows the new
    /// value only when a frame is drawn.
    public func didChange() {
        registrar.withMutation(of: self, keyPath: Self.changesPath) {}
        AppState.shared.setNeedsRender()
    }
}

// MARK: - Built-in Entries

/// One key of a built-in store: the bytes that are persisted, the value they
/// last decoded to, and the key's ``StoredKey``.
///
/// The decoded value is what makes a read cheap. Reading a stored value used
/// to decode it from JSON on every call — 666 ns against 51 for the kept value
/// (release, measured) — and a read is on the render path. It is served only
/// as the very type it was decoded or stored as: any other type decodes the
/// bytes afresh, as a read always did. A class instance is never kept, since
/// every read handing out one shared instance would let a mutation of one
/// copy change the next read; each read decodes its own, as before.
///
/// Guarded by its store's lock: a class so that one lookup finds it and the
/// read updates it in place.
final class StoredEntry {
    /// The persisted bytes, or `nil` when nothing is stored for the key.
    var data: Data?

    /// The last value `data` decoded to, or was stored as, and its type.
    private var decoded: (value: Any, type: ObjectIdentifier)?

    /// The key as Observation sees it.
    let key = StoredKey()

    init(data: Data? = nil) {
        self.data = data
    }

    /// The stored value as `T`, from the kept value when it is a `T`, else
    /// decoded from the bytes and kept.
    func value<T: Codable>(as type: T.Type) -> T? {
        // The very type, not merely one the kept value casts to: an `as?` alone
        // would also answer for a type a fresh decode of the bytes might not.
        if let decoded, decoded.type == ObjectIdentifier(T.self), let value = decoded.value as? T {
            return value
        }
        guard let data, let value = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        keep(value)
        return value
    }

    /// Records a new value and the bytes it was encoded to.
    func set<T: Codable>(_ value: T, encoded data: Data) {
        self.data = data
        decoded = nil
        keep(value)
    }

    /// Takes `data` as the bytes now stored, keeping the decoded value only if
    /// they are the bytes it came from: for a store whose bytes can change
    /// under it (`UserDefaults`, which another process may write).
    func reload(_ data: Data?) {
        guard data != self.data else { return }
        self.data = data
        decoded = nil
    }

    /// Records that nothing is stored for the key.
    func clear() {
        data = nil
        decoded = nil
    }

    private func keep<T>(_ value: T) {
        guard !(T.self is AnyObject.Type) else { return }
        decoded = (value, ObjectIdentifier(T.self))
    }
}
