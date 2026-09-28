//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservationLeases.swift
//
//  When an observation scope may be cancelled.
//
//  Not when its reader is evaluated again. A size the cache keeps from an
//  evaluation under another context (a hugging `List` walks its rows under a
//  context of its own), or at another proposal (the size memo keeps one entry
//  per proposal), still depends on the old scope when a later frame evaluates
//  the reader only one way. And not when its reader leaves the pass: a size
//  kept ABOVE the reader — the content-width ladder's record, a hug — still
//  depends on it, and `_MemoizedRow.sizeThatFits` marks nothing, so a reader
//  measured under a kept result leaves the pass it was measured in.
//
//  A scope may go exactly when nothing kept depends on the evaluation that
//  armed it. So every scope is armed under a LEASE: the lease of the
//  innermost computation whose result something may keep — a memo's buffer, a
//  size in the cross-frame table, a per-pass measure, a container's kept
//  record — or, for everything else, the frame being drawn. The kept result
//  holds its lease; a computation that uses a kept result, served or computed,
//  holds that result's lease; the cache holds the frame's until the NEXT frame
//  is drawn, since the screen shows it until then. When the last holder lets
//  go, the lease retires: it writes its sentinel, and every scope armed under
//  it is cancelled (`ObservationLease`).
//
//  So a reader drawn every frame has the scope of the frame before cancelled
//  once the next is drawn — a cancel at re-arm, one frame late — and a scope a
//  kept result still depends on is not cancelled until that result goes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

/// The computations one render cache's walks arm scopes under, the frames'
/// leases, and when a scope may be cancelled. Main actor only, like the walk.
///
/// Nothing here costs anything until a body of some type has been seen to
/// read an `@Observable` (``isActive``): every entry point is one load and a
/// branch before that, so an app that reads none pays nothing else.
package final class ObservationLeases {
    /// When a scope may be cancelled.
    ///
    /// `leases` is the design. The others are kept, package-only, as the
    /// baselines it is measured against: `never` is the tree before leases —
    /// what `Stress --census` compares with in the same build — and the two
    /// naive rules are the negative controls each of the holes' tests runs,
    /// and must see fail.
    package enum Retirement: String, Sendable, CaseIterable {
        /// Never: every scope lives until a property it read is written.
        case never
        /// Naive: one live scope per reader identity; the reader's first arm
        /// in a pass cancels its scopes from every earlier pass.
        case perReader
        /// Naive, and bounded: `perReader`, and a reader neither armed in a
        /// pass nor inside a subtree the pass retained is cancelled at the
        /// pass's prune.
        case perReaderAndPrune
        /// A scope goes when the last kept result embedding the evaluation
        /// that armed it lets go of its lease.
        case leases
    }

    /// What a new cache starts with: `TUIKIT_OBSERVATION_RETIREMENT` when it
    /// names a rule, otherwise `leases`.
    package static let defaultRetirement: Retirement = {
        guard let name = ProcessInfo.processInfo.environment["TUIKIT_OBSERVATION_RETIREMENT"],
            let rule = Retirement(rawValue: name)
        else { return .leases }
        return rule
    }()

    /// When this cache's scopes may be cancelled.
    package var retirement: Retirement {
        didSet { updateActivity() }
    }

    /// Whether scopes read sentinels and computations open slots: a reader
    /// type is known to read, and the rule cancels anything.
    package private(set) var isActive = false

    /// Whether any reader type is known to read (the cache's
    /// `readingTypes`). Set once, by ``noteReaderLearned()``.
    private var hasReaders = false

    /// One computation in progress.
    private struct Slot {
        /// Its lease, made only when something beneath it armed a scope or
        /// used a kept result.
        var lease: ObservationLease?
        /// Whether its lease stands apart from the computation enclosing it:
        /// not held by it, so it retires the moment its own holder lets go —
        /// what a memo verifier's fresh evaluation runs in.
        let isDetached: Bool
    }

    /// The computations in progress, innermost last. Slot 0 is the frame's.
    private var stack = [Slot(lease: nil, isDetached: false)]

    /// How many of those are detached: while any is open, every scope reads
    /// the innermost lease's sentinel whatever the rule, so a verifier's check
    /// observes nothing past itself under the naive rules too.
    private var detachedDepth = 0

    /// The frame before the one being drawn: the screen shows it until this
    /// one replaces it, so what it guarded stays observed until then.
    private var displayed: ObservationLease?

    /// The naive rules' sentinels, one per reader identity, with the pass it
    /// was made in and the identity (for the prune).
    private var readerSentinels: [Int: (sentinel: ScopeSentinel, pass: UInt64, identity: ViewIdentity)] = [:]

    /// Passes ended, for the naive rules.
    private var pass: UInt64 = 0

    /// What the bookkeeping did — what `Stress --census` prints, per pass.
    package struct Counts: Equatable, Sendable {
        /// Scopes armed reading a sentinel.
        package var sentinelScopes = 0
        /// Computations opened: memo and kept-size misses, per-pass measure
        /// misses, walks.
        package var computations = 0
        /// Leases made: computations under which something armed or was used.
        package var leasesMade = 0
        /// Kept results a computation used: serves of an entry that had a
        /// lease.
        package var uses = 0
        /// Passes ended.
        package var passes = 0

        /// None yet.
        package init() {}
    }

    /// What the bookkeeping has done so far.
    package private(set) var counts = Counts()

    package init(retirement: Retirement = ObservationLeases.defaultRetirement) {
        self.retirement = retirement
    }

    private func updateActivity() {
        isActive = hasReaders && retirement != .never
    }

    /// Called when the cache learns its first reading type: from here on,
    /// scopes read sentinels.
    package func noteReaderLearned() {
        guard !hasReaders else { return }
        hasReaders = true
        updateActivity()
    }

    // MARK: Computations

    /// Opens a computation whose result something may keep, and returns the
    /// mark ``endComputation(_:)`` takes — `nil`, and nothing opened, when
    /// nothing is active.
    @inline(__always)
    package func beginComputation() -> Int? {
        guard isActive else { return nil }
        return open(isDetached: false)
    }

    /// Opens a computation whose lease nothing encloses: it retires as soon as
    /// ``endComputation(_:)``'s caller lets go of what it returns, and every
    /// scope armed beneath it with it. What a memo verifier re-evaluates a
    /// served result in, so that its fresh evaluation observes nothing past
    /// the check — see `verifyServe`.
    @inline(__always)
    package func beginDetachedComputation() -> Int? {
        guard isActive else { return nil }
        return open(isDetached: true)
    }

    private func open(isDetached: Bool) -> Int {
        counts.computations += 1
        if isDetached { detachedDepth += 1 }
        stack.append(Slot(lease: nil, isDetached: isDetached))
        return stack.count - 1
    }

    /// Closes the computation `mark` opened and returns its lease: `nil` when
    /// nothing beneath it armed or used anything. A lease that exists is held
    /// already by the enclosing computation — whose result embeds this one's
    /// whether or not anything keeps this one — unless it was opened detached.
    @inline(__always)
    package func endComputation(_ mark: Int?) -> ObservationLease? {
        guard let mark else { return nil }
        assert(stack.count - 1 == mark, "an observation lease computation was closed out of order")
        let slot = stack.removeLast()
        if slot.isDetached { detachedDepth -= 1 }
        return slot.lease
    }

    /// The innermost computation uses a kept result guarded by `lease`: it
    /// holds it, so the result's scopes live as long as what embeds it.
    @inline(__always)
    package func use(_ lease: ObservationLease?) {
        guard let lease else { return }
        counts.uses += 1
        materialize(stack.count - 1).hold(lease)
    }

    /// The lease of the computation at `index`, made — and held by every
    /// enclosing computation down to one that has a lease already, or a
    /// detached one — when it has none yet.
    private func materialize(_ index: Int) -> ObservationLease {
        if let lease = stack[index].lease { return lease }
        let made = ObservationLease()
        counts.leasesMade += 1
        stack[index].lease = made
        var child = made
        var cursor = index
        while cursor > 0, !stack[cursor].isDetached {
            cursor -= 1
            if let enclosing = stack[cursor].lease {
                enclosing.hold(child)
                break
            }
            let enclosing = ObservationLease()
            counts.leasesMade += 1
            enclosing.hold(child)
            stack[cursor].lease = enclosing
            child = enclosing
        }
        return made
    }

    // MARK: Scopes

    /// The sentinel a scope about to be armed at `identity` by a reader of a
    /// type known to read must read, or `nil` when it reads none. Asked only
    /// while ``isActive``.
    package func sentinel(at identity: ViewIdentity) -> ScopeSentinel? {
        if retirement == .leases || detachedDepth > 0 {
            counts.sentinelScopes += 1
            return materialize(stack.count - 1).scopeSentinel()
        }
        switch retirement {
        case .never, .leases:
            return nil
        case .perReader, .perReaderAndPrune:
            counts.sentinelScopes += 1
            let key = identity.structuralHash
            if let known = readerSentinels[key], known.pass == pass { return known.sentinel }
            readerSentinels[key]?.sentinel.retire()
            let made = ScopeSentinel()
            readerSentinels[key] = (made, pass, identity)
            return made
        }
    }

    // MARK: Passes

    /// Ends a pass: the frame just drawn becomes the displayed one, and the
    /// one before it — no longer on screen — lets go of what it held. Under
    /// `perReaderAndPrune`, a reader not armed in the pass and not retained is
    /// cancelled.
    ///
    /// - Parameter isRetained: Whether the pass kept an identity alive
    ///   without visiting it (the cache's retained subtrees).
    package func endPass(isRetained: (ViewIdentity) -> Bool) {
        if retirement == .perReaderAndPrune {
            var gone: [Int] = []
            for (key, reader) in readerSentinels where reader.pass != pass && !isRetained(reader.identity) {
                reader.sentinel.retire()
                gone.append(key)
            }
            for key in gone { readerSentinels.removeValue(forKey: key) }
        }
        pass &+= 1
        counts.passes += 1
        assert(stack.count == 1, "an observation lease computation was left open at the end of a pass")
        displayed = stack[0].lease
        stack[0].lease = nil
    }

    /// Lets go of every lease the cache holds, retiring what nothing else
    /// holds, and every naive sentinel.
    package func reset() {
        stack = [Slot(lease: nil, isDetached: false)]
        detachedDepth = 0
        displayed = nil
        for reader in readerSentinels.values { reader.sentinel.retire() }
        readerSentinels.removeAll()
    }

    // MARK: For tests

    /// The lease of the computation innermost now, if it has one.
    package var innermostLease: ObservationLease? { stack.last?.lease }

    /// The frame being drawn's lease, if anything armed or was used in it.
    package var frameLease: ObservationLease? { stack[0].lease }

    /// The frame on screen's lease.
    package var displayedLease: ObservationLease? { displayed }

    /// How many computations are open, the frame's included.
    package var depth: Int { stack.count }
}
