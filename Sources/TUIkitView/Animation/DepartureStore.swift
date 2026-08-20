//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DepartureStore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIkitCore

/// What a view left behind when it was removed from the tree, so something can
/// still draw it while it leaves.
///
/// ## The problem a removal transition has and an insertion does not
///
/// An inserted view *exists*: the tree contains it, it renders, and the
/// transition is applied to what it drew. A removed one does not. The body that
/// produced it no longer produces it, and a terminal rebuilds its whole frame
/// from the tree — so by the time anything notices the view is gone, there is
/// nothing left to animate.
///
/// What there IS is the picture it drew on the last frame it was present. That
/// is enough: a removal transition does not need the view, it needs the cells.
/// So a transitioning view leaves a closure behind on every frame it renders —
/// "if I vanish, here is what I look like part-way gone" — and whatever occupies
/// its slot in the tree (an `Optional` that has become `nil`, a
/// ``ConditionalView`` branch that flipped) plays it out.
///
/// The closure is why this type is here rather than beside `AnyTransition`: the
/// hosts live in this module and the transitions live above it. A closure from
/// phase to buffer is the whole contract, and it lets each side keep what it
/// knows to itself.
/// Main-actor by discipline rather than by annotation, exactly as
/// ``StateStorage`` is — it is a stored property of one, and rendering is
/// single-threaded on the run loop.
public final class DepartureStore: @unchecked Sendable {

    /// A view's parting picture.
    public struct Departure {
        /// Draws the view at `phase` — `1` fully present, `0` fully gone.
        public let render: (Double) -> FrameBuffer

        /// The size it occupied, so its slot keeps its shape while it leaves.
        public let width: Int

        /// The number of rows it occupied.
        public let height: Int

        /// How it leaves.
        public let animation: Animation

        /// Creates a departure record.
        public init(
            width: Int, height: Int, animation: Animation,
            render: @escaping (Double) -> FrameBuffer
        ) {
            self.width = width
            self.height = height
            self.animation = animation
            self.render = render
        }
    }

    private struct Entry {
        var departure: Departure
        /// When the view stopped being rendered, or `nil` while it is still
        /// present.
        var leftAtNanos: Int64?
        /// Whether the view re-declared itself this pass.
        var presentThisPass = false
    }

    private var entries: [ViewIdentity: Entry] = [:]

    /// Creates an empty store.
    public init() {}

    /// How many departures are being tracked (tests, diagnostics).
    public var count: Int { entries.count }
}

extension DepartureStore {
    /// Declares that the view at `identity` is present, and records how to draw
    /// it part-way gone.
    ///
    /// Called on every frame the view renders. Re-declaring is what tells the
    /// store it has not left — the same contract the animation scheduler uses
    /// for its tokens, and for the same reason: nothing else can report an
    /// absence.
    public func present(_ departure: Departure, at identity: ViewIdentity) {
        entries[identity] = Entry(departure: departure, leftAtNanos: nil, presentThisPass: true)
    }

    /// The picture to draw in the slot at `identity`, for a view that has gone.
    ///
    /// Returns `nil` when nothing left from there, or when the removal has
    /// finished — at which point the slot really is empty and the record is
    /// dropped.
    public func departing(at identity: ViewIdentity, nowNanos: Int64) -> FrameBuffer? {
        guard var entry = entries[identity], !entry.presentThisPass else { return nil }
        let left = entry.leftAtNanos ?? nowNanos
        entry.leftAtNanos = left
        entries[identity] = entry

        let elapsed = Double(nowNanos - left) / 1_000_000_000
        guard !entry.departure.animation.isFinished(at: elapsed) else {
            entries.removeValue(forKey: identity)
            return nil
        }
        // Backwards: a removal runs the transition from present to absent.
        return entry.departure.render(1 - entry.departure.animation.fraction(at: elapsed))
    }

    /// The size a departing view is still holding open, or `nil` if none is.
    ///
    /// Asked only from a slot that has already established the view is gone —
    /// an `Optional` that is `nil` — so presence is not re-tested here. It must
    /// not be: the question arrives on the MEASURE walk, which runs before any
    /// of this frame's renders and therefore before the frame's presence marks
    /// exist at all. Testing them would report every still-present view as
    /// departing on every measure.
    ///
    /// Nor can it require the removal to have already started. The first frame
    /// of a removal is measured before it is rendered, so on that frame
    /// `leftAtNanos` is still `nil` — insisting on it collapsed the slot to
    /// nothing exactly when the transition needed it most, and the first frame
    /// of every departure was drawn into no rows.
    public func departingSize(at identity: ViewIdentity, nowNanos: Int64)
        -> (width: Int, height: Int)?
    {
        guard let entry = entries[identity], !isFinished(entry, at: nowNanos) else { return nil }
        return (entry.departure.width, entry.departure.height)
    }

    /// Whether a view of `type` registered *directly* under `parent` is still
    /// leaving.
    ///
    /// A container that flattens its children asks this when a child slot has
    /// become `nil`: the answer decides whether the slot still exists. Both
    /// halves of the question are load-bearing.
    ///
    /// *Directly* under, not anywhere below: an enclosing stack must not hold a
    /// slot open on behalf of something departing several levels down, which is
    /// already held open by its own parent.
    ///
    /// Of that *type*, because the caller knows the child's type but not the
    /// index it will be flattened to, and because a slot it cannot actually
    /// draw is worse than no slot. A `nil` whose content would have flattened
    /// into *several* children has no single type to match, finds nothing here,
    /// and contributes nothing — the same instant removal as before, rather
    /// than an empty child that would push its siblings apart by a stack's
    /// spacing.
    ///
    /// The empty check is the whole point of the fast path: almost every tree
    /// has no departures at all, and this is asked once per `nil` optional per
    /// pass.
    public func hasDeparture(
        directlyUnder parent: ViewIdentity, ofType type: Any.Type, nowNanos: Int64
    ) -> Bool {
        guard !entries.isEmpty else { return false }
        let wanted = ObjectIdentifier(type)
        for (identity, entry) in entries where !isFinished(entry, at: nowNanos) {
            guard let leaf = identity.leafType, ObjectIdentifier(leaf) == wanted else { continue }
            if identity.parent == parent { return true }
        }
        return false
    }

    /// Whether `entry`'s removal has played out. An entry that has not started
    /// leaving is never finished.
    private func isFinished(_ entry: Entry, at nowNanos: Int64) -> Bool {
        guard let left = entry.leftAtNanos else { return false }
        return entry.departure.animation.isFinished(at: Double(nowNanos - left) / 1_000_000_000)
    }

    /// Whether anything is still leaving — the run loop's question, asked once.
    public func hasDepartures(at nowNanos: Int64) -> Bool {
        entries.values.contains { entry in
            guard let left = entry.leftAtNanos, !entry.presentThisPass else { return false }
            return !entry.departure.animation.isFinished(
                at: Double(nowNanos - left) / 1_000_000_000)
        }
    }

    /// Starts a pass: every view is provisionally absent until it re-declares.
    public func beginRenderPass() {
        for key in entries.keys {
            entries[key]?.presentThisPass = false
        }
    }

    /// Drops everything.
    public func removeAll() {
        entries.removeAll()
    }
}
