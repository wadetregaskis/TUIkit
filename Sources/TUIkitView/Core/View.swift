//  🖥️ TUIKit — Terminal UI Kit for Swift
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
}

public extension View {
    /// Default: a view is not a spacer. `Spacer` overrides this.
    static var _isSpacer: Bool { false }

    /// Default: a view carries no explicit z-index. `_ZIndexView` overrides this.
    static var _providesZIndex: Bool { false }
}
