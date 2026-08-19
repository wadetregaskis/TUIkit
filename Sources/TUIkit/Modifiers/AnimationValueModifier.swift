//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationValueModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Animates this view's subtree whenever `value` changes.
    ///
    /// The declarative counterpart to ``withAnimation(_:_:)``: that one says
    /// "this change is animated", stated where the change is made; this one says
    /// "changes to *this* value are animated here", stated where the change is
    /// seen. Use it when the change is made somewhere that has no business
    /// knowing how it will be shown — a model update, a network result, a
    /// binding written by a control.
    ///
    /// ```swift
    /// Bar(fraction: progress)
    ///     .animation(.easeOut(duration: 0.3), value: progress)
    /// ```
    ///
    /// Scoped to the value, which is what makes it safe to leave in place: a
    /// change to anything *else* in the subtree is not animated by this. It
    /// adds an animation rather than masking one, so several of them compose —
    /// each governs its own value — and an explicit ``withAnimation(_:_:)``
    /// elsewhere still reaches the subtree, because that is a deliberate act at
    /// the call site and this modifier has said nothing about it.
    ///
    /// To refuse animation outright, say so outright:
    ///
    /// ```swift
    /// content.transaction { $0.disablesAnimations = true }
    /// ```
    ///
    /// The first render is not a change: a view does not animate into existence.
    ///
    /// - Parameters:
    ///   - animation: How to animate changes to `value`, or `nil` for none.
    ///   - value: The value to watch.
    /// - Returns: A view whose subtree animates on changes to `value`.
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        _AnimationValueModifier(content: self, animation: animation, value: value)
    }
}

/// Publishes an animation to its subtree on the frames where `value` changed.
/// See ``View/animation(_:value:)``.
///
/// Size-neutral: whether a change is animated never changes what the subtree
/// measures — only which value it is measured *at*, which the animation store
/// answers identically on both walks.
struct _AnimationValueModifier<Content: View, V: Equatable>: View {
    let content: Content
    let animation: Animation?
    let value: V

    var body: Never {
        fatalError("_AnimationValueModifier renders via Renderable")
    }

    /// The subtree's context, with this modifier's verdict published.
    ///
    /// Keyed by identity and by this modifier's own generic type, so nesting
    /// two of them — `.animation(a, value: x).animation(b, value: y)` — gives
    /// each its own record: the outer one's `Content` is the inner one, so the
    /// types differ.
    private func childContext(_ context: RenderContext, isMeasuring: Bool) -> RenderContext {
        guard let storage = context.stateStorage else { return context }
        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self))
        let changed = storage.animations.triggerChanged(
            value, for: key, isMeasuring: isMeasuring)
        // Only on the frames where the value moved. Clearing it otherwise
        // would make these uncomposable: `.animation(a, value: x)` inside
        // `.animation(b, value: y)` renders at ONE identity, so the inner one
        // would wipe the outer one's animation on every frame that was not its
        // own — a change to `y` would silently snap. It would also mask an
        // explicit `withAnimation`, which is a deliberate act at a call site
        // that has said nothing about this subtree.
        guard changed else { return context }
        var childContext = context
        childContext.environment.transaction.animation = animation
        return childContext
    }
}

extension _AnimationValueModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(
            content, context: childContext(context, isMeasuring: context.isMeasuring))
    }
}

extension _AnimationValueModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            content, proposal: proposal,
            context: childContext(context, isMeasuring: true))
    }
}
