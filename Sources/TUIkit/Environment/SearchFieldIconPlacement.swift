//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SearchFieldIconPlacement.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Search field icon placement

/// Which side of a ``TUIkit/View/searchable(text:placement:prompt:)`` field its
/// magnifier icon is drawn on.
///
/// TUI-specific. SwiftUI always draws the icon leading and has no equivalent,
/// and this is deliberately NOT carried on ``SearchFieldPlacement`` — that type
/// mirrors SwiftUI's `.toolbar` / `.sidebar` / `.navigationBarDrawer`, which
/// answer "where does the field go", not "which side of it is the icon".
///
/// The glyph follows the side, so the lens always faces the field it belongs
/// to: 🔎 (U+1F50E RIGHT-POINTING) when the icon leads, 🔍 (U+1F50D
/// LEFT-POINTING) when it trails. Both measure two cells and advance two under
/// every terminal model TUIkit knows, so switching sides never shifts the row.
///
/// > Note: On terminals outside the emoji-chrome allowlist no icon is drawn at
///   all (see ``EnvironmentValues/supportsEmojiChrome``), so this has no visible
///   effect there — a mis-drawn glyph is worse than none.
public enum SearchFieldIconPlacement: Sendable, Hashable {
    /// The icon precedes the field, drawn as 🔎.
    case leading
    /// The icon follows the field, drawn as 🔍.
    case trailing
}

private struct SearchFieldIconPlacementKey: EnvironmentKey {
    static let defaultValue: SearchFieldIconPlacement = .leading
}

extension EnvironmentValues {
    /// Which side of a `.searchable` field its magnifier is drawn on.
    /// Defaults to ``SearchFieldIconPlacement/leading``.
    public var searchFieldIconPlacement: SearchFieldIconPlacement {
        get { self[SearchFieldIconPlacementKey.self] }
        set { self[SearchFieldIconPlacementKey.self] = newValue }
    }
}

extension View {
    /// Sets which side of a `.searchable` field the magnifier icon is drawn on,
    /// for search fields in this subtree.
    ///
    /// The glyph follows the placement — 🔎 leading, 🔍 trailing — so the lens
    /// faces the field either way.
    ///
    /// - Parameter placement: The side to draw the icon on.
    /// - Returns: A view whose search fields place their icon accordingly.
    public func searchFieldIconPlacement(
        _ placement: SearchFieldIconPlacement
    ) -> some View {
        environment(\.searchFieldIconPlacement, placement)
    }
}
