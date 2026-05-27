//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OnMouseEventModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - On Mouse Event Modifier

/// A modifier that subscribes a view to mouse events.
///
/// The modifier registers a handler with the per-frame
/// ``MouseEventDispatcher`` and emits a ``HitTestRegion`` whose
/// dimensions match the wrapped content's rendered bounds. When a
/// mouse event lands inside the region the dispatcher calls the
/// handler; once the handler claims a button-down event the
/// dispatcher routes every subsequent `.dragged` / `.released` event
/// for that button to the same handler regardless of where the cursor
/// actually is, so drag tracking works naturally.
public struct OnMouseEventModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The handler. Returns `true` if it consumed the event.
    let handler: (MouseEvent) -> Bool

    public var body: Never {
        fatalError("OnMouseEventModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension OnMouseEventModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Render first so the buffer dimensions are known; the
        // hit-test region we emit afterwards has to match the rendered
        // bounds exactly.
        var buffer = TUIkit.renderToBuffer(content, context: context)

        // No dispatcher (e.g. measure pass) — skip registration. The
        // measure path renders content for sizing but never sees a
        // real mouse event, so the registration would just churn ids.
        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        else {
            return buffer
        }

        let handlerID = dispatcher.register(handler)
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: handlerID
            )
        )
        return buffer
    }
}

// MARK: - Layoutable

extension OnMouseEventModifier: Layoutable {
    /// Forwards measurement straight to the content — the mouse
    /// modifier doesn't change layout.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
