//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+ZIndex.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Z-Index View

/// A view that carries an explicit z-index for sibling draw ordering.
///
/// `_ZIndexView` is produced by the ``View/zIndex(_:)`` modifier. It renders
/// transparently as its wrapped content; the z-index is metadata consumed by
/// overlapping container views — notably ``ZStack`` — to decide the order in
/// which children are drawn.
///
/// - Important: Framework infrastructure. Created by ``View/zIndex(_:)``; do
///   not instantiate directly.
public struct _ZIndexView<Content: View>: View {
    /// The z-index value. Higher values draw later (on top).
    ///
    /// Public because it witnesses the `public` ``ZIndexProviding`` requirement.
    public let zIndexValue: Double

    /// The wrapped content view.
    let content: Content

    public var body: some View {
        content
    }

    /// Static witness used by the child-layout path to detect a z-index wrapper
    /// without a runtime `as? ZIndexProviding` cast. See ``View/_providesZIndex``.
    public static var _providesZIndex: Bool { true }
}

extension _ZIndexView: ZIndexProviding {}

// MARK: - Equatable Conformance

extension _ZIndexView: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: _ZIndexView<Content>, rhs: _ZIndexView<Content>) -> Bool {
        lhs.zIndexValue == rhs.zIndexValue && lhs.content == rhs.content
    }
}

// MARK: - Z-Index Modifier

extension View {
    /// Controls the display order of this view relative to overlapping
    /// siblings.
    ///
    /// Within a ``ZStack`` (or any overlapping container) children are drawn
    /// in ascending order of their z-index, so a higher value brings a view
    /// to the front. Children left at the default `0` keep their natural
    /// tree order.
    ///
    /// ```swift
    /// ZStack {
    ///     Text("background")
    ///     Text("front").zIndex(1)   // drawn on top
    /// }
    /// ```
    ///
    /// Outside an overlapping container the modifier has no visible effect.
    /// Apply it as the outermost modifier on a `ZStack` child so the
    /// container can detect it.
    ///
    /// - Parameter value: The relative drawing order. Higher draws later.
    /// - Returns: A view with the given z-index.
    public func zIndex(_ value: Double) -> some View {
        _ZIndexView(zIndexValue: value, content: self)
    }
}
