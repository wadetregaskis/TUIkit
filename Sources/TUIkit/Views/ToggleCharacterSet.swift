//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ToggleCharacterSet.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - ToggleCharacterSet

/// The glyph repertoire a ``Toggle`` draws with — a TUI-specific rendering
/// choice, distinct from the SwiftUI-parity ``ToggleStyle`` (which selects
/// checkbox vs switch *semantics*). It governs BOTH forms: the checkbox marks
/// (■/□, ⬛︎/⬜︎, `[x]`/`[ ]`) and the switch track (block-glyph or emoji knob,
/// or the bracketed `[o ]`/`[ o]` under ``ascii``).
///
/// Three built-in sets:
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
/// with ``SwiftUICore/View/toggleCharacterSet(_:)``:
///
/// ```swift
/// SettingsForm()
///     .toggleCharacterSet(.ascii)   // [x] / [ ] everywhere below
/// ```
///
/// A character set is just the on/off marks plus an optional bracket pair. When the
/// brackets are empty (``unicode``) the mark is a self-contained glyph whose
/// *shape* shows the on/off state, so its colour is free to show focus /
/// checked / disabled. When brackets are present (``ascii``) they are coloured
/// by focus while the inner mark is coloured by on/off — the classic two-tone
/// `[x]`.
public struct ToggleCharacterSet: Sendable, Equatable {
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

    /// Marks the value produced by ``automatic``: "decide from the terminal at
    /// render time" rather than a decided set of glyphs.
    ///
    /// This is what makes ``automatic`` adapt. The alternative — resolving the
    /// glyphs when the value is *created* — bakes in whatever the terminal
    /// looked like at that moment, which is wrong the instant it changes: under
    /// tmux the answer depends on the attached CLIENT, and a detach and
    /// re-attach from a different terminal changes it mid-run.
    ///
    /// The marks carried alongside are ``unicode``'s, so a value that somehow
    /// escapes resolution still draws correct, universally-safe glyphs rather
    /// than nothing.
    ///
    /// Participates in `Equatable`, deliberately: `.automatic` is NOT `.unicode`
    /// even though they carry the same marks, because they mean different things
    /// — which is what lets a caller (the example's Theme picker) match
    /// `case .automatic` and show it as its own option.
    var resolvesFromTerminal: Bool = false

    /// Creates a character set from its marks and (optional) brackets.
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

    /// The terminal-adaptive default: ``emoji`` on terminals verified to
    /// draw the emoji-repertoire squares correctly (Apple's Terminal.app
    /// and iTerm2 — see `TerminalHost.supportsEmojiChrome`), ``unicode``
    /// everywhere else.
    ///
    /// On the allowlisted hosts the ⬛︎ / ⬜︎ text-presentation squares render
    /// as single seamless glyphs, monochrome and theme-tintable, so the
    /// bolder two-cell style is both safe and prettier there. No such
    /// guarantee holds for other terminals — mis-measuring the selector
    /// shears the row (issue #9) — so they get the universally-correct
    /// ``unicode`` squares.
    ///
    /// This is what a running app uses when no ``SwiftUICore/View/toggleCharacterSet(_:)``
    /// modifier applies. (The bare `EnvironmentValues` default — what headless
    /// renders and tests see — is the terminal-independent ``unicode``.)
    ///
    /// **Resolved at render, not here.** This returns a marker
    /// (``resolvesFromTerminal``), and the render loop supplies the answer for
    /// the terminal in front of the user *this frame*. That matters because the
    /// answer can change while the app runs: under tmux it depends on the
    /// attached CLIENT's font, and detaching and re-attaching from a different
    /// terminal changes it. Resolving eagerly — as this used to — froze whatever
    /// was true when the value happened to be constructed, typically at app-state
    /// init, so `.toggleCharacterSet(.automatic)` could never notice.
    ///
    /// Outside a run loop (headless renders, tests) there is no terminal to
    /// consult and this draws ``unicode``, deterministically.
    public static var automatic: Self {
        var style = Self.unicode
        style.resolvesFromTerminal = true
        return style
    }

    /// The concrete style ``automatic`` resolves TO for a given terminal — the
    /// render loop's half of the deferral, and the testable core of the choice.
    static func automatic(emojiChrome: Bool) -> Self {
        emojiChrome ? .emoji : .unicode
    }
}

// MARK: - Environment

private struct ToggleCharacterSetKey: EnvironmentKey {
    /// The terminal-independent ``ToggleCharacterSet/unicode``, NOT
    /// ``ToggleCharacterSet/automatic``: a bare `EnvironmentValues` (headless
    /// renders, the test suite) must resolve identically whatever terminal
    /// hosts the process. The app run loop injects `.automatic` at the root
    /// (see `RenderLoop.buildEnvironment`), so real apps are terminal-adaptive.
    static let defaultValue: ToggleCharacterSet = .unicode
}

/// What ``ToggleCharacterSet/automatic`` resolves to for the terminal in front of the
/// user right now — supplied per frame by `RenderLoop.buildEnvironment`.
///
/// Its own default is ``ToggleCharacterSet/unicode`` so that a bare
/// `EnvironmentValues` (headless renders, the test suite) resolves `.automatic`
/// deterministically, with no dependence on whichever terminal happens to be
/// running the process.
private struct ResolvedAutomaticToggleCharacterSetKey: EnvironmentKey {
    static let defaultValue: ToggleCharacterSet = .unicode
}

extension EnvironmentValues {
    /// The glyph repertoire for ``Toggle``s in this environment.
    ///
    /// May be ``ToggleCharacterSet/automatic``, which is a marker rather than a
    /// decided set of glyphs — read ``effectiveToggleCharacterSet`` to draw with.
    public var toggleCharacterSet: ToggleCharacterSet {
        get { self[ToggleCharacterSetKey.self] }
        set { self[ToggleCharacterSetKey.self] = newValue }
    }

    /// The concrete style ``ToggleCharacterSet/automatic`` stands for this frame.
    var resolvedAutomaticToggleCharacterSet: ToggleCharacterSet {
        get { self[ResolvedAutomaticToggleCharacterSetKey.self] }
        set { self[ResolvedAutomaticToggleCharacterSetKey.self] = newValue }
    }

    /// The style to actually DRAW with: ``ToggleCharacterSet/automatic`` resolved
    /// against this frame's terminal, anything explicit used as it stands.
    ///
    /// Every render site must read this rather than ``toggleCharacterSet``, or an
    /// `.automatic` marker reaches the glyph code as its ``ToggleCharacterSet/unicode``
    /// fallback and the adaptation silently does nothing.
    var effectiveToggleCharacterSet: ToggleCharacterSet {
        let style = toggleCharacterSet
        return style.resolvesFromTerminal ? resolvedAutomaticToggleCharacterSet : style
    }
}

extension View {
    /// Sets the glyph repertoire (``ToggleCharacterSet/unicode`` by default, or
    /// e.g. ``ToggleCharacterSet/ascii``) for ``Toggle``s in this view — both
    /// checkbox marks and the switch track.
    ///
    /// TUI-specific: SwiftUI has no equivalent, so this is kept separate from the
    /// SwiftUI-parity ``toggleStyle(_:)``.
    public func toggleCharacterSet(_ style: ToggleCharacterSet) -> some View {
        environment(\.toggleCharacterSet, style)
    }
}
