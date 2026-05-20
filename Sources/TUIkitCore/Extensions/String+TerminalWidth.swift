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
        if (0x1F3FB...0x1F3FF).contains(scalarValue) { return 0 }  // emoji skin-tone modifiers (Fitzpatrick types 1–6, always combine with preceding emoji)

        // Multi-scalar grapheme clusters (emoji sequences with ZWJ, skin tones,
        // flag sequences, keycap sequences) are typically 2 cells wide.
        if scalars.count > 1 {
            // If the only extra scalars are variation selectors (U+FE0F/U+FE0E),
            // fall through to the base character width check. Many terminals
            // don't widen characters just because of a presentation selector
            // (e.g. ⚙️ = U+2699 + U+FE0F is still 1 cell in most terminals).
            let hasNonVariationExtras = scalars.dropFirst().contains { scalar in
                let sv = scalar.value
                return !(0xFE00...0xFE0F).contains(sv) && !(0xE0100...0xE01EF).contains(sv)
            }
            if hasNonVariationExtras {
                // True multi-character sequence (ZWJ, flags, keycaps, skin tones)
                return 2
            }
            // Just base + variation selector(s): fall through to base char width
        }

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
        guard scalars.count > 1 else { return terminalWidth }

        // VS-16 (U+FE0F) emoji presentation selector on a pictographic base
        // in the 0x1F000–0x1FBFF block: Terminal.app renders the glyph as a
        // 2-cell wide emoji but only advances the cursor by 1.
        let hasVS16 = scalars.contains { $0.value == 0xFE0F }
        let hasNonVariationExtras = scalars.dropFirst().contains { scalar in
            let sv = scalar.value
            return !(0xFE00...0xFE0F).contains(sv) && !(0xE0100...0xE01EF).contains(sv)
        }
        if hasVS16 && !hasNonVariationExtras {
            if let first = scalars.first, (0x1F000...0x1FBFF).contains(first.value) {
                return 1
            }
        }

        // Fitzpatrick skin-tone modifiers (U+1F3FB–U+1F3FF) on a pictographic
        // base in the 0x1F000–0x1FBFF block: Terminal.app renders the glyph
        // 2 cells wide but advances the cursor by 4.
        // `withTerminalAppCursorCompensation` emits the cluster inline and
        // leaves the cursor over-advanced; `FrameDiffWriter.repaintRightEdge`
        // re-writes the row's right edge via absolute cursor positioning so
        // the border still lands where the layout reserved it.  Any cursor
        // escape that would undo the over-advance directly (CUB / CHA /
        // DECRC after the cluster) makes Terminal.app drop the Fitzpatrick
        // scalar.
        let skinToneRange: ClosedRange<UInt32> = 0x1F3FB...0x1F3FF
        let hasSkinTone = scalars.contains { skinToneRange.contains($0.value) }
        if hasSkinTone {
            if let first = scalars.first, (0x1F000...0x1FBFF).contains(first.value) {
                return 4
            }
        }

        return terminalWidth
    }
}

extension String {
    /// Returns `true` if any character in this string differs in claimed
    /// visible width vs Terminal.app cursor advance (VS-16 emoji under-
    /// advancing by 1, Fitzpatrick skin-tone clusters over-advancing by 2).
    /// Both quirks trigger Terminal.app's right-edge phantom-cell bug and
    /// need the two-pass repaint to land the last two cells at the app's
    /// background.
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

    /// Returns `true` if this string contains at least one skin-tone-modified
    /// emoji (a grapheme cluster whose scalars include a Fitzpatrick modifier,
    /// U+1F3FB–U+1F3FF, combined with a base emoji scalar).
    ///
    /// Used by ``FrameDiffWriter`` to scope Terminal.app's phantom-cell
    /// right-edge repaint to only rows that actually need it.
    public var containsSkinToneEmoji: Bool {
        let skinToneRange: ClosedRange<UInt32> = 0x1F3FB...0x1F3FF
        for char in self {
            let scalars = char.unicodeScalars
            guard scalars.count > 1 else { continue }
            guard scalars.first?.value != 0x1B else { continue }
            if scalars.contains(where: { skinToneRange.contains($0.value) }) {
                return true
            }
        }
        return false
    }
}

extension String {
    /// Returns a copy of this string with Terminal.app cursor-advance quirks
    /// compensated for.  Convenience over
    /// ``withTerminalAppCursorCompensationParts()`` that concatenates the
    /// main content and the trailing deferred-cluster writes.
    public func withTerminalAppCursorCompensation() -> String {
        let parts = withTerminalAppCursorCompensationParts()
        return parts.main + parts.deferred
    }

    /// Returns the string in two pieces: the `main` content that should be
    /// written in place, and a `deferred` trailing section that must be
    /// written AFTER any padding the caller appends to the line.
    ///
    /// Terminal.app's cursor-advance quirks are handled like this:
    ///
    /// - **VS-16 pictographic emoji under-advance** (e.g. 🖥️):  a CUF
    ///   (cursor-forward) is injected after the cluster to push the cursor
    ///   to its visual end.  Emitted in `main` next to the cluster.
    /// - **Fitzpatrick skin-tone over-advance** (e.g. 🤙🏽):  emitted
    ///   inline with **no** compensation.  Terminal.app's cursor counter
    ///   ends up 2 columns past where the layout reserved cells, which
    ///   would normally push subsequent content right — but the
    ///   per-row right-edge repaint in `FrameDiffWriter` (driven by
    ///   ``containsTerminalAppCursorAdvanceQuirk``) re-writes the right-
    ///   most 2 cells via absolute cursor positioning, putting the box's
    ///   right border back where the layout intended.
    ///
    ///   Any cursor escape that would undo the over-advance directly
    ///   (CUB / CHA / DECRC after the cluster) makes Terminal.app drop
    ///   the Fitzpatrick modifier — so we explicitly do not emit one.
    ///
    /// `deferred` is currently always empty — the field is retained for
    /// API compatibility with callers that destructure the tuple, and so
    /// the deferred-write path can be reinstated for any future Terminal.app
    /// quirk that genuinely needs end-of-row positioning.  ANSI escape
    /// sequences in the input are preserved.
    public func withTerminalAppCursorCompensationParts() -> (main: String, deferred: String, mainCursorEnd: Int) {
        var main = ""
        main.reserveCapacity(self.count + 8)
        var index = startIndex
        var col = 1   // 1-indexed cursor column after the most recent main write

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
                main += self[seqStart..<index]
                continue
            }

            let claimed = c.terminalWidth
            let actual = c.terminalAppCursorAdvance
            if claimed > actual {
                // Under-advancer (e.g. VS-16 pictographic emoji): push
                // the cursor forward to the visual end of the glyph.
                main.append(c)
                main += "\u{1B}[\(claimed - actual)C"
                col += claimed
            } else if actual > claimed {
                // Over-advancer (Fitzpatrick skin-tone cluster).
                // Terminal.app applies a row-wide LEFT shift to any row
                // containing the cluster — every cell painted by the
                // line ends up ~2 columns left of where its bytes
                // placed it.  When the cluster is followed by inline
                // content on the same line (e.g. trailing padding +
                // a box border), that border falls into the shifted-
                // away cells at the right edge and the rightmost 2
                // cells are unpainted.  Empirically, no compensating
                // cursor escape recovers this — CUB/CHA/DECRC after
                // the cluster strip the modifier, CUP past the edge
                // clamps, and inline overdraw past the edge wraps.
                //
                // So when there's visible content after the cluster
                // on the same line, sacrifice the Fitzpatrick scalar
                // (emit only the base emoji's scalars).  Terminal.app
                // then renders the cluster as a normal 2-cell emoji
                // with no over-advance and no row-wide shift, keeping
                // the layout intact.  When the cluster IS the last
                // visible content on the line we keep the modifier —
                // the over-advance happens after the row is done so
                // it can't push anything out of place.
                if Self.hasVisibleContentAfter(string: self, after: self.index(after: index)) {
                    for scalar in c.unicodeScalars {
                        if !(0x1F3FB...0x1F3FF).contains(scalar.value) {
                            main.unicodeScalars.append(scalar)
                        }
                    }
                } else {
                    main.append(c)
                }
                col += claimed
            } else {
                main.append(c)
                col += claimed
            }
            index = self.index(after: index)
        }

        return (main: main, deferred: "", mainCursorEnd: col)
    }

    /// Returns `true` if any character at or after `start` in `string`
    /// contributes a visible cell to the rendered output (i.e. would
    /// occupy a terminal column).  Plain ASCII, CJK, emoji etc. all
    /// count; ANSI escape sequences are skipped.  Used by
    /// ``withTerminalAppCursorCompensationParts()`` to decide whether
    /// an over-advancing cluster has anything following it on the row
    /// that would suffer the row-wide LEFT shift.
    fileprivate static func hasVisibleContentAfter(string: String, after start: String.Index) -> Bool {
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
        var count = 0
        var index = startIndex

        while index < endIndex {
            if self[index] == "\u{1B}" {
                // Skip ANSI sequence: ESC [ params letter
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
            } else {
                count += self[index].terminalWidth
                index = self.index(after: index)
            }
        }

        return count
    }

    /// The string with all ANSI escape codes removed.
    public var stripped: String {
        var result = ""
        result.reserveCapacity(count)
        var index = startIndex

        while index < endIndex {
            if self[index] == "\u{1B}" {
                // Skip ANSI sequence: ESC [ params letter
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
                result.append(self[index])
                index = self.index(after: index)
            }
        }

        return result
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
                cursor  += charWidth
                index = self.index(after: index)
                continue
            }
            result.append(c)
            visible += charWidth
            cursor  += advance
            index = self.index(after: index)
        }

        return result
    }

    /// Returns the accumulated SGR (colour/style) state as of `visibleOffset`
    /// visible cells into the string, concatenated with all remaining content
    /// from that offset onward.
    ///
    /// This is used by ``FrameDiffWriter`` to re-emit the last few cells of a
    /// line with the correct SGR context, compensating for Terminal.app's
    /// phantom-cell bug that leaves the right edge at the default terminal
    /// background (see `repaintRightEdge`).
    ///
    /// - Non-SGR ANSI sequences (cursor movement, erase, etc.) before the
    ///   split are dropped from the context — only `m`-terminated SGR
    ///   sequences are replayed.
    /// - Non-SGR sequences that appear *at or after* the split are included
    ///   verbatim in the returned content.
    ///
    /// - Parameter visibleOffset: The number of visible terminal cells to skip.
    /// - Returns: Accumulated SGR state + content from `visibleOffset` onward,
    ///   or `nil` if the string has fewer than `visibleOffset` visible cells.
    public func ansiSGRContextAndSuffix(from visibleOffset: Int) -> String? {
        var sgrContext = ""
        var index = startIndex
        var visible = 0

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
                            // SGR sequence — accumulate for context replay
                            sgrContext += String(self[seqStart...index])
                        }
                        // Non-SGR sequences (CUF, ED, EL, …) are consumed but not kept
                        index = self.index(after: index)
                    }
                }
            } else {
                visible += self[index].terminalWidth
                index = self.index(after: index)
            }
        }

        guard visible >= visibleOffset else { return nil }
        return sgrContext + String(self[index...])
    }

    /// Returns the accumulated SGR (colour/style) state as of `visibleOffset` visible cells,
    /// concatenated with the remaining visible content and SGR sequences — but with all
    /// non-SGR ANSI sequences (cursor movement, erase, etc.) stripped from both the
    /// context scan *and* the returned suffix.
    ///
    /// Use this instead of ``ansiSGRContextAndSuffix(from:)`` when you are about to
    /// position the terminal cursor explicitly before writing the result. Any CUF,
    /// EL, or other cursor-movement sequence left in the string would displace the
    /// cursor from where you positioned it, writing subsequent characters in the wrong
    /// terminal column.
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
