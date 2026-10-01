//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StorageKeyObservation.swift
//
//  Which stored keys a view read, so a write reaches exactly those views.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation

/// The stored keys `@AppStorage` and `@SceneStorage` read and write, as
/// Observation sees them: a read is an access to the key, a write a mutation
/// of it.
///
/// A write used to clear the WHOLE render cache. The render memo keys a kept
/// subtree on identity, view value and proposal, and a stored value is in none
/// of the three, so something had to drop what was drawn with the old value —
/// and a store write carries no view identity to walk from. So every buffer and
/// size went, on every write: a keystroke into a stored field, a `Slider`
/// bound to `$storage` on every drag tick, and in a test process any other
/// test's app that drew next (the clear was a flag the next frame took,
/// whichever app drew it).
///
/// Read through here, a stored value is observed like an `@Observable`
/// property: a body that reads it is invalidated at its own identity, and a
/// control that reads it through its `Binding` is caught by the kept result
/// around it (`observingKeptResult`). What read nothing keeps its buffer.
///
/// One registrar for every store, keyed by the key actually written (a scene's
/// keys carry its `scene.` namespace). The stores themselves are process-wide
/// — ``StorageDefaults/backend`` is — and a write needs no store in hand to
/// reach its readers. Two stores holding the same key name each invalidate
/// the other's readers, which costs a redraw and never serves a stale one.
final class StorageKeyObservation: Observable, Sendable {
    /// Every `@AppStorage` and `@SceneStorage` in the process.
    static let stored = StorageKeyObservation()

    private let registrar = ObservationRegistrar()

    /// The key path a key is observed at. Never read for a value: it exists so
    /// each key has a path of its own for the registrar to tell apart.
    subscript(_ key: String) -> Int { 0 }

    /// Notes that `key` was read, for the observation scope in force.
    func access(_ key: String) {
        registrar.access(self, keyPath: \.[key])
    }

    /// Tells every scope that read `key` that it changed.
    func changed(_ key: String) {
        registrar.withMutation(of: self, keyPath: \.[key]) {}
    }
}
