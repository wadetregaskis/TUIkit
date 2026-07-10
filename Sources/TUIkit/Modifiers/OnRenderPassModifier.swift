//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OnRenderPassModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - RenderPass

/// The kinds of per-frame work a view can participate in, reported by
/// ``SwiftUICore/View/onRenderPass(_:)``.
public enum RenderPass: Sendable, Equatable {
    /// The view was *measured* — its size was computed (`sizeThatFits`, or a
    /// measuring render), during the layout pass or by a parent sizing its
    /// children. A lazily-windowed container may measure views it never draws.
    case measure

    /// The view was *rendered* — its content was actually drawn into the
    /// frame's buffer.
    case render
}

// MARK: - OnRenderPass Modifier

/// Instrumentation wrapper behind ``SwiftUICore/View/onRenderPass(_:)``:
/// reports every measurement and every real render of its content.
struct OnRenderPassModifier<Content: View>: View {
    let content: Content
    let action: (RenderPass) -> Void

    var body: Never {
        fatalError("OnRenderPassModifier renders via Renderable")
    }
}

extension OnRenderPassModifier: Renderable, Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Observation must not be memoised away: a cached measurement that
        // skips this call would hide real layout participation from the
        // instrumentation. Declaring the side effect makes the memos decline.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        action(.measure)
        return measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        // A measuring render is still only sizing — the content isn't being
        // drawn to the screen buffer.
        action(context.isMeasuring ? .measure : .render)
        return TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - View Extension

extension View {
    /// Reports this view's participation in the frame's passes — every
    /// measurement (``RenderPass/measure``) and every real render
    /// (``RenderPass/render``).
    ///
    /// An instrumentation/debugging hook, TUI-specific (SwiftUI exposes no
    /// pass introspection): use it to observe *which* views a lazy container
    /// actually measures versus draws, or how often something re-renders. The
    /// action can fire several times per frame (parents may size a child more
    /// than once) and runs in the middle of layout/render — record into a
    /// plain sink and read it elsewhere; do NOT mutate view state from it.
    public func onRenderPass(_ action: @escaping (RenderPass) -> Void) -> some View {
        OnRenderPassModifier(content: self, action: action)
    }
}
