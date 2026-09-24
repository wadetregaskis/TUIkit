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
/// its slot in the tree plays it out. That is the `nil` an `Optional` became,
/// and only that: an `if`/`else` whose branch flips hands the slot to the other
/// branch at once, so nothing is left there to play the leaving branch's
/// removal, and it is dropped at the end of the pass.
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

        /// The type of the view that left this picture — the view carrying the
        /// transition. A slot plays the picture only if the view it held WAS
        /// that view, or draws it unchanged; see
        /// ``departing(at:ofType:nowNanos:frameAnimation:)``.
        public let viewType: ObjectIdentifier

        /// Creates a departure record.
        public init(
            viewType: Any.Type, width: Int, height: Int, explicitAnimation: Animation?,
            render: @escaping (Double) -> FrameBuffer
        ) {
            self.viewType = ObjectIdentifier(viewType)
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
        /// The type-erasing wrapper that drew this picture unchanged at the
        /// identity it was left at, on the frame it was recorded — `AnyView`,
        /// the one such wrapper that cannot say so by its type. See
        /// ``noteDrawnUnchanged(at:leftBy:byErasing:)``.
        var erasedBy: ObjectIdentifier?

        /// Whether a slot that may draw the picture of a view of `type` may
        /// draw this one: the view that left it, or the eraser that drew it.
        func wasLeft(by type: ObjectIdentifier) -> Bool {
            departure.viewType == type || erasedBy == type
        }
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
    ///
    /// ## Only the picture of the view the slot held
    ///
    /// `type` is the view whose picture the slot may draw — the view it stands
    /// in for, or the one inside it that it draws unchanged at its own identity
    /// (`departingPictureType(heldAs:)`) — and the picture is drawn only if
    /// that view is the one that left it (``Departure/viewType``), or an
    /// `AnyView` that vouched for it (``noteDrawnUnchanged(at:leftBy:byErasing:)``).
    /// The picture is the transitioning view's alone: whatever stood between it
    /// and the slot is not in it. With `X.transition(t).padding(.leading, 3)`
    /// in the `if`, the padding renders at the transition's identity, so the
    /// slot found the transition's picture — and drew it without the padding:
    /// on the first frame of its removal the view jumped three cells to the
    /// slot's edge, the slot shrank to the picture, and the removal played
    /// there. Such a removal snaps instead: the end state, drawn right. The
    /// record is left alone and dropped at the end of the pass, like any other
    /// that nothing plays. A wrapper that draws nothing of its own —
    /// `X.transition(t).onAppear { … }` — is looked through, so that removal
    /// plays.
    public func departing(
        at identity: ViewIdentity, ofType type: Any.Type, nowNanos: Int64,
        frameAnimation: Animation?
    ) -> FrameBuffer? {
        guard var entry = entries[identity], !entry.presentThisPass,
            entry.wasLeft(by: ObjectIdentifier(type))
        else { return nil }
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
    ///
    /// Of `type`, as ``departing(at:ofType:nowNanos:frameAnimation:)`` is: a
    /// slot that will not draw a picture must not hold its size open either.
    public func departingSize(
        at identity: ViewIdentity, ofType type: Any.Type, nowNanos: Int64,
        frameAnimation: Animation?
    ) -> (width: Int, height: Int)? {
        guard let entry = entries[identity],
            entry.wasLeft(by: ObjectIdentifier(type)),
            willPlay(entry, frameAnimation: frameAnimation),
            !isFinished(entry, at: nowNanos)
        else { return nil }
        return (entry.departure.width, entry.departure.height)
    }

    /// Whether the view registered *directly* under `parent` as `address` is
    /// still leaving, with a picture left by a view of `type`.
    ///
    /// A container that flattens its children asks this when a child slot has
    /// become `nil`: the answer decides whether the slot still exists. Both
    /// halves of the question are load-bearing.
    ///
    /// *Directly* under, not anywhere below: an enclosing stack must not hold a
    /// slot open on behalf of something departing several levels down, which is
    /// already held open by its own parent.
    ///
    /// As `address`, because together with `parent` it is the whole address.
    /// A present optional hands its view over as `(Wrapped, 0)` under the scope
    /// it is resolved in, and its `nil` claims that same child (see
    /// `Optional`'s `ChildViewProvider` conformance), so the index is always 0
    /// and is not compared. Nothing looser will do: a slot the `nil` cannot
    /// actually draw is worse than no slot. A `nil` whose content holds one
    /// view through structure of its own — a nested `if`, a `Group`, an
    /// `if`/`else` — asks that structure where the view went
    /// (`DepartingSlotAddressing`) and brings the question here or to
    /// ``hasDeparture(at:ofType:nowNanos:frameAnimation:)``. One whose content
    /// has several children left nothing at any single address, finds nothing,
    /// and contributes nothing: the same instant removal as before, rather than
    /// an empty child that would push its siblings apart by a stack's spacing.
    /// And the picture registered there must have been left by `type`, not
    /// merely by the view at the address — `address` itself, or the view inside
    /// it that it draws unchanged (`departingPictureType(heldAs:)`): a slot the
    /// `nil` would draw without what stood around the transition is one it
    /// cannot draw; see ``departing(at:ofType:nowNanos:frameAnimation:)``.
    ///
    /// The empty check is the whole point of the fast path: almost every tree
    /// has no departures at all, and this is asked once per `nil` optional per
    /// pass.
    ///
    /// ## Forgetting a removal that has played out
    ///
    /// A finished removal is dropped HERE, because nothing else would drop it. A
    /// slot host that finds the removal finished stops drawing the slot, so
    /// ``departing(at:ofType:nowNanos:frameAnimation:)`` — which drops a
    /// finished record when it is asked for one — is never asked again, and
    /// ``endRenderPass()`` keeps every record whose removal has started. Left
    /// in place, one removal that had played out in a stack kept the store
    /// non-empty for the rest of the session, and every `nil` optional in every
    /// stack paid this loop on every walk instead of the empty check above.
    ///
    /// Safe on the measure walk, which runs before the frame's presence marks:
    /// a removal that has finished stays finished, and a view that comes back
    /// records a fresh entry when it renders.
    public func hasDeparture(
        directlyUnder parent: ViewIdentity, addressedAs address: Any.Type, ofType type: Any.Type,
        nowNanos: Int64, frameAnimation: Animation?
    ) -> Bool {
        guard !entries.isEmpty else { return false }
        let addressType = ObjectIdentifier(address)
        let pictureType = ObjectIdentifier(type)
        var finished: [ViewIdentity] = []
        defer { for identity in finished { entries.removeValue(forKey: identity) } }
        for (identity, entry) in entries {
            guard !isFinished(entry, at: nowNanos) else {
                finished.append(identity)
                continue
            }
            guard willPlay(entry, frameAnimation: frameAnimation) else { continue }
            guard entry.wasLeft(by: pictureType), let leaf = identity.leafType,
                ObjectIdentifier(leaf) == addressType
            else { continue }
            if identity.parent == parent { return true }
        }
        return false
    }

    /// Whether the view registered at exactly `identity` is still leaving:
    /// ``hasDeparture(directlyUnder:addressedAs:ofType:nowNanos:frameAnimation:)``
    /// for a slot whose whole address is already known.
    ///
    /// That is a branch of an `if`/`else` holding one plain view, which renders
    /// AT the branch's identity rather than a step below it — so it has no type
    /// step of its own to match, and the identity is what tells it apart. The
    /// view that left the picture must still be of `type`, for the reason the
    /// other question requires it. A removal that has played out is dropped
    /// here, for the reason the other question drops one.
    public func hasDeparture(
        at identity: ViewIdentity, ofType type: Any.Type, nowNanos: Int64,
        frameAnimation: Animation?
    ) -> Bool {
        guard let entry = entries[identity], entry.wasLeft(by: ObjectIdentifier(type))
        else { return false }
        guard !isFinished(entry, at: nowNanos) else {
            entries.removeValue(forKey: identity)
            return false
        }
        return willPlay(entry, frameAnimation: frameAnimation)
    }

    /// Records that `eraser` — `AnyView` — drew the picture left at `identity`
    /// this pass, unchanged, if the view that left it is `type`: what a slot
    /// that held the eraser would find there is then that picture, and it may
    /// play it as one that held the transition may.
    ///
    /// A wrapper that draws its content unchanged says so by its type
    /// (`DrawsContentUnchanged`), and the slot looks through it without asking
    /// here. An `AnyView` cannot: what it wraps is known only once it renders,
    /// so it vouches for the picture then, after its content has recorded it.
    /// `type` is what its content's picture was left by — the content itself,
    /// or the view inside it behind wrappers of the first kind — so
    /// `AnyView(X.transition(t))` vouches and `AnyView(X.transition(t).padding())`
    /// does not. A picture already vouched for by an inner `AnyView` is matched
    /// as `AnyView`, so erasers nest.
    ///
    /// Only a picture recorded this pass: the view is present, and the next
    /// frame it is not is the one whose slot asks.
    ///
    /// `type` is an autoclosure, asked only where an entry is present at
    /// `identity`: working it out is a walk of existential-metatype casts, and
    /// while any transition is on screen every `AnyView` render asks.
    public func noteDrawnUnchanged(
        at identity: ViewIdentity, leftBy type: @autoclosure () -> Any.Type, byErasing eraser: Any.Type
    ) {
        guard var entry = entries[identity], entry.presentThisPass,
            entry.wasLeft(by: ObjectIdentifier(type()))
        else { return }
        entry.erasedBy = ObjectIdentifier(eraser)
        entries[identity] = entry
    }

    /// Whether `entry`'s removal will actually PLAY: already resolved, named by
    /// the transition, or animated by the frame doing the removing. A slot
    /// exists only for one that will — an unanimated removal snaps, and its
    /// slot must close up on the same frame.
    private func willPlay(_ entry: Entry, frameAnimation: Animation?) -> Bool {
        entry.animation ?? entry.departure.explicitAnimation ?? frameAnimation != nil
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
    /// dropped by whichever of ``departing(at:ofType:nowNanos:frameAnimation:)``,
    /// ``hasDeparture(directlyUnder:addressedAs:ofType:nowNanos:frameAnimation:)`` and
    /// ``hasDeparture(at:ofType:nowNanos:frameAnimation:)`` next sees it
    /// finished; this has no clock to tell.)
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
