//  🖥️ TUIKit — Terminal UI Kit for Swift
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
            return context.stateStorage?.departures.departing(
                at: context.identity, nowNanos: context.environment.frameNowNanos)
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
                let leaving = context.stateStorage?.departures.departingSize(
                    at: context.identity, nowNanos: context.environment.frameNowNanos)
            else { return ViewSize.fixed(0, 0) }
            return ViewSize.fixed(leaving.width, leaving.height)
        }
    }
}
