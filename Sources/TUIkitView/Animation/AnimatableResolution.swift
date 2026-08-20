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
    V._animated(view, context: context, isMeasuring: isMeasuring)
}

extension View where Self: Animatable {
    /// An ``Animatable`` view nominates something continuous about itself, so
    /// the render and measure walks must ask the animation store what to draw
    /// it at. See ``View/_isAnimatable``.
    @inlinable
    public static var _isAnimatable: Bool { true }

    /// This view at the value the store says to draw, or `nil` when that is
    /// exactly what the tree already says.
    ///
    /// Generic in `Self`, so nothing is boxed and nothing is cast back — see
    /// ``View/_animated(_:context:isMeasuring:)``.
    @MainActor
    public static func _animated(
        _ view: Self, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        guard let storage = context.stateStorage else { return nil }
        let animation = context.environment.canAnimate
            ? context.environment.transaction.effectiveAnimation : nil
        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self))
        let target = view.animatableData
        let drawn = storage.animations.value(
            for: key, target: target, animation: animation,
            nowNanos: context.environment.frameNowNanos, isMeasuring: isMeasuring)
        guard drawn != target else { return nil }

        // The subtree's appearance is now a function of time, which a value memo
        // cannot reproduce from a cached buffer — it would freeze the animation
        // on its first frame. Same declaration `requestAnimation` makes.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        var copy = view
        copy.animatableData = drawn
        return copy
    }
}
