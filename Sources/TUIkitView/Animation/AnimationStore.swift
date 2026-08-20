//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationStore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIkitCore

/// What each animating thing in the tree is doing, and where its picture has
/// got to.
///
/// A terminal rebuilds its whole frame from the view tree, so nothing about a
/// view persists between passes except what a store like this remembers. An
/// animation is precisely a thing that must persist: the tree says the value is
/// `1`, and the picture has to keep saying `0.4` until the animation is done.
/// So the store holds, per animating place, where the value was when the change
/// arrived, where it is going, and when it started — and every pass asks it
/// what to draw.
///
/// ## What it is keyed by
///
/// A ``ViewIdentity`` (the view's structural position, as `@State` uses), plus
/// the *type* that owns the animation and a slot within it. The type is needed
/// because modifiers do not descend the identity — `.opacity(x)` renders at its
/// content's identity — so two different animatable modifiers wrapping the same
/// view would otherwise collide. Nesting the same modifier twice changes its
/// generic type, so that case is distinguished too.
///
/// Deliberately NOT a per-frame claimed counter, which is how `onChange`
/// disambiguates: a counter is only stable if every pass walks the tree the
/// same way, and the measure walk does not — it visits subtrees the render
/// walk skips, and vice versa. A key built from what the code says rather than
/// from what the walk did is the same in both.
public final class AnimationStore: @unchecked Sendable {

    /// Identifies one animating value at one place in the tree.
    public struct Key: Hashable, Sendable {
        /// The view's structural position.
        public let identity: ViewIdentity

        /// The type that owns the animation — the animatable view, or the
        /// modifier that paints with the value.
        public let owner: ObjectIdentifier

        /// Which of that type's animatable values this is. `0` unless a type
        /// animates more than one thing.
        public let slot: Int

        /// Creates a key.
        public init(identity: ViewIdentity, owner: ObjectIdentifier, slot: Int = 0) {
            self.identity = identity
            self.owner = owner
            self.slot = slot
        }
    }

    /// One animating value's history. Type-erased for the same reason
    /// `StateStorage.trackedValues` is: the store is one dictionary and the
    /// values in it are of whatever type each call site animates.
    private struct Record {
        /// Where the picture was when this animation began.
        var from: Any

        /// What the tree last said the value is.
        var target: Any

        /// What is running, or `nil` when the picture has arrived.
        var animation: Animation?

        /// When it began, on the frame clock.
        var startNanos: Int64

        /// Whether this frame's render handed the run loop the whole cycle
        /// pre-rendered, so the loop needs no further renders for it.
        ///
        /// Cleared every pass by ``beginRenderPass()`` and re-declared by
        /// whoever emitted the runs, exactly as the animation scheduler makes
        /// a view re-declare its rate: a producer that stops emitting (its
        /// content changed shape, its cycle grew past the cap) stops being
        /// counted as served and the loop starts rendering for it again.
        var servedByRuns = false
    }

    private var records: [Key: Record] = [:]

    /// The last value each `View.animation(_:value:)` saw, so it can tell a
    /// change from a re-render. Kept here rather than in `StateStorage`'s
    /// tracked values because those are keyed by a *positionally claimed*
    /// property index, and this is read on the measure walk as well as the
    /// render one — where the claim order does not hold.
    private var triggers: [Key: Any] = [:]

    /// Which animating values the tree asked about this pass.
    ///
    /// The store cannot lean on `StateStorage`'s active-identity set the way
    /// `@State` does, and finding that out cost a live debugging session: a
    /// modifier that animates — `.opacity(_:)` — is a `Renderable`, and a
    /// `Renderable` renders at its PARENT's identity and marks nothing active.
    /// So every record here was pruned on the pass that created it, and every
    /// pass then saw a first sight, which never animates. The fade froze on its
    /// target and the loop went quiet, which looks exactly like success.
    ///
    /// Re-declaration instead: anything the tree asks about is alive, and
    /// anything it stops asking about has left. Same contract as the animation
    /// scheduler's per-frame token declarations.
    private var seenThisPass: Set<Key> = []

    /// Creates an empty store.
    public init() {}

    /// How many animating values are being tracked (tests, diagnostics).
    public var count: Int { records.count }
}

// MARK: - Asking what to draw

extension AnimationStore {
    /// The value to draw this frame for `key`, given what the tree now says it
    /// is and how the change was meant to arrive.
    ///
    /// - Parameters:
    ///   - key: The animating value's place in the tree.
    ///   - target: What the view tree says the value is now.
    ///   - animation: The animation in force for this change, or `nil` to snap.
    ///   - nowNanos: The frame's timestamp. The *frame's*, not a live reading:
    ///     a pass may walk the tree more than once, and two walks of one frame
    ///     must agree on what the picture shows.
    ///   - isMeasuring: Whether this is a measure pass, which must not mutate.
    /// - Returns: The value to draw.
    public func value<D: VectorArithmetic>(
        for key: Key, target: D, animation: Animation?, nowNanos: Int64, isMeasuring: Bool
    ) -> D {
        seenThisPass.insert(key)
        guard let record = records[key],
            let from = record.from as? D,
            let recorded = record.target as? D
        else {
            // First sight of this value. An appearance is not a change, so it
            // does not animate — a view that faded in from nothing every time it
            // scrolled into view would be a distraction, not an animation, and
            // SwiftUI does not do it either.
            store(Record(from: target, target: target, animation: nil, startNanos: nowNanos),
                for: key, isMeasuring: isMeasuring)
            return target
        }

        let presented = presented(record, from: from, target: recorded, nowNanos: nowNanos)

        guard recorded != target else {
            // Unchanged. Retire a finished animation so the next frame does not
            // have to ask again, and so the loop stops rendering for it.
            if let running = record.animation, running.isFinished(at: elapsed(record, nowNanos)) {
                store(
                    Record(from: recorded, target: recorded, animation: nil, startNanos: nowNanos),
                    for: key, isMeasuring: isMeasuring)
            }
            return presented
        }

        guard let animation else {
            // Changed, with nothing to animate it: the picture jumps, and any
            // animation that WAS running is abandoned where it stood. That is
            // what an unanimated change means — not "finish the old one first".
            store(Record(from: target, target: target, animation: nil, startNanos: nowNanos),
                for: key, isMeasuring: isMeasuring)
            return target
        }

        // Changed, animated: start from where the picture actually IS, not from
        // where the last animation was headed. Retargeting mid-flight is the
        // common case (a value driven by held arrow keys), and starting from the
        // old target would snap backwards before moving forwards.
        store(
            Record(from: presented, target: target, animation: animation, startNanos: nowNanos),
            for: key, isMeasuring: isMeasuring)
        return presented
    }

    /// Whether `value` differs from the last one seen at `key`.
    ///
    /// First sight is **not** a change: a view appearing is not a value moving,
    /// so `.animation(_:value:)` does not animate a subtree into existence.
    ///
    /// Records on render passes only, so a measure that runs before the render
    /// of the same frame reaches the same answer it will.
    public func triggerChanged<V: Equatable>(
        _ value: V, for key: Key, isMeasuring: Bool
    ) -> Bool {
        seenThisPass.insert(key)
        let previous = triggers[key] as? V
        if !isMeasuring { triggers[key] = value }
        guard let previous else { return false }
        return previous != value
    }

    /// Whether anything is still moving at `nowNanos` — the run loop's whole
    /// question, asked once per frame rather than per animating view.
    public func hasLiveAnimations(at nowNanos: Int64) -> Bool {
        records.values.contains { record in
            guard let animation = record.animation, !record.servedByRuns else { return false }
            return !animation.isFinished(at: elapsed(record, nowNanos))
        }
    }

    /// The repeating animation at `key` sampled onto the replay clock, or `nil`
    /// when there is nothing repeating there (or its cycle is too long to hold).
    ///
    /// Asking changes nothing: a caller that asks and then cannot emit runs —
    /// because its phases disagreed about the shape of the picture — must leave
    /// the animation being rendered for. Declaring it served is a separate,
    /// deliberate step, so the "a dropped run looks like a win" trap cannot be
    /// sprung by an early return.
    ///
    /// - Parameters:
    ///   - key: The animating value's place in the tree.
    ///   - nowNanos: This frame's timestamp.
    ///   - tick: The replay clock's tick count for this frame.
    public func cycle<D: VectorArithmetic & Sendable>(
        for key: Key, nowNanos: Int64, tick: Int
    ) -> AnimationCycle<D>? {
        seenThisPass.insert(key)
        guard let record = records[key],
            let animation = record.animation, animation.repeatsForever,
            let from = record.from as? D, let target = record.target as? D
        else { return nil }
        return AnimationCycle<D>(
            animation: animation, from: from, to: target,
            startNanos: record.startNanos, nowNanos: nowNanos, tick: tick)
    }

    /// Declares that this frame handed the run loop the whole cycle at `key`,
    /// so the loop needs no further renders for it.
    ///
    /// Re-declared every frame — ``beginRenderPass()`` clears it — exactly as
    /// an animating view re-declares its rate to the scheduler. A producer that
    /// stops emitting runs starts being rendered for again on the next frame.
    public func noteServedByRuns(_ key: Key) {
        records[key]?.servedByRuns = true
    }

    /// Starts a pass: nothing has been asked about yet, and nothing has been
    /// served by runs yet.
    ///
    /// Called from ``StateStorage/beginRenderPass()``.
    public func beginRenderPass() {
        seenThisPass.removeAll(keepingCapacity: true)
        for key in records.keys {
            records[key]?.servedByRuns = false
        }
    }

    /// Where the picture is now, under whatever is running.
    private func presented<D: VectorArithmetic>(
        _ record: Record, from: D, target: D, nowNanos: Int64
    ) -> D {
        guard let animation = record.animation else { return target }
        return from.interpolated(
            towards: target, amount: animation.fraction(at: elapsed(record, nowNanos)))
    }

    private func elapsed(_ record: Record, _ nowNanos: Int64) -> TimeInterval {
        Double(nowNanos - record.startNanos) / 1_000_000_000
    }

    /// Writes a record, unless this is a measure pass.
    ///
    /// Measuring must be free of side effects — it happens an unpredictable
    /// number of times per frame, and on subtrees that are never drawn — so it
    /// reads the store and never writes it. It still gets the right answer:
    /// every branch above computes the value it returns *before* deciding what
    /// to store, so measure and render agree on the frame a change lands.
    private func store(_ record: Record, for key: Key, isMeasuring: Bool) {
        guard !isMeasuring else { return }
        records[key] = record
    }
}

// MARK: - Lifetime

extension AnimationStore {
    /// Drops the animations the tree stopped asking about.
    ///
    /// Called from ``StateStorage/endRenderPass()``. Keyed on what was asked
    /// this pass rather than on `@State`'s active-identity set: a modifier that
    /// animates is a `Renderable`, which renders at its parent's identity and
    /// marks nothing active, so that set can never answer this question.
    public func endRenderPass() {
        guard !records.isEmpty || !triggers.isEmpty else { return }
        records = records.filter { seenThisPass.contains($0.key) }
        triggers = triggers.filter { seenThisPass.contains($0.key) }
    }

    /// Drops the animations of everything below `ancestor` — the
    /// conditional-branch switch that `StateStorage/invalidateDescendants(of:)`
    /// performs for state.
    public func removeDescendants(of ancestor: ViewIdentity) {
        for key in records.keys where ancestor.isAncestor(of: key.identity) {
            records.removeValue(forKey: key)
        }
        for key in triggers.keys where ancestor.isAncestor(of: key.identity) {
            triggers.removeValue(forKey: key)
        }
    }

    /// Drops everything.
    public func removeAll() {
        records.removeAll()
        triggers.removeAll()
    }
}
