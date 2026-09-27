//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Renderable.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation
import TUIkitCore

// MARK: - Renderable Protocol

/// A protocol for views that produce terminal output directly.
///
/// TUIkit uses a **dual rendering system** inspired by SwiftUI:
///
/// - **`View.body`** — Compositional path: views declare *what* they
///   are made of by composing other `View` types.
/// - **`Renderable.renderToBuffer`** — Primitive path: views define
///   *how* they look by producing a ``FrameBuffer`` directly.
///
/// When the free function ``renderToBuffer(_:context:)`` encounters a
/// view, it checks `Renderable` conformance **first**. If the view
/// conforms, `renderToBuffer(context:)` is called and `body` is never
/// consulted. Only if the view is *not* `Renderable` does the function
/// recurse into `body`.
///
/// ## Who conforms to Renderable?
///
/// - **Leaf views**: `Text`, `EmptyView`, `Spacer`, `Divider`
/// - **ViewBuilder glue**: `TupleView`, `ConditionalView`, `ViewArray`
/// - **Modifier infrastructure**: `ModifiedView`, `DimmedModifier`, etc.
/// - **Private `_*Core` views**: `_VStackCore`, `_HStackCore`, `_ZStackCore`,
///   `_ButtonCore`, `_StatusBarCore`, `_PanelCore`, `_ContainerViewCore`,
///   `_AlertCore`, `_DialogCore`, `_CardCore`, and friends — the procedural
///   rendering behind the public controls
///
/// The public controls are deliberately **not** on that list, and this list
/// once said otherwise: `VStack`, `HStack`, `ZStack`, `Button`, `ButtonRow`,
/// `Menu`, `StatusBar`, `Panel`, `ContainerView`, `Alert`, `Dialog` and `Card`
/// each moved behind a private core during the February 2026 migration
/// (`d9010bab`, `e2474a54` and friends). Every one of them is now a `View`
/// with a real `body: some View`, which is what makes modifiers and
/// environment values flow through the whole hierarchy the way SwiftUI's do.
///
/// The types listed above do declare `body: Never` (which `fatalError`s)
/// because their rendering is fully handled by `Renderable`.
///
/// ## Composite views (body only)
///
/// Views that do **not** conform to `Renderable` use `body` to compose
/// other views. Example: `Box` returns `content.bordered(...)` from its
/// `body`, which builds a `ContainerView` — itself a composite now, whose
/// `body` wraps the `Renderable` `_ContainerViewCore`.
///
/// ## Adding a new view type
///
/// - If your view composes other views → implement `body`, skip `Renderable`.
/// - If your view produces terminal output directly → conform to `Renderable`
///   and set `body: Never`.
/// - **Warning**: A view with `body: Never` that does *not* conform to
///   `Renderable` will silently render as empty. There is no runtime error.
@MainActor
public protocol Renderable {
    /// Renders this view into a ``FrameBuffer``.
    ///
    /// Called by the free function ``renderToBuffer(_:context:)`` when
    /// the view conforms to `Renderable`. The `body` property is never
    /// consulted in this case.
    ///
    /// - Parameter context: The rendering context with layout constraints,
    ///   environment values, and the `TUIContext`.
    /// - Returns: A buffer containing the rendered terminal output.
    func renderToBuffer(context: RenderContext) -> FrameBuffer
}

// MARK: - Layoutable Protocol

/// A protocol for views that support two-pass layout.
///
/// Views conforming to `Layoutable` can participate in the two-pass layout system:
/// 1. **Measure pass**: `sizeThatFits` is called to determine how much space the view needs
/// 2. **Layout pass**: `renderToBuffer` is called with the final allocated size
///
/// This enables proper layout distribution in containers like HStack and VStack,
/// where flexible views (Spacer, TextField) share remaining space after fixed
/// views (Text, Button) have claimed their natural size.
///
/// ## Conformance
///
/// Views that conform to `Layoutable` must also conform to `Renderable`.
/// The `sizeThatFits` method should return consistent results with what
/// `renderToBuffer` actually produces.
///
/// ## Default Implementation
///
/// Views that don't implement `sizeThatFits` get a default implementation
/// that renders the view and measures the resulting buffer. This is less
/// efficient but ensures backward compatibility.
@MainActor
public protocol Layoutable: Renderable {
    /// Returns the size this view needs given a proposed size.
    ///
    /// Called during the measure pass of two-pass layout. The view should
    /// return its ideal size, optionally constrained by the proposal.
    ///
    /// - Parameters:
    ///   - proposal: The size proposed by the parent (nil dimensions mean "use ideal").
    ///   - context: The rendering context.
    /// - Returns: The size this view needs and whether it's flexible.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize
}

// MARK: - Default Layoutable Implementation

extension Layoutable {
    /// Default implementation that renders the view to measure its size.
    ///
    /// This fallback ensures backward compatibility but is less efficient
    /// than a proper `sizeThatFits` implementation that calculates size
    /// without rendering.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Create a context with proposed dimensions if available
        var measureContext = context
        if let width = proposal.width {
            measureContext.availableWidth = width
        }
        if let height = proposal.height {
            measureContext.availableHeight = height
        }

        // Render to measure
        let buffer = renderToBuffer(context: measureContext)
        return ViewSize.fixed(buffer.width, buffer.height)
    }
}

// MARK: - Rendering Dispatch

/// Renders any `View` into a ``FrameBuffer`` using the dual rendering system.
///
/// This is the **single entry point** for all view rendering in TUIkit.
/// Every recursive call in the view tree passes through this function.
///
/// ## Decision order
///
/// 1. **Renderable** — If the view conforms to ``Renderable``, call
///    `renderToBuffer(context:)` directly. The `body` property is
///    never accessed.
/// 2. **Body recursion** — If the view does *not* conform to `Renderable`
///    and its `Body` type is not `Never`, recurse into `view.body`.
/// 3. **Empty fallback** — If neither applies (`Body` is `Never` and no
///    `Renderable` conformance), return an empty ``FrameBuffer``.
///    This is a silent no-op — no error, no warning.
///
/// ## Example flow
///
/// ```
/// renderToBuffer(Box { Text("Hi") })
///   → Box is NOT Renderable, Body != Never
///   → recurse into Box.body → ContainerView
///     → ContainerView IS Renderable
///     → calls ContainerView.renderToBuffer(context:)
///       → internally calls renderToBuffer(Text("Hi"), context:)
///         → Text IS Renderable → produces FrameBuffer
/// ```
///
/// - Parameters:
///   - view: The view to render.
///   - context: The rendering context with layout constraints.
/// - Returns: A ``FrameBuffer`` containing the rendered terminal output.
@MainActor
public func renderToBuffer<V: View>(_ view: V, context: RenderContext) -> FrameBuffer {
    // `RenderContext` carries two services in stored mirrors, and only
    // `withEnvironment(_:)` re-derives them. Checked here because this is the
    // one function every rendered view passes through, and `assert` compiles
    // out of a release build — so the check exists exactly where it is free.
    assert(
        context.servicesAreMirrored,
        "RenderContext.environment was replaced without re-mirroring its services — assign through withEnvironment(_:)")
    // An `Animatable` view renders at where its picture has GOT to, not at what
    // the tree says — so substitute before anything reads it, INCLUDING the
    // `Renderable` branch below (a modifier that animates is a `Renderable`).
    //
    // Split rather than folded into one rebinding of `view`, because rebinding
    // copies the struct: doing it unconditionally cost a measured ~1% of a
    // frame on `table`, `deep` and `kitchensink`, paid by every app whether or
    // not it animates anything. The static witness makes the branch a constant
    // the specialiser can fold, and the common path never binds a new value.
    if V._isAnimatable,
        let animated = resolvingAnimation(view, context: context, isMeasuring: context.isMeasuring)
    {
        return renderResolved(animated, context: context)
    }
    return renderResolved(view, context: context)
}

/// ``renderToBuffer(_:context:)`` once the animation substitution is settled.
@MainActor
private func renderResolved<V: View>(_ view: V, context: RenderContext) -> FrameBuffer {
    // Priority 1: Direct rendering via Renderable protocol.
    //
    // The result is clamped to the available space — the universal layout
    // safety net. A view that mis-sizes itself can never overwrite a sibling
    // or overflow the terminal; at worst its own content is truncated.
    // Correctly-sized views hit `clamped`'s fast path, which is a no-op.
    // The composite `body` path below is covered transitively: it recurses
    // through this same function, whose base case is a `Renderable`.
    if let buffer = V._renderSelf(view, context: context) {
        return buffer.clamped(
            toWidth: context.availableWidth, height: context.availableHeight)
    }

    // Priority 2: Composite view — bind this view's @State to its own identity,
    // resolve its @Environment, then recurse into body, which renders one
    // identity step further in (the body's type).
    if V.Body.self != Never.self {
        let childContext = context.withChildIdentity(type: V.Body.self)
        let body = evaluateCompositeBody(of: view, context: context)
        return TUIkitView.renderToBuffer(body, context: childContext)
    }

    // Priority 3: No rendering path — return empty buffer silently.
    // This happens for types with body: Never that forgot Renderable conformance.
    return FrameBuffer()
}

// MARK: - Evaluating a composite's body

/// A composite view's `body`, evaluated exactly as the render walk evaluates it
/// before descending into it: `@Environment` resolved, `@State` bound to the
/// view's OWN identity, the evaluation observed, and the identity marked active.
///
/// `context` is the context the view itself renders in. The body it returns is
/// drawn one identity step further in — `context.withChildIdentity(type:
/// V.Body.self)` — and that step is the caller's to take, as the render walk
/// takes it.
///
/// A function of its own so that anything needing a composite's body without
/// drawing it evaluates that body exactly as a render would — a `List` or a
/// `Section` asking a view of the app's own which rows its body holds
/// (`listRowsBody(of:context:)`, in `TUIkit`) is the other caller. A body
/// evaluated any other way would bind the view's `@State` somewhere else, or
/// read an `@Environment` it was never handed, or be one no change to an
/// `@Observable` it read could ever invalidate.
///
/// - `@Environment` is resolved against the environment the view renders in,
///   into its (reference) box. The box is shared with any closure `body`
///   creates that captures the view, so an `@Environment` read inside an event
///   handler or an action is correct, not just one during `body`.
/// - `@State` binds here, not at construction: keyed by THIS view's render
///   identity, so views a conditional swaps between don't alias each other's
///   state. Mirrored in `measureChild`.
/// - The evaluation is observed, so an `@Observable` property `body` read
///   re-renders the view when it changes. No environment hydration: the
///   `@Environment` step has already filled every `@Environment` (and
///   `@FocusState`) box on this view, so publishing the environment as well
///   was pure overhead on the single most-executed operation in the framework.
///
///   The change invalidates THIS view's identity — its subtree and the
///   ancestors whose buffers contain it — through the sink a `@State` write
///   uses, not the whole cache. It used to clear everything: a model that
///   changes every frame (a clock, a progress counter, a download's byte
///   count) then made every frame a cold render of the entire tree, and the
///   memo machinery never served a single buffer while it did. Measured on
///   `Stress` under autopilot, every scenario cost its `--bench --cold` price,
///   not its warm one — `fanout` 113 ms a frame for 12.8 ms of work. The
///   tracking is per body, so the identity whose body read the value is exactly
///   the one to drop; an ancestor that did not read it keeps a buffer that
///   never held it. The whole-cache clear remains only where there is no cache
///   to scope to (a headless render with no `RenderCache` in the environment).
/// - The `onChange` holds the cache WEAKLY. A registration lives until a
///   property it read is written, which for a property nothing writes is for
///   good, and a strong capture kept the cache — every buffer and size in it —
///   alive with it, after the app that owned the cache had gone. See
///   ``reportObservedChange(at:to:hadCache:fallback:)``.
///
/// `@inline(__always)` so the render walk's own copy compiles to what it was
/// before this was a function: it runs once per composite per frame, and it
/// must not become a call there.
@inline(__always)
@MainActor
package func evaluateCompositeBody<V: View>(of view: V, context: RenderContext) -> V.Body {
    resolveEnvironmentProperties(of: view, in: context.environment)
    bindStateProperties(
        of: view, identity: context.identity, storage: context.stateStorage!)
    let body = withObservationTracking {
        view.body
    } onChange: { [weak cache = context.renderCache, hadCache = context.renderCache != nil, identity = context.identity] in
        reportObservedChange(at: identity, to: cache, hadCache: hadCache)
    }
    context.stateStorage!.markActive(context.identity)
    return body
}

/// Where an observed body's change goes: to the cache the body was drawn
/// with, as an invalidation at the body's identity; to the whole-cache
/// fallback when it was drawn with no cache; and nowhere when it was drawn
/// with a cache that has since gone.
///
/// The last case is why the registration holds the cache weakly. A
/// registration is freed only when a property it read is written, so one
/// armed by a body that reads a property nothing ever writes lives for as
/// long as the model does — and held strongly, it kept the whole render cache
/// alive with it, long after the app, the `TUIContext` or the test that owned
/// the cache had let it go. A cache that has gone has nothing left to
/// invalidate, and whatever replaced it arms registrations of its own the
/// first time it draws, so the change is dropped.
///
/// - Parameters:
///   - identity: The identity whose body read the property.
///   - cache: The cache the body was drawn with, if it is still alive.
///   - hadCache: Whether there was a cache when the body was drawn, which
///     tells a cache that has gone from a render that never had one.
///   - fallback: What a change does to a render with no cache: clears
///     everything and asks for a frame. A parameter so a test can see it run.
package func reportObservedChange(
    at identity: ViewIdentity, to cache: RenderCache?, hadCache: Bool,
    fallback: () -> Void = { AppState.shared.setNeedsRenderWithCacheClear() }
) {
    if let cache {
        cache.invalidateRender(for: identity)
    } else if !hadCache {
        fallback()
    }
}

// MARK: - Static witnesses

extension View where Self: Renderable {
    /// A ``Renderable`` view draws itself; the render walk calls this instead
    /// of descending into `body`. See ``View/_renderSelf(_:context:)`` for why
    /// this is a witness rather than a cast.
    @MainActor
    public static func _renderSelf(_ view: Self, context: RenderContext) -> FrameBuffer? {
        view.renderToBuffer(context: context)
    }
}

extension View where Self: Layoutable {
    /// A ``Layoutable`` view measures itself. See
    /// ``View/_measureSelf(_:proposal:context:)``.
    ///
    /// The `isMeasuring` flip stays at the CALL SITE rather than here, because
    /// it is the caller that knows whether the context already has it set —
    /// and skipping the copy when it does is what keeps a deep chain from
    /// re-copying the context at every level.
    @MainActor
    public static func _measureSelf(
        _ view: Self, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize? {
        view.sizeThatFits(proposal: proposal, context: context)
    }
}
