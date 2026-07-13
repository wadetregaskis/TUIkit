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
    /// When set, the child's identity is keyed by this stable string (a
    /// `ForEach` element's id) instead of `childIndex` — identity then follows
    /// the element across reorders, as SwiftUI's `ForEach` contract requires.
    private let identityKey: String?

    /// Whether this child is a Spacer.
    public let isSpacer: Bool

    /// The minimum length of this spacer (only relevant if isSpacer is true).
    public let spacerMinLength: Int?

    /// The child's explicit z-index (`0` unless set via `View.zIndex(_:)`).
    /// Overlapping containers like `ZStack` draw children in ascending order
    /// of this value; ties keep their original tree order.
    public let zIndex: Double

    /// Resolves a child's spacer flag and minimum length without a speculative
    /// runtime conformance cast on the common (non-spacer) path.
    ///
    /// The static witness ``View/_isSpacer`` answers the detection per type
    /// (`false` for everything but `Spacer`); only the rare spacer is then cast
    /// to `SpacerProtocol` to read its `spacerMinLength`.
    static func spacerInfo<V: View>(of view: V) -> (isSpacer: Bool, minLength: Int?) {
        guard V._isSpacer else { return (false, nil) }
        return (true, (view as? SpacerProtocol)?.spacerMinLength)
    }

    /// Resolves a child's z-index without a speculative runtime conformance
    /// cast on the common path — same shape as ``spacerInfo(of:)``, using the
    /// static witness ``View/_providesZIndex``.
    static func zIndexInfo<V: View>(of view: V) -> Double {
        V._providesZIndex ? ((view as? ZIndexProviding)?.zIndexValue ?? 0) : 0
    }

    public init<V: View>(_ view: V) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.view = view
        self.identityType = nil
        self.childIndex = 0
        self.identityKey = nil
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
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.view = view
        self.identityType = V.self
        self.childIndex = childIndex
        self.identityKey = nil
    }

    /// Full-field copy initializer backing ``reindexed(to:)``.
    private init(
        view: any View,
        identityType: Any.Type?,
        childIndex: Int,
        identityKey: String?,
        isSpacer: Bool,
        spacerMinLength: Int?,
        zIndex: Double
    ) {
        self.view = view
        self.identityType = identityType
        self.childIndex = childIndex
        self.identityKey = identityKey
        self.isSpacer = isSpacer
        self.spacerMinLength = spacerMinLength
        self.zIndex = zIndex
    }

    /// A copy whose positional identity is rebased to `index`.
    ///
    /// When a provider's flattened children are spliced into an enclosing
    /// container's child list, their identity must reflect the FLATTENED
    /// position — two same-typed children contributed by different providers
    /// (two `Group`s, two `if` branches) would otherwise carry identical
    /// (type, inner-index) identities and collide in `StateStorage` (the
    /// second silently adopts the first's state and focus slots). Children
    /// with a stable `identityKey` (`ForEach` rows) keep it and are returned
    /// unchanged; a child with no identity type adopts its view's dynamic
    /// type, matching what it would get as a direct tuple child.
    func reindexed(to index: Int) -> Self {
        guard identityKey == nil else { return self }
        return Self(
            view: view,
            identityType: identityType ?? type(of: view),
            childIndex: index,
            identityKey: nil,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex)
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
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.view = view
        self.identityType = identityType
        self.childIndex = childIndex
        self.identityKey = nil
    }

    /// Creates a child wrapper whose per-child identity is keyed by a stable
    /// string (a `ForEach` element's id) under `identityType`, rather than by
    /// a positional index — see ``ViewIdentity/child(erasedType:key:)``.
    public init<V: View, IdentityType>(
        _ view: V, identityType: IdentityType.Type, key: String
    ) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.view = view
        self.identityType = identityType
        self.childIndex = 0
        self.identityKey = key
    }

    /// The wrapped child view itself, for containers that need to inspect the
    /// original view value — e.g. `List` peeling a `.badge(_:)` wrapper off a
    /// row — rather than measure or render it.
    public var wrappedView: any View { view }

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
        if let identityKey {
            return context.withChildIdentity(erasedType: identityType, key: identityKey)
        }
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
    // Static witnesses gate the rare conformance casts: only a z-index wrapper
    // is cast to `ZIndexProviding`, only a spacer to `SpacerProtocol`. The common
    // child (neither) does no speculative cast at all.
    let zIndex = V._providesZIndex ? ((view as? ZIndexProviding)?.zIndexValue ?? 0) : 0
    if V._isSpacer {
        return ChildInfo(
            buffer: nil,
            isSpacer: true,
            spacerMinLength: (view as? SpacerProtocol)?.spacerMinLength,
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
    // to the single-render fallback below.
    if !(view is Renderable), V.Body.self != Never.self {
        // Descend into the body under the SAME child identity `renderToBuffer`
        // uses (it appends the body type via `withChildIdentity`). Measuring
        // under the parent identity instead made the measure pass hydrate a
        // composite view's `@State` from a different slot than the render pass,
        // so a state-dependent view could measure a different size than it
        // rendered. Hydration still keys off `context` (the parent), exactly as
        // render does; only the recursion descends with the child identity.
        let childContext = context.withChildIdentity(type: V.Body.self)
        bindStateProperties(
            of: view, identity: context.identity, storage: context.environment.stateStorage!)
        let body = StateRegistration.withHydration(context: context) {
            view.body
        }
        return measureChild(body, proposal: proposal, context: childContext)
    }

    // Fallback: a `Renderable` view with no `Layoutable` conformance. Measure by
    // a SINGLE render, reported fixed.
    //
    // This used to render the view *twice* — once at the proposal, then again at
    // `naturalWidth + 8` to probe whether the view grows (and so is width-
    // flexible). That probe is now retired: every view whose measure depends on
    // width-flexibility (the stacks, frames, containers, controls, the
    // behavioural decorators, AnyView, …) conforms to `Layoutable` and is handled
    // above, where its `sizeThatFits` reports flexibility precisely. The probe was
    // also imprecise — it called any view that *reflows* wider (a wrapping `Text`)
    // "flexible", contradicting the `ViewSize` flexibility contract.
    //
    // What reaches here now is the fixed-size Renderable long tail: structural
    // wrappers that vertically stack (`TupleView`, `ViewArray`), and leaf cores
    // rendered within already-`Layoutable` parents or directly by the render loop
    // (the status bar, table rows, list content, the alert button row, …). For
    // these a single render is size-exact; they don't fill, so reporting fixed is
    // correct. A NEW Renderable view that genuinely fills its width must conform
    // to `Layoutable` to advertise that — the equivalence harness
    // (`MeasureRenderEquivalenceTests`) is the guard that catches one that doesn't.
    return measureFixedByRendering(view, proposal: proposal, context: context)
}

/// Measures a fixed-size view by rendering it ONCE in measuring mode and
/// reporting the result as a fixed size.
///
/// This is the measure used by a `Layoutable` view that never grows to fill — a
/// `Button`, `Toggle`, `Stepper`, a `Menu`, and the like — whose width can't be
/// derived structurally (it's assembled procedurally in `renderToBuffer`). It is
/// also exactly what `measureChild`'s fallback now does for the Renderable long
/// tail that isn't `Layoutable`: render once, report fixed. (Historically that
/// fallback rendered *twice* — a second render at `naturalWidth + 8` to probe
/// width-flexibility — but that probe was retired once the flexible views became
/// `Layoutable`; see `measureChild`.)
///
/// The single render goes through the same clamped `renderToBuffer(_:context:)`
/// the real layout pass uses, and sets `isMeasuring` / `hasExplicitWidth` so the
/// view reports its natural (minimum) size — identical to what render produces.
/// A view that needs to advertise width/height *flexibility* must not use this
/// alone (it always reports fixed): see how `_ToggleCore` combines it with a
/// structural label probe.
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
    // Clear hasExplicitWidth so the view reports its natural (minimum) size
    // rather than expanding to fill the full available width.
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
