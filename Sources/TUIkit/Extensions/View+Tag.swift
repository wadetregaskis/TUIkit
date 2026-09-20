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
/// and a ``List``'s rows, through `staticListRowID(of:ordinal:as:)` for a
/// statically-built one and `ForEach`'s own `rowID(at:)` for a looped one —
/// to associate a view with a selection value.
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
    /// expressed only when the selection is an `Int`.
    ///
    /// On a row produced by a ``ForEach`` the tag is a *default* the element's
    /// `id` supplies, and writing one explicitly replaces it — SwiftUI's rule,
    /// worked end to end in Apple's own `Picker` documentation, where a row of
    /// `ForEach(Flavor.allCases)` carrying `.tag(flavor.suggestedTopping)`
    /// binds the topping rather than the flavour:
    ///
    /// ```swift
    /// List(selection: $topping) {
    ///     ForEach(Flavor.allCases) { flavor in
    ///         Text(flavor.name).tag(flavor.suggestedTopping)
    ///     }
    /// }
    /// ```
    ///
    /// The tag is the row's SELECTION value and nothing else. The row's
    /// *identity* is still its element's `id` — what its `@State`, its focus
    /// and its cached buffer are keyed by, and the key a
    /// ``ScrollViewProxy/scrollTo(_:anchor:)`` seeks — so a tag changes what
    /// the binding receives and does not make the row a second scroll target.
    /// An untagged loop row is unchanged: its `id` is its selection value.
    ///
    /// A `ForEach` that is the `List`'s content or a `Section`'s is reached; a
    /// `ForEach` flattened in beside hand-written rows is not, that path keying
    /// every flattened row by ordinal (it answers to no `id` there either).
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
/// Used by `List` to key a row: a statically-built one, where the fallback is
/// the row's ordinal, and a `ForEach` row, where it is the element's own `id`.
@MainActor
func extractTagValue<V: View, Value: Hashable>(from view: V, as valueType: Value.Type) -> Value? {
    guard let tag = (view as? any TagCarrying)?.carriedTag else { return nil }
    return resolveTag(tag.value, includeOptional: tag.includeOptional, as: valueType)
}

/// Whether ``extractTagValue(from:as:)`` could ever answer for a view of
/// `type` — a static property of the row TYPE, no instance needed.
///
/// ``viewTypeCarriesBadge(_:)``'s gate, for the same reason it exists: a
/// `ForEach` row's tag can only be read off the BUILT row, and a `List` asks
/// for a row's id on every frame, for the whole visible window. A row type
/// that cannot be carrying a tag — anything but a `.tag(_:)`-outermost row —
/// skips that build and keeps the key-path read it had.
@MainActor
func viewTypeCarriesTag<V: View>(_ type: V.Type) -> Bool {
    type is any TagCarrying.Type
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

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _TaggedView: SingleContentWrapper {
    public var wrappedContent: Content { content }
}
