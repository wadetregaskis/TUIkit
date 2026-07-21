//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollAnchor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Scroll anchor

/// What a scrollable is anchored to — the user-facing vocabulary for
/// `Documentation/Scroll-anchoring.md` §1.1, bound through
/// ``TUIkit/View/anchorPosition(_:)``.
///
/// Note that ``top`` / ``bottom`` are **positional** policies while ``row`` is
/// an **identity** policy, and they are deliberately not interchangeable: under
/// a data change at that edge they diverge. `.bottom` follows appends — it
/// re-targets to whatever the last row now is — whereas `.row(lastID)` pins to
/// that specific row and lets new rows arrive *below* it. Likewise a prepend
/// leaves `.top` on the new first row but leaves `.row(firstID)` showing the old
/// one, now at ordinal 1. Encoding the edges as sentinel row ids would collapse
/// exactly the distinction they exist to express.
public enum ScrollAnchor<ID: Hashable>: Equatable {
    /// Stay at the top, whatever rows are added / removed / moved.
    case top

    /// Stay at the bottom — follow-the-log.
    case bottom

    /// Keep this specific row in place as rows change around it.
    case row(ID)

    /// Explicitly *no* anchor: the position stays where it is in line
    /// coordinates. Distinct from a `nil` binding — see
    /// ``TUIkit/View/anchorPosition(_:)``.
    case window
}

// MARK: - Type-erased form

/// ``ScrollAnchor`` with its row id erased, so the binding can live in the
/// environment (which cannot hold a generic). `AnyHashable` preserves the base
/// value, so a `.row` written by the framework maps back to the app's own `ID`
/// without loss.
typealias ErasedScrollAnchor = ScrollAnchor<AnyHashable>

extension ErasedScrollAnchor {
    /// The stable row key this anchor names, in the same spelling `ForEach`
    /// builds its child keys with — or `nil` for the non-identity cases.
    var rowKey: String? {
        if case .row(let id) = self { return String(describing: id.base) }
        return nil
    }
}

private struct AnchorPositionKey: EnvironmentKey {
    // `Binding` is not `Sendable`, so the immutable `nil` default needs
    // `nonisolated(unsafe)` — the value never mutates, so it is genuinely safe
    // (the same treatment `\.editMode` gets).
    nonisolated(unsafe) static let defaultValue: Binding<ErasedScrollAnchor?>? = nil
}

extension EnvironmentValues {
    /// The bound anchor override for scrollables in this subtree, or `nil` when
    /// none was supplied. See ``TUIkit/View/anchorPosition(_:)``.
    var anchorPosition: Binding<ErasedScrollAnchor?>? {
        get { self[AnchorPositionKey.self] }
        set { self[AnchorPositionKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Binds the anchor a scrollable in this subtree is currently holding —
    /// readable to observe it, writable to change it.
    ///
    /// The binding is **optional, and `nil` is meaningful**: it means *no
    /// departure from the declared anchor*, i.e. whatever
    /// ``TUIkit/View/defaultScrollAnchor(_:)`` said (or Window, its default).
    /// A non-`nil` value overrides that declaration.
    ///
    /// ```swift
    /// List { … }
    ///     .defaultScrollAnchor(.bottom)     // declared: follow-the-log
    ///     .anchorPosition($anchor)          // live override / observation
    /// ```
    ///
    /// | Value | Meaning |
    /// |---|---|
    /// | `nil` | Following the declared anchor |
    /// | `.window` | Released — the user scrolled away |
    /// | `.row(id)` | Pinned to that row |
    /// | `.top` / `.bottom` | Explicit edge override |
    ///
    /// Writing `nil` therefore *restores the declared anchor* — which is why no
    /// imperative `restoreDefaultAnchor()` is needed. And because `.window` and
    /// `nil` are distinct, "am I still following the log?" is simply
    /// `anchor == nil`: a released scrollable reads `.window`, an untouched one
    /// reads `nil`.
    ///
    /// - Parameter anchor: The bound anchor override.
    /// - Returns: A view whose scrollables read and write that anchor.
    public func anchorPosition<ID: Hashable>(
        _ anchor: Binding<ScrollAnchor<ID>?>
    ) -> some View {
        // Erase ID ↔ AnyHashable. `AnyHashable` keeps the base value, so a
        // `.row` round-trips back to the caller's own ID type; a `.row` whose
        // base is some *other* type (only reachable if two differently-typed
        // bindings target one scrollable) is treated as no override rather than
        // force-cast.
        let erased = Binding<ErasedScrollAnchor?>(
            get: {
                switch anchor.wrappedValue {
                case .none: return nil
                case .top: return .top
                case .bottom: return .bottom
                case .window: return .window
                case .row(let id): return .row(AnyHashable(id))
                }
            },
            set: { newValue in
                switch newValue {
                case .none: anchor.wrappedValue = nil
                case .top: anchor.wrappedValue = .top
                case .bottom: anchor.wrappedValue = .bottom
                case .window: anchor.wrappedValue = .window
                case .row(let erasedID):
                    guard let id = erasedID.base as? ID else { return }
                    anchor.wrappedValue = .row(id)
                }
            })
        return environment(\.anchorPosition, erased)
    }
}
