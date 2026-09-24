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
        TUIkit.renderToBuffer(content, context: transformedContext(context) ?? context)
    }

    /// The context with the transform applied — on the frames `value` moved —
    /// or `nil` when it did not.
    ///
    /// Applied on BOTH walks. "A transaction moves nothing" was this file's
    /// original premise, and it is false: the transform can enable an
    /// animation on an animatable geometry value (`.padding`, `.frame`), and
    /// on the frame the value changes a measure that did not see the
    /// animation measured the TARGET while the render drew the START — the
    /// subtree was laid out for a frame that was not on screen.
    ///
    /// The change question is answered by ``AnimationStore/triggerChanged``,
    /// which records on render passes only — so every measure of a frame
    /// reaches the same answer its render will, no matter how many run, and
    /// none of them consumes the change. That also retires the positional
    /// `nextOnChangeIndex` slot this used to claim, which the measure walk
    /// could never share (claim order does not hold there). Distinctness of
    /// chained `.transaction(value:)`s now rides on the OWNER type instead:
    /// each wraps the previous, so `Content` — and with it `Self` — differs
    /// at every link of the chain.
    private func transformedContext(_ context: RenderContext) -> RenderContext? {
        guard let storage = context.stateStorage else { return nil }
        // The comparison is per-frame work a cached buffer OR a cached size
        // cannot reproduce: a memoized subtree containing this would compare
        // once and then never notice another change.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self))
        guard
            storage.animations.triggerChanged(
                value, for: key, isMeasuring: context.isMeasuring)
        else { return nil }
        var child = context
        transform(&child.environment.transaction)
        return child
    }
}

extension _ValueScopedTransactionView: Layoutable {
    /// Measures as its content — under the same transaction the render will
    /// use, so animatable geometry is measured where it is drawn.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: transformedContext(context) ?? context)
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension _ValueScopedTransactionView: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<Inner: View>(_ view: Inner) -> any View {
        _ValueScopedTransactionView<Inner, V>(content: view, value: value, transform: transform)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension _ValueScopedTransactionView: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension _ValueScopedTransactionView: GridRowProviding where Content: GridRowProviding {}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _ValueScopedTransactionView: DrawsContentUnchanged {}
