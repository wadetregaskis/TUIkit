//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutValueKey.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Layout Value Key

/// A key for a value a view hands to the ``Layout`` that arranges it.
///
/// The channel by which a subview tells its layout something the layout cannot
/// work out from geometry alone — a column span, a sort rank, a "this one is
/// the hero" flag:
///
/// ```swift
/// private struct Span: LayoutValueKey {
///     static let defaultValue = 1
/// }
///
/// extension View {
///     func span(_ n: Int) -> some View { layoutValue(key: Span.self, value: n) }
/// }
///
/// // …then inside the layout:
/// let columns = subview[Span.self]
/// ```
///
/// The value travels with the view, not through the environment, so it reaches
/// exactly the one layout that arranges it and no deeper.
public protocol LayoutValueKey {
    /// The type of value this key carries.
    associatedtype Value

    /// The value a subview that never set one reports.
    static var defaultValue: Value { get }
}

// MARK: - Carrying the Values

/// A view carrying layout values for its container's ``Layout`` to read.
///
/// Produced by ``View/layoutValue(key:value:)``. Renders transparently as its
/// content; the values are metadata.
///
/// - Important: Framework infrastructure. Created by
///   ``View/layoutValue(key:value:)``; do not instantiate directly.
public struct _LayoutValueView<Content: View>: View {
    /// The key this view sets, identified by its type.
    let key: ObjectIdentifier

    /// The value, type-erased — recovered by the `LayoutValueKey`-typed
    /// subscript on ``LayoutSubview``, which knows what it asked for.
    let value: Any

    /// The wrapped content view.
    let content: Content

    public var body: some View {
        content
    }
}

/// A view that can answer for the layout values set on it.
///
/// Implemented by the wrapper ``View/layoutValue(key:value:)`` produces. Unlike
/// the alignment-guide equivalent this needs no static witness: it is only ever
/// consulted from inside a ``Layout``, which is already off the hot path that
/// every child of every stack walks.
@MainActor
protocol LayoutValueProviding {
    /// The value set for `key`, or `nil` if this view (or anything it wraps)
    /// did not set one.
    func layoutValue(for key: ObjectIdentifier) -> Any?
}

extension _LayoutValueView: LayoutValueProviding {
    func layoutValue(for key: ObjectIdentifier) -> Any? {
        if key == self.key { return value }
        // Chained values nest, so a wrapper that cannot answer asks the one it
        // wraps. The OUTERMOST wins for a repeated key, as with every modifier.
        return (content as? LayoutValueProviding)?.layoutValue(for: key)
    }
}

extension View {
    /// Associates a value with this view, for the ``Layout`` that arranges it
    /// to read.
    ///
    /// - Important: Apply it as the **outermost** modifier on a subview the
    ///   layout should read, for the reason given on
    ///   ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)``: a
    ///   modifier applied after it hides the value from the container.
    ///
    /// - Parameters:
    ///   - key: The key type.
    ///   - value: The value to associate.
    /// - Returns: A view carrying the layout value.
    public func layoutValue<K: LayoutValueKey>(key: K.Type, value: K.Value) -> some View {
        _LayoutValueView(key: ObjectIdentifier(K.self), value: value, content: self)
    }
}

// MARK: - Layout Priority

/// The built-in key behind ``View/layoutPriority(_:)``.
private struct LayoutPriorityKey: LayoutValueKey {
    static let defaultValue: Double = 0
}

extension View {
    /// Sets the priority with which a ``Layout`` should give this view space.
    ///
    /// A layout is free to interpret this however it likes; the convention it
    /// inherits from SwiftUI is that higher-priority subviews are offered their
    /// ideal size first and lower-priority ones absorb what is left. TUIkit's
    /// own stacks do **not** consult it — they distribute by the flexibility
    /// each child reports (see ``ViewSize``), which answers the same question
    /// more directly. It is here for custom layouts.
    ///
    /// - Parameter value: The priority. Higher wins; the default is `0`.
    /// - Returns: A view carrying the priority.
    public func layoutPriority(_ value: Double) -> some View {
        layoutValue(key: LayoutPriorityKey.self, value: value)
    }
}

extension LayoutSubview {
    /// The priority set with ``View/layoutPriority(_:)``, or `0`.
    public var priority: Double {
        self[LayoutPriorityKey.self]
    }
}
