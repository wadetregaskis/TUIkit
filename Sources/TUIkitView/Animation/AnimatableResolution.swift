//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableResolution.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Substitutes the animated value into an ``Animatable`` view before its body is
/// evaluated, so the subtree is built from where the picture *is* rather than
/// from where the tree says the value has got to.
///
/// This is the general case, and the expensive one: the body is re-evaluated on
/// every frame of the animation, because a terminal has no render server to
/// hand an interpolation to. That is affordable for the length of a change and
/// is not affordable forever — see <doc:AnimatingYourOwnView>.
///
/// - Parameters:
///   - view: The view about to be rendered or measured.
///   - context: Its render context.
///   - isMeasuring: Whether this is the measure walk, which must not write to
///     the store. Passed rather than read from `context.isMeasuring`, because
///     that flag means something narrower — a *render* performed only in order
///     to measure — and is false on the ordinary structural measure walk, where
///     writing would be just as wrong.
/// - Returns: A copy at this frame's value, or **`nil` when there is nothing to
///   substitute** — which is the answer for every view but the animating ones,
///   and is why it is an `Optional` rather than the view itself. Returning
///   `view` would make every caller rebind it, and rebinding copies the struct
///   on every render of every view in the tree. That copy, not the check, was
///   the +1% a paired A/B kept finding.
@MainActor
func resolvingAnimation<V: View>(
    _ view: V, context: RenderContext, isMeasuring: Bool
) -> V? {
    guard let animatable = view as? any Animatable else { return nil }
    guard let storage = context.stateStorage else { return nil }

    let key = AnimationStore.Key(identity: context.identity, owner: ObjectIdentifier(V.self))
    // Passing an `any Animatable` to a generic parameter opens the existential,
    // so the animatable data keeps its real type through the store.
    guard let resolved = substituting(
        animatable, key: key, storage: storage, context: context, isMeasuring: isMeasuring)
    else { return nil }
    return resolved as? V
}

/// Replaces `value`'s animatable data with what the store says to draw, or
/// `nil` when the store says to draw exactly what the tree already says.
@MainActor
private func substituting<A: Animatable>(
    _ value: A, key: AnimationStore.Key, storage: StateStorage, context: RenderContext,
    isMeasuring: Bool
) -> A? {
    let transaction = context.environment.transaction
    let animation = context.environment.canAnimate ? transaction.effectiveAnimation : nil
    let drawn = storage.animations.value(
        for: key,
        target: value.animatableData,
        animation: animation,
        nowNanos: context.environment.frameNowNanos,
        isMeasuring: isMeasuring)
    guard drawn != value.animatableData else { return nil }

    // The subtree's appearance is now a function of time, which a value memo
    // cannot reproduce from a cached buffer — it would freeze the animation on
    // its first frame. Same declaration `requestAnimation` makes, for the same
    // reason.
    context.environment.volatileReadTracker?.recordRenderSideEffect()

    var copy = value
    copy.animatableData = drawn
    return copy
}

extension View where Self: Animatable {
    /// An ``Animatable`` view nominates something continuous about itself, so
    /// the render and measure walks must ask the animation store what to draw
    /// it at. See ``View/_isAnimatable``.
    @inlinable
    public static var _isAnimatable: Bool { true }
}
