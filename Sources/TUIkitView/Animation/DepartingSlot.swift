//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DepartingSlot.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Finding a removal through the structure an `if` holds

/// Content that holds at most one view through structure of its own, and can
/// say where that view was addressed — so a `nil` that stands where the content
/// stood can find a removal still playing there.
///
/// ## Why the `nil` needs telling
///
/// A `nil` in a stack keeps a slot only for a removal it can find, and it finds
/// one by address: the present view was handed over as `(Wrapped, 0)` under the
/// optional's scope, so the `nil` claims that. It holds for a `Wrapped` that is
/// one plain view. It does not for a `Wrapped` that flattens through a provider
/// of its own, because then that provider addresses the view, not the optional:
///
/// - `if a { if b { X } }` — the inner optional hands `X` over as `(X, 0)`,
///   and the outer `nil` looked for `(Optional<X>, 0)`;
/// - `if a { Group { X } }` — the `Group` hands `X` over transparent, with no
///   step of its own;
/// - `if a { if c { X } else { Y } }` — the conditional pins its branch's one
///   view to the branch's own identity.
///
/// All three are one view, with nothing drawn between it and the `if`, so all
/// three removals are playable — and jumped. Each conforming type answers from
/// its TYPE alone: the `nil` has no value of what it held, only `Wrapped`.
///
/// ## Why only these
///
/// A provider with a picture of its own between the `if` and the view — a
/// modifier on a `Group`, say — cannot conform: the slot would draw the view's
/// parting picture without it. Nor can one with several members, which has no
/// single slot to keep. Both still remove at once; ``View/transition(_:)``
/// lists them.
@MainActor
package protocol DepartingSlotAddressing {
    /// The slot a `nil` standing in for content of this type keeps open for a
    /// removal still playing there, or `nil` when nothing it held is leaving.
    ///
    /// - Parameters:
    ///   - context: The scope the content was resolved in.
    ///   - transparentAtScope: Where a view this content hands over TRANSPARENT
    ///     rendered: at the scope itself (a conditional's branch pins it there)
    ///     or a step below it, as `(its type, 0)` (an optional pins it there —
    ///     see `ChildView.addressedIfTransparent(under:)`). A content that hands
    ///     its view on untouched, like `Group`, passes this through.
    static func departingSlot(context: RenderContext, transparentAtScope: Bool) -> ChildView?
}

/// The slot a `nil` keeps open for content of type `Content` that was resolved
/// under `context`, or `nil` when nothing it held is leaving — the whole claim a
/// `nil` optional makes, and the step each ``DepartingSlotAddressing`` content
/// takes towards the one view it holds.
///
/// The slot is a `DepartureSlot` for the view found, so it draws that view's
/// picture and nothing else's.
@MainActor
package func departingSlot<Content: View>(
    heldAs content: Content.Type, context: RenderContext, transparentAtScope: Bool
) -> ChildView? {
    if let addressing = Content.self as? any DepartingSlotAddressing.Type {
        return addressing.departingSlot(context: context, transparentAtScope: transparentAtScope)
    }
    guard let storage = context.stateStorage else { return nil }
    // One read for both halves — see `AnimatableResolution`.
    let frame = context.environment.animationFrame
    let frameAnimation =
        frame.canAnimate ? context.environment.transaction.effectiveAnimation : nil
    let slot = DepartureSlot(viewType: Content.self)
    if transparentAtScope {
        guard
            storage.departures.hasDeparture(
                at: context.identity, ofType: Content.self, nowNanos: frame.nowNanos,
                frameAnimation: frameAnimation)
        else { return nil }
        return ChildView(slot)
    }
    guard
        storage.departures.hasDeparture(
            directlyUnder: context.identity, ofType: Content.self, nowNanos: frame.nowNanos,
            frameAnimation: frameAnimation)
    else { return nil }
    return ChildView(slot, identityType: Content.self, childIndex: 0)
}

/// `if a { if b { X } }`: the inner optional hands a plain `X` over as `(X, 0)`
/// in the same scope, and pins a transparent one there — whatever the outer
/// optional's caller would have done with it.
extension Optional: DepartingSlotAddressing where Wrapped: View {
    package static func departingSlot(
        context: RenderContext, transparentAtScope: Bool
    ) -> ChildView? {
        TUIkitView.departingSlot(heldAs: Wrapped.self, context: context, transparentAtScope: false)
    }
}

/// `if a { if c { X } else { Y } }`: each branch is resolved under a branch
/// step of its own, and a branch that is one plain view is pinned to that step
/// itself (`ChildView.resolvingIdentity(inBranch:)`). Whichever branch was
/// showing, its view's departure is there. Tried in order, since the `nil`
/// cannot know which branch it was.
extension ConditionalView: DepartingSlotAddressing {
    package static func departingSlot(
        context: RenderContext, transparentAtScope: Bool
    ) -> ChildView? {
        slot(inBranch: "true", heldAs: TrueContent.self, context: context)
            ?? slot(inBranch: "false", heldAs: FalseContent.self, context: context)
    }

    /// The slot in the branch labelled `label`, resolved as
    /// ``resolveChildViews(from:context:)`` resolves that branch's children.
    private static func slot<Branch: View>(
        inBranch label: String, heldAs branch: Branch.Type, context: RenderContext
    ) -> ChildView? {
        let branchContext = context.withBranchIdentity(label)
        return TUIkitView.departingSlot(
            heldAs: Branch.self, context: branchContext, transparentAtScope: true
        )?
        .resolvingIdentity(inBranch: branchContext.identity)
    }
}
