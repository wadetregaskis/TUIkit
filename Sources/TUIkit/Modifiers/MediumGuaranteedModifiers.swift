//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MediumGuaranteedModifiers.swift
//
//  SwiftUI modifiers whose GUARANTEE a character grid already provides.
//
//  These return `self`, and that is not a stub. A stub accepts a request the
//  medium cannot meet and quietly drops it — TUIkit removes those instead, so
//  the call fails to compile and the gap is the developer's to decide about
//  (`.submitLabel` was one, deleted for exactly that reason). These make a
//  promise the medium keeps: every cell is one column wide, so text is already
//  monospaced and digits are already tabular; nothing between the keyboard and
//  a `TextField`'s binding rewrites what was typed, so there is no
//  autocorrection to disable.
//
//  The distinction is directional, and worth stating because the argument is
//  ignored either way: `.monospaced(true)` is honoured — by the grid, for
//  free — while `.monospaced(false)` asks for proportional text, which no
//  terminal can give. The modifier survives because its default and its
//  overwhelmingly common spelling are the satisfiable ones; deleting it to
//  reject `false` would reject the honoured case too.
//
//  Each is covered by a test that asserts the GUARANTEE — equal cell widths
//  for equal character counts, a misspelling arriving intact — rather than
//  asserting the no-op, which would prove nothing and would keep passing if
//  the medium ever stopped holding up its end.
//
//  Created by Wade Tregaskis
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Renders this view's text with a monospaced font — mirrors SwiftUI's
    /// `monospaced(_:)`.
    ///
    /// Already true, and not by choice: a terminal draws into a grid of equal
    /// cells, so every glyph advances the same distance. The modifier exists so
    /// SwiftUI source compiles and expresses the same intent; it has nothing to
    /// change.
    ///
    /// - Parameter isActive: Ignored — the guarantee holds either way. A
    ///   terminal cannot render *proportionally*, so `false` cannot mean what
    ///   it means in SwiftUI.
    /// - Returns: This view, unchanged.
    public func monospaced(_ isActive: Bool = true) -> some View {
        self
    }

    /// Renders digits with uniform width — mirrors SwiftUI's
    /// `monospacedDigit()`.
    ///
    /// SwiftUI needs this because a proportional font gives `1` and `8`
    /// different widths, so a changing number jitters. In a cell grid they are
    /// one cell each already, which is why a `ProgressView`'s percentage or a
    /// `Table`'s numeric column has never had to ask.
    ///
    /// - Returns: This view, unchanged.
    public func monospacedDigit() -> some View {
        self
    }

    /// Disables autocorrection for text input in this view — mirrors SwiftUI's
    /// `autocorrectionDisabled(_:)`.
    ///
    /// There is none to disable. Nothing between the key event and the
    /// binding rewrites what was typed: TUIkit has no autocorrection,
    /// autocapitalisation or spell-check, and a terminal supplies none either.
    /// A field holds exactly the characters that arrived.
    ///
    /// - Parameter disable: Ignored — text is never corrected, so `false`
    ///   cannot turn a correction back on.
    /// - Returns: This view, unchanged.
    public func autocorrectionDisabled(_ disable: Bool = true) -> some View {
        self
    }
}
