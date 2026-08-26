//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// Whether the tag also matches a selection of the tag's OPTIONAL type.
    ///
    /// See ``View/tag(_:includeOptional:)`` for what the two answers mean and
    /// why `true` is what an untagged call has always done here.
    let includeOptional: Bool

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
    /// The tag's type must match the container's selection-value type — or be
    /// the type it wraps, which is what `includeOptional` is about. Outside
    /// such a container the modifier has no visible effect: the view renders
    /// exactly as it would untagged.
    ///
    /// ## includeOptional
    ///
    /// A `Picker` bound to `Binding<Speed?>` matches `.tag(Speed.slow)`,
    /// because the tag is cast INTO the selection's type and `as?` promotes a
    /// value to its Optional. That is almost always what you want, and it is
    /// what an unlabelled `.tag(_:)` has always done here, so `true` is the
    /// default and the shipped behaviour.
    ///
    /// `false` withholds the promotion, so the tag matches a `Speed` selection
    /// and not a `Speed?` one. The case for it is a picker over an Optional
    /// where some row is tagged `nil` and the distinction between "no choice"
    /// and a choice has to survive.
    ///
    /// - Parameters:
    ///   - tag: The hashable value to associate with this view.
    ///   - includeOptional: Whether the tag also matches a selection of the
    ///     tag's Optional type.
    /// - Returns: A view tagged with the given value.
    public func tag<V: Hashable>(_ tag: V, includeOptional: Bool = true) -> some View {
        _TaggedView(tagValue: AnyHashable(tag), includeOptional: includeOptional, content: self)
    }
}
