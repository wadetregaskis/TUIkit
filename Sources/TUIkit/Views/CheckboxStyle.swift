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
/// Three built-in styles, named by glyph repertoire:
/// - ``unicode`` — single-cell text squares ■ / □. Monochrome, theme-tintable,
///   and one cell wide on every terminal: the maximum-compatibility choice.
/// - ``emoji`` — the large squares ⬛︎ / ⬜︎ from the emoji repertoire, rendered
///   in text presentation. Two cells wide and visually bolder, but correct
///   only on terminals that honour the presentation selector (Terminal.app).
/// - ``ascii`` — the classic bracketed `[x]` / `[ ]`, for terminals or fonts
///   where neither square renders well.
///
/// A running app defaults to ``automatic`` — ``emoji`` under Apple's
/// Terminal.app, ``unicode`` everywhere else. Override for a whole subtree
/// with ``SwiftUICore/View/checkboxStyle(_:)``:
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

    /// Filled / empty text squares, ■ / □ (U+25A0 / U+25A1) — the
    /// maximum-compatibility style.
    ///
    /// These are deliberately *outside* Unicode's emoji repertoire, so every
    /// terminal renders them monochrome (theme-tintable for focus / checked /
    /// disabled) and one cell wide — nothing terminal-specific to go wrong.
    public static let unicode = Self(onMark: "\u{25A0}", offMark: "\u{25A1}")

    /// Filled / empty large squares from the emoji repertoire, ⬛︎ / ⬜︎
    /// (U+2B1B / U+2B1C with the U+FE0E text-presentation selector).
    ///
    /// Two cells wide and visually bolder than ``unicode``. The selector keeps
    /// them monochrome and theme-tintable — but only on terminals that honour
    /// it: bare emoji presentation paints fixed-colour squares that ignore the
    /// tint, and some terminals mis-measure the selector itself, shearing the
    /// row (issue #9). Terminal.app renders this style correctly (TUIkit's
    /// output path carries its emoji advance workarounds), which is why
    /// ``automatic`` selects it there and nowhere else.
    public static let emoji = Self(onMark: "\u{2B1B}\u{FE0E}", offMark: "\u{2B1C}\u{FE0E}")

    /// A pure-ASCII style, `[x]` / `[ ]`, for terminals where the square glyphs
    /// don't render correctly. Three cells wide, two-tone (brackets show focus,
    /// the inner mark shows on/off).
    public static let ascii = Self(onMark: "x", offMark: " ", openBracket: "[", closeBracket: "]")

    /// The terminal-adaptive default: ``emoji`` under Apple's Terminal.app,
    /// ``unicode`` everywhere else.
    ///
    /// Terminal.app draws the emoji-repertoire squares as single seamless
    /// glyphs (and TUIkit's output path carries its emoji advance
    /// workarounds), so the bolder two-cell style is both safe and prettier
    /// there. No such guarantee holds for other terminals, so they get the
    /// universally-correct ``unicode`` squares.
    ///
    /// This is what a running app uses when no ``SwiftUICore/View/checkboxStyle(_:)``
    /// modifier applies. (The bare `EnvironmentValues` default — what headless
    /// renders and tests see — is the terminal-independent ``unicode``.)
    public static var automatic: Self {
        automatic(isAppleTerminal: TerminalHost.isAppleTerminal)
    }

    /// Testable core of ``automatic``.
    static func automatic(isAppleTerminal: Bool) -> Self {
        isAppleTerminal ? .emoji : .unicode
    }
}

// MARK: - Environment

private struct CheckboxStyleKey: EnvironmentKey {
    /// The terminal-independent ``CheckboxStyle/unicode``, NOT
    /// ``CheckboxStyle/automatic``: a bare `EnvironmentValues` (headless
    /// renders, the test suite) must resolve identically whatever terminal
    /// hosts the process. The app run loop injects `.automatic` at the root
    /// (see `RenderLoop.buildEnvironment`), so real apps are terminal-adaptive.
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
