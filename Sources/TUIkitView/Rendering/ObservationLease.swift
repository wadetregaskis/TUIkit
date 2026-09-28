//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservationLease.swift
//
//  How an observation scope is cancelled, and what keeps one alive.
//
//  A scope `withObservationTracking` arms is freed only when a property it
//  read is written (or every object it read from is deinitialized). So a body
//  evaluated every frame that reads a property nobody writes adds a
//  registration every frame, for good: about 1.2 KB each, and the first write
//  runs all of them on the writer's thread. Swift's Observation has no public
//  cancel — the one it declares is `@_spi(SwiftUI)`, and nothing hands back a
//  tracking before its scope fires — but a scope that ALSO read a property of
//  ours is fired, and so freed from every registrar it read, by writing that
//  property: the SENTINEL.
//
//  When a scope may be cancelled is not decided here. A lease belongs to one
//  computation whose result may be kept, and it retires — cancelling every
//  scope armed under it — when the last kept result that embeds that
//  computation lets go of it.
//
//  The facts this rests on are Observation's, not TUIkit's, and are pinned by
//  `ObservationLeaseFactTests` on every CI lane: writing a sentinel cancels
//  every scope that read it; releasing one unwritten cancels nothing; a
//  retirement racing a write on another thread can run a registration's
//  `onChange` twice, so the closure must be idempotent.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkitCore

// MARK: - The sentinel

/// A property every scope armed under one lease also reads, so that writing it
/// fires — and so frees — all of them at once.
///
/// Written only to retire, and marked retired first: a scope whose `onChange`
/// finds its sentinel retired was cancelled, not changed, and reports nothing.
///
/// A hand-written `Observable` rather than an `@Observable` class: one key path,
/// no stored value, and the registrar's own `willSet`/`didSet` are the write.
package final class ScopeSentinel: Observable, Sendable {
    private let registrar = ObservationRegistrar()
    private let retired = Lock(initialState: false)

    package init() {}

    /// The key path a scope reads. Its value is never looked at.
    package var token: Int { 0 }

    /// Whether this sentinel has retired its scopes. Read from any thread: a
    /// scope's `onChange` runs on the thread of the write that fires it.
    package var isRetired: Bool { retired.withLock { $0 } }

    /// Reads the sentinel inside the scope being armed.
    @inline(__always)
    package func touch() {
        registrar.access(self, keyPath: \.token)
    }

    /// Cancels every scope that read this sentinel: marks it retired, then
    /// writes it, which runs each scope's `onChange` — finding it retired, each
    /// returns — and removes each from every registrar it read.
    package func retire() {
        retired.withLock { $0 = true }
        registrar.willSet(self, keyPath: \.token)
        registrar.didSet(self, keyPath: \.token)
    }
}

// MARK: - The lease

/// What keeps the scopes armed under it alive, and cancels them when it goes.
///
/// A lease belongs to one computation whose result may be kept — a memo's
/// buffer, a size kept across frames, a container's kept record, or the frame
/// on screen. Every scope armed while the computation runs reads its sentinel.
/// The kept result holds the lease; so does every computation that used the
/// kept result, served or computed (``hold(_:)``), so the lease lives exactly
/// as long as something kept embeds what it guards. When the last holder lets
/// go, `deinit` retires the sentinel.
///
/// Not `Sendable`: leases are made, held and let go of by the render walk and
/// by what the render cache keeps, and so retire where the cache's owner lets
/// go of them. Only the sentinel is reached from another thread.
package final class ObservationLease {
    private var sentinel: ScopeSentinel?
    private var held: [ObservationLease] = []

    package init() {}

    /// The sentinel a scope armed under this lease reads, made on first use:
    /// a lease under which nothing reads anything costs no sentinel.
    package func scopeSentinel() -> ScopeSentinel {
        if let sentinel { return sentinel }
        let made = ScopeSentinel()
        sentinel = made
        return made
    }

    /// Keeps `lease` alive for as long as this one lives.
    ///
    /// A lease held already as the last one is not added again: a kept result
    /// served several times running within one computation — its measure and
    /// its render, each walk of a pass — is held once.
    package func hold(_ lease: ObservationLease) {
        if held.last === lease { return }
        held.append(lease)
    }

    /// How many leases this one holds.
    package var heldCount: Int { held.count }

    /// Whether this one holds `lease` itself (not through another).
    package func holds(_ lease: ObservationLease) -> Bool {
        held.contains { $0 === lease }
    }

    /// Whether a scope has been armed under this lease: whether its sentinel
    /// was ever asked for.
    package var hasSentinel: Bool { sentinel != nil }

    deinit {
        sentinel?.retire()
    }
}
