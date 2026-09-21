//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// The base protocol for all TUIkit views.
///
/// `View` is the central protocol in TUIkit and works similarly to `View` in SwiftUI.
/// It defines how components declare their structure and content.
///
/// Every View defines a `body` composed of other Views.
/// This enables a hierarchical, declarative UI description.
///
/// ## Dual Rendering System
///
/// TUIkit uses two rendering paths:
///
/// - **Composite views** implement `body` to compose other views.
///   The rendering system recurses into `body` to resolve the tree.
/// - **Primitive views** additionally conform to `Renderable` and
///   produce a ``FrameBuffer`` directly. They set `body: Never`
///   (which `fatalError`s if called) because their `body` is never used.
///
/// The free function `renderToBuffer(_:context:)` checks `Renderable`
/// first, then falls back to `body`. See `Renderable` for details.
///
/// ## Creating a composite view
///
/// ```swift
/// struct MyView: View {
///     var body: some View {
///         Text("Hello, TUIkit!")
///     }
/// }
/// ```
///
/// ## Creating a primitive view
///
/// ```swift
/// struct MyPrimitive: View {
///     var body: Never { fatalError() }
/// }
///
/// extension MyPrimitive: Renderable {
///     func renderToBuffer(context: RenderContext) -> FrameBuffer {
///         FrameBuffer(text: "output")
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Like SwiftUI, all view operations are confined to the main actor.
/// This ensures thread-safe access to state, environment, and rendering.
@MainActor
public protocol View {
    /// The type of the body view.
    ///
    /// Swift automatically infers this type from the `body` implementation.
    /// Primitive views that conform to `Renderable` set this to `Never`.
    associatedtype Body: View

    /// The content and behavior of this view.
    ///
    /// Implement this property to define the structure of your view
    /// by composing other `View` types.
    ///
    /// For primitive views that conform to `Renderable`, set this
    /// to `Never` with a `fatalError` body. The rendering system will
    /// call `renderToBuffer(context:)` instead.
    @ViewBuilder
    var body: Body { get }

    /// Static witness: whether this view type is a spacer (the layout system's
    /// flexible filler — `Spacer`). `false` for every view but `Spacer`, which
    /// overrides it to `true`.
    ///
    /// The child layout path (`ChildView.init`, `makeChildInfo`) reads this
    /// per-type instead of probing each child with `as? SpacerProtocol` — an
    /// almost-always-failing runtime conformance cast on a hot path (`Spacer` is
    /// the sole conformer). When the witness is `true`, the rare spacer is cast
    /// to `SpacerProtocol` to read its `spacerMinLength`.
    static var _isSpacer: Bool { get }

    /// Static witness: whether this view type carries an explicit z-index (the
    /// wrapper `View.zIndex(_:)` produces). `false` for every view but
    /// `_ZIndexView`, which overrides it to `true`.
    ///
    /// `makeChildInfo` reads this per-type instead of probing each child with
    /// `as? ZIndexProviding` — an almost-always-failing runtime conformance cast
    /// (`_ZIndexView` is the sole conformer). When the witness is `true`, the
    /// rare z-index wrapper is cast to `ZIndexProviding` to read its
    /// `zIndexValue`.
    static var _providesZIndex: Bool { get }

    /// Static witness: whether this view's own bytes are an ADDRESS of its
    /// value rather than the value. `false` for every view but ``AnyView``,
    /// which overrides it to `true`.
    ///
    /// The per-pass memos key a view by the raw bytes of its struct, which is
    /// what makes them affordable. A pointer names a value only for as long as
    /// that value is alive: free the box and ask for another, and the allocator
    /// hands back the address it has just taken, doing exactly its job. Two
    /// different views then have identical bytes within one pass, and the memo
    /// answers the second question with the first one's answer.
    ///
    /// `viewValueHash` reads this and asks such a view for a hash of what it
    /// points AT.
    static var _valueIsBoxed: Bool { get }

    /// Static witness: whether this view type carries an explicit alignment
    /// guide (the wrapper `View.alignmentGuide(_:computeValue:)` produces).
    /// `false` for every view but `_AlignmentGuideView`, which overrides it to
    /// `true`.
    ///
    /// Same shape and same reason as ``_providesZIndex``: the aligning
    /// containers consult a stored `Bool` per child and only cast the rare
    /// wrapper. Without it every child of every stack would pay an
    /// almost-always-failing conformance cast on the hottest path there is.
    static var _providesAlignmentGuide: Bool { get }

    /// Static witness: whether this view type nominates something continuous
    /// about itself — that is, whether it conforms to ``Animatable``. `false`
    /// for every view but those, which get `true` from the constrained default
    /// below.
    ///
    /// Same shape and same reason as ``_isSpacer``, and the reason is measured:
    /// this is asked once per view per walk, on both the render and the measure
    /// side, and conformance-checking each one — even against a
    /// direct-mapped-by-metadata-pointer cache — cost a paired **+0.6% to +0.9%
    /// on `table`, `deep` and `kitchensink`** (41 reps, tight intervals). A tax
    /// on every app, including every app that animates nothing. As a static
    /// witness it is a constant the specialiser can fold away.
    ///
    /// Not to be implemented by hand: conform to ``Animatable`` instead.
    static var _isAnimatable: Bool { get }

    /// Static witness: this view at the value the animation store says to draw
    /// it at, or `nil` when nothing is moving.
    ///
    /// A witness rather than `view as? any Animatable` because the cast BOXES —
    /// a view struct is several words, so opening the existential heap-allocates
    /// once per animatable node per walk, and casting the result back is a
    /// second dynamic cast. With `.padding` and `.frame` animatable that is
    /// every layout node in the tree: it cost **+14% on `deep`**, whose whole
    /// shape is nested layout modifiers measured O(depth²) times.
    ///
    /// Here `Self` is concrete, so the store call is generic and nothing is
    /// boxed. Not to be implemented by hand.
    @MainActor
    static func _animated(_ view: Self, context: RenderContext, isMeasuring: Bool) -> Self?

    /// Static witness: this view rendered procedurally, or `nil` when it is a
    /// composite whose `body` should be descended into instead.
    ///
    /// A witness rather than `view as? Renderable` for the reason
    /// ``_isAnimatable`` is one, and this is the hotter of the two: the cast
    /// ran once per view per render, and `swift_dynamicCast` under it accounted
    /// for **4.5% of a frame** on the `fanout` scenario, 2.2% on `deep` and
    /// 1.0% on `kitchensink` (Instruments, Time Profiler, `--callers`). It is
    /// also the cast that succeeds most often, which is what makes it
    /// expensive rather than merely wasteful — a failing conformance check can
    /// stop at the metadata, a succeeding one builds the existential.
    ///
    /// Returning the BUFFER rather than the `Renderable` is the point: `Self`
    /// is concrete here, so the call is a direct one and nothing is boxed.
    /// Handing back `any Renderable` would keep the allocation this exists to
    /// remove.
    ///
    /// Not to be implemented by hand: conform to ``Renderable`` instead.
    @MainActor
    static func _renderSelf(_ view: Self, context: RenderContext) -> FrameBuffer?

    /// Static witness: this view's own measured size, or `nil` when it has no
    /// opinion and its `body` should be measured instead.
    ///
    /// The measure-side twin of ``_renderSelf(_:context:)``, replacing
    /// `view as? Layoutable` on the path deep nesting recurses through.
    ///
    /// Not to be implemented by hand: conform to ``Layoutable`` instead.
    @MainActor
    static func _measureSelf(
        _ view: Self, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize?
}

public extension View {
    /// Default: a view is not a spacer. `Spacer` overrides this.
    static var _isSpacer: Bool { false }

    /// Default: a view carries no explicit z-index. `_ZIndexView` overrides this.
    static var _providesZIndex: Bool { false }

    /// Default: a view's bytes are its value. ``AnyView`` overrides this.
    static var _valueIsBoxed: Bool { false }

    /// Default: a view sets no alignment guide. `_AlignmentGuideView` overrides
    /// this.
    static var _providesAlignmentGuide: Bool { false }

    /// A view says nothing continuous about itself unless it is ``Animatable``.
    @inlinable
    static var _isAnimatable: Bool { false }

    /// A view with nothing continuous about it never needs substituting.
    @inlinable
    static func _animated(_ view: Self, context: RenderContext, isMeasuring: Bool) -> Self? {
        nil
    }

    /// Default: a view renders through its `body`, not procedurally.
    /// ``Renderable`` conformers override this.
    @inlinable
    @MainActor
    static func _renderSelf(_ view: Self, context: RenderContext) -> FrameBuffer? { nil }

    /// Default: a view has no size of its own; its `body` is measured instead.
    /// ``Layoutable`` conformers override this.
    @inlinable
    @MainActor
    static func _measureSelf(
        _ view: Self, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize? { nil }
}
