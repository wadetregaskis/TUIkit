//  🖥️ TUIKit — Terminal UI Kit for Swift
//  String+CursorCompensation.swift
//
//  Terminal-specific cursor-advance workarounds for the output path: some
//  terminals move the cursor by a different amount than the cells a glyph
//  paints, so `FrameDiffWriter` rewrites each built line through the walk
//  matching the detected host. The per-host advance MODELS live beside
//  `terminalWidth` (`Character.terminalAppCursorAdvance` /
//  `Character.iTerm2CursorAdvance`); this file holds the line rewriters.
//  Every model value is DSR-measured — see
//  Documentation/Terminal-compatibility.md, and update it when anything
//  here changes.
//
//  Created by Wade Tregaskis
//  License: MIT

private extension String {
    /// `true` iff any UTF-8 byte has its high bit set — i.e. the string is not
    /// pure ASCII.
    ///
    /// Scans 8 bytes per iteration by loading a `UInt64` and testing it against
    /// the high-bit mask `0x8080…80`; any set bit means some byte was ≥ 0x80.
    /// This is ~9× faster than `utf8.contains { $0 >= 0x80 }`, which walks the
    /// `UTF8View` one element at a time through its index machinery rather than
    /// a raw byte loop (microbenchmark: 0.068s vs 0.612s for 5M scans of a
    /// 127-byte ASCII line, `-O`). Falls back to the element scan for the rare
    /// string with no contiguous UTF-8 storage (e.g. a lazily-bridged
    /// `NSString`), which `withContiguousStorageIfAvailable` reports as `nil`.
    var utf8ContainsNonASCII: Bool {
        utf8.withContiguousStorageIfAvailable { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let count = buffer.count
            var i = 0
            while i + 8 <= count {
                let chunk = UnsafeRawPointer(base + i).loadUnaligned(as: UInt64.self)
                if chunk & 0x8080_8080_8080_8080 != 0 { return true }
                i += 8
            }
            while i < count {
                if base[i] >= 0x80 { return true }
                i += 1
            }
            return false
        } ?? utf8.contains { $0 >= 0x80 }
    }
}

extension String {
    /// Returns a copy safe to emit as a single terminal row.
    ///
    /// Every C0 control character that would move the cursor off the row — a
    /// line feed (`\n`), carriage return (`\r`), tab, vertical tab, form feed,
    /// backspace, and the rest of `0x00…0x1F` — plus `DEL` (`0x7F`) is replaced
    /// with a space. The `ESC` (`0x1B`) that introduces an ANSI colour / cursor
    /// sequence is deliberately preserved: those sequences are intentional and,
    /// after the leading `ESC`, contain only printable bytes, so nothing else in
    /// them is touched.
    ///
    /// A `FrameBuffer` line is, by contract, exactly one terminal row; a stray
    /// control character in one (e.g. user data with an embedded newline placed
    /// verbatim into a cell) otherwise prints literally and shoves the cursor —
    /// drawing outside the intended bounds and corrupting every row below.
    /// Applied at the terminal-write boundary, this guarantees no view can do
    /// that, whatever it put in its buffer.
    ///
    /// Returns `self` unchanged — no allocation — when there is nothing to
    /// sanitize, which is the overwhelmingly common case.
    public func sanitizedForTerminalRow() -> String {
        func isStray(_ value: UInt32) -> Bool {
            (value < 0x20 && value != 0x1B) || value == 0x7F
        }
        // Fast reject for the clean line that virtually every line is, and which
        // runs once per *changed* terminal row per frame: every byte we'd
        // replace is single-byte UTF-8 (< 0x80), so a raw contiguous-byte scan is
        // correct and far cheaper than walking the `UnicodeScalarView` (whose
        // per-element index validation showed up in render profiling).
        let hasStray =
            utf8.withContiguousStorageIfAvailable { buffer -> Bool in
                for byte in buffer where (byte < 0x20 && byte != 0x1B) || byte == 0x7F {
                    return true
                }
                return false
            } ?? unicodeScalars.contains { isStray($0.value) }
        guard hasStray else { return self }

        var result = String()
        result.unicodeScalars.reserveCapacity(unicodeScalars.count)
        for scalar in unicodeScalars {
            result.unicodeScalars.append(isStray(scalar.value) ? " " : scalar)
        }
        return result
    }

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
        // Fast path: every cursor-advance quirk is an emoji cluster, which is
        // always non-ASCII, so a line whose bytes are all < 0x80 cannot need
        // compensation — return it untouched and skip the char-by-char rebuild.
        // `FrameDiffWriter.buildOutputLines` runs this on EVERY output line
        // every frame (on Apple_Terminal — it is gated off elsewhere), and most
        // lines of a non-emoji UI are pure ASCII (text + ANSI escapes, which are
        // also ASCII). The gate reads no Unicode properties — far cheaper than
        // the full `containsTerminalAppCursorAdvanceQuirk` predicate, which costs
        // about as much as the rebuild it would guard — and scans the bytes 8 at
        // a time (see `utf8ContainsNonASCII`).
        guard utf8ContainsNonASCII else { return self }

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

    /// Returns a copy of this string with every Fitzpatrick skin-tone
    /// modifier stripped from its cluster — falling back to the
    /// generic-yellow base emoji.
    ///
    /// For terminals that render the modifier as a SEPARATE colour swatch
    /// beside the base instead of merging it into one glyph (iTerm2 in its
    /// default width configuration): the cluster then paints 4 cells where
    /// the column accounting (``terminalWidth``, which claims 2) allocated
    /// 2, shifting the rest of the row right by two cells per cluster.
    /// Stripping restores the 2-cell claim exactly, and makes the output's
    /// advance independent of the terminal's Unicode-version width setting
    /// (the ambiguous base+modifier cluster no longer reaches it):
    ///
    /// - an emoji-presentation base (👍) renders 2 cells bare;
    /// - a text-presentation base (☝) gets U+FE0F appended so it keeps the
    ///   2-cell colour-emoji rendering. No cursor compensation follows —
    ///   unlike Terminal.app, these terminals advance VS-16 clusters by
    ///   their painted width.
    ///
    /// STANDALONE modifiers (a bare U+1F3FB…U+1F3FF with no base) are
    /// intentional content — a 2-cell swatch, correctly claimed — and pass
    /// through untouched, as do ANSI escape sequences.
    public func withSkinToneFallback() -> String {
        // Fast path: a skin-tone cluster is always non-ASCII, so a line whose
        // bytes are all < 0x80 cannot need the fallback (same gate as
        // `withTerminalAppCursorCompensation` — this too runs on every
        // (re)built output line on the terminals it applies to).
        guard utf8ContainsNonASCII else { return self }

        var result = ""
        result.reserveCapacity(self.count)
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

            let scalars = c.unicodeScalars
            let isModifiedCluster =
                scalars.count > 1
                && scalars.first!.properties.isEmojiModifierBase
                && scalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
            if isModifiedCluster {
                var keptVS16 = false
                for scalar in scalars where !(0x1F3FB...0x1F3FF).contains(scalar.value) {
                    if scalar.value == 0xFE0F { keptVS16 = true }
                    result.unicodeScalars.append(scalar)
                }
                let base = scalars.first!
                if !keptVS16 && base.properties.isEmoji && !base.properties.isEmojiPresentation {
                    result.unicodeScalars.append(Unicode.Scalar(0xFE0F)!)
                }
            } else {
                result.append(c)
            }
            index = self.index(after: index)
        }

        return result
    }

    /// Returns a copy of this string with iTerm2's cursor-advance quirks
    /// worked around: a `CUF` is injected after each cluster whose painted
    /// width exceeds its ``Character/iTerm2CursorAdvance`` (keycap
    /// sequences and Plane-16 PUA glyphs — SF Symbols), pushing the cursor
    /// to the glyph's visual end exactly as
    /// ``withTerminalAppCursorCompensation()`` does for Terminal.app's
    /// (larger) set of under-advancers. iTerm2 has no over-advancers left
    /// by the time this runs: skin-tone clusters are stripped first by
    /// ``withSkinToneFallback()``. ANSI escape sequences are preserved.
    public func withITerm2CursorCompensation() -> String {
        withCursorForwardCompensation { $0.iTerm2CursorAdvance }
    }

    /// Returns a copy of this string with Ghostty's two cursor-advance quirks
    /// worked around, by the same CUF injection
    /// ``withITerm2CursorCompensation()`` uses: the VS-15 chrome glyphs
    /// (⬛︎ ⬜︎ — painted 2 cells, advanced 1, so an uncompensated label
    /// collides with the glyph) and Plane-16 PUA SF Symbols (rendered
    /// grid-strictly at 1 cell against a 2-cell claim). Ghostty has no
    /// over-advancers in any class TUIkit emits — it is the only measured
    /// terminal that advances VS-16, ZWJ, keycaps, flags and skin tones
    /// exactly as claimed, so nothing is stripped on this path.
    /// ANSI escape sequences are preserved.
    public func withGhosttyCursorCompensation() -> String {
        withCursorForwardCompensation { $0.ghosttyCursorAdvance }
    }

    /// Returns a copy of this string with Warp's lone-regional-indicator
    /// under-advance worked around by CUF injection, as
    /// ``withITerm2CursorCompensation()`` does for iTerm2. Warp's other
    /// divergences are OVER-advances (keycaps, 〰️/〽️, ZWJ) which no CUF can
    /// correct, or skin-tone clusters — stripped first by
    /// ``withSkinToneFallback()``, exactly as on iTerm2.
    /// ANSI escape sequences are preserved.
    public func withWarpCursorCompensation() -> String {
        withCursorForwardCompensation { $0.warpCursorAdvance }
    }

    /// Returns a copy of this string with tmux's cursor-advance divergences
    /// worked around by the same CUF injection the other hosts use: Plane-16
    /// PUA (SF Symbols), bare SMP pictographs — including the `Emoji=No`
    /// dominoes and playing cards — and lone regional indicators all advance 1
    /// against a 2-cell claim, so each gets one CUF.
    ///
    /// Unlike the native terminals this is not a bug in a renderer but a
    /// disagreement with a *compositor's* width table: tmux allocates the cells
    /// it thinks a cluster needs, so without the CUF every later column on the
    /// row shears left by one per glyph and enclosing borders land early.
    /// Pushing the cursor to the claimed column keeps the layout intact and
    /// leaves the glyph a blank cell to paint into.
    ///
    /// tmux's BMP-base skin-tone over-advance is handled upstream by
    /// ``withSkinToneFallback()``, as on iTerm2 and Warp; a bare ☝ remains
    /// uncorrectable (see ``Character/tmuxCursorAdvance``).
    /// ANSI escape sequences are preserved.
    public func withTmuxCursorCompensation() -> String {
        withCursorForwardCompensation { $0.tmuxCursorAdvance }
    }

    /// Shared CUF-injection walk: appends each character, then pushes the
    /// cursor forward by the shortfall whenever the host advances it less
    /// than the character's painted ``Character/terminalWidth``.
    ///
    /// One walk serves every host whose quirks are pure under-advances
    /// (iTerm2, Ghostty, Warp); only the per-host advance model differs, so
    /// it is the parameter. Terminal.app keeps its own walk — it must also
    /// rewrite content (stripping mid-line skin tones), which this cannot
    /// express. ANSI escape sequences are copied through untouched.
    ///
    /// - Parameter advance: The host's cursor advance for a character.
    private func withCursorForwardCompensation(
        advance: (Character) -> Int
    ) -> String {
        // Fast path: every quirk cluster is non-ASCII (same reasoning and
        // same gate as the Terminal.app walk).
        guard utf8ContainsNonASCII else { return self }

        var result = ""
        result.reserveCapacity(self.count + 8)
        var index = startIndex

        while index < endIndex {
            let c = self[index]

            if c == "\u{1B}" {
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

            result.append(c)
            let claimed = c.terminalWidth
            let actual = advance(c)
            if claimed > actual {
                result += "\u{1B}[\(claimed - actual)C"
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
