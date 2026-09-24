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

        /// The animation the transition itself names, if any — the only part
        /// of the removal's timing knowable while the view is still present.
        /// How the view actually leaves is resolved on the frame it goes:
        /// this, or the transaction of the change that removed it.
        public let explicitAnimation: Animation?

        /// Creates a departure record.
        public init(
            width: Int, height: Int, explicitAnimation: Animation?,
            render: @escaping (Double) -> FrameBuffer
        ) {
            self.width = width
            self.height = height
            self.explicitAnimation = explicitAnimation
            self.render = render
        }
    }

    private struct Entry {
        var departure: Departure
        /// When the view stopped being rendered, or `nil` while it is still
        /// present.
        var leftAtNanos: Int64?
        /// How the view is leaving — resolved on the frame it went, from
        /// ``Departure/explicitAnimation`` or that frame's transaction. `nil`
        /// while it is still present.
        var animation: Animation?
        /// Whether the view re-declared itself this pass.
        var presentThisPass = false
    }

    private var entries: [ViewIdentity: Entry] = [:]

    /// Creates an empty store.
    public init() {}

    /// How many departures are being tracked (tests, diagnostics).
    public var count: Int { entries.count }

    /// Whether nothing is tracked at all — the one check a `nil` optional in an
    /// app that animates nothing pays.
    public var isEmpty: Bool { entries.isEmpty }
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
        entries[identity] = Entry(
            departure: departure, leftAtNanos: nil, animation: nil, presentThisPass: true)
    }

    /// The picture to draw in the slot at `identity`, for a view that has gone.
    ///
    /// Returns `nil` when nothing left from there, when the removal has
    /// finished — at which point the slot really is empty and the record is
    /// dropped — or when nothing animates it: how a view leaves is decided by
    /// the frame that removed it, so `frameAnimation` is that frame's
    /// effective animation, and a removal with no explicit animation and none
    /// on the frame simply snaps. The resolved answer is stored, because the
    /// transaction applies to exactly one pass and the removal plays over
    /// many.
    public func departing(
        at identity: ViewIdentity, nowNanos: Int64, frameAnimation: Animation?
    ) -> FrameBuffer? {
        guard var entry = entries[identity], !entry.presentThisPass else { return nil }
        guard
            let animation = entry.animation
                ?? entry.departure.explicitAnimation ?? frameAnimation
        else {
            entries.removeValue(forKey: identity)
            return nil
        }
        let left = entry.leftAtNanos ?? nowNanos
        entry.leftAtNanos = left
        entry.animation = animation
        entries[identity] = entry

        let elapsed = Double(nowNanos - left) / 1_000_000_000
        guard !animation.isFinished(at: elapsed) else {
            entries.removeValue(forKey: identity)
            return nil
        }
        // Backwards: a removal runs the transition from present to absent.
        return entry.departure.render(1 - animation.fraction(at: elapsed))
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
    public func departingSize(
        at identity: ViewIdentity, nowNanos: Int64, frameAnimation: Animation?
    ) -> (width: Int, height: Int)? {
        guard let entry = entries[identity],
            entry.animation ?? entry.departure.explicitAnimation ?? frameAnimation != nil,
            !isFinished(entry, at: nowNanos)
        else { return nil }
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
    ///
    /// ## Forgetting a removal that has played out
    ///
    /// A finished removal is dropped HERE, because nothing else would drop it. A
    /// slot host that finds the removal finished stops drawing the slot, so
    /// ``departing(at:nowNanos:frameAnimation:)`` — which drops a finished record
    /// when it is asked for one — is never asked again, and ``endRenderPass()``
    /// keeps every record whose removal has started. Left in place, one removal
    /// that had played out in a stack kept the store non-empty for the rest of
    /// the session, and every `nil` optional in every stack paid this loop on
    /// every walk instead of the empty check above.
    ///
    /// Safe on the measure walk, which runs before the frame's presence marks:
    /// a removal that has finished stays finished, and a view that comes back
    /// records a fresh entry when it renders.
    public func hasDeparture(
        directlyUnder parent: ViewIdentity, ofType type: Any.Type, nowNanos: Int64,
        frameAnimation: Animation?
    ) -> Bool {
        guard !entries.isEmpty else { return false }
        let wanted = ObjectIdentifier(type)
        var finished: [ViewIdentity] = []
        defer { for identity in finished { entries.removeValue(forKey: identity) } }
        for (identity, entry) in entries {
            guard !isFinished(entry, at: nowNanos) else {
                finished.append(identity)
                continue
            }
            // A slot exists only for a removal that will actually PLAY:
            // already resolved, named by the transition, or animated by the
            // frame doing the removing. An unanimated removal snaps, and its
            // slot must close up on the same frame.
            guard
                entry.animation ?? entry.departure.explicitAnimation ?? frameAnimation != nil
            else { continue }
            guard let leaf = identity.leafType, ObjectIdentifier(leaf) == wanted else { continue }
            if identity.parent == parent { return true }
        }
        return false
    }

    /// Whether `entry`'s removal has played out. An entry that has not started
    /// leaving is never finished.
    private func isFinished(_ entry: Entry, at nowNanos: Int64) -> Bool {
        guard let left = entry.leftAtNanos, let animation = entry.animation else { return false }
        return animation.isFinished(at: Double(nowNanos - left) / 1_000_000_000)
    }

    /// Whether anything is still leaving — the run loop's question, asked once.
    public func hasDepartures(at nowNanos: Int64) -> Bool {
        entries.values.contains { entry in
            guard let left = entry.leftAtNanos, let animation = entry.animation,
                !entry.presentThisPass
            else { return false }
            return !animation.isFinished(at: Double(nowNanos - left) / 1_000_000_000)
        }
    }

    /// Starts a pass: every view is provisionally absent until it re-declares.
    public func beginRenderPass() {
        for key in entries.keys {
            entries[key]?.presentThisPass = false
        }
    }

    /// Ends a pass: drops the entries of views that vanished without anything
    /// starting their removal. (A removal that started and has finished is
    /// dropped by whichever of ``departing(at:nowNanos:frameAnimation:)`` and
    /// ``hasDeparture(directlyUnder:ofType:nowNanos:frameAnimation:)`` next
    /// sees it finished; this has no clock to tell.)
    ///
    /// The parting picture is recorded on EVERY frame a transitioning view
    /// renders, so every such view holds an entry while it is present. When
    /// one leaves, its slot host resolves the removal the same pass — playing
    /// it or snapping it. An entry that is neither present nor departing by
    /// the end of the pass belongs to a view that left with no host to ask (a
    /// subtree removed whole, a `nil` that flattens to several children) and
    /// would otherwise sit in the store forever.
    public func endRenderPass() {
        guard !entries.isEmpty else { return }
        var stale: [ViewIdentity] = []
        for (identity, entry) in entries
        where !entry.presentThisPass && entry.leftAtNanos == nil {
            stale.append(identity)
        }
        for identity in stale { entries.removeValue(forKey: identity) }
    }

    /// Drops everything.
    public func removeAll() {
        entries.removeAll()
    }
}
