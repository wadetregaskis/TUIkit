//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// Static witness: whether this modifier type nominates something
    /// continuous about itself — that is, whether it conforms to ``Animatable``.
    ///
    /// The same shape and the same measured reason as ``View/_isAnimatable``,
    /// and it exists separately because a *conditional* conformance cannot
    /// supply that witness: `ModifiedView` is `Animatable` only when its
    /// modifier is, so Swift picks the unconstrained default for it and the
    /// answer would always be `false`. `ModifiedView` forwards to this instead,
    /// which stays a constant the specialiser can fold.
    ///
    /// Not to be implemented by hand: conform to ``Animatable`` instead.
    static var _isAnimatable: Bool { get }

    /// Static witness: this modifier at the value the animation store says to
    /// draw it at, or `nil` when nothing is moving. See
    /// ``View/_animated(_:context:isMeasuring:)`` for why it is a witness
    /// rather than an existential cast.
    ///
    /// `owner` is passed in rather than taken as `Self` so the store key stays
    /// the `ModifiedView`'s own generic type — which distinguishes two of the
    /// same modifier nested around one view, where the modifier type alone
    /// would not.
    @MainActor
    static func _animated(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self?

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
    /// Passes the context through unchanged.
    ///
    /// The default, and the right answer for any modifier that only rewrites
    /// the buffer its content produced. Override it when the modifier changes
    /// the space the content is being offered — padding and borders reduce
    /// `availableWidth`/`availableHeight` here so a flexible child fills the
    /// interior rather than the whole box and then overflows it.
    ///
    /// - Parameter context: The context this modifier was reached with.
    /// - Returns: The context its content should render under.
    public func adjustContext(_ context: RenderContext) -> RenderContext {
        context
    }

    /// A modifier says nothing continuous about itself unless it is
    /// ``Animatable``.
    @inlinable
    public static var _isAnimatable: Bool { false }

    /// A modifier with nothing continuous about it never needs substituting.
    @inlinable
    public static func _animated(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        nil
    }
}

extension ViewModifier where Self: Animatable {
    /// An ``Animatable`` modifier's data is substituted before its view
    /// renders, exactly as an animatable view's is.
    @inlinable
    public static var _isAnimatable: Bool { true }

    /// This modifier at the value the store says to draw it at.
    @MainActor
    public static func _animated(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        guard let storage = context.stateStorage else { return nil }
        let animation = context.environment.canAnimate
            ? context.environment.transaction.effectiveAnimation : nil
        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(owner))
        let target = modifier.animatableData
        let drawn = storage.animations.value(
            for: key, target: target, animation: animation,
            nowNanos: context.environment.frameNowNanos, isMeasuring: isMeasuring)
        guard drawn != target else { return nil }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        var copy = modifier
        copy.animatableData = drawn
        return copy
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
    ///
    /// A `var` only so an animatable modifier's data can be substituted before
    /// the view renders; nothing else mutates it.
    public var modifier: Modifier

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

// MARK: - Animating a modifier

extension ModifiedView: Animatable where Modifier: Animatable {
    /// A modified view's animatable data is its modifier's.
    ///
    /// The general route by which a *modifier* animates — `.padding`,
    /// `.offset`, and any `ViewModifier` an app writes. It is where SwiftUI
    /// puts it too (`ModifiedContent: Animatable where Modifier: Animatable`),
    /// and it means a modifier author declares one property rather than
    /// learning anything about the render pipeline.
    public var animatableData: Modifier.AnimatableData {
        get { modifier.animatableData }
        set { modifier.animatableData = newValue }
    }
}

extension ModifiedView {
    /// Forwarded from the modifier.
    ///
    /// **Unconditional**, deliberately: the `Animatable` conformance above is
    /// conditional, so a witness declared inside it cannot satisfy the
    /// *unconditional* `View` conformance — Swift falls back to the `false`
    /// default and every animated modifier silently stops animating. Which is
    /// exactly what happened, and what the padding test caught.
    @inlinable
    public static var _isAnimatable: Bool { Modifier._isAnimatable }

    /// Forwarded to the modifier, for the same reason and with the same
    /// unconditional placement as ``_isAnimatable``.
    @MainActor
    public static func _animated(
        _ view: Self, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        guard let animated = Modifier._animated(
            view.modifier, owner: Self.self, context: context, isMeasuring: isMeasuring)
        else { return nil }
        var copy = view
        copy.modifier = animated
        return copy
    }
}
