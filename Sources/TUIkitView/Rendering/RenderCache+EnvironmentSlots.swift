//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+EnvironmentSlots.swift
//
//  The render cache's record of what each environment modifier applied, and
//  the change it reports — the check that keeps a scoped style change from
//  serving a buffer drawn under the old style.
//
//  Split out of `RenderCache.swift`, which had reached the file-length ceiling.
//  The table itself stays a stored property there, as a class's must.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension RenderCache {
    /// What ``noteAppliedEnvironment(_:identity:keyPath:depth:)`` found.
    public enum EnvironmentChange {
        /// Nothing was applied here before — nothing below can be stale. True
        /// because a slot is kept for as long as anything cached below it is:
        /// seen this pass, or inside a subtree a memo served (see
        /// ``removeInactive()``).
        case first
        /// The same value as last pass.
        case unchanged
        /// A different value: cached buffers below are stale.
        case changed
        /// The value is not `Equatable`, so change cannot be detected at all.
        case incomparable
    }

    /// What one slot applied last, and when.
    struct AppliedEnvironment {
        var value: Any
        var lastSeenFrame: UInt64
        var isComparable: Bool
    }

    /// Records the environment value applied at a slot and reports whether it
    /// differs from the previous pass.
    ///
    /// This is what keeps a *scoped* style change from serving a stale buffer.
    /// The cache key is the identity's hash + view value + size, and deliberately carries
    /// no environment: a `.foregroundStyle` applied **above** an `.equatable()`
    /// boundary leaves the view value untouched, so without this the lookup hits
    /// and returns the buffer rendered under the old style. Detecting the change
    /// where it is applied — rather than fingerprinting the environment at every
    /// lookup — costs one comparison per environment modifier per pass instead
    /// of a dictionary walk per memoized view per pass.
    ///
    /// Called from both the measure and render walks. That is deliberate, and it
    /// is *not* the measure-side-effect bug: this table is the cache's own
    /// coherency record, not view state. The measure memo has the same blind
    /// spot as the buffer cache and measurement runs first, so a change noticed
    /// only on the render walk would already have served a stale size. Whichever
    /// walk sees it first clears; the other then reports `.unchanged`, so the
    /// clear happens once.
    ///
    /// - Returns: `.incomparable` when `value` is not `Equatable` — the caller
    ///   must then decline caching, because nothing here can tell whether it
    ///   changed.
    public func noteAppliedEnvironment(
        _ value: Any,
        identity: ViewIdentity,
        keyPath: AnyKeyPath,
        depth: Int
    ) -> EnvironmentChange {
        let slot = EnvironmentSlot(identity: identity, keyPath: keyPath, depth: depth)
        guard var previous = appliedEnvironment[slot] else {
            let comparable = value is any Equatable
            appliedEnvironment[slot] = AppliedEnvironment(
                value: value, lastSeenFrame: frameCounter, isComparable: comparable)
            return comparable ? .first : .incomparable
        }

        // Already answered this pass. Two-pass layout visits the same modifier
        // many times per frame and the value cannot change between those visits,
        // so everything below — two existential casts and a comparison, on a
        // path every environment modifier in the tree runs through — is done
        // once per pass rather than once per visit. Without this the whole
        // scheme costs ~17% of a frame; with it, nothing measurable.
        if previous.lastSeenFrame == frameCounter {
            return previous.isComparable ? .unchanged : .incomparable
        }

        guard previous.isComparable, let equatable = value as? any Equatable else {
            previous.lastSeenFrame = frameCounter
            previous.isComparable = false
            appliedEnvironment[slot] = previous
            return .incomparable
        }
        if equatable.isEqual(to: previous.value) {
            previous.lastSeenFrame = frameCounter
            appliedEnvironment[slot] = previous
            return .unchanged
        }
        appliedEnvironment[slot] = AppliedEnvironment(
            value: value, lastSeenFrame: frameCounter, isComparable: true)
        return .changed
    }
}
