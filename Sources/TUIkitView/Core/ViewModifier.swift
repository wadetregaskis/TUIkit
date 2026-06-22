//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// A modifier that transforms a view's rendered output.
///
/// `ViewModifier` works on the `FrameBuffer` level: it takes a rendered
/// buffer and returns a transformed buffer. This allows modifiers like
/// `.padding()` and `.frame()` to manipulate layout after rendering.
///
/// # Example
///
/// ```swift
/// struct MyModifier: ViewModifier {
///     func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
///         // transform the buffer
///         return buffer
///     }
/// }
/// ```
@MainActor
public protocol ViewModifier {
    /// Transforms a rendered buffer.
    ///
    /// - Parameters:
    ///   - buffer: The rendered content of the wrapped view.
    ///   - context: The rendering context.
    /// - Returns: The modified buffer.
    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer

    /// Adjusts the rendering context before the wrapped content is rendered.
    ///
    /// Override this method in modifiers that consume space (like padding)
    /// to reduce `availableWidth` or `availableHeight` so that flexible
    /// child views size themselves correctly.
    ///
    /// The default implementation returns the context unchanged.
    ///
    /// - Parameter context: The current rendering context.
    /// - Returns: The adjusted context for content rendering.
    func adjustContext(_ context: RenderContext) -> RenderContext
}

extension ViewModifier {
    public func adjustContext(_ context: RenderContext) -> RenderContext {
        context
    }
}

// MARK: - ModifiedView

/// A view that wraps another view with a modifier.
///
/// This is the return type of modifier methods like `.frame()` and `.padding()`.
/// It is created automatically — users don't instantiate this directly.
///
/// `ModifiedView` is a **primitive view**: it declares `body: Never`
/// and conforms to `Renderable`. The rendering system calls
/// `renderToBuffer(context:)` which first renders the
/// wrapped `content`, then applies the modifier's transformation.
/// The `body` property is never called.
///
/// - Important: This is framework infrastructure. Created automatically by
///   `.modifier()`. Do not instantiate directly.
public struct ModifiedView<Content: View, Modifier: ViewModifier>: View {
    /// The original view.
    public let content: Content

    /// The modifier to apply.
    public let modifier: Modifier

    /// Creates a modified view.
    ///
    /// - Parameters:
    ///   - content: The original view.
    ///   - modifier: The modifier to apply.
    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }

    /// Never called — rendering is handled by `Renderable` conformance.
    public var body: Never {
        fatalError("ModifiedView renders via Renderable")
    }
}

// MARK: - ModifiedView Rendering

extension ModifiedView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let adjustedContext = modifier.adjustContext(context)
        let childBuffer = TUIkitView.renderToBuffer(content, context: adjustedContext)
        var result = modifier.modify(buffer: childBuffer, context: context)

        // Overlay-layer safety net: if the modifier produced a buffer without
        // overlay layers but the wrapped content carried some, re-attach them.
        // Modifiers that reposition content (padding, …) attach their own
        // shifted layers, so this only fires for transform-in-place modifiers
        // (background, foreground colour, …) that leave content where it is.
        if result.overlays.isEmpty && !childBuffer.overlays.isEmpty {
            result.overlays = childBuffer.overlays
        }
        return result
    }
}

// MARK: - Layoutable

extension ModifiedView: Layoutable {
    /// Measures the wrapped content through the modifier without rendering it.
    ///
    /// `Renderable` views without a `Layoutable` conformance fall through to
    /// `measureChild`'s render-to-measure fallback (a single `renderToBuffer` —
    /// historically two, with a `naturalWidth + 8` flexibility probe since
    /// retired). Rendering to measure is a disaster for expensive content (an
    /// `Image` whose `renderToBuffer` runs the ASCII converter, for example)
    /// wrapped in even one `.padding()` or custom modifier — so forward instead.
    ///
    /// Forwards measurement to the content under the modifier's
    /// `adjustContext`, then adds the per-axis delta the modifier shrank
    /// off back onto the reported size. For modifiers that don't adjust
    /// the context — colour, background, etc. — the delta is zero and we
    /// just report the child's size. For modifiers that do (padding), the
    /// caller sees the post-modifier dimensions, which matches what
    /// `renderToBuffer` would produce.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let adjustedContext = modifier.adjustContext(context)
        let widthDelta = max(0, context.availableWidth - adjustedContext.availableWidth)
        let heightDelta = max(0, context.availableHeight - adjustedContext.availableHeight)

        // Propagate the modifier's shrink to the proposal too, so a flex
        // child still treats the remaining space as its budget.
        var adjustedProposal = proposal
        if let proposedWidth = proposal.width {
            adjustedProposal = ProposedSize(
                width: max(0, proposedWidth - widthDelta),
                height: proposal.height
            )
        }
        if let proposedHeight = adjustedProposal.height {
            adjustedProposal = ProposedSize(
                width: adjustedProposal.width,
                height: max(0, proposedHeight - heightDelta)
            )
        }

        let childSize = measureChild(content, proposal: adjustedProposal, context: adjustedContext)
        return ViewSize(
            width: childSize.width + widthDelta,
            height: childSize.height + heightDelta,
            isWidthFlexible: childSize.isWidthFlexible,
            isHeightFlexible: childSize.isHeightFlexible
        )
    }
}
