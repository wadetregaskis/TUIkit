//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BehindContentTapModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A left-click target BEHIND its content rather than in front of it.
///
/// ``OnMouseEventModifier`` — and so `.onTapGesture` — appends its region after the
/// content's, which makes it the innermost match on every cell: it takes each click
/// from whatever it wraps, and a `Button` inside never sees one. This inserts its region
/// at index 0 instead, the fallback-region convention `_ListCore`, `.contextMenu` and
/// `ScrollView` already follow inline. A control inside wins its own clicks, and a
/// click that lands on nothing interactive reaches this.
///
/// For a row whose label should do what its control does, where the control and any
/// interactive content in the label must keep their own clicks.
struct _BehindContentTapModifier<Content: View>: View {
    let content: Content

    /// Run on the release of a left click this region claimed.
    let action: () -> Void

    var body: Never {
        fatalError("_BehindContentTapModifier renders via Renderable")
    }
}

extension _BehindContentTapModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)
        // A measure sees no events, and a disabled view takes none — the rule
        // `Button` applies to itself.
        guard !context.isMeasuring, context.environment.isEnabled,
            let dispatcher = context.environment.mouseEventDispatcher,
            buffer.width > 0, buffer.height > 0
        else { return buffer }
        let action = self.action
        let handlerID = dispatcher.register(in: context) { event in
            guard event.button == .left else { return false }
            switch event.phase {
            // Claimed, so the release routes back here even if the pointer moved.
            case .pressed: return true
            case .released:
                action()
                return true
            default: return false
            }
        }
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                handlerID: handlerID),
            at: 0)
        return buffer
    }
}

extension _BehindContentTapModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
