//  🖥️ TUIKit — Terminal UI Kit for Swift
//  CheckboxStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - CheckboxStyle

/// How a ``Toggle``'s checkbox indicator is drawn — a TUI-specific rendering
/// choice, distinct from the SwiftUI-parity ``ToggleStyle`` (which selects
/// checkbox vs switch *semantics*).
///
/// The default ``unicode`` uses the square glyphs ■ / □. Terminals or
/// fonts that don't render those well can opt into the pure-ASCII ``ascii``
/// style (`[x]` / `[ ]`) for a whole subtree with ``SwiftUICore/View/checkboxStyle(_:)``:
///
/// ```swift
/// SettingsForm()
///     .checkboxStyle(.ascii)   // [x] / [ ] everywhere below
/// ```
///
/// A style is just the on/off marks plus an optional bracket pair. When the
/// brackets are empty (``unicode``) the mark is a self-contained glyph whose
/// *shape* shows the on/off state, so its colour is free to show focus /
/// checked / disabled. When brackets are present (``ascii``) they are coloured
/// by focus while the inner mark is coloured by on/off — the classic two-tone
/// `[x]`.
public struct CheckboxStyle: Sendable, Equatable {
    /// The mark shown when the toggle is **on** (e.g. `■` or `x`).
    public let onMark: String

    /// The mark shown when the toggle is **off** (e.g. `□` or a space).
    public let offMark: String

    /// The opening bracket drawn before the mark, or `""` for a self-contained
    /// glyph.
    public let openBracket: String

    /// The closing bracket drawn after the mark, or `""` for a self-contained
    /// glyph.
    public let closeBracket: String

    /// Creates a checkbox style from its marks and (optional) brackets.
    public init(onMark: String, offMark: String, openBracket: String = "", closeBracket: String = "") {
        self.onMark = onMark
        self.offMark = offMark
        self.openBracket = openBracket
        self.closeBracket = closeBracket
    }

    /// The default: filled / empty Unicode squares, ■ / □ (U+25A0 / U+25A1).
    ///
    /// These are deliberately *outside* Unicode's emoji repertoire, so every
    /// terminal renders them monochrome (theme-tintable for focus / checked /
    /// disabled) and one cell wide. The former large squares (U+2B1B / U+2B1C)
    /// are emoji-presentation codepoints: bare, terminals paint them as
    /// fixed-colour emoji that ignore the theme tint, and their U+FE0E
    /// text-presentation selector is mis-measured by some terminals, shearing
    /// the row layout (issue #9).
    public static let unicode = Self(onMark: "\u{25A0}", offMark: "\u{25A1}")

    /// A pure-ASCII style, `[x]` / `[ ]`, for terminals where the square glyphs
    /// don't render correctly. Three cells wide, two-tone (brackets show focus,
    /// the inner mark shows on/off).
    public static let ascii = Self(onMark: "x", offMark: " ", openBracket: "[", closeBracket: "]")
}

// MARK: - Environment

private struct CheckboxStyleKey: EnvironmentKey {
    static let defaultValue: CheckboxStyle = .unicode
}

extension EnvironmentValues {
    /// The checkbox indicator style for ``Toggle``s in this environment.
    public var checkboxStyle: CheckboxStyle {
        get { self[CheckboxStyleKey.self] }
        set { self[CheckboxStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the checkbox indicator style (``CheckboxStyle/unicode`` by default,
    /// or ``CheckboxStyle/ascii``) for ``Toggle``s in this view.
    ///
    /// TUI-specific: SwiftUI has no equivalent, so this is kept separate from the
    /// SwiftUI-parity ``toggleStyle(_:)``.
    public func checkboxStyle(_ style: CheckboxStyle) -> some View {
        environment(\.checkboxStyle, style)
    }
}
