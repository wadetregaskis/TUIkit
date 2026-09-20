//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Tag.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Tagged View

/// A view that carries a hashable tag value.
///
/// `_TaggedView` is produced by the ``View/tag(_:includeOptional:)`` modifier.
/// It renders transparently as its wrapped content; the tag is metadata
/// consumed by container views — ``Picker``, through ``PickerOptionProvider``,
/// and a ``List``'s statically-built rows, through
/// `staticListRowID(of:ordinal:as:)` — to associate a view with a selection
/// value.
///
/// - Important: Framework infrastructure. Created by
///   ``View/tag(_:includeOptional:)``; do not instantiate directly.
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
    /// container such as a ``Picker`` or a ``List``.
    ///
    /// ```swift
    /// Picker("Speed", selection: $speed) {
    ///     Text("Slow").tag(Speed.slow)
    ///     Text("Fast").tag(Speed.fast)
    /// }
    ///
    /// List(selection: $letter) {
    ///     Text("alpha").tag("a")
    ///     Text("beta").tag("b")
    /// }
    /// ```
    ///
    /// The tag's type must match the container's selection-value type — or be
    /// the type it wraps, which is what `includeOptional` is about. Outside
    /// such a container the modifier has no visible effect: the view renders
    /// exactly as it would untagged.
    ///
    /// ## In a List
    ///
    /// A tag is what makes a *statically-built* row selectable, exactly as in
    /// SwiftUI: a row that carries none falls back to its ordinal, which can be
    /// expressed only when the selection is an `Int`. Rows produced by a
    /// ``ForEach`` are identified by the element's own `id` instead, and a
    /// `.tag(_:)` written on one of those rows is not consulted.
    ///
    /// The tag must be the row's OWN wrapper — `Text("a").tag("a")`, not
    /// `Text("a").tag("a").padding()`, which is `.badge(_:)`'s rule as well.
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

// MARK: - Reading a tag

/// A view carrying a `.tag(_:)`, minus its content type.
///
/// The `BadgeCarrying` shape from `BadgeModifier`: a private protocol the
/// generic wrapper conforms to, so a container holding its row as `any View`
/// can ask it. `Picker` has no need of it — it walks its content tree through
/// ``PickerOptionProvider`` and meets `_TaggedView` at its own static type —
/// but a `List` row arrives already resolved to one child, and the question
/// there is only ever about the child's own wrapper.
///
/// Which is the limit worth stating: this reads the view's OWN tag, not its
/// subtree's. `Text("a").tag("a").padding()` has no tag from here, exactly as
/// a `.badge(_:)` written under a `.padding()` is not the row's badge.
@MainActor
private protocol TagCarrying {
    var carriedTag: (value: AnyHashable, includeOptional: Bool) { get }
}

extension _TaggedView: TagCarrying {
    fileprivate var carriedTag: (value: AnyHashable, includeOptional: Bool) {
        (tagValue, includeOptional)
    }
}

/// The selection value `view`'s own `.tag(_:)` names — `nil` when it carries no
/// tag, or one that cannot be expressed as `Value`.
///
/// Used by `List` to key a statically-built row, which in SwiftUI is the only
/// thing `.tag(_:)` is for outside a `Picker`.
@MainActor
func extractTagValue<V: View, Value: Hashable>(from view: V, as valueType: Value.Type) -> Value? {
    guard let tag = (view as? any TagCarrying)?.carriedTag else { return nil }
    return resolveTag(tag.value, includeOptional: tag.includeOptional, as: valueType)
}

/// Resolves a type-erased tag against a container's selection-value type.
///
/// Cast the TAG into the selection's type; never compare two `AnyHashable`s.
/// `as?` promotes a value to its Optional as a language rule, so
/// `.tag(Speed.slow)` matches a `Speed?` selection on every platform.
/// (`AnyHashable` equality does the same thing only for types carrying an ObjC
/// bridge, which is how `TabView` came to draw the wrong tab on Linux-shaped
/// input — see its `index(matching:)`.)
///
/// `includeOptional: false` withholds exactly that promotion, by requiring the
/// tag's DYNAMIC type to be the selection type rather than something
/// assignable to it.
///
/// One function rather than one rule per container: `Picker` and `List` both
/// match tags, and the comment above is the whole of why the obvious
/// alternative is wrong.
func resolveTag<Value: Hashable>(
    _ tag: AnyHashable, includeOptional: Bool, as valueType: Value.Type
) -> Value? {
    guard includeOptional || type(of: tag.base) == Value.self else { return nil }
    return tag.base as? Value
}
