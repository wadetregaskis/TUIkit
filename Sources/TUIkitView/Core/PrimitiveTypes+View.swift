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
            // See ``DepartureStore``. Rendered directly, an optional hands its
            // view its own identity, so the picture here was left by the
            // innermost view through nested optionals and the wrappers that
            // draw their content unchanged: `X` for `if a { if b { X } }`.
            return context.departingPicture(of: departingPictureType(heldAs: Wrapped.self))
                ?? FrameBuffer()
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
            guard
                let leaving = context.departingSize(of: departingPictureType(heldAs: Wrapped.self))
            else { return ViewSize.fixed(0, 0) }
            return ViewSize.fixed(leaving.width, leaving.height)
        }
    }
}

// MARK: - The slot a removal plays in

/// What a `nil` in a stack keeps in the slot its view left, while that view's
/// removal plays: the picture the view left behind, part-way gone, at the size
/// it had.
///
/// A view of its own rather than the `nil` itself, because the flattening
/// claim has already established WHICH view left from here (`viewType`) and
/// the `nil`'s own type need not say so — see `Optional`'s
/// `ChildViewProvider` conformance.
struct DepartureSlot: View {
    /// The view that left: only a picture it left behind is drawn.
    let viewType: Any.Type

    var body: Never {
        fatalError("DepartureSlot renders via Renderable")
    }
}

extension DepartureSlot: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.departingPicture(of: viewType) ?? FrameBuffer()
    }
}

extension DepartureSlot: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let leaving = context.departingSize(of: viewType) else { return ViewSize.fixed(0, 0) }
        return ViewSize.fixed(leaving.width, leaving.height)
    }
}

extension RenderContext {
    /// The picture a view of `type` left at this identity, drawn part-way gone,
    /// or `nil` when nothing of that type is leaving from here.
    ///
    /// Asked of every `nil` on every walk, so the store's emptiness comes
    /// first, and `type` is only worked out when something might be leaving:
    /// a `nil` in an app that animates nothing pays one check.
    func departingPicture(of type: @autoclosure () -> Any.Type) -> FrameBuffer? {
        guard let store = stateStorage?.departures, !store.isEmpty else { return nil }
        // One read for both halves — see `AnimatableResolution`.
        let frame = environment.animationFrame
        guard
            let picture = store.departing(
                at: identity, ofType: type(), nowNanos: frame.nowNanos,
                frameAnimation: frame.canAnimate ? environment.transaction.effectiveAnimation : nil)
        else { return nil }
        declaresDepartureInFlight()
        return picture
    }

    /// The size a departing view of `type` is still holding open here, or
    /// `nil` — the measure walk's half of ``departingPicture(of:)``.
    func departingSize(of type: @autoclosure () -> Any.Type) -> (width: Int, height: Int)? {
        guard let store = stateStorage?.departures, !store.isEmpty else { return nil }
        let frame = environment.animationFrame
        guard
            let size = store.departingSize(
                at: identity, ofType: type(), nowNanos: frame.nowNanos,
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
