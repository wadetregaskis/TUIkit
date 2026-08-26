//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+TerminalWidth.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ANSI Segment

/// One segment of a string produced by `String.ansiSegments()`: either a
/// complete ANSI (CSI) escape sequence or a single visible grapheme cluster.
public enum ANSISegment {
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

    /// Whether `sv` is a scalar that can only ever be a grapheme cluster **by
    /// itself** — it never joins with the scalar before or after it.
    ///
    /// Unicode's grapheme-break algorithm only *suppresses* a break for scalars
    /// in a handful of categories: `Extend` (combining marks, variation
    /// selectors, skin-tone modifiers), `ZWJ`, `SpacingMark`, `Prepend`,
    /// `Regional_Indicator` (flags), Hangul jamo, the Indic conjunct forms, and
    /// `CR`/`LF`. Every other pair of adjacent scalars breaks (GB999). So when
    /// **both** neighbours answer `true` here there is guaranteed to be a
    /// cluster boundary between them, and a width scan can simply add
    /// ``Unicode/Scalar/loneTerminalWidth`` per scalar instead of asking the
    /// standard library to segment the string.
    ///
    /// That segmentation — `_opaqueCharacterStride` /
    /// `_swift_stdlib_getGraphemeBreakProperty` /
    /// `_GraphemeBreakingState.shouldBreak` — was measured at ~17% of all CPU
    /// in a `kitchensink` Time-Profiler trace, purely to re-derive that (say)
    /// `│` and a space are two separate characters.
    ///
    /// This is a deliberately **conservative allow-list**: it names the blocks
    /// that terminal UIs are actually built from, and everything else — every
    /// complex script, all of the emoji planes, Hangul — answers `false` and
    /// takes the exact (segmenting) path. A wrong `false` costs speed; only a
    /// wrong `true` could cost correctness, so no block containing a combining
    /// mark, a joiner, a regional indicator or a jamo appears below.
    static func isStandaloneClusterScalar(_ sv: UInt32) -> Bool {
        switch sv {
        case 0x20...0x7E:  // printable ASCII
            return true
        case 0x2500...0x259F:  // Box Drawing, Block Elements — framework chrome
            return true
        case 0x00A0...0x02AF:  // Latin-1 Supplement … IPA Extensions (0x0300 starts combining)
            return true
        case 0x0370...0x0482:  // Greek, Cyrillic letters (0x0483 starts combining)
            return true
        case 0x2010...0x2027, 0x2030...0x205E:  // General Punctuation, minus the zero-width/format scalars
            return true
        case 0x2070...0x20CF:  // super/subscripts, currency (0x20D0 starts combining)
            return true
        case 0x2100...0x2426, 0x2440...0x244A, 0x2460...0x24FF:  // letterlike, arrows, maths, enclosed
            return true
        case 0x25A0...0x2BFF, 0x2E00...0x2E7F:  // geometric shapes … supplemental punctuation
            return true
        case 0x2E80...0x3029, 0x3030...0x3098, 0x309B...0x30FF:  // CJK radicals, punctuation, kana
            return true
        case 0x3105...0x312F, 0x3190...0x4DBF, 0x4E00...0x9FFF:  // Bopomofo, CJK
            return true
        case 0xF900...0xFAFF, 0xFF01...0xFF60, 0xFFE0...0xFFE6:  // CJK compatibility, fullwidth
            return true
        case 0x20000...0x3134F:  // CJK unified extensions B-G
            return true
        case 0x100000...0x10FFFD:  // Plane-16 PUA — SF Symbols
            return true
        default:
            return false
        }
    }

    /// How many terminal cells this grapheme cluster occupies: 0, 1 or 2.
    ///
    /// The single most important measurement in the framework — every layout,
    /// truncation and pad decision is counted in cells, and a `Character` is
    /// not one cell (see ``String/strippedLength``, which sums this across a
    /// line). Wide East Asian characters and most emoji take two; combining
    /// marks and zero-width joiners take none; the rest take one.
    ///
    /// A cluster of a single scalar — nearly all terminal text — is answered
    /// directly by ``Unicode/Scalar/loneTerminalWidth``. Multi-scalar clusters
    /// (emoji sequences, flags, keycaps, skin-tone modifiers) are resolved by
    /// inspecting the sequence, because their width is a property of the whole
    /// cluster rather than of any one scalar in it.
    ///
    /// - Note: This is what the terminal *reserves*, which is not always what
    ///   a given terminal *advances* the cursor by — see
    ///   `Documentation/Terminal-compatibility.md` for the emulators that
    ///   disagree and how ``FrameDiffWriter`` compensates.
    public var terminalWidth: Int {
        let scalars = unicodeScalars
        guard let first = scalars.first else { return 0 }

        // A cluster of one scalar — the overwhelming majority of terminal text
        // — is exactly its scalar's own width.
        guard scalars.count > 1 else { return first.loneTerminalWidth }

        // Zero-width lead: a cluster whose base is itself a combining mark,
        // joiner, variation selector or tag adds no cells.
        if Self.isWidthNeutralExtraScalar(first.value) { return 0 }

        // NOTE: a skin-tone modifier reaching here is the FIRST scalar of the
        // grapheme cluster, i.e. it is *standalone* (no base) — when it
        // combines with a preceding emoji it is part of a multi-scalar cluster
        // whose first scalar is the base, handled below. Terminal.app paints a
        // standalone modifier as a 2-cell colour swatch (this is exactly how
        // the emoji-corpus list shows U+1F3FB…U+1F3FF), so it is 2 cells wide —
        // NOT zero. (Returning 0 here was a bug: it shifted everything after a
        // lone modifier left by 2 cells and dropped the enclosing border.)
        if (0x1F3FB...0x1F3FF).contains(first.value) { return 2 }  // standalone Fitzpatrick skin-tone swatch

        // Multi-scalar grapheme clusters (emoji sequences with ZWJ, skin tones,
        // flag sequences, keycap sequences) are typically 2 cells wide.
        //
        // A cluster is only forced to 2 cells when it carries an extra scalar
        // that actually *adds* width — another emoji (ZWJ sequences), a
        // regional indicator (flags), a skin-tone modifier. Extras that add NO
        // width — variation selectors AND combining marks, ZWJ/joiners, and
        // tags — do not make the cluster wide; a base letter carrying only
        // those keeps the base's own width. This is what makes a *decomposed*
        // (NFD) accented letter such as "é" (e + U+0301) one cell, not two —
        // critical because macOS hands filenames back in NFD, so mis-measuring
        // it drifts every border and column that renders such text. (A composed
        // "é", U+00E9, is a single scalar and never reaches here.)
        let hasWidthAddingExtras = scalars.dropFirst().contains { scalar in
            !Self.isWidthNeutralExtraScalar(scalar.value)
        }
        if hasWidthAddingExtras {
            // True multi-character sequence (ZWJ, flags, keycaps, skin tones)
            return 2
        }
        // Base + variation selector(s).  If the selector is U+FE0F and
        // the base can be rendered as emoji, the cluster is 2 cells.
        // Otherwise the cluster is exactly as wide as its base.
        if scalars.contains(where: { $0.value == 0xFE0F }) && first.properties.isEmoji {
            return 2
        }
        return first.loneTerminalWidth
    }
}

// MARK: - Scalar Width

extension Unicode.Scalar {
    /// The display width, in terminal cells, of this scalar when it forms a
    /// grapheme cluster **on its own**.
    ///
    /// This is the single source of truth for per-codepoint width;
    /// ``Character/terminalWidth`` is this plus the multi-scalar cluster rules.
    /// Splitting it out is what lets the width scanners
    /// (``Swift/StringProtocol/visibleRunWidth``) measure a run of
    /// non-combining scalars without paying for grapheme-cluster segmentation —
    /// see ``Character/isStandaloneClusterScalar(_:)``.
    var loneTerminalWidth: Int {
        let scalarValue = value

        // Fast path: printable ASCII is always exactly one cell. This is the
        // overwhelming majority of terminal text, and returning here skips the
        // Unicode-property queries below (`isEmoji` / `isEmojiPresentation`) —
        // those resolve through `_swift_stdlib_getBinaryProperties`, one of the
        // hottest leaves in render profiling.
        if scalarValue >= 0x20, scalarValue <= 0x7E { return 1 }

        // Zero-width characters (combining marks, joiners, selectors, tags).
        if Character.isWidthNeutralExtraScalar(scalarValue) { return 0 }

        // Standalone Fitzpatrick skin-tone swatch — 2 cells (see the note in
        // ``Character/terminalWidth``).
        if (0x1F3FB...0x1F3FF).contains(scalarValue) { return 2 }

        // Second fast path: Box Drawing and Block Elements. Every bordered
        // view, divider, scrollbar, progress track and shaded fill in the
        // framework is built from these, so they are the most common non-ASCII
        // scalars by a wide margin — and none of them is emoji or wide, so the
        // property query and the whole East-Asian range ladder below are pure
        // overhead for them.
        if (0x2500...0x259F).contains(scalarValue) { return 1 }

        // Single-scalar codepoints that default to colour emoji presentation
        // are painted as 2-cell glyphs by Terminal.app (and most modern
        // terminal emulators) regardless of whether they're in any of the
        // East Asian Wide ranges below.  This catches BMP codepoints like
        // ⌚ (U+231A), ⌛ (U+231B), ⏩ (U+23E9) that the range checks miss.
        if properties.isEmojiPresentation {
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
        // Enclosed Ideographic Supplement — 🈀 🈐 🈛 🈰 🈻 🉠. Genuinely East
        // Asian Wide, and the ONLY non-emoji block in the pictographic planes
        // that is: measured 2 on all five hosts.
        if (0x1F200...0x1F2FF).contains(scalarValue) { return 2 }

        // The rest of the pictographic planes. Two cells only if this scalar
        // is an emoji, because that is what makes macOS font fallback reach
        // Apple Color Emoji and paint a double-width glyph — the bare
        // pictographs 🖥 🛡 🕹 (`Emoji=Yes, Emoji_Presentation=No`, the
        // `isEmojiPresentation` check above having already taken the rest).
        //
        // Everything else here is a one-cell symbol, and claiming 2 for it
        // sheared every row that contained one: mahjong 🀀, dominoes 🁠,
        // playing cards 🂡, Enclosed Alphanumeric Supplement 🅲, ornamental
        // dingbats 🙐, alchemical 🜀, Supplemental Arrows-C 🠀, chess 🨀, and
        // Symbols for Legacy Computing 🬀 — the last of which are block
        // graphics, siblings of the U+2500…U+259F fast path above, and were
        // the most damaging to claim wide.
        //
        // Measured 2026-08-26 over all 1361 assigned non-emoji scalars in the
        // range, on Terminal.app 455.1 and Ghostty 1.3.1: the two agree on
        // every one, 1312 advance 1 and 49 advance 2, and all 49 are the
        // Enclosed Ideographic Supplement handled above. Paint width checked
        // separately by drawing ten of each uncompensated — a paint-2 glyph
        // overlaps its neighbour and mangles the row, and these do not.
        if (0x1F000...0x1FBFF).contains(scalarValue) { return properties.isEmoji ? 2 : 1 }
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

        // A bare (selector-less) text-presentation SMP pictograph — 🖥 🛡 🕹 —
        // paints 2 via Apple Color Emoji fallback but advances 1, exactly like
        // its VS-16 form. See ``isBarePictographUnderAdvancer``.
        if isBarePictographUnderAdvancer {
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
        if isVS16UnderAdvancer || isBarePictographUnderAdvancer {
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
        if isVS15ChromeUnderAdvancer || isBarePictographUnderAdvancer {
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
        if isLoneRegionalIndicator || isBarePictographUnderAdvancer {
            return 1
        }
        return terminalWidth
    }

    /// The number of columns **tmux** advances the text cursor by when this
    /// character is printed (DSR-measured inside tmux 3.7b, 2026-07-15).
    ///
    /// tmux is a compositor: it parses our output into its own grid using its
    /// own width table, so the number that matters is tmux's, not the outer
    /// terminal's. Measured with Apple Terminal, iTerm2, Ghostty and Warp
    /// attached, and with NO client attached: **all five runs are identical
    /// across all 58 probed clusters**, so this model is client-independent by
    /// measurement, not just by theory.
    ///
    /// tmux's table is plain `wcwidth` plus emoji-presentation, which diverges
    /// from what the glyphs actually paint in three classes:
    ///
    /// - **Plane-16 Private Use Area** (SF Symbols): 1, against a 2-cell claim.
    ///   tmux's `wcwidth` has never heard of SF Symbols. This is the one that
    ///   visibly breaks: the example's "Supports SF Symbols" box draws three of
    ///   them, and its right border landed 3 cells early (measured 65 vs 68).
    /// - **Bare pictographs** — a lone SMP scalar whose presentation is not
    ///   emoji: 1, against 2. Broader than
    ///   ``isBarePictographUnderAdvancer``, which additionally requires
    ///   `Emoji=Yes`: tmux gives 1 to *any* non-emoji-presentation SMP
    ///   pictograph, including 🁠 dominoes (U+1F060) and 🂡 playing cards
    ///   (U+1F0A1), which are `Emoji=No` and so are not in that set.
    /// - **Lone regional indicators** (🇦 alone): 1, against 2 — same as
    ///   Terminal.app and Warp.
    ///
    /// Everything else agrees: CJK 2, emoji-presentation 2, ZWJ families 2,
    /// flag pairs 2, SMP + skin tone 2, NFD 1, powerline 1, blocks 1.
    ///
    /// Skin-tone clusters on a **BMP** base (✊🏻 = U+270A U+1F3FB) OVER-advance
    /// at 4 — tmux declines to join them — but never reach this model: the
    /// output path strips the modifier via ``String/withSkinToneFallback()``
    /// first, exactly as on iTerm2 and Warp, after which the base advances 2 as
    /// claimed. The one uncorrectable divergence is a bare ☝ (U+261D with no
    /// selector): tmux advances 2 against a 1-cell claim, and CUF cannot claw a
    /// cursor back. It is left alone and documented, as ZWJ is on Terminal.app.
    public var tmuxCursorAdvance: Int {
        let scalars = unicodeScalars
        if scalars.count == 1, let only = scalars.first {
            // Plane-16 PUA — SF Symbols.
            if (0x100000...0x10FFFD).contains(only.value) { return 1 }
        }
        // Bare pictographs. This rule used to be broader — any lone
        // non-emoji-presentation SMP pictograph, dominoes and cards included —
        // because ``terminalWidth`` claimed 2 for those and something had to
        // make up the difference. The claim was the defect: they paint and
        // advance 1 on every host. With it corrected, the set that still needs
        // a CUF here is exactly the set the predicate names.
        if isBarePictographUnderAdvancer { return 1 }
        if isLoneRegionalIndicator { return 1 }
        return terminalWidth
    }

    /// Whether this character is a **bare** SMP pictograph — an emoji-capable
    /// scalar whose default presentation is TEXT (`Emoji=Yes`,
    /// `Emoji_Presentation=No`), carrying no variation selector — such as
    /// 🖥 🛡 🕹 🕷 🎞 🏙 (U+1F5A5, U+1F6E1, …).
    ///
    /// Not to be confused with `🖥️`, the same base **plus U+FE0F**, which is
    /// what real text (and TUIkit's own demo app) overwhelmingly uses and
    /// which is handled by ``isVS16UnderAdvancer``. This predicate is for the
    /// selector-less form only, which is a different grapheme cluster.
    ///
    /// ``terminalWidth`` claims 2 for these, via the `isEmoji` arm of its
    /// closing `0x1F000…0x1FBFF` rule — and that claim is CORRECT: macOS font
    /// fallback has no text glyph for them, so it reaches Apple Color Emoji
    /// and paints 2 cells. The `Emoji=Yes` requirement is what carries that
    /// reasoning: a scalar in the same planes that is NOT an emoji gets no
    /// such fallback, paints one cell, and is claimed one. Measured 2026-07-14 with `paintcard.py`: on Apple
    /// Terminal the glyph overwrites the closing `|` of a `|<glyph>|X`
    /// probe row, exactly as a VS-16 cluster does, while the BMP members of
    /// the same Unicode class (✏ ❤ ☝ — correctly claimed 1) leave it intact.
    ///
    /// But **every** terminal measured advances the cursor by only 1
    /// (Apple 455.1, iTerm2 3.6.11, Ghostty 1.3.1, Warp 2026.07.08, tmux 3.7b
    /// — all five agree). Without this predicate the per-host models fall through
    /// to ``terminalWidth`` and report 2, contradicting the measurement, so
    /// no CUF is emitted and the rest of the row shears one cell left.
    ///
    /// Ghostty is the one host that paints these at 1 cell (grid-strict), so
    /// its CUF buys alignment at the cost of a blank cell — the same trade
    /// already accepted for SF Symbols there, and strictly better than the
    /// shear, since a claim is host-independent and must cover the widest
    /// painter (Apple) or content would be overwritten.
    var isBarePictographUnderAdvancer: Bool {
        let scalars = unicodeScalars
        guard scalars.count == 1, let only = scalars.first else { return false }
        guard (0x1F000...0x1FBFF).contains(only.value) else { return false }
        let properties = only.properties
        return properties.isEmoji && !properties.isEmojiPresentation
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
            if byte >= 0x80 { return unicodeScalars.terminalRunWidth }
            width += 1
        }
        return width
    }
}

extension Sequence where Element == Unicode.Scalar {
    /// Terminal width of an escape-free run of scalars.
    ///
    /// Sums per-scalar widths for as long as every scalar is guaranteed to
    /// stand alone as its own grapheme cluster (see
    /// ``Character/isStandaloneClusterScalar(_:)``) — which covers ASCII, all
    /// the box-drawing chrome, punctuation and CJK, i.e. essentially every line
    /// the framework draws. Only when a scalar that *might* combine appears —
    /// an emoji, a combining mark, a flag, a jamo — does it fall back to real
    /// grapheme-cluster segmentation, which is where the multi-scalar rules in
    /// ``Character/terminalWidth`` live.
    ///
    /// Taking the run as a scalar view rather than a `Substring` matters as
    /// much as skipping the segmentation: slicing a `String` with scalar
    /// indices that may not sit on `Character` boundaries makes the standard
    /// library round each bound down (`_slowRoundDownToNearestCharacter`),
    /// which segments the string all over again.
    var terminalRunWidth: Int {
        var width = 0
        for scalar in self {
            let sv = scalar.value
            if sv >= 0x20, sv <= 0x7E {  // printable ASCII — one cell, no checks
                width += 1
                continue
            }
            guard Character.isStandaloneClusterScalar(sv) else {
                // This run may contain multi-scalar clusters; measure it the
                // exact way, from the start (partial progress is not reusable —
                // an earlier scalar could belong to the cluster we just hit).
                var exact = ""
                exact.unicodeScalars.append(contentsOf: self)
                return exact.reduce(0) { $0 + $1.terminalWidth }
            }
            width += scalar.loneTerminalWidth
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

    /// `run`'s index at every offset, `0...count`, computed once.
    ///
    /// `run.prefix(n)` looks free and is not: `Collection.prefix` advances an
    /// index n places, and `String`'s index advancement is a GRAPHEME walk —
    /// one break query per space, per call. Padding a line is the most common
    /// operation in the framework, so that walk showed up as
    /// `String.index(_:offsetBy:limitedBy:)` under `Collection.prefix` at
    /// 2.9% of a `deep` frame, entirely to re-derive an offset into a run of
    /// spaces that never changes. The table makes the slice O(1).
    static let indices: [String.Index] = {
        var result: [String.Index] = []
        result.reserveCapacity(count + 1)
        var index = run.startIndex
        for _ in 0..<count {
            result.append(index)
            index = run.index(after: index)
        }
        result.append(index)  // == run.endIndex
        return result
    }()
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
        return ASCIISpaces.run[..<ASCIISpaces.indices[count]]
    }
    // Wider than a full terminal row — vanishingly rare. Build it once here; the
    // caller still appends a Substring, keeping the call site uniform.
    return Substring(String(repeating: " ", count: count))
}

extension String {
    /// The visible width of this line up to its last cell that must be painted
    /// — everything after it is unstyled blank space that an overlay has no
    /// business writing.
    ///
    /// Compositing is opaque per cell (see ``FrameBuffer/composited(with:at:)``),
    /// so a floating drag preview writes its padding as blank cells and erases
    /// whatever it passes over. Trailing blanks that carry a BACKGROUND are
    /// kept: on a selected or filled row they are the fill, not padding.
    func visibleWidthBeforeTrailingBlanks() -> Int {
        var width = 0
        var keep = 0
        var background = false
        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                if isSGR { background = Self.background(after: sequence, wasSet: background) }
            case .visible(let character):
                width += character.terminalWidth
                if character != " " || background { keep = width }
            }
        }
        return keep
    }

    /// Whether a background colour is in force after `sequence`, given that it
    /// `wasSet` before. Parameters are applied in order, so `ESC[0;41m` ends up
    /// set and `ESC[41;0m` does not.
    private static func background(after sequence: String, wasSet: Bool) -> Bool {
        var background = wasSet
        let body = sequence.dropFirst(2).dropLast()  // strip "ESC[" and the final "m"
        let parameters = body.split(separator: ";", omittingEmptySubsequences: false)
        if parameters.isEmpty { return false }  // a bare ESC[m is a reset
        var index = 0
        while index < parameters.count {
            let parameter = parameters[index]
            // Only the LEADING sub-parameter names the attribute. In the colon
            // form (`38:5:104`) the whole colour lives inside one `;` parameter,
            // so the components never reach this switch at all — and reading the
            // parameter whole would fail to parse and fall to 0, which is a
            // RESET. That is how a foreground colour used to clear a background.
            // An empty parameter is ECMA-48's default of 0.
            let attribute = parameter.prefix { $0 != ":" }
            let code = Int(attribute) ?? 0
            switch code {
            case 0, 49: background = false
            case 40...47, 48, 100...107: background = true
            default: break  // 38/58 (foreground / underline colour) included
            }
            // 38, 48 and 58 INTRODUCE a colour. In the `;` form its components
            // follow as further parameters — `5;n` or `2;r;g;b` — and walking
            // those through the switch above reads a colour channel as an
            // attribute: `ESC[38;2;200;40;90m` "sets" a background on the green
            // 40, and `ESC[38;2;255;0;0m` clears one on the blue 0. Skip them.
            // (In the colon form they are already inside `parameter`, so the
            // `attribute.count == parameter.count` test leaves those alone.)
            if code == 38 || code == 48 || code == 58, attribute.count == parameter.count {
                index += extendedColorArgumentCount(after: index, in: parameters)
            }
            index += 1
        }
        return background
    }

    /// How many parameters after `index` are the arguments of a `;`-form
    /// extended-colour introducer (38 / 48 / 58).
    ///
    /// The selector says how many follow: `5` (indexed) takes one, `2`
    /// (truecolor) takes three. Anything else — a truncated sequence, or a
    /// selector this does not know — takes none, so an unparseable tail is
    /// walked normally rather than swallowing the rest of the sequence.
    /// Whether SGR styling is still in force at the end of this string — i.e.
    /// whether text appended to it would inherit colour or attributes.
    ///
    /// The terminal applies SGR parameters in order, so only the LAST sequence
    /// decides: a pure reset (`ESC[0m`, a bare `ESC[m`, an all-zero parameter
    /// list) closes everything, and anything else leaves something on.
    ///
    /// Erring toward `true` costs a redundant four-byte reset; erring toward
    /// `false` bleeds the attribute over whatever the caller appends. So a
    /// sequence this cannot prove is a reset counts as open.
    public var leavesSGROpen: Bool {
        guard utf8.contains(0x1B) else { return false }  // plain text: no scan
        var open = false
        for segment in ansiSegments() {
            if case .ansi(let sequence, isSGR: true) = segment {
                open = !Self.isSGRReset(sequence)
            }
        }
        return open
    }

    /// Whether an SGR sequence turns everything off.
    private static func isSGRReset(_ sequence: String) -> Bool {
        let body = sequence.dropFirst(2).dropLast()  // strip "ESC[" and the 'm'
        if body.isEmpty { return true }  // a bare ESC[m is a reset
        return body.split(separator: ";", omittingEmptySubsequences: false)
            .allSatisfy { $0.isEmpty || Int($0) == 0 }
    }

    private static func extendedColorArgumentCount(
        after index: Int, in parameters: [Substring]
    ) -> Int {
        let available = parameters.count - index - 1
        guard available > 0 else { return 0 }
        switch Int(parameters[index + 1].prefix { $0 != ":" }) ?? -1 {
        case 5: return Swift.min(2, available)  // selector + one index
        case 2: return Swift.min(4, available)  // selector + r, g, b
        default: return 0
        }
    }

    /// The visible width of the string in terminal cells, excluding ANSI escape codes.
    ///
    /// Accounts for wide characters (emoji, CJK) that occupy 2 terminal cells
    /// and zero-width characters (combining marks, variation selectors).
    public var strippedLength: Int {
        // Fast path: an all-ASCII line, styled or not, is one cell per visible
        // byte — no scalar decoding, no grapheme clustering, no slicing. That
        // covers labels, wrapped words, table cells and every SGR-coloured line
        // built from them, which is the overwhelming majority of what a terminal
        // draws. `strippedLength` runs per word during `Text.wordWrap` and per
        // line during render, every frame, so this is the single most-executed
        // width path in the framework.
        if let ascii = asciiStrippedLength() { return ascii }

        // Non-ASCII, no escapes: one visible run — the whole string.
        // (ESC is a standalone byte, never part of a multi-byte scalar, so a
        // direct byte search settles it without decoding.)
        if !utf8.contains(0x1B) {
            return unicodeScalars.terminalRunWidth
        }

        // General path: ANSI present — measure each visible run independently (a
        // trailing Extend scalar after an SGR terminator must not fuse onto the
        // previous run; see `forEachVisibleANSIRun(_:)`). Each run is a borrowed
        // scalar slice, so this counts widths without allocating.
        var total = 0
        forEachVisibleANSIRun { run in
            total += run.terminalRunWidth
        }
        return total
    }

    /// Visible width of this string when every byte of it is ASCII, or `nil` if
    /// any byte is not.
    ///
    /// ASCII is exactly one cell per visible byte and no ASCII byte can combine
    /// with a neighbour into a wider grapheme cluster, so the whole measurement
    /// reduces to running the CSI state machine of ``forEachVisibleANSIRun(_:)``
    /// over the UTF-8 bytes and counting what falls outside the escapes. The
    /// scalar-level scan it replaces here decoded every scalar, sliced a run per
    /// escape and re-scanned each slice; this touches each byte once.
    ///
    /// Not `private`: the tests call it directly, so that "the fast path and
    /// the general path agree" is asserted rather than assumed.
    func asciiStrippedLength() -> Int? {
        enum ScanState { case normal, sawESC, inCSI }
        var state = ScanState.normal
        var width = 0
        for byte in utf8 {
            if byte >= 0x80 { return nil }
            switch state {
            case .normal:
                if byte == 0x1B { state = .sawESC } else { width += 1 }

            case .sawESC:
                if byte == 0x5B {  // '[' → CSI introducer
                    state = .inCSI
                } else if byte != 0x1B {  // a bare ESC is dropped; this byte is visible
                    width += 1
                    state = .normal
                }

            case .inCSI:
                let value = UInt32(byte)
                if Self.isCSIBodyByte(value) { continue }  // parameter or intermediate
                if Self.isCSIFinalByte(value) {
                    state = .normal  // introducer complete, terminator consumed
                } else if byte == 0x1B {
                    state = .sawESC  // ESC interrupts a malformed CSI
                } else {  // not a CSI byte where a terminator was expected
                    width += 1
                    state = .normal
                }
            }
        }
        return width
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
    /// *between* runs), so a borrowed slice carries the same scalars with no
    /// copy.
    ///
    /// The run is handed over as a **scalar view** slice, not a `Substring`.
    /// The scan runs at the scalar level (it must — see below), and its
    /// boundaries need not fall on `Character` boundaries, so building a
    /// `Substring` from them makes the standard library round each bound down
    /// to the nearest cluster (`_slowRoundDownToNearestCharacter`) — grapheme
    /// segmentation of the whole line, twice per run, purely to produce a slice
    /// whose callers only wanted its scalars back.
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
    private func forEachVisibleANSIRun(_ body: (Substring.UnicodeScalarView) -> Void) {
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
                    if hasRun { body(scalars[runStart..<index]); hasRun = false }
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
                if Self.isCSIBodyByte(value) {
                    break  // parameter or intermediate byte — stay in CSI
                }
                if Self.isCSIFinalByte(value) {
                    state = .normal  // final byte — introducer complete, consumed
                } else if value == 0x1B {  // ESC interrupts a malformed CSI
                    state = .sawESC
                } else {  // not a CSI byte at all where a terminator was
                    runStart = index  // expected: it starts a visible run
                    hasRun = true
                    state = .normal
                }
            }
            index = scalars.index(after: index)
        }
        if hasRun { body(scalars[runStart..<index]) }  // index == endIndex
    }

    /// Whether `value` is a CSI parameter or intermediate byte — everything
    /// allowed between the `[` and the final byte (ECMA-48: parameters
    /// `0x30...0x3F`, which covers digits, `;`, the colon of an SGR
    /// sub-parameter and the `?`/`<`/`=`/`>` private markers; intermediates
    /// `0x20...0x2F`, e.g. the space of DECSCUSR `ESC[2 q`).
    ///
    /// Accepting only digits and `;` — as this did — made every other form
    /// leak: the `[` was consumed and the `?` of `ESC[?25l` then started a
    /// VISIBLE run, so `stripped` left "?25l" on screen, `sanitizedForTerminal`
    /// (documented as sanitising user input against escape injection) let it
    /// through, and the wrapper measured 4 cells for a sequence the terminal
    /// paints in 0 — border and column misalignment.
    public static func isCSIBodyByte(_ value: UInt32) -> Bool {
        (0x20...0x3F).contains(value)
    }

    /// Whether `value` terminates a CSI sequence (ECMA-48 final bytes
    /// `0x40...0x7E` — the letters plus `@[\]^_\`{|}~`).
    public static func isCSIFinalByte(_ value: UInt32) -> Bool {
        (0x40...0x7E).contains(value)
    }

    /// The index just past the CSI escape sequence beginning at `index`, which
    /// must address the ESC.
    ///
    /// One walker, because there were six and five of them used a rule this
    /// file documents as wrong: "digits and `;`, then a letter" stops at the
    /// `?` of `ESC[?25l`, leaves the rest to be counted as VISIBLE text, and so
    /// mis-measures a row the terminal paints in zero cells. The classifiers
    /// above are the ECMA-48 ones, and everything that skips an escape should
    /// go through them.
    ///
    /// A lone ESC, or an ESC followed by something that is not `[`, yields the
    /// index just past the ESC — the callers all treat the remainder as
    /// ordinary content, which is the safe reading for a byte we cannot
    /// account for.
    func csiSequenceEnd(from index: Index) -> Index {
        var cursor = self.index(after: index)
        guard cursor < endIndex, self[cursor] == "[" else { return cursor }
        cursor = self.index(after: cursor)
        func classify(_ test: (UInt32) -> Bool) -> Bool {
            guard cursor < endIndex else { return false }
            let scalars = self[cursor].unicodeScalars
            guard scalars.count == 1, let value = scalars.first?.value else { return false }
            return test(value)
        }
        while classify(Self.isCSIBodyByte) { cursor = self.index(after: cursor) }
        if classify(Self.isCSIFinalByte) { cursor = self.index(after: cursor) }
        return cursor
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
    public func ansiSegments() -> [ANSISegment] {
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
                while index < scalars.endIndex, Self.isCSIBodyByte(scalars[index].value) {
                    sequence.append(scalars[index])
                    index = scalars.index(after: index)
                }
                // Final byte, consumed by exactly one scalar so a trailing
                // Extend scalar stays a visible segment.
                if index < scalars.endIndex, Self.isCSIFinalByte(scalars[index].value) {
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
        // copy). Otherwise append each visible run (a borrowed scalar slice)
        // into one result — no intermediate `[String]`.
        if !unicodeScalars.contains(where: { $0.value == 0x1B }) { return self }
        var result = ""
        result.reserveCapacity(utf8.count)
        forEachVisibleANSIRun { result.unicodeScalars.append(contentsOf: $0) }
        return result
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
}
