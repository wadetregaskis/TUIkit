//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ChildInfo.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Child Info

/// A type-erased wrapper for a child view that enables two-pass layout.
///
/// This wrapper stores the view and allows measuring without rendering,
/// then rendering with a specific size allocation.
@MainActor
public struct ChildView {
    /// The wrapped child, stored as an existential so the (often large,
    /// deeply-generic) view value is boxed ONCE here rather than copied into a
    /// pair of measure / render closure contexts. `measureChild` / `renderChild`
    /// open it back to a concrete type via implicit existential opening.
    private let view: any View
    /// The type whose name forms this child's identity-path component, or `nil`
    /// when the child descends under the parent identity (no disambiguation).
    private let identityType: Any.Type?
    private let childIndex: Int

    /// Whether this child is a Spacer.
    public let isSpacer: Bool

    /// The minimum length of this spacer (only relevant if isSpacer is true).
    public let spacerMinLength: Int?

    public init<V: View>(_ view: V) {
        if let spacer = view as? SpacerProtocol {
            self.isSpacer = true
            self.spacerMinLength = spacer.spacerMinLength
        } else {
            self.isSpacer = false
            self.spacerMinLength = nil
        }

        self.view = view
        self.identityType = nil
        self.childIndex = 0
    }

    /// Creates a child view wrapper with an explicit child index for identity propagation.
    ///
    /// Use this initializer when wrapping children from a `TupleView` or similar
    /// container so that each child receives a unique `ViewIdentity` during
    /// measure and render passes.
    ///
    /// - Parameters:
    ///   - view: The child view to wrap.
    ///   - childIndex: The positional index used for identity disambiguation.
    public init<V: View>(_ view: V, childIndex: Int) {
        if let spacer = view as? SpacerProtocol {
            self.isSpacer = true
            self.spacerMinLength = spacer.spacerMinLength
        } else {
            self.isSpacer = false
            self.spacerMinLength = nil
        }

        self.view = view
        self.identityType = V.self
        self.childIndex = childIndex
    }

    /// Creates a child wrapper that renders `view` but derives its per-child
    /// identity from a *different* type `IdentityType`.
    ///
    /// Used when a row is wrapped in a transparent helper (e.g. `_MemoizedRow`)
    /// that must not appear in the identity path: pass the wrapper as `view` and
    /// the original content type as `identityType`, so the child's
    /// `ViewIdentity` — and thus its `@State` / focus slots — is exactly what it
    /// would be unwrapped. The wrapper itself adds no identity (it is
    /// `Renderable`), so the inner content keeps the same identity either way.
    ///
    /// - Parameters:
    ///   - view: The (possibly wrapped) view to measure and render.
    ///   - identityType: The type whose name forms the identity path component.
    ///   - childIndex: The positional index used for identity disambiguation.
    public init<V: View, IdentityType>(
        _ view: V, identityType: IdentityType.Type, childIndex: Int
    ) {
        if let spacer = view as? SpacerProtocol {
            self.isSpacer = true
            self.spacerMinLength = spacer.spacerMinLength
        } else {
            self.isSpacer = false
            self.spacerMinLength = nil
        }

        self.view = view
        self.identityType = identityType
        self.childIndex = childIndex
    }

    /// Measures this child view without rendering.
    public func measure(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(view, proposal: proposal, context: childContext(context))
    }

    /// Renders this child view with the given size allocation.
    public func render(width: Int, height: Int, context: RenderContext) -> FrameBuffer {
        renderChild(view, width: width, height: height, context: childContext(context))
    }

    /// The context to measure / render the child in: the parent context with
    /// this child's identity appended, or the parent context unchanged when
    /// `identityType` is `nil` (the no-disambiguation initializer).
    private func childContext(_ context: RenderContext) -> RenderContext {
        guard let identityType else { return context }
        return context.withChildIdentity(erasedType: identityType, index: childIndex)
    }
}

/// A view that carries an explicit z-index for sibling draw ordering.
///
/// Implemented by the wrapper produced by `View.zIndex(_:)`. Container views
/// that overlap their children — notably `ZStack` — read this to decide the
/// order in which children are drawn.
@MainActor
public protocol ZIndexProviding {
    /// The z-index of the view. Higher values draw later (on top).
    var zIndexValue: Double { get }
}

/// Describes a child view within a stack for layout purposes.
public struct ChildInfo {
    /// The rendered buffer of this child (nil for spacers, computed later).
    public let buffer: FrameBuffer?

    /// Whether this child is a Spacer.
    public let isSpacer: Bool

    /// The minimum length of this spacer (only relevant if isSpacer is true).
    public let spacerMinLength: Int?

    /// The size this child needs (from sizeThatFits).
    /// Only available when using two-pass layout.
    public let size: ViewSize?

    /// The child's explicit z-index (`0` unless set via `View.zIndex(_:)`).
    ///
    /// Overlapping containers like `ZStack` draw children in ascending order
    /// of this value; ties keep their original tree order.
    public let zIndex: Double

    /// Creates a new child info.
    public init(
        buffer: FrameBuffer?,
        isSpacer: Bool,
        spacerMinLength: Int?,
        size: ViewSize?,
        zIndex: Double = 0
    ) {
        self.buffer = buffer
        self.isSpacer = isSpacer
        self.spacerMinLength = spacerMinLength
        self.size = size
        self.zIndex = zIndex
    }
}

// MARK: - Child Info Provider

/// Internal protocol that allows stack containers to extract individual
/// child info from their content (which is typically a TupleView).
@MainActor
public protocol ChildInfoProvider {
    /// Returns an array of ``ChildInfo``, one per child view.
    ///
    /// - Parameter context: The rendering context for child rendering.
    /// - Returns: An array of child descriptions for layout.
    func childInfos(context: RenderContext) -> [ChildInfo]
}

// MARK: - Child View Provider

/// Protocol for views that can provide type-erased children for two-pass layout.
///
/// This enables measuring children before rendering them with final sizes.
@MainActor
public protocol ChildViewProvider {
    /// Returns an array of type-erased child views for two-pass layout.
    ///
    /// - Parameter context: The rendering context (for child identity).
    /// - Returns: An array of ``ChildView`` wrappers.
    func childViews(context: RenderContext) -> [ChildView]
}

/// Creates a ChildInfo for a single view.
///
/// If the view conforms to ``SpacerProtocol``, the returned info marks it as such
/// with its minimum length. Otherwise the view is rendered into a
/// ``FrameBuffer`` via ``renderToBuffer(_:context:)``.
///
/// - Parameters:
///   - view: The child view.
///   - context: The rendering context.
/// - Returns: A ``ChildInfo`` describing the view.
@MainActor
public func makeChildInfo<V: View>(for view: V, context: RenderContext) -> ChildInfo {
    let zIndex = (view as? ZIndexProviding)?.zIndexValue ?? 0
    if let spacer = view as? SpacerProtocol {
        return ChildInfo(
            buffer: nil,
            isSpacer: true,
            spacerMinLength: spacer.spacerMinLength,
            size: nil,
            zIndex: zIndex
        )
    }
    return ChildInfo(
        buffer: renderToBuffer(view, context: context),
        isSpacer: false,
        spacerMinLength: nil,
        size: nil,
        zIndex: zIndex
    )
}

// MARK: - Two-Pass Layout Support

/// Measures a child view without rendering it.
///
/// Uses `sizeThatFits` if the view is `Layoutable`, otherwise falls back
/// to rendering and measuring the buffer.
///
/// - Parameters:
///   - view: The child view.
///   - proposal: The proposed size from the parent.
///   - context: The rendering context.
/// - Returns: The size this view needs.
@MainActor
public func measureChild<V: View>(_ view: V, proposal: ProposedSize, context: RenderContext) -> ViewSize {
    // Use Layoutable if available (mark as measuring to suppress side-effects).
    //
    // Spacer is handled here too: it conforms to `Layoutable` and its
    // `sizeThatFits` returns the same fully-flexible size a dedicated
    // `SpacerProtocol` branch would build by hand — so checking `as?
    // SpacerProtocol` first only added a redundant runtime conformance cast to
    // EVERY measured child (Spacer is the sole conformer and is `Layoutable`).
    // `SpacerProtocol` is still used by the stacks for fill distribution.
    if let layoutable = view as? Layoutable {
        var measureContext = context
        measureContext.isMeasuring = true
        return layoutable.sizeThatFits(proposal: proposal, context: measureContext)
    }

    // For composite views (Body != Never, NOT Renderable), traverse into
    // the body to find an inner Layoutable. This handles cases like
    // TextField<Text> whose body is _TextFieldCore<Text> which IS Layoutable.
    //
    // Skip Renderable views: their rendering logic (including environment
    // injection) lives in renderToBuffer, not in body. They fall through
    // to the render-to-measure fallback below, which runs the full pipeline.
    if !(view is Renderable), V.Body.self != Never.self {
        // Descend into the body under the SAME child identity `renderToBuffer`
        // uses (it appends the body type via `withChildIdentity`). Measuring
        // under the parent identity instead made the measure pass hydrate a
        // composite view's `@State` from a different slot than the render pass,
        // so a state-dependent view could measure a different size than it
        // rendered. Hydration still keys off `context` (the parent), exactly as
        // render does; only the recursion descends with the child identity.
        let childContext = context.withChildIdentity(type: V.Body.self)
        let body = StateRegistration.withHydration(context: context) {
            view.body
        }
        return measureChild(body, proposal: proposal, context: childContext)
    }

    // Fallback: render to measure (without side-effects)
    var measureContext = context
    measureContext.isMeasuring = true
    // Clear hasExplicitWidth so views report their natural (minimum) size
    // instead of expanding to fill the full available width.
    measureContext.hasExplicitWidth = false
    if let width = proposal.width {
        measureContext.availableWidth = width
    }
    if let height = proposal.height {
        measureContext.availableHeight = height
    }
    let buffer = renderToBuffer(view, context: measureContext)
    let naturalWidth = buffer.width

    // Determine width-flexibility by observation rather than by guessing
    // from the parent's `hasExplicitWidth`. Render again with more room
    // and see whether the view actually grows: a fixed view (a `Text`, or
    // a size-preserving modifier such as `.background()` wrapped around
    // one) renders the same width, while a genuinely flexible view
    // expands. The old heuristic flagged *every* modified view in an
    // explicit-width context as flexible, which made a backgrounded
    // `Text` get shrunk ahead of its fixed siblings in a stack.
    var probeContext = measureContext
    probeContext.availableWidth = naturalWidth + 8
    let probedWidth = renderToBuffer(view, context: probeContext).width

    if probedWidth > naturalWidth {
        return ViewSize.flexibleWidth(minWidth: naturalWidth, height: buffer.height)
    }
    return ViewSize.fixed(naturalWidth, buffer.height)
}

/// Measures a fixed-size view by rendering it ONCE in measuring mode and
/// reporting the result as a fixed size.
///
/// The measure-pass twin of `measureChild`'s render-to-measure fallback for the
/// common case of a control that never grows to fill — a `Button`, `Toggle`,
/// `Stepper`, and the like. That fallback renders such a view *twice* (once at
/// the proposal, once at `naturalWidth + 8` to probe width-flexibility) only to
/// conclude it is fixed. A view that is known to be fixed skips the probe:
/// render once, report fixed — halving the measure cost.
///
/// The single render goes through the same clamped `renderToBuffer(_:context:)`
/// the real layout pass uses, and sets `isMeasuring` / `hasExplicitWidth`
/// exactly as the fallback's first render does, so the size reported here is
/// identical to the fallback's `naturalWidth` and to what render produces.
///
/// - Parameters:
///   - view: The fixed-size view.
///   - proposal: The proposed size from the parent.
///   - context: The rendering context.
/// - Returns: The view's size, always reported as fixed.
@MainActor
public func measureFixedByRendering<V: View>(_ view: V, proposal: ProposedSize, context: RenderContext) -> ViewSize {
    var measureContext = context
    measureContext.isMeasuring = true
    // Report the natural (minimum) size, not an expanded one — as the fallback does.
    measureContext.hasExplicitWidth = false
    if let width = proposal.width {
        measureContext.availableWidth = width
    }
    if let height = proposal.height {
        measureContext.availableHeight = height
    }
    let buffer = renderToBuffer(view, context: measureContext)
    return ViewSize.fixed(buffer.width, buffer.height)
}

/// Renders a child view with a specific size allocation.
///
/// - Parameters:
///   - view: The child view.
///   - width: The allocated width.
///   - height: The allocated height.
///   - context: The rendering context.
/// - Returns: The rendered buffer.
@MainActor
public func renderChild<V: View>(_ view: V, width: Int, height: Int, context: RenderContext) -> FrameBuffer {
    var renderContext = context
    renderContext.availableWidth = width
    renderContext.availableHeight = height
    // Safety net: a child must never exceed the space allocated to it,
    // otherwise it would overwrite a sibling or overflow the stack.
    return renderToBuffer(view, context: renderContext).clamped(toWidth: width, height: height)
}

// MARK: - Child Info Resolution

/// Resolves child infos from a view's content.
///
/// If the content conforms to ``ChildInfoProvider`` (e.g. TupleViews),
/// it returns individual child infos. Otherwise it returns the content
/// as a single-element array.
///
/// - Parameters:
///   - content: The content view.
///   - context: The rendering context.
/// - Returns: An array of ``ChildInfo``.
@MainActor
public func resolveChildInfos<V: View>(from content: V, context: RenderContext) -> [ChildInfo] {
    if let provider = content as? ChildInfoProvider {
        return provider.childInfos(context: context)
    }
    return [makeChildInfo(for: content, context: context)]
}

// MARK: - Two-Pass Layout Resolution

/// Resolves child views from a view's content for two-pass layout.
///
/// If the content conforms to ``ChildViewProvider`` (e.g. TupleViews),
/// it returns individual child views. Otherwise it wraps the content
/// in a single-element array.
///
/// - Parameters:
///   - content: The content view.
///   - context: The rendering context.
/// - Returns: An array of ``ChildView``.
@MainActor
public func resolveChildViews<V: View>(from content: V, context: RenderContext) -> [ChildView] {
    if let provider = content as? ChildViewProvider {
        return provider.childViews(context: context)
    }
    return [ChildView(content)]
}
