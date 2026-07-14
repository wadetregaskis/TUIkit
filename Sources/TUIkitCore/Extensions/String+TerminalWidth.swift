//  🖥️ TUIKit — Terminal UI Kit for Swift
//  String+TerminalWidth.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ANSI Segment

/// One segment of a string produced by ``Swift/String/ansiSegments()``:
/// either a complete ANSI (CSI) escape sequence or a single visible
/// grapheme cluster.
enum ANSISegment {
    /// A complete escape sequence; `isSGR` is `true` for colour/style
    /// (`…m`) sequences and `false` for cursor-movement, erase, etc.
    case ansi(String, isSGR: Bool)

    /// A single visible grapheme cluster.
    case visible(Character)
}

// MARK: - Terminal Character Width

extension Character {
    /// The display width of this character in a terminal (number of cells).
    ///
    /// Most characters occupy 1 cell. East Asian wide characters (CJK, most
    /// emoji) occupy 2 cells. Zero-width characters (combining marks,
    /// variation selectors, ZWJ) occupy 0 cells.
    /// Whether `sv` is a scalar that adds no terminal-cell width when it
    /// appears as a *non-first* scalar of a grapheme cluster: a variation
    /// selector, a combining mark, a zero-width joiner/space, or a tag. Used
    /// by ``terminalWidth`` to tell a base-plus-accent cluster (width = the
    /// base's) from a genuine multi-glyph sequence like a ZWJ emoji or a flag
    /// (width 2). Mirrors the single-scalar zero-width ranges above.
    static func isWidthNeutralExtraScalar(_ sv: UInt32) -> Bool {
        switch sv {
        case 0x200B, 0x200C, 0x200D, 0xFEFF, 0x00AD:  // ZWSP/ZWNJ/ZWJ/BOM, soft hyphen
            return true
        case 0xFE00...0xFE0F, 0xE0100...0xE01EF:  // variation selectors (+ supplement)
            return true
        case 0x0300...0x036F, 0x1AB0...0x1AFF, 0x1DC0...0x1DFF,  // combining diacriticals (+ ext/supp)
            0x20D0...0x20FF, 0xFE20...0xFE2F:  // combining marks for symbols, half marks
            return true
        case 0xE0000...0xE007F:  // tags block
            return true
        default:
            return false
        }
    }

    public var terminalWidth: Int {
        let scalars = unicodeScalars
        guard let first = scalars.first else { return 0 }
        let scalarValue = first.value

        // Fast path: a lone printable-ASCII scalar is always exactly one
        // cell. This is the overwhelming majority of terminal text, and
        // returning here skips the Unicode-property queries below
        // (`isEmoji` / `isEmojiPresentation`) — those resolve through
        // `_swift_stdlib_getBinaryProperties`, the single hottest leaf in
        // render profiling. Restricted to single-scalar clusters so an
        // ASCII base that carries combining marks, a keycap selector, etc.
        // (e.g. "1️⃣") still falls through to the full width logic below.
        if scalarValue >= 0x20, scalarValue <= 0x7E, scalars.count == 1 {
            return 1
        }

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
            // A cluster is only forced to 2 cells when it carries an extra
            // scalar that actually *adds* width — another emoji (ZWJ
            // sequences), a regional indicator (flags), a skin-tone modifier.
            // Extras that add NO width — variation selectors AND combining
            // marks, ZWJ/joiners, and tags — do not make the cluster wide; a
            // base letter carrying only those keeps the base's own width.
            // This is what makes a *decomposed* (NFD) accented letter such as
            // "é" (e + U+0301) one cell, not two — critical because macOS
            // hands filenames back in NFD, so mis-measuring it drifts every
            // border and column that renders such text. (A composed "é",
            // U+00E9, is a single scalar and never reaches here.)
            let hasWidthAddingExtras = scalars.dropFirst().contains { scalar in
                !Self.isWidthNeutralExtraScalar(scalar.value)
            }
            if hasWidthAddingExtras {
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

        // SF Symbols occupy the Plane-16 Private Use Area (U+100000…U+10FFFD).
        // A terminal whose font carries the glyphs — Terminal.app with SF Mono,
        // the only context in which these render at all (see ``SFSymbol``) —
        // paints each one 2 cells wide, but advances the cursor by only 1; the
        // under-advance is handled in ``terminalAppCursorAdvance`` and worked
        // around by ``withTerminalAppCursorCompensation``. These codepoints are
        // only emitted by the Apple-gated symbol resolver (or pasted literally),
        // so on a terminal without the glyphs they simply never appear.
        if (0x100000...0x10FFFD).contains(scalarValue) { return 2 }  // Plane-16 PUA — SF Symbols (SF Mono: 2 cells)

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
        if isLoneRegionalIndicator {
            return 1
        }

        // SF Symbols occupy the Plane-16 Private Use Area (U+100000…U+10FFFD).
        // Terminal.app (SF Mono) paints the glyph 2 cells wide — see
        // ``terminalWidth`` — but advances the cursor by only 1, the same
        // under-advance as a VS-16 pictographic emoji, so
        // ``withTerminalAppCursorCompensation`` injects a CUF(1) after it.
        if scalars.count == 1, let only = scalars.first,
            (0x100000...0x10FFFD).contains(only.value)
        {
            return 1
        }

        guard scalars.count > 1, let first = scalars.first else { return terminalWidth }

        // `<base>+U+FE0F` where the base is a default-text-presentation
        // emoji (e.g. ❤️ = U+2764+FE0F, ✏️ = U+270F+FE0F, 🖥️ = U+1F5A5+FE0F):
        // paints the glyph 2 cells wide (matching `terminalWidth`) but only
        // advances the cursor by 1 — on Terminal.app AND on iTerm2's
        // alternate screen (see ``isVS16UnderAdvancer``).
        if isVS16UnderAdvancer {
            return 1
        }

        // Flag emoji — a pair of regional-indicator scalars
        // (U+1F1E6…U+1F1FF), e.g. 🇺🇸 = U+1F1FA + U+1F1F8: paints 2 cells
        // AND advances 2 (measured by DSR on Terminal.app 455.1 /
        // macOS 15.7) — matching `terminalWidth`, so no compensation.
        // A LONE regional indicator still under-advances (see above);
        // an earlier model treated the pair like the lone case and the
        // injected CUF pushed everything after a flag one cell right.
        if scalars.count == 2,
            (0x1F1E6...0x1F1FF).contains(first.value),
            let second = scalars.dropFirst().first,
            (0x1F1E6...0x1F1FF).contains(second.value)
        {
            return 2
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

    /// The number of terminal cells iTerm2's cursor actually moves after
    /// printing this character — its analogue of ``terminalAppCursorAdvance``.
    ///
    /// **Measured on the ALTERNATE screen** (iTerm2 3.6.11, default
    /// profile, DSR) — the buffer TUIkit apps actually run in, which
    /// matters: on its PRIMARY screen iTerm2 advances VS-16 pictographic
    /// clusters by their full 2 cells, but on the alternate screen it
    /// under-advances them by 1, exactly like Terminal.app. An earlier
    /// model here was built from primary-screen measurements and declared
    /// iTerm2 free of the VS-16 quirk — the demo's Bug A row promptly
    /// painted its closing brackets into the glyphs. Probe in the same
    /// screen mode as the app.
    ///
    /// Paint-2 / advance-1 under-advancers on iTerm2 (alternate screen):
    ///
    /// - **VS-16 pictographic clusters** (❤️ ✏️ 🖥️ …), with the same
    ///   East-Asian-Wide exceptions as Terminal.app (〰️ 〽️ ㊗️ ㊙️
    ///   advance their full 2) — see ``isVS16UnderAdvancer``.
    /// - **Keycap sequences** (base + U+20E3, with or without U+FE0F).
    /// - **Plane-16 Private Use Area** (U+100000…U+10FFFD — SF Symbols).
    ///
    /// Unlike Terminal.app: flag pairs AND lone regional indicators
    /// advance 2, and ZWJ sequences mostly advance 2 (except VS-16-leading
    /// ones like ❤️‍🔥, advance 1 — unhandled, as ZWJ is on both hosts).
    /// Fitzpatrick skin-tone clusters also mis-advance on iTerm2 (SMP
    /// bases merge to 2, BMP bases draw base + swatch at 4/3), but the
    /// iTerm2 output path strips them first (``withSkinToneFallback()``),
    /// so they never reach the compensation walk.
    public var iTerm2CursorAdvance: Int {
        let scalars = unicodeScalars
        if scalars.contains(where: { $0.value == 0x20E3 }) {
            return 1
        }
        if scalars.count == 1, let only = scalars.first,
            (0x100000...0x10FFFD).contains(only.value)
        {
            return 1
        }
        if isVS16UnderAdvancer {
            return 1
        }
        return terminalWidth
    }

    /// The number of columns Ghostty advances the text cursor by when this
    /// character is printed (DSR-measured on the alternate screen, Ghostty
    /// 1.3.1, 2026-07-14).
    ///
    /// Ghostty is by far the most Unicode-correct terminal TUIkit has
    /// measured: VS-16 clusters, keycaps, flags, lone regional indicators,
    /// ZWJ sequences and Fitzpatrick skin tones ALL advance exactly the 2
    /// cells ``terminalWidth`` claims — no compensation needed for any of the
    /// classes Terminal.app and iTerm2 get wrong. Only two under-advance:
    ///
    /// - **VS-15 chrome glyphs** (⬛︎ ⬜︎ — an emoji-presentation base plus
    ///   U+FE0E): painted 2 cells, cursor advances 1, so an uncompensated
    ///   label lands on the glyph's right half (`■On` instead of `■ On` —
    ///   observed on the Toggle demo's `.emoji` checkbox column).
    /// - **Plane-16 Private Use Area** (SF Symbols): Ghostty renders these
    ///   grid-strictly at ONE cell and advances 1, where Terminal.app and
    ///   iTerm2 paint 2 and advance 1. The CUF still restores the 2-cell
    ///   claim the layout allocated — the glyph is simply narrower here, so
    ///   a symbol is followed by one blank cell rather than shearing every
    ///   later column on the row left by one.
    public var ghosttyCursorAdvance: Int {
        let scalars = unicodeScalars
        if scalars.count == 1, let only = scalars.first,
            (0x100000...0x10FFFD).contains(only.value)
        {
            return 1
        }
        if isVS15ChromeUnderAdvancer {
            return 1
        }
        return terminalWidth
    }

    /// The number of columns Warp advances the text cursor by when this
    /// character is printed (DSR-measured on the alternate screen, Warp
    /// v0.2026.07.08, 2026-07-14).
    ///
    /// Warp gets VS-16 clusters and VS-15 chrome right (unlike Terminal.app
    /// and Ghostty respectively) but mishandles the composed-emoji classes:
    ///
    /// - **Fitzpatrick skin tones** paint base + a separate swatch at 4 cells
    ///   (3 for BMP bases) — the same shape as Terminal.app's Bug B, and
    ///   handled the same way: the output path strips the modifiers via
    ///   ``String/withSkinToneFallback()`` BEFORE this model is consulted, so
    ///   they never reach the compensation walk.
    /// - **Lone regional indicators** (🇦 alone) advance 1 against a claim of
    ///   2 — same as Terminal.app; CUF fixes it.
    /// - **Keycaps** (1️⃣, advance 3), **〰️/〽️** (advance 3) and **ZWJ
    ///   sequences** (👩‍🚀 advances 5, 👩🏽‍🚀 7) OVER-advance. CUF cannot
    ///   claw a cursor back and these paint wider than any claim, so they are
    ///   left alone and documented, exactly as ZWJ is on Terminal.app.
    ///   Warp additionally disagrees with itself across screen buffers (its
    ///   primary screen advances VS-16 by 1, the alternate by 2); the model
    ///   uses the alternate screen, where TUIkit apps run.
    public var warpCursorAdvance: Int {
        if isLoneRegionalIndicator {
            return 1
        }
        return terminalWidth
    }

    /// Whether this character is a single regional-indicator scalar with no
    /// partner (🇦 alone rather than the 🇺🇸 pair).
    ///
    /// Terminal.app and Warp both paint it 2 cells but advance 1; iTerm2 and
    /// Ghostty advance the full 2. Shared by the per-host advance models.
    var isLoneRegionalIndicator: Bool {
        let scalars = unicodeScalars
        guard scalars.count == 1, let only = scalars.first else { return false }
        return (0x1F1E6...0x1F1FF).contains(only.value)
    }

    /// Whether this character is an emoji-presentation base carrying the
    /// U+FE0E TEXT-presentation selector (⬛︎ ⬜︎ — TUIkit's emoji chrome
    /// glyphs), which Ghostty paints 2 cells wide but advances by only 1.
    ///
    /// The mirror image of ``isVS16UnderAdvancer``: there a text-presentation
    /// base is forced to emoji and under-advances; here an emoji-presentation
    /// base is forced to text and under-advances. Measured on U+2B1B/U+2B1C;
    /// Terminal.app, iTerm2 and Warp all advance these by the full 2.
    var isVS15ChromeUnderAdvancer: Bool {
        let scalars = unicodeScalars
        guard scalars.count > 1, let first = scalars.first else { return false }
        guard scalars.contains(where: { $0.value == 0xFE0E }) else { return false }
        let hasNonVariationExtras = scalars.dropFirst().contains { scalar in
            let sv = scalar.value
            return !(0xFE00...0xFE0F).contains(sv) && !(0xE0100...0xE01EF).contains(sv)
        }
        return !hasNonVariationExtras && first.properties.isEmojiPresentation
    }

    /// Whether this character is a `<base>+U+FE0F` pictographic cluster
    /// that paints 2 cells but advances the cursor by only 1 — on
    /// Terminal.app (both screen buffers) and on iTerm2's ALTERNATE screen
    /// (its primary screen advances these correctly; TUIkit apps run on
    /// the alternate screen, so the models use the alternate behaviour).
    ///
    /// The BMP East Asian Wide emoji bases — 〰 U+3030, 〽 U+303D,
    /// ㊗ U+3297, ㊙ U+3299 — are excluded: their CJK width is 2 with or
    /// without VS16 and BOTH terminals advance them by that full width
    /// (measured); "compensating" pushed the cursor a third cell along,
    /// and the skipped cell was never painted — a black hole after every
    /// 〰️, whatever the palette. (Framework width tables are NOT the
    /// discriminator: a pictographic base like U+1F5A5 also measures 2 yet
    /// genuinely under-advances.) `Unicode.Scalar.Properties` catches BMP
    /// bases too, not just the `0x1F000–0x1FBFF` block.
    var isVS16UnderAdvancer: Bool {
        let scalars = unicodeScalars
        guard scalars.count > 1, let first = scalars.first else { return false }
        let hasVS16 = scalars.contains { $0.value == 0xFE0F }
        let hasNonVariationExtras = scalars.dropFirst().contains { scalar in
            let sv = scalar.value
            return !(0xFE00...0xFE0F).contains(sv) && !(0xE0100...0xE01EF).contains(sv)
        }
        guard hasVS16 && !hasNonVariationExtras
            && first.properties.isEmoji
            && !first.properties.isEmojiPresentation
        else { return false }
        switch first.value {
        case 0x3030, 0x303D, 0x3297, 0x3299:
            return false
        default:
            return true
        }
    }
}

// MARK: - ANSI String Helpers

extension StringProtocol {
    /// Terminal width of a run that contains NO ANSI escapes, fast-pathing pure
    /// ASCII.
    ///
    /// ASCII is exactly one cell per byte, so for an all-ASCII run the width is
    /// the byte count — computed by a plain byte scan that skips grapheme-cluster
    /// segmentation. That segmentation (`_opaqueCharacterStride` /
    /// `getGraphemeBreakProperty` / `_GraphemeBreakingState.shouldBreak`) is the
    /// single dominant cost in render profiling, and the overwhelming majority of
    /// terminal text — labels, wrapped words, table cells — is ASCII. The first
    /// non-ASCII byte falls back to summing per-`Character` ``Character/terminalWidth``,
    /// so results are byte-identical to the grapheme path.
    var visibleRunWidth: Int {
        var width = 0
        for byte in utf8 {
            if byte >= 0x80 { return reduce(0) { $0 + $1.terminalWidth } }
            width += 1
        }
        return width
    }
}

// MARK: - Shared ASCII Spaces

/// A pre-built run of ASCII spaces that the per-line padding hot paths slice
/// instead of allocating a fresh `String(repeating: " ", count:)` every call.
///
/// Buffer assembly pads almost every line, every frame, with a throwaway spaces
/// string — `String(repeating:count:)` was ~5.6% inclusive in the `fanout`
/// Time-Profiler trace, with the `_StringGuts` growth helpers it feeds another
/// ~11% combined. The padding count is always a small terminal column count, so
/// one fixed run covers it: ``asciiSpaces(_:)`` returns a borrowed `Substring`
/// prefix of this run with **zero** per-call allocation. The run is an immutable
/// `Sendable` `String` initialized once, so a plain `static let` is already
/// data-race-free (every access is a pure read of immutable storage).
private enum ASCIISpaces {
    /// The cached length. Generous relative to real terminal widths (a 1024-cell
    /// row is already far past any terminal); a pad wider than this falls back to
    /// `String(repeating:)`, which is then rare enough not to matter.
    static let count = 1024

    /// `count` ASCII spaces. Immutable after initialization.
    static let run = String(repeating: " ", count: count)
}

/// Returns `count` ASCII spaces (`U+0020`) as a borrowed `Substring`, allocating
/// nothing for the common case.
///
/// This is the in-place-friendly replacement for `String(repeating: " ", count:)`
/// on the render path: append the result onto a result string that has already
/// reserved its capacity, rather than building a temporary spaces `String` and
/// concatenating it. For `count` within the shared run's length the result is a
/// slice of a single process-wide buffer (no allocation); only an unusually wide
/// `count` (beyond a full 1024-cell row) allocates, via the `String(repeating:)`
/// fallback. A non-positive `count` yields an empty `Substring`.
///
/// - Parameter count: The number of spaces required.
/// - Returns: Exactly `max(0, count)` space characters.
public func asciiSpaces(_ count: Int) -> Substring {
    guard count > 0 else { return "" }
    if count <= ASCIISpaces.count {
        return ASCIISpaces.run.prefix(count)
    }
    // Wider than a full terminal row — vanishingly rare. Build it once here; the
    // caller still appends a Substring, keeping the call site uniform.
    return Substring(String(repeating: " ", count: count))
}

extension String {
    /// The visible width of the string in terminal cells, excluding ANSI escape codes.
    ///
    /// Accounts for wide characters (emoji, CJK) that occupy 2 terminal cells
    /// and zero-width characters (combining marks, variation selectors).
    public var strippedLength: Int {
        // Fast path: a string with no ESC byte is a single visible run — the
        // whole string — so grapheme-cluster it in place and sum cell widths
        // with ZERO allocation. The general path below scans the runs, which
        // used to materialize a `[String]` plus a `String` copy per run and then
        // discard them — pure churn for a width count. `strippedLength` runs per
        // word during `Text.wordWrap` and per line during render, every frame
        // (profiling the `nested` tree: `String.strippedLength` ~23% inclusive,
        // the run scan ~15%, dominated by `_StringGuts.append` /
        // `_uncheckedFromUTF8` / tiny_malloc), and the text being measured while
        // wrapping is plain (unstyled), so this is the overwhelming common case.
        // Byte-identical: a no-ESC string yields exactly one run equal to the
        // whole string.
        // ESC detection is a direct byte search (0x1B is a standalone byte, never
        // part of a multi-byte scalar), cheaper than decoding scalars.
        if !utf8.contains(0x1B) {
            return visibleRunWidth
        }
        // General path: ANSI present — measure each visible run independently (a
        // trailing Extend scalar after an SGR terminator must not fuse onto the
        // previous run; see `forEachVisibleANSIRun(_:)`). Each run is a borrowed
        // `Substring`, so this counts widths without allocating, and each run
        // takes the ASCII byte-count fast path when it has no wide characters.
        var total = 0
        forEachVisibleANSIRun { run in
            total += run.visibleRunWidth
        }
        return total
    }

    /// Invokes `body` once per visible run — the text between and around CSI
    /// (`ESC [ … letter`) escape sequences, with the sequences removed —
    /// passing each run as a `Substring` of `self`.
    ///
    /// This is the allocation-free core behind ``strippedLength`` and
    /// ``stripped``. The previous form returned `[String]`, allocating the array
    /// and copying every run into a fresh `String` only for callers to discard
    /// it after summing widths or joining — pure churn (it showed up in render
    /// profiling as `_StringGuts.append` / `_uncheckedFromUTF8` / tiny_malloc).
    /// A run is always a contiguous slice of the original (escapes only fall
    /// *between* runs), so a borrowed `Substring` carries the same scalars with
    /// no copy.
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
    ///    (the residual off-by-one after fix 1). Each run is a slice bounded by
    ///    the escapes, so it grapheme-clusters on its own — a run that begins
    ///    at an `Extend` scalar starts a fresh cluster there, exactly as a
    ///    standalone `String` of those scalars would.
    private func forEachVisibleANSIRun(_ body: (Substring) -> Void) {
        // Single forward pass over the scalar view, tracking the start index of
        // the current visible run so each run can be yielded as a slice
        // `self[runStart..<index]` — no array, no per-run copy. A 3-state
        // machine subsumes the look-ahead:
        //
        //   normal — inside (or about to start) a visible run
        //   sawESC — just saw ESC; a following '[' opens a CSI introducer
        //   inCSI  — inside ESC[…; consume parameter bytes then one terminator
        //
        // An ESC, and a complete CSI introducer (ESC [ params letter), are
        // dropped; everything else is visible. Exactly one scalar is consumed
        // for the terminator so a trailing Extend scalar stays visible.
        let scalars = unicodeScalars
        var index = scalars.startIndex
        var runStart = index
        var hasRun = false  // whether [runStart, index) holds visible scalars

        enum ScanState { case normal, sawESC, inCSI }
        var state = ScanState.normal

        while index < scalars.endIndex {
            let value = scalars[index].value
            switch state {
            case .normal:
                if value == 0x1B {  // ESC ends the current run
                    if hasRun { body(self[runStart..<index]); hasRun = false }
                    state = .sawESC
                } else if !hasRun {  // first visible scalar of a new run
                    runStart = index
                    hasRun = true
                }

            case .sawESC:
                if value == 0x5B {  // '[' → CSI introducer
                    state = .inCSI
                } else if value == 0x1B {  // ESC ESC → drop the first, restart
                    state = .sawESC
                } else {  // a bare ESC: it is dropped, this scalar starts a run
                    runStart = index
                    hasRun = true
                    state = .normal
                }

            case .inCSI:
                if (0x30...0x39).contains(value) || value == 0x3B {
                    break  // parameter byte (digit or ';') — stay in CSI
                }
                if (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) {
                    state = .normal  // final letter — introducer complete, consumed
                } else if value == 0x1B {  // ESC interrupts a malformed CSI
                    state = .sawESC
                } else {  // non-letter where a terminator was expected: not part
                    runStart = index  // of the introducer, so it starts a run
                    hasRun = true
                    state = .normal
                }
            }
            index = scalars.index(after: index)
        }
        if hasRun { body(self[runStart..<index]) }  // index == endIndex
    }

    /// Splits the string into ordered segments — each either a complete
    /// ANSI (CSI) escape sequence or a single visible grapheme cluster.
    ///
    /// The scan runs at the Unicode-scalar level so an escape's terminator
    /// byte (e.g. the `m` of an SGR colour code) never fuses with a
    /// following `Extend` scalar (a lone Fitzpatrick modifier, VS-16, …)
    /// into one `Character`. `Character`-level scanning *does* fuse them,
    /// which makes the "skip the final byte" step swallow the modifier as
    /// part of the escape — corrupting every visible-width computation
    /// that follows. Visible runs between escapes are grapheme-clustered
    /// on their own (escapes always break clusters anyway), so widths come
    /// out the same as for un-styled text.
    func ansiSegments() -> [ANSISegment] {
        var segments: [ANSISegment] = []
        let scalars = unicodeScalars
        var index = scalars.startIndex
        var visible = Self.UnicodeScalarView()

        func flushVisible() {
            guard !visible.isEmpty else { return }
            for character in String(visible) { segments.append(.visible(character)) }
            visible = Self.UnicodeScalarView()
        }

        while index < scalars.endIndex {
            guard scalars[index].value == 0x1B else {  // not ESC → visible
                visible.append(scalars[index])
                index = scalars.index(after: index)
                continue
            }
            flushVisible()
            var sequence = Self.UnicodeScalarView()
            sequence.append(scalars[index])
            index = scalars.index(after: index)
            var isSGR = false
            if index < scalars.endIndex, scalars[index].value == 0x5B {  // '['
                sequence.append(scalars[index])
                index = scalars.index(after: index)
                while index < scalars.endIndex,
                    (0x30...0x39).contains(scalars[index].value) || scalars[index].value == 0x3B {
                    sequence.append(scalars[index])
                    index = scalars.index(after: index)
                }
                // Final byte: a single ASCII letter, consumed by exactly one
                // scalar so a trailing Extend scalar stays a visible segment.
                if index < scalars.endIndex,
                    (0x41...0x5A).contains(scalars[index].value)
                        || (0x61...0x7A).contains(scalars[index].value) {
                    isSGR = scalars[index].value == 0x6D  // 'm'
                    sequence.append(scalars[index])
                    index = scalars.index(after: index)
                }
            }
            segments.append(.ansi(String(sequence), isSGR: isSGR))
        }
        flushVisible()
        return segments
    }

    /// The string with all ANSI (CSI) escape codes removed.
    public var stripped: String {
        // Fast path: no ESC byte → nothing to strip, return self (no scan, no
        // copy). Otherwise append each visible run (a borrowed `Substring`) into
        // one result — no intermediate `[String]`.
        if !unicodeScalars.contains(where: { $0.value == 0x1B }) { return self }
        var result = ""
        result.reserveCapacity(utf8.count)
        forEachVisibleANSIRun { result += $0 }
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
        // Build the padded line in place: reserve once, then append `self`
        // followed by a borrowed run of trailing spaces — no `String(repeating:)`
        // temporary and no `+`-chain intermediate. The visible bytes are
        // identical to `self + <spaces>`: the appended spaces are plain ASCII
        // `U+0020`, so reserving `utf8.count + padCount` bytes is exact for the
        // padding (the content's own multi-byte scalars are already counted by
        // `utf8.count`). This is the central pad primitive (BackgroundModifier,
        // FrameBuffer.appendHorizontally, ScrollView, FrameModifier, App, …), so
        // it carries the most call sites.
        let padCount = targetWidth - currentWidth
        var result = ""
        result.reserveCapacity(utf8.count + padCount)
        result += self
        result += asciiSpaces(padCount)
        return result
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
        ansiAwarePrefixWithWidth(visibleCount: visibleCount).prefix
    }

    /// Like ``ansiAwarePrefix(visibleCount:)`` but also returns the visible cell
    /// width of the clipped result.
    ///
    /// The clip counts visible cells as it goes, so the width comes for free
    /// here — a caller that needs it (e.g. to compute right-padding) avoids a
    /// redundant `strippedLength` re-scan of the clipped string. The width is
    /// exactly `prefix.strippedLength` by construction.
    public func ansiAwarePrefixWithWidth(visibleCount: Int) -> (prefix: String, visibleWidth: Int) {
        guard visibleCount > 0 else { return ("", 0) }

        var result = ""
        var visible = 0

        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, _):
                result += sequence
            case .visible(let character):
                let charWidth = character.terminalWidth
                if visible + charWidth > visibleCount { return (result, visible) }
                result.append(character)
                visible += charWidth
            }
        }

        return (result, visible)
    }

    /// A horizontal slice: the visible columns in
    /// `visibleStart ..< (visibleStart + visibleCount)`, with ANSI styling intact.
    ///
    /// This is the column-windowing primitive for horizontal scrolling. The dropped
    /// leading columns' SGR (colour/style) escapes are *carried* onto the front of
    /// the result, so the slice keeps whatever styling was active at `visibleStart`
    /// even though the codes that set it scrolled out of view. Non-SGR escapes
    /// (cursor moves) in the dropped region are not replayed. A wide character that
    /// straddles either edge is dropped (it can't be shown whole), leaving a gap —
    /// the same treatment ``ansiAwarePrefix(visibleCount:)`` gives the right edge.
    ///
    /// - Parameters:
    ///   - visibleStart: The first visible column to include (0-based).
    ///   - visibleCount: How many visible columns to include.
    public func ansiAwareSlice(visibleStart: Int, visibleCount: Int) -> String {
        guard visibleCount > 0 else { return "" }
        guard visibleStart > 0 else { return ansiAwarePrefix(visibleCount: visibleCount) }

        let end = visibleStart + visibleCount
        var carriedStyle = ""  // SGR history replayed so the slice starts correctly styled
        var body = ""
        var visible = 0

        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                if visible < visibleStart {
                    if isSGR { carriedStyle += sequence }
                } else if visible < end {
                    body += sequence
                }
            case .visible(let character):
                let charWidth = character.terminalWidth
                if visible >= visibleStart && visible + charWidth <= end {
                    body.append(character)
                }
                visible += charWidth
            }
        }
        return carriedStyle + body
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
        ansiAwarePrefixForTerminalAppWithWidth(visibleCount: visibleCount).prefix
    }

    /// Width-returning twin of ``ansiAwarePrefixForTerminalApp(visibleCount:)``
    /// — see ``ansiAwarePrefixWithWidth(visibleCount:)`` for why the visible
    /// width is free. The width is exactly `prefix.strippedLength` (the space
    /// substitution for an over-advancer keeps the visible width intact).
    public func ansiAwarePrefixForTerminalAppWithWidth(visibleCount: Int) -> (prefix: String, visibleWidth: Int) {
        guard visibleCount > 0 else { return ("", 0) }

        var result = ""
        var visible = 0
        var cursor  = 0   // Terminal.app cursor advance from start of line

        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, _):
                result += sequence
            case .visible(let character):
                let charWidth = character.terminalWidth
                if visible + charWidth > visibleCount { return (result, visible) }
                let advance = character.terminalAppCursorAdvance
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
                } else {
                    result.append(character)
                    visible += charWidth
                    cursor += advance
                }
            }
        }

        return (result, visible)
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
        var suffix = ""
        var visible = 0

        for segment in ansiSegments() {
            // Before the offset is reached we're accumulating the entry
            // colour state; at or after it, content belongs in the suffix.
            let inSuffix = visible >= visibleOffset
            switch segment {
            case .ansi(let sequence, let isSGR):
                // Keep only SGR sequences; non-SGR (CUF, EL, …) are dropped
                // so they can't displace the cursor at a fixed write column.
                guard isSGR else { continue }
                if inSuffix {
                    suffix += sequence
                } else {
                    sgrContext += sequence
                }
            case .visible(let character):
                if inSuffix {
                    suffix.append(character)
                } else {
                    visible += character.terminalWidth
                }
            }
        }

        guard visible >= visibleOffset else { return nil }
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
        var result = ""

        for segment in ansiSegments() {
            // Everything at or after the drop boundary is kept verbatim
            // (ANSI included); everything before it is discarded.
            let keeping = visible >= dropCount
            switch segment {
            case .ansi(let sequence, _):
                if keeping { result += sequence }
            case .visible(let character):
                if keeping {
                    result.append(character)
                } else {
                    visible += character.terminalWidth
                }
            }
        }

        return result
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

    /// The net SGR styling active just before visible column `column` — every SGR
    /// escape that appears strictly before that column, concatenated (the terminal
    /// nets them, so an opening sequence followed by a reset leaves no styling).
    ///
    /// Unlike ``leadingANSISequences()`` (the styling set up before the FIRST
    /// visible character), this reflects styling reset or changed partway along
    /// the line: underlined text followed by a reset and plain padding yields an
    /// empty state past the reset, not a lingering underline. It restores the
    /// correct tail state after an overlay is composited over a line's middle —
    /// preserving a uniform background while not bleeding the prefix's text
    /// decorations (bold/underline) onto the suffix. See `FrameBuffer.insertOverlay`.
    public func ansiStateBefore(visibleColumn column: Int) -> String {
        var visible = 0
        var state = ""
        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                if isSGR && visible < column { state += sequence }
            case .visible(let character):
                visible += character.terminalWidth
            }
        }
        return state
    }
}
