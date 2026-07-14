//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OnHoverModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - On Hover Modifier

/// A modifier that fires a callback when the cursor enters or
/// leaves the wrapped view's hit region.
///
/// `OnHoverModifier` participates in TUIkit's hover state
/// machine, which lives in ``MouseEventDispatcher``: bare
/// `.moved` events on the dispatcher synthesise `.entered` /
/// `.exited` transitions whenever the cursor crosses a region
/// boundary. The modifier registers a handler that reacts to
/// only those synthetic phases — never raw motion — and
/// surfaces them through a SwiftUI-compatible callback shape.
///
/// The modifier also calls
/// ``MouseEventDispatcher/requestFeature(_:)`` every frame with
/// `.motion`, so the terminal switches into any-event
/// mouse-tracking mode while the view is on screen. Once the
/// view disappears the request is no longer made and the
/// dispatcher relaxes back to whatever the base scene-level
/// ``MouseSupport`` configuration set.
public struct OnHoverModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The hover callback. Receives `true` when the cursor
    /// enters the view's hit region, `false` when it leaves.
    let action: @MainActor (Bool) -> Void

    public var body: Never {
        fatalError("OnHoverModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension OnHoverModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)

        // SwiftUI parity (verified empirically on macOS 15): a hover callback
        // registered INSIDE a `.disabled(true)` scope never fires, while one
        // attached outside the disabled subtree (`.disabled(true).onHover`)
        // still does. Gating on the environment's `isEnabled` reproduces that
        // scoping exactly — the outer-attachment case renders this modifier
        // with an enabled environment.
        guard !context.isMeasuring,
              context.environment.isEnabled,
              let dispatcher = context.environment.mouseEventDispatcher
        else {
            return buffer
        }

        // Ask the dispatcher to enable motion reporting for this
        // frame — necessary because the terminal only emits
        // `.moved` events when motion tracking is active.
        dispatcher.requestFeature(.motion)

        let capturedAction = action
        let handlerID = dispatcher.register { event in
            switch event.phase {
            case .entered:
                capturedAction(true)
                return true
            case .exited:
                capturedAction(false)
                return true
            default:
                // Don't claim any non-hover event so other
                // siblings / parents still get a shot at it
                // (especially clicks and wheel scrolling).
                return false
            }
        }
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

extension OnHoverModifier: Layoutable {
    /// Forwards measurement straight to the content — the
    /// hover modifier doesn't change layout.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - View Extension

extension View {
    /// Adds an action to perform when the cursor enters or
    /// leaves the view's hit region.
    ///
    /// SwiftUI-compatible signature. The closure receives
    /// `true` on enter, `false` on leave — driven by the
    /// dispatcher's hover state machine, not by raw motion, so
    /// transitions are de-duplicated and only fire on actual
    /// region crossings.
    ///
    /// > Note: Hover requires the terminal's any-event motion
    ///   reporting mode. This modifier requests it
    ///   automatically per-frame; the AppRunner unions the
    ///   request with the base ``MouseSupport`` configuration
    ///   each frame.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Hover me")
    ///     .onHover { isHovered in
    ///         print(isHovered ? "in" : "out")
    ///     }
    /// ```
    ///
    /// - Parameter action: A closure invoked with `true` when
    ///   the cursor enters and `false` when it leaves.
    /// - Returns: A view that reports cursor enter / exit
    ///   transitions to `action`.
    public func onHover(_ action: @escaping @MainActor (Bool) -> Void) -> some View {
        OnHoverModifier(content: self, action: action)
    }
}
