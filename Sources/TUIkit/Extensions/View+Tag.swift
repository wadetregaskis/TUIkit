//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+Tag.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Tagged View

/// A view that carries a hashable tag value.
///
/// `_TaggedView` is produced by the ``View/tag(_:)`` modifier. It renders
/// transparently as its wrapped content; the tag is metadata consumed by
/// container views such as ``Picker`` to associate an option view with a
/// selection value.
///
/// - Important: Framework infrastructure. Created by ``View/tag(_:)``; do
///   not instantiate directly.
public struct _TaggedView<Content: View>: View {
    /// The tag value, type-erased.
    let tagValue: AnyHashable

    /// The wrapped content view.
    let content: Content

    public var body: some View {
        content
    }
}

// MARK: - Tag Modifier

extension View {
    /// Sets a unique tag value to use for selection within an enclosing
    /// container such as a ``Picker``.
    ///
    /// ```swift
    /// Picker("Speed", selection: $speed) {
    ///     Text("Slow").tag(Speed.slow)
    ///     Text("Fast").tag(Speed.fast)
    /// }
    /// ```
    ///
    /// The tag's type must match the container's selection-value type.
    /// Outside such a container the modifier has no visible effect — the
    /// view renders exactly as it would untagged.
    ///
    /// - Parameter tag: The hashable value to associate with this view.
    /// - Returns: A view tagged with the given value.
    public func tag<V: Hashable>(_ tag: V) -> some View {
        _TaggedView(tagValue: AnyHashable(tag), content: self)
    }
}
