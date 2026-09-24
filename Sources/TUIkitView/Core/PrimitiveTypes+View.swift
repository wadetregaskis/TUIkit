//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PrimitiveTypes+View.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Never as View

/// `Never` conforms to View for views that have no body.
///
/// Primitive views like `Text` or containers like `TupleView` have no
/// body of their own - they are rendered directly. This extension allows
/// using `Never` as the body type.
extension Never: View {
    public var body: Never {
        fatalError("Never.body should never be called")
    }
}

// MARK: - Optional View Conformance

/// Optional views conform to View when their Wrapped type does.
extension Optional: View where Wrapped: View {
    public var body: some View {
        switch self {
        case .some(let view):
            view
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Optional Rendering

extension Optional: Renderable where Wrapped: View {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        switch self {
        case .some(let view):
            return TUIkitView.renderToBuffer(view, context: context)
        case .none:
            // An `if` without an `else` is the commonest way a view is removed,
            // and this slot is the only thing left of it: the view is gone from
            // the tree, so nothing else can play out its removal transition.
            // See ``DepartureStore``.
            return context.departingPicture() ?? FrameBuffer()
        }
    }
}

extension Optional: Layoutable where Wrapped: View {
    /// `.some` measures as the wrapped view; `.none` is empty. Forwarding keeps an
    /// optional view off ``measureChild``'s render-to-measure fallback.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        switch self {
        case .some(let view):
            return measureChild(view, proposal: proposal, context: context)
        case .none:
            // A view on its way out still holds its slot open, or the page
            // would close up around it on the first frame of the removal and
            // the transition would play in a space that had already gone.
            guard let leaving = context.departingSize() else { return ViewSize.fixed(0, 0) }
            return ViewSize.fixed(leaving.width, leaving.height)
        }
    }
}

extension RenderContext {
    /// The picture a view left at this identity, drawn part-way gone, or `nil`
    /// when nothing is leaving from here — what a `nil` optional draws.
    func departingPicture() -> FrameBuffer? {
        guard let store = stateStorage?.departures else { return nil }
        // One read for both halves — see `AnimatableResolution`.
        let frame = environment.animationFrame
        guard
            let picture = store.departing(
                at: identity, nowNanos: frame.nowNanos,
                frameAnimation: frame.canAnimate ? environment.transaction.effectiveAnimation : nil)
        else { return nil }
        declaresDepartureInFlight()
        return picture
    }

    /// The size a departing view is still holding open here, or `nil` — the
    /// measure walk's half of ``departingPicture()``.
    func departingSize() -> (width: Int, height: Int)? {
        guard let store = stateStorage?.departures else { return nil }
        let frame = environment.animationFrame
        guard
            let size = store.departingSize(
                at: identity, nowNanos: frame.nowNanos,
                frameAnimation: frame.canAnimate ? environment.transaction.effectiveAnimation : nil)
        else { return nil }
        declaresDepartureInFlight()
        return size
    }

    /// Tells any value memo enclosing this `nil` that it is drawing a removal
    /// part-way through, so the subtree it is in must not be stored.
    ///
    /// The picture is a function of the clock and of a store no memo keys on:
    /// the row, the `.equatable()` view or the `List` row around it compares
    /// equal on every frame of the removal, because the change that removed the
    /// view happened on the first one. Stored on that first frame — the row
    /// missed, its value having just changed, and nothing below it declared
    /// anything — it was served from the second on: the departing view stood
    /// frozen at the start of its removal, in the row it was holding open,
    /// until the row's value next changed. Nothing asked the store for the
    /// picture again, either, so the finished removal was never dropped.
    ///
    /// A render side effect, as a view whose value is still animating
    /// declares one (`ViewModifier._animated`): each frame of it is different,
    /// and the run loop, not the pulse timer, is what draws the next one.
    /// Declared on the measure walk too, since the size half of the memo would
    /// otherwise keep the held-open row's height past the end of the removal.
    /// Only while a removal is in flight: a `nil` nothing is leaving from
    /// declares nothing, and its subtree is stored exactly as before.
    private func declaresDepartureInFlight() {
        environment.volatileReadTracker?.recordRenderSideEffect()
    }
}
