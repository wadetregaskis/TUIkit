//  🖥️ TUIKit — Terminal UI Kit for Swift
//  String+TerminalWidth.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Terminal Character Width

extension Character {
    /// The display width of this character in a terminal (number of cells).
    ///
    /// Most characters occupy 1 cell. East Asian wide characters (CJK, most
    /// emoji) occupy 2 cells. Zero-width characters (combining marks,
    /// variation selectors, ZWJ) occupy 0 cells.
    public var terminalWidth: Int {
        let scalars = unicodeScalars
        guard let first = scalars.first else { return 0 }
        let scalarValue = first.value

        // Zero-width characters
        if scalarValue == 0x200B || scalarValue == 0x200C || scalarValue == 0x200D || scalarValue == 0xFEFF { return 0 }  // ZW space/NJ/J/BOM
        if scalarValue == 0x00AD { return 0 }  // soft hyphen
        if (0xFE00...0xFE0F).contains(scalarValue) { return 0 }  // variation selectors
        if (0xE0100...0xE01EF).contains(scalarValue) { return 0 }  // variation selectors supplement
        if (0x0300...0x036F).contains(scalarValue) { return 0 }  // combining diacritical marks
        if (0x1AB0...0x1AFF).contains(scalarValue) { return 0 }  // combining diacritical marks extended
        if (0x1DC0...0x1DFF).contains(scalarValue) { return 0 }  // combining diacritical marks supplement
        if (0x20D0...0x20FF).contains(scalarValue) { return 0 }  // combining marks for symbols
        if (0xFE20...0xFE2F).contains(scalarValue) { return 0 }  // combining half marks
        if (0xE0000...0xE007F).contains(scalarValue) { return 0 }  // tags block
        // NOTE: a skin-tone modifier reaching here is the FIRST scalar of the
        // grapheme cluster, i.e. it is *standalone* (no base) — when it
        // combines with a preceding emoji it is part of a multi-scalar cluster
        // whose first scalar is the base, handled below. Terminal.app paints a
        // standalone modifier as a 2-cell colour swatch (this is exactly how
        // the emoji-corpus list shows U+1F3FB…U+1F3FF), so it is 2 cells wide —
        // NOT zero. (Returning 0 here was a bug: it shifted everything after a
        // lone modifier left by 2 cells and dropped the enclosing border.)
        if (0x1F3FB...0x1F3FF).contains(scalarValue) { return 2 }  // standalone Fitzpatrick skin-tone swatch

        // Multi-scalar grapheme clusters (emoji sequences with ZWJ, skin tones,
        // flag sequences, keycap sequences) are typically 2 cells wide.
        if scalars.count > 1 {
            // If the only extra scalars are variation selectors (U+FE0F/U+FE0E),
            // check whether the variation selector promotes the base to emoji
            // presentation.  A `<base>+U+FE0F` cluster where the base has the
            // Emoji property paints 2 cells in Terminal.app — this catches
            // BMP emoji like ❤️ (U+2764+FE0F), ✏️ (U+270F+FE0F), ⚙️ (U+2699+FE0F)
            // that the historical range checks below would otherwise have
            // reported as 1 cell wide.
            let hasNonVariationExtras = scalars.dropFirst().contains { scalar in
                let sv = scalar.value
                return !(0xFE00...0xFE0F).contains(sv) && !(0xE0100...0xE01EF).contains(sv)
            }
            if hasNonVariationExtras {
                // True multi-character sequence (ZWJ, flags, keycaps, skin tones)
                return 2
            }
            // Base + variation selector(s).  If the selector is U+FE0F and
            // the base can be rendered as emoji, the cluster is 2 cells.
            // Otherwise fall through to the base character width check.
            if scalars.contains(where: { $0.value == 0xFE0F }) && first.properties.isEmoji {
                return 2
            }
        }

        // Single-scalar codepoints that default to colour emoji presentation
        // are painted as 2-cell glyphs by Terminal.app (and most modern
        // terminal emulators) regardless of whether they're in any of the
        // East Asian Wide ranges below.  This catches BMP codepoints like
        // ⌚ (U+231A), ⌛ (U+231B), ⏩ (U+23E9) that the range checks miss.
        if first.properties.isEmojiPresentation {
            return 2
        }

        // Emoji-presentation-by-default codepoints in the U+2300 block that
        // some platforms' `isEmojiPresentation` under-reports (notably macOS,
        // where the bundled Unicode data lags): Terminal.app paints these
        // 2 cells but the property check above returns false, so they'd
        // otherwise fall through to the 1-cell default. Pin them explicitly
        // so the width is correct cross-platform. (On Linux the property check
        // already catches them; these ranges are then a harmless no-op.)
        if (0x231A...0x231B).contains(scalarValue) { return 2 }  // ⌚ ⌛
        if (0x23E9...0x23EC).contains(scalarValue) { return 2 }  // ⏩ ⏪ ⏫ ⏬
        if scalarValue == 0x23F0 || scalarValue == 0x23F3 { return 2 }  // ⏰ ⏳

        // East Asian Wide and Fullwidth characters (2 cells)
        if (0x1100...0x115F).contains(scalarValue) { return 2 }  // Hangul Jamo
        if (0x2329...0x232A).contains(scalarValue) { return 2 }  // angle brackets
        if (0x2E80...0x303E).contains(scalarValue) { return 2 }  // CJK radicals, Kangxi, ideographic
        if (0x3041...0x33BF).contains(scalarValue) { return 2 }  // Hiragana, Katakana, Bopomofo, Hangul compat, Kanbun, CJK
        if (0x33D0...0x33FF).contains(scalarValue) { return 2 }  // CJK compatibility
        if (0x3400...0x4DBF).contains(scalarValue) { return 2 }  // CJK unified ext A
        if (0x4E00...0x9FFF).contains(scalarValue) { return 2 }  // CJK unified
        if (0xA000...0xA4CF).contains(scalarValue) { return 2 }  // Yi
        if (0xA960...0xA97F).contains(scalarValue) { return 2 }  // Hangul Jamo extended A
        if (0xAC00...0xD7AF).contains(scalarValue) { return 2 }  // Hangul syllables
        if (0xF900...0xFAFF).contains(scalarValue) { return 2 }  // CJK compatibility ideographs
        if (0xFE10...0xFE19).contains(scalarValue) { return 2 }  // vertical forms
        if (0xFE30...0xFE6F).contains(scalarValue) { return 2 }  // CJK compatibility forms, small forms
        if (0xFF01...0xFF60).contains(scalarValue) { return 2 }  // fullwidth forms
        if (0xFFE0...0xFFE6).contains(scalarValue) { return 2 }  // fullwidth signs
        if (0x1F000...0x1FBFF).contains(scalarValue) { return 2 }  // emoji and symbols (Mahjong, Dominos, Playing Cards, Emoji, etc.)
        if (0x20000...0x2FA1F).contains(scalarValue) { return 2 }  // CJK unified extensions B-F, compatibility supplement
        if (0x30000...0x3134F).contains(scalarValue) { return 2 }  // CJK unified extension G

        return 1
    }
}

// MARK: - Terminal.app Cursor-Advance Quirks

extension Character {
    /// The number of columns Terminal.app actually advances the text cursor
    /// by when this character is printed, which may differ from
    /// ``terminalWidth`` (the number of visual cells the character occupies).
    ///
    /// Terminal.app has a cluster of bugs around emoji presentation where
    /// certain grapheme clusters render visually at one width but advance
    /// the cursor by a different (smaller) amount. The classic examples are
    /// emoji with the U+FE0F emoji presentation selector whose base scalar
    /// lies in the 0x1F000–0x1FBFF pictographic block (e.g. 🖥️ = U+1F5A5 +
    /// U+FE0F): the glyph paints 2 cells wide but the cursor only advances
    /// by 1, so subsequent characters overlap the right half of the emoji.
    ///
    /// When ``terminalWidth`` and ``terminalAppCursorAdvance`` disagree,
    /// callers can emit a CUF (cursor forward) escape after the character
    /// to push the cursor to the visually-correct column. See
    /// ``String/withTerminalAppCursorCompensation()``.
    public var terminalAppCursorAdvance: Int {
        let scalars = unicodeScalars

        // A *lone* regional indicator (e.g. U+1F1E6 on its own — the emoji
        // corpus lists each one individually) paints 2 cells but Terminal.app
        // advances the cursor by only 1, the same under-advance as a flag
        // PAIR. This must be handled before the multi-scalar guard below (a
        // lone indicator is a single scalar); otherwise it reports advance =
        // width = 2 and the following content (and any enclosing border) lands
        // one cell too far left. (Terminal.app additionally mis-paints the
        // lone glyph itself — clipped/offset — which no escape sequence can
        // fix; this only corrects the cursor accounting so the layout aligns.)
        if scalars.count == 1, let only = scalars.first,
            (0x1F1E6...0x1F1FF).contains(only.value)
        {
            return 1
        }

        guard scalars.count > 1, let first = scalars.first else { return terminalWidth }

        let hasVS16 = scalars.contains { $0.value == 0xFE0F }
        let hasNonVariationExtras = scalars.dropFirst().contains { scalar in
            let sv = scalar.value
            return !(0xFE00...0xFE0F).contains(sv) && !(0xE0100...0xE01EF).contains(sv)
        }

        // `<base>+U+FE0F` where the base is a default-text-presentation
        // emoji (e.g. ❤️ = U+2764+FE0F, ✏️ = U+270F+FE0F, 🖥️ = U+1F5A5+FE0F):
        // Terminal.app paints the glyph 2 cells wide (matching `terminalWidth`)
        // but only advances the cursor by 1.  Using `Unicode.Scalar.Properties`
        // catches BMP bases too, not just the `0x1F000-0x1FBFF` block.
        if hasVS16 && !hasNonVariationExtras
            && first.properties.isEmoji
            && !first.properties.isEmojiPresentation
        {
            return 1
        }

        // Flag emoji — a pair of regional-indicator scalars
        // (U+1F1E6…U+1F1FF), e.g. 🇺🇸 = U+1F1FA + U+1F1F8.
        // Terminal.app paints 2 cells but advances the cursor by only 1,
        // the same under-advance pattern as VS-16 pictographic emoji.
        // Subsequent characters on the row would otherwise land one cell
        // to the left of where the column accounting expects them.
        if scalars.count == 2,
            (0x1F1E6...0x1F1FF).contains(first.value),
            let second = scalars.dropFirst().first,
            (0x1F1E6...0x1F1FF).contains(second.value)
        {
            return 1
        }

        // Fitzpatrick skin-tone modifier (U+1F3FB–U+1F3FF) on an emoji-
        // modifier-base codepoint: Terminal.app paints 2 cells but advances
        // the cursor by either 4 (default-emoji-presentation bases like
        // 🤙 ✊ 👍) or 3 (default-text-presentation bases like ☝ ✌ ✍ ⛹
        // 🏋 🏌 🕴 🕵 🖐 — the "BMP-style" variant catalogued empirically).
        // The split tracks the bare-base width: emoji-presentation bases
        // are 2-cell bare and over-advance by 2; text-presentation bases
        // are 1-cell bare and over-advance by 2 from that baseline → 3.
        let hasSkinTone = scalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
        if hasSkinTone && first.properties.isEmojiModifierBase {
            return first.properties.isEmojiPresentation ? 4 : 3
        }

        return terminalWidth
    }
}

extension String {
    /// Returns `true` if any character in this string has a Terminal.app
    /// cursor advance that differs from its visible cell width — VS-16
    /// pictographic emoji (advance 1, width 2) or any Fitzpatrick skin-
    /// tone cluster whose modifier survived ``withTerminalAppCursorCompensation``
    /// (i.e. it was the last visible character on the line — advance 4,
    /// width 2).  These rows trip Terminal.app's right-edge phantom-cell
    /// bug; `FrameDiffWriter.repaintRightEdge` uses this check to scope
    /// its two-pass repaint to only the rows that need it.
    public var containsTerminalAppCursorAdvanceQuirk: Bool {
        var index = startIndex
        while index < endIndex {
            if self[index] == "\u{1B}" {
                // Skip ANSI escape sequences.
                index = self.index(after: index)
                if index < endIndex && self[index] == "[" {
                    index = self.index(after: index)
                    while index < endIndex && (self[index].isNumber || self[index] == ";") {
                        index = self.index(after: index)
                    }
                    if index < endIndex && self[index].isLetter {
                        index = self.index(after: index)
                    }
                }
                continue
            }
            let c = self[index]
            if c.terminalAppCursorAdvance != c.terminalWidth {
                return true
            }
            index = self.index(after: index)
        }
        return false
    }

    /// Returns a copy of this string with Terminal.app's cursor-advance
    /// quirks worked around.
    ///
    /// - **VS-16 pictographic emoji** (under-advance: paints 2 cells but
    ///   advances the cursor by 1, e.g. 🖥️):  a `CUF(1)` is injected after
    ///   the cluster to push the cursor to its visual end.
    ///
    /// - **Fitzpatrick skin-tone cluster** (over-advance: paints 2 cells
    ///   but advances the cursor by 4, e.g. 🤙🏽):
    ///   * If the cluster is followed by any visible content on the same
    ///     line, the Fitzpatrick scalar is **stripped** — Terminal.app's
    ///     row-wide LEFT shift on rows that carry the modifier would
    ///     otherwise push the trailing content (padding, box border)
    ///     into the row's rightmost 2 cells and leave them unpainted.
    ///     No ANSI escape recovers from this: any backward cursor
    ///     movement after the cluster strips the modifier anyway, and
    ///     forward writes past the right edge wrap or clamp.
    ///   * If the cluster is the last visible character on the line,
    ///     the modifier is **kept** — the over-advance happens with
    ///     nothing on the row after it, so the shift has nothing to
    ///     push out of place.
    ///
    /// ANSI escape sequences in the input are preserved.
    public func withTerminalAppCursorCompensation() -> String {
        var result = ""
        result.reserveCapacity(self.count + 8)
        var index = startIndex

        while index < endIndex {
            let c = self[index]

            if c == "\u{1B}" {
                // Preserve an entire ANSI escape sequence: ESC [ params letter
                let seqStart = index
                index = self.index(after: index)
                if index < endIndex && self[index] == "[" {
                    index = self.index(after: index)
                    while index < endIndex && (self[index].isNumber || self[index] == ";") {
                        index = self.index(after: index)
                    }
                    if index < endIndex && self[index].isLetter {
                        index = self.index(after: index)
                    }
                }
                result += self[seqStart..<index]
                continue
            }

            let claimed = c.terminalWidth
            let actual = c.terminalAppCursorAdvance
            if claimed > actual {
                // Under-advancer — push the cursor forward to the
                // visual end of the glyph with CUF.
                result.append(c)
                result += "\u{1B}[\(claimed - actual)C"
            } else if actual > claimed && Self.hasVisibleContent(in: self, after: self.index(after: index)) {
                // Over-advancer followed by content — strip the
                // Fitzpatrick scalar so Terminal.app doesn't apply the
                // row-wide LEFT shift.
                var baseScalar: Unicode.Scalar?
                var keptVS16 = false
                for scalar in c.unicodeScalars where !(0x1F3FB...0x1F3FF).contains(scalar.value) {
                    if baseScalar == nil { baseScalar = scalar }
                    if scalar.value == 0xFE0F { keptVS16 = true }
                    result.unicodeScalars.append(scalar)
                }
                // Text-default emoji bases (☝ U+261D, ✌ U+270C, 🖐 U+1F590…)
                // render bare as a 1-cell text glyph in Terminal.app — so
                // simply dropping the Fitzpatrick would shrink the cluster
                // from 2 cells to 1, displacing every subsequent character
                // on the row left by 1 cell.  Restore the 2-cell coloured-
                // emoji rendering by appending U+FE0F (a no-op for default-
                // emoji-presentation bases like ✊, so we only do it for
                // text-default bases), then emit CUF(1) to compensate for
                // the VS-16 under-advance (Bug A).
                if let base = baseScalar,
                   base.properties.isEmoji && !base.properties.isEmojiPresentation
                {
                    if !keptVS16 {
                        result.unicodeScalars.append(Unicode.Scalar(0xFE0F)!)
                    }
                    result += "\u{1B}[1C"
                }
            } else {
                // Normal char, or an over-advancer at the very end of
                // the input — emit verbatim.
                result.append(c)
            }
            index = self.index(after: index)
        }

        return result
    }

    /// Returns `true` if any character at or after `start` in `string`
    /// occupies a terminal cell.  Plain ASCII, CJK, emoji etc. all
    /// count; ANSI escape sequences and zero-width characters do not.
    fileprivate static func hasVisibleContent(in string: String, after start: String.Index) -> Bool {
        var index = start
        while index < string.endIndex {
            if string[index] == "\u{1B}" {
                index = string.index(after: index)
                if index < string.endIndex && string[index] == "[" {
                    index = string.index(after: index)
                    while index < string.endIndex && (string[index].isNumber || string[index] == ";") {
                        index = string.index(after: index)
                    }
                    if index < string.endIndex && string[index].isLetter {
                        index = string.index(after: index)
                    }
                }
                continue
            }
            if string[index].terminalWidth > 0 {
                return true
            }
            index = string.index(after: index)
        }
        return false
    }
}

// MARK: - ANSI String Helpers

extension String {
    /// The visible width of the string in terminal cells, excluding ANSI escape codes.
    ///
    /// Accounts for wide characters (emoji, CJK) that occupy 2 terminal cells
    /// and zero-width characters (combining marks, variation selectors).
    public var strippedLength: Int {
        visibleANSIRuns().reduce(0) { total, run in
            total + run.reduce(0) { $0 + $1.terminalWidth }
        }
    }

    /// The visible text of this string split into runs separated by CSI
    /// (`ESC [ … letter`) escape sequences, with the sequences removed.
    ///
    /// Two things matter here, both about grapheme clustering around escape
    /// sequences:
    ///
    /// 1. **Scan at the scalar level, not by `Character`.** An SGR
    ///    terminator is a letter (e.g. `m`), and styled output places visible
    ///    content right after it. If that content begins with an `Extend`
    ///    scalar — a Fitzpatrick skin-tone modifier (U+1F3FB…U+1F3FF), a ZWJ,
    ///    a combining mark, a variation selector — Swift grapheme-clusters it
    ///    onto the terminator letter (`m` + 🏽 → one `Character`). A
    ///    `Character`-level skip of "the final letter" would consume the
    ///    modifier with the escape sequence and drop its width (an
    ///    ANSI-wrapped standalone modifier measured 0 cells). Skipping one
    ///    scalar for the terminator keeps the modifier visible.
    ///
    /// 2. **Keep the runs separate; do not concatenate before measuring.**
    ///    Content on opposite sides of an escape sequence is visually
    ///    distinct and must be measured independently. A space ending one
    ///    styled run followed by a skin-tone modifier starting the next is
    ///    1 + 2 cells, but concatenating them would let the `Extend` modifier
    ///    cluster onto the space and be miscounted as a single 2-cell glyph
    ///    (the residual off-by-one after fix 1). Each run is grapheme-
    ///    clustered on its own.
    private func visibleANSIRuns() -> [String] {
        var runs: [String] = []
        var current = Self.UnicodeScalarView()
        let scalars = unicodeScalars
        var index = scalars.startIndex

        func flush() {
            if !current.isEmpty {
                runs.append(String(current))
                current = Self.UnicodeScalarView()
            }
        }

        while index < scalars.endIndex {
            if scalars[index].value == 0x1B {  // ESC — start of a CSI sequence
                flush()
                index = scalars.index(after: index)
                if index < scalars.endIndex, scalars[index].value == 0x5B {  // '['
                    index = scalars.index(after: index)
                    // Parameter bytes: ASCII digits and ';'.
                    while index < scalars.endIndex,
                        (0x30...0x39).contains(scalars[index].value) || scalars[index].value == 0x3B {
                        index = scalars.index(after: index)
                    }
                    // Final byte: a single ASCII letter. Advance exactly one
                    // scalar so any following Extend scalar is preserved.
                    if index < scalars.endIndex,
                        (0x41...0x5A).contains(scalars[index].value)
                            || (0x61...0x7A).contains(scalars[index].value) {
                        index = scalars.index(after: index)
                    }
                }
            } else {
                current.append(scalars[index])
                index = scalars.index(after: index)
            }
        }
        flush()
        return runs
    }

    /// The string with all ANSI (CSI) escape codes removed.
    public var stripped: String {
        visibleANSIRuns().joined()
    }

    /// Returns a copy with ANSI escape sequences removed, suitable for rendering user-provided content.
    ///
    /// Use this to sanitize user input before passing it to ``Text`` or other views
    /// to prevent terminal escape sequence injection (cursor manipulation, color changes, etc.).
    ///
    /// ```swift
    /// Text(userInput.sanitizedForTerminal)
    /// ```
    public var sanitizedForTerminal: String {
        stripped
    }

    /// Pads the string to the specified visible width using spaces.
    ///
    /// ANSI codes and wide characters are handled correctly.
    ///
    /// - Parameter targetWidth: The desired visible width in terminal cells.
    /// - Returns: The padded string.
    public func padToVisibleWidth(_ targetWidth: Int) -> String {
        let currentWidth = strippedLength
        if currentWidth >= targetWidth {
            return self
        }
        return self + String(repeating: " ", count: targetWidth - currentWidth)
    }

    // MARK: - ANSI-Aware Splitting

    /// Returns the first `visibleCount` terminal cells worth of visible characters,
    /// preserving all ANSI codes that appear before or within that range.
    ///
    /// Wide characters (emoji, CJK) count as 2 cells. If a wide character would
    /// exceed the limit, it is excluded.
    ///
    /// - Parameter visibleCount: The number of terminal cells to include.
    /// - Returns: A substring with ANSI codes intact up to the visible boundary.
    public func ansiAwarePrefix(visibleCount: Int) -> String {
        guard visibleCount > 0 else { return "" }

        var result = ""
        var visible = 0
        var index = startIndex

        while index < endIndex && visible < visibleCount {
            // Check if we're at the start of an ANSI escape sequence
            if self[index] == "\u{1B}" {
                // Consume the entire ANSI sequence (ESC [ ... letter)
                let seqStart = index
                index = self.index(after: index)
                if index < endIndex && self[index] == "[" {
                    index = self.index(after: index)
                    // Skip parameter bytes (digits, semicolons)
                    while index < endIndex && (self[index].isNumber || self[index] == ";") {
                        index = self.index(after: index)
                    }
                    // Skip the final byte (letter)
                    if index < endIndex && self[index].isLetter {
                        index = self.index(after: index)
                    }
                }
                result += String(self[seqStart..<index])
            } else {
                let charWidth = self[index].terminalWidth
                if visible + charWidth > visibleCount { break }
                result.append(self[index])
                visible += charWidth
                index = self.index(after: index)
            }
        }

        return result
    }

    /// Like ``ansiAwarePrefix(visibleCount:)`` but cursor-aware — clips so
    /// that no character's Terminal.app cursor advance would push past the
    /// right edge.
    ///
    /// An over-advancing emoji (e.g. Fitzpatrick skin-tone 🤙🏽: claims 2
    /// cells, advances cursor by 4) whose VISIBLE cells fit but whose
    /// advance overflows the right edge is REPLACED with plain spaces of
    /// its claimed visible width.  If we let Terminal.app see the cluster
    /// in this case it wraps the glyph to the next row (because it can't
    /// reserve the 4 cells of buffer it wants), corrupting the layout
    /// of the row below.
    ///
    /// - Parameter visibleCount: The number of terminal cells to include.
    /// - Returns: A substring with ANSI codes intact, clipped so that no
    ///   character wraps off the right edge.
    public func ansiAwarePrefixForTerminalApp(visibleCount: Int) -> String {
        guard visibleCount > 0 else { return "" }

        var result = ""
        var visible = 0
        var cursor  = 0   // Terminal.app cursor advance from start of line
        var index   = startIndex

        while index < endIndex && visible < visibleCount {
            if self[index] == "\u{1B}" {
                let seqStart = index
                index = self.index(after: index)
                if index < endIndex && self[index] == "[" {
                    index = self.index(after: index)
                    while index < endIndex && (self[index].isNumber || self[index] == ";") {
                        index = self.index(after: index)
                    }
                    if index < endIndex && self[index].isLetter {
                        index = self.index(after: index)
                    }
                }
                result += String(self[seqStart..<index])
                continue
            }
            let c = self[index]
            let charWidth = c.terminalWidth
            if visible + charWidth > visibleCount { break }
            let advance = c.terminalAppCursorAdvance
            if advance > charWidth && cursor + advance > visibleCount {
                // Over-advancer that would push Terminal.app's cursor past
                // the right edge.  Replace with `charWidth` plain spaces
                // to preserve the layout but avoid the wrap-to-next-row
                // bug.  Skin tone is sacrificed in this narrow case.
                if charWidth > 0 {
                    result.append(String(repeating: " ", count: charWidth))
                }
                visible += charWidth
                cursor += charWidth
                index = self.index(after: index)
                continue
            }
            result.append(c)
            visible += charWidth
            cursor += advance
            index = self.index(after: index)
        }

        return result
    }

    /// Returns the accumulated SGR (colour/style) state as of `visibleOffset` visible cells,
    /// concatenated with the remaining visible content and SGR sequences — but with all
    /// non-SGR ANSI sequences (cursor movement, erase, etc.) stripped from both the
    /// context scan *and* the returned suffix.
    ///
    /// Used by ``FrameDiffWriter.repaintRightEdge`` to re-emit the last few cells of a
    /// line with the correct SGR context: the caller positions the terminal cursor
    /// explicitly before writing the result, so any CUF / EL / other cursor-movement
    /// sequence left in the string would displace the cursor from where the caller put
    /// it and write subsequent characters in the wrong terminal column.
    ///
    /// - Parameter visibleOffset: The number of visible terminal cells to skip.
    /// - Returns: Accumulated SGR state + visible content from `visibleOffset` onward
    ///   (all non-SGR sequences stripped), or `nil` if the string has fewer than
    ///   `visibleOffset` visible cells.
    public func ansiSGRContextAndCleanSuffix(from visibleOffset: Int) -> String? {
        var sgrContext = ""
        var index = startIndex
        var visible = 0

        // Phase 1: scan to visibleOffset, accumulate only SGR sequences.
        while index < endIndex && visible < visibleOffset {
            if self[index] == "\u{1B}" {
                let seqStart = index
                index = self.index(after: index)
                if index < endIndex && self[index] == "[" {
                    index = self.index(after: index)
                    while index < endIndex && (self[index].isNumber || self[index] == ";") {
                        index = self.index(after: index)
                    }
                    if index < endIndex && self[index].isLetter {
                        if self[index] == "m" {
                            sgrContext += String(self[seqStart...index])
                        }
                        // Non-SGR sequences (CUF, EL, …) consumed but not kept
                        index = self.index(after: index)
                    }
                }
            } else {
                visible += self[index].terminalWidth
                index = self.index(after: index)
            }
        }

        guard visible >= visibleOffset else { return nil }

        // Phase 2: build suffix keeping visible chars and SGR sequences only.
        // Non-SGR ANSI sequences (CUF, ESC[2K, etc.) are dropped so they
        // cannot displace the cursor when the caller writes at a fixed column.
        var suffix = ""
        while index < endIndex {
            if self[index] == "\u{1B}" {
                let seqStart = index
                index = self.index(after: index)
                if index < endIndex && self[index] == "[" {
                    index = self.index(after: index)
                    while index < endIndex && (self[index].isNumber || self[index] == ";") {
                        index = self.index(after: index)
                    }
                    if index < endIndex && self[index].isLetter {
                        if self[index] == "m" {
                            // SGR — keep it
                            suffix += String(self[seqStart...index])
                        }
                        // Non-SGR — drop it entirely
                        index = self.index(after: index)
                    }
                }
            } else {
                suffix.append(self[index])
                index = self.index(after: index)
            }
        }

        return sgrContext + suffix
    }

    /// Returns everything after the first `dropCount` terminal cells of visible characters,
    /// preserving ANSI codes that appear at or after that boundary.
    ///
    /// Wide characters count as 2 cells.
    ///
    /// - Parameter dropCount: The number of terminal cells to skip.
    /// - Returns: The remainder of the string with ANSI codes intact.
    public func ansiAwareSuffix(droppingVisible dropCount: Int) -> String {
        var visible = 0
        var index = startIndex

        while index < endIndex && visible < dropCount {
            if self[index] == "\u{1B}" {
                // Skip the entire ANSI sequence
                index = self.index(after: index)
                if index < endIndex && self[index] == "[" {
                    index = self.index(after: index)
                    while index < endIndex && (self[index].isNumber || self[index] == ";") {
                        index = self.index(after: index)
                    }
                    if index < endIndex && self[index].isLetter {
                        index = self.index(after: index)
                    }
                }
            } else {
                visible += self[index].terminalWidth
                index = self.index(after: index)
            }
        }

        guard index < endIndex else { return "" }
        return String(self[index...])
    }

    // MARK: - ANSI State Extraction

    /// Extracts all leading ANSI SGR sequences that appear before the first
    /// visible character and returns them concatenated.
    ///
    /// This captures the full styling state set up at the beginning of a line
    /// (e.g. background, foreground, dim) so it can be replayed to restore
    /// that state after an interruption (like an overlay insertion).
    ///
    /// Unlike scanning the entire string, this avoids picking up trailing
    /// codes that follow a reset (e.g. the lone background code appended by
    /// `applyPersistentBackground`).
    ///
    /// - Returns: The concatenated leading ANSI sequences, or an empty string
    ///   if the line starts with a visible character.
    public func leadingANSISequences() -> String {
        var result = ""
        var index = startIndex

        while index < endIndex {
            guard self[index] == "\u{1B}" else { break }

            // Consume the ANSI sequence (ESC [ params letter)
            let seqStart = index
            index = self.index(after: index)
            if index < endIndex && self[index] == "[" {
                index = self.index(after: index)
                while index < endIndex && (self[index].isNumber || self[index] == ";") {
                    index = self.index(after: index)
                }
                if index < endIndex && self[index].isLetter {
                    index = self.index(after: index)
                }
            }
            result += String(self[seqStart..<index])
        }

        return result
    }
}
