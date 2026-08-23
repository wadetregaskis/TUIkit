//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransactionModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension View {
    /// Changes the ``Transaction`` this view's subtree renders under.
    ///
    /// The subtree-shaped counterpart to ``withTransaction(_:_:)``: that one
    /// scopes a transaction to *a change*, this one to *a place*. Most usefully,
    /// it is how part of the tree opts out of an animation the rest of it wants:
    ///
    /// ```swift
    /// VStack {
    ///     Header(count: items.count)
    ///         .transaction { $0.disablesAnimations = true }   // snaps
    ///     ItemList(items)                                     // slides
    /// }
    /// ```
    ///
    /// - Parameter transform: Receives the inherited transaction and modifies it
    ///   in place. It runs on both the measure and the render walk, so it must
    ///   be a pure function of the value it is handed.
    /// - Returns: A view whose subtree sees the transformed transaction.
    public func transaction(
        _ transform: @escaping (inout Transaction) -> Void
    ) -> some View {
        transformEnvironment(\.transaction, transform: transform)
    }

    /// Changes the ``Transaction`` this view's subtree renders under, but only
    /// on frames where `value` changed.
    ///
    /// The scoped counterpart to ``transaction(_:)``: that one states something
    /// about a PLACE for as long as the place exists, this one about a place
    /// for the update that a particular value moved. The case for it is a view
    /// that should animate one of the things it depends on and not the others.
    ///
    /// ```swift
    /// Chart(points)
    ///     .transaction(value: zoom) { $0.animation = .easeInOut }   // zooming glides
    ///                                                               // new data snaps
    /// ```
    ///
    /// ## What "caused by" means here, and where it differs from SwiftUI
    ///
    /// SwiftUI applies the transform to updates CAUSED BY `value` changing; it
    /// can, because its dependency graph knows which node produced the value.
    /// This framework re-evaluates bodies each frame and has no such graph, so
    /// what it can ask is whether `value` differs from the last frame's — which
    /// is the same answer whenever the change that moved `value` is the change
    /// being rendered, i.e. essentially always.
    ///
    /// They part when several changes coalesce into one frame and only one of
    /// them is `value`. Nothing could be exact there: a frame carries ONE
    /// transaction, and the collision already has a stated rule (see
    /// `TransactionTests`, "The last animated change of a frame is the one that
    /// runs"). So the extra precision would have nowhere to go even if it were
    /// available — which is why this is an approximation rather than a
    /// deferral.
    ///
    /// The first render applies nothing: with no previous value there has been
    /// no change, as `onChange` without `initial:` likewise reports nothing.
    ///
    /// - Parameters:
    ///   - value: The value whose changes the transform is scoped to.
    ///   - transform: Receives the inherited transaction and modifies it in
    ///     place, on the frames `value` moved.
    /// - Returns: A view whose subtree sees the transformed transaction on
    ///   those frames.
    public func transaction<V: Equatable>(
        value: V,
        _ transform: @escaping (inout Transaction) -> Void
    ) -> some View {
        _ValueScopedTransactionView(content: self, value: value, transform: transform)
    }
}

/// Applies a transaction transform on the frames its value changed.
///
/// - Important: Framework infrastructure. Created by
///   ``View/transaction(value:_:)``.
public struct _ValueScopedTransactionView<Content: View, V: Equatable>: View {
    let content: Content
    let value: V
    let transform: (inout Transaction) -> Void

    public var body: Never {
        fatalError("_ValueScopedTransactionView renders via Renderable")
    }
}

extension _ValueScopedTransactionView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A measure pass is a question, not an update — and there are several
        // per frame, so comparing on one would consume the change before the
        // render could see it. The transaction has no geometric effect, so
        // measuring as a plain pass-through costs nothing. Same rule, and the
        // same reason, as `OnChangeModifier`.
        guard !context.isMeasuring, let storage = context.stateStorage else {
            return TUIkit.renderToBuffer(content, context: context)
        }
        // The comparison is per-frame work a cached buffer cannot reproduce: a
        // value-memoized subtree containing this would compare once and then
        // never notice another change.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        // A unique slot per modifier at this identity, claimed POSITIONALLY —
        // the same counter `onChange` uses, and needed for the same reason. A
        // `Renderable` adds no child identity, so two `.transaction(value:)`s
        // on one view render under the SAME `context.identity`; a fixed
        // property index would put both on one slot, and each would read the
        // other's previous value. Two independent values then fired each
        // other's transform, which is what the two-value case caught.
        let key = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: storage.nextOnChangeIndex(for: context.identity))
        let previous: V? = storage.trackedValue(for: key)
        storage.setTrackedValue(value, for: key)
        // Manual tracked values are pruned unless the identity is marked.
        storage.markActive(context.identity)

        guard let previous, previous != value else {
            return TUIkit.renderToBuffer(content, context: context)
        }
        var child = context
        transform(&child.environment.transaction)
        return TUIkit.renderToBuffer(content, context: child)
    }
}

extension _ValueScopedTransactionView: Layoutable {
    /// Measures as its content: a transaction moves nothing.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
