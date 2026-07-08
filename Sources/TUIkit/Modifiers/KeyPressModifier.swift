//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyPressModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that adds a key press handler to a view.
///
/// The handler returns a Bool indicating whether the event was consumed.
/// If false is returned, the event continues to propagate to other handlers.
public struct KeyPressModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The keys to listen for (nil = all keys).
    let keys: Set<Key>?

    /// The handler to call when a matching key is pressed.
    /// Returns true if the event was handled, false to let it propagate.
    let handler: (KeyEvent) -> Bool

    public var body: Never {
        fatalError("KeyPressModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension KeyPressModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The registration is a render-pass side effect, twice over:
        // - never during a measure pass — a render-to-measure ancestor would
        //   register a SECOND handler for the same modifier within the frame,
        //   running the action twice per keypress;
        // - always declared to any value-memoizing ancestor — the dispatcher
        //   clears its handlers every frame, so a cached row would stop
        //   re-registering and its onKeyPress would go dead while the row is
        //   still on screen.
        guard !context.isMeasuring else {
            return TUIkit.renderToBuffer(content, context: context)
        }
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        // Register the key handler
        context.environment.keyEventDispatcher!.addHandler { [keys, handler] event in
            // Check if we should handle this key
            if let allowedKeys = keys {
                guard allowedKeys.contains(event.key) else {
                    return false
                }
            }

            // Call handler and return whether it consumed the event
            return handler(event)
        }

        // Render the content
        return TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - Layoutable

extension KeyPressModifier: Layoutable {
    /// Behaviour-only decorator — it renders `content` unchanged. Forwarding the
    /// measure keeps it off ``measureChild``'s render-to-measure fallback and lets
    /// the wrapped view's flexibility propagate.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
