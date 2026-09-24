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
/// picture and nothing else's. `Content` is where the slot is ADDRESSED; the
/// picture it may draw is the one left by `Content` or by the view inside it
/// that `Content` draws unchanged (``departingPictureType(heldAs:)``).
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
    let pictureType = departingPictureType(heldAs: Content.self)
    let slot = DepartureSlot(viewType: pictureType)
    if transparentAtScope {
        guard
            storage.departures.hasDeparture(
                at: context.identity, ofType: pictureType, nowNanos: frame.nowNanos,
                frameAnimation: frameAnimation)
        else { return nil }
        return ChildView(slot)
    }
    guard
        storage.departures.hasDeparture(
            directlyUnder: context.identity, addressedAs: Content.self, ofType: pictureType,
            nowNanos: frame.nowNanos, frameAnimation: frameAnimation)
    else { return nil }
    return ChildView(slot, identityType: Content.self, childIndex: 0)
}

// MARK: - Wrappers a parting picture passes through

/// A single-content wrapper that draws its content UNCHANGED, at its own
/// identity — so the picture a transition inside it leaves behind is the
/// picture the wrapper itself would have drawn, and a slot that held the
/// wrapper may play it.
///
/// ## Why a slot needs telling
///
/// A slot plays a parting picture only if the view it held is the view that
/// left it (`DepartureStore.Departure.viewType`), because the picture is the
/// transitioning view's alone: with `X.transition(t).padding(.leading, 3)` in
/// the `if`, the padding renders at the transition's identity, and a slot that
/// drew the transition's picture there dropped the padding — the view jumped
/// to the slot's edge on the first frame of its removal. But most of what is
/// written after a `.transition` draws nothing of its own: `.onAppear`,
/// `.foregroundStyle`, `.disabled`, `.onKeyPress`. Their picture IS their
/// content's, and an exact match of types snapped
/// `if show { Toast().transition(.opacity).onAppear { … } }` — the commonest
/// toast there is — although the picture was right. A wrapper that conforms
/// is looked through, to the view inside it; see
/// ``departingPictureType(heldAs:)``.
///
/// ## What may conform
///
/// A wrapper whose render hands its content the context it was given — its
/// IDENTITY unchanged, whatever it does to the environment — and returns the
/// content's buffer with nothing visible added or changed. Environment and
/// style modifiers qualify: the transition inside renders under them, so its
/// picture already carries what they do. So do lifecycle, event, focus and
/// registration modifiers, including those that attach a hit-test region —
/// something no removal needs, the view being on its way out.
///
/// NOT, and each of these still snaps rather than play a picture without it:
/// - a wrapper that moves or resizes its content — `.padding`, `.frame`,
///   `.offset`, `.position`, a list row's insets;
/// - one that draws over, behind or instead of it — `.background`,
///   `.overlay`, `.border`, `.opacity`, `.hidden()`, a colour effect, a list
///   row's colours, `.help`'s tooltip, a drag source's blank, a
///   selection-disabled row's dim, the animated runs `AnimatedCellsModifier`
///   adds;
/// - one that renders its content a step below its own identity — any view
///   with a `body` (`.tag`, `.zIndex`, `.redacted`, `.alignmentGuide`, a view
///   of your own), a presentation modifier (`.sheet`, `.alert`, `.popover`,
///   `.contextMenu`), `.id`.
///
/// `AnyView` draws its content unchanged at its own identity too, but what
/// that content is, is known only when it renders, so it cannot say so by
/// type: it vouches for the picture as it draws it instead
/// (`DepartureStore.noteDrawnUnchanged(at:leftBy:byErasing:)`).
///
/// Refines ``SingleContentWrapper`` for its ``SingleContentWrapper/WrappedContent``,
/// the type the look-through steps to.
@MainActor
package protocol DrawsContentUnchanged: SingleContentWrapper {}

/// The type of view whose parting picture a slot that held a view of `type`
/// may draw: `type` itself, or the view inside it, through every wrapper that
/// draws its content unchanged at its own identity — a ``DrawsContentUnchanged``
/// wrapper, and an optional, which hands its view its own identity when it is
/// rendered directly.
///
/// `X` for `if a { if b { X } }` rendered directly, `_TransitionView<X>` for
/// `X.transition(t).onAppear { … }`, and `ModifiedView<_TransitionView<X>,
/// PaddingModifier>` — no further — for `X.transition(t).padding()`, whose
/// picture the transition did not leave.
///
/// By type alone: the slot has no value of what it held. It terminates for the
/// reason ``throughWrappers(_:as:)`` does — each step moves strictly inward
/// through a statically nested generic type.
@MainActor
package func departingPictureType(heldAs type: Any.Type) -> Any.Type {
    var current = type
    while true {
        if let wrapper = current as? any DrawsContentUnchanged.Type {
            current = wrappedContentType(of: wrapper)
        } else if let optional = current as? any OptionalOfView.Type {
            current = optional.wrappedViewType
        } else {
            return current
        }
    }
}

/// The wrapper's content type, the existential metatype opened to reach it.
@MainActor
private func wrappedContentType<Wrapper: DrawsContentUnchanged>(of _: Wrapper.Type) -> Any.Type {
    Wrapper.WrappedContent.self
}

/// An optional of a view, seen from where it is rendered directly: it hands
/// its view its OWN identity.
private protocol OptionalOfView {
    static var wrappedViewType: Any.Type { get }
}

extension Optional: OptionalOfView where Wrapped: View {
    fileprivate static var wrappedViewType: Any.Type { Wrapped.self }
}

extension RenderContext {
    /// Tells the departure store that the `AnyView` rendering here drew the
    /// picture its content left at this identity, unchanged — if the view that
    /// left it is `content`, or inside `content` behind wrappers that draw
    /// their content unchanged.
    ///
    /// The one wrapper that cannot say so by type (``DrawsContentUnchanged``),
    /// since what it wraps is known only now. A slot that held the `AnyView`
    /// then plays the picture: `if show { AnyView(X.transition(t)) }` snapped,
    /// where `AnyView(X.transition(t).padding())` still must.
    ///
    /// Render walk only, as the picture itself is recorded; a store with
    /// nothing in it — every app that animates nothing — pays one check.
    @MainActor
    func noteDepartureDrawnWhole(byErasing content: Any.Type) {
        guard !isMeasuring, let store = stateStorage?.departures, !store.isEmpty else { return }
        store.noteDrawnUnchanged(
            at: identity, leftBy: departingPictureType(heldAs: content), byErasing: AnyView.self)
    }
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
