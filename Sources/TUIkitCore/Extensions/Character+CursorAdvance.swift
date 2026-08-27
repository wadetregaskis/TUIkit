//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Character+CursorAdvance.swift
//
//  Where each measured terminal puts the character AFTER a cluster.
//
//  Split out of `String+TerminalWidth.swift`, which holds the question these
//  answer against: `terminalWidth` is the CLAIM, the cells the layout reserves,
//  and these are what the host actually does with them. The gap between the two
//  is what `String+CursorCompensation.swift` closes, and the subject of
//  `Documentation/Terminal-compatibility.md`.
//
//  Every value here is measured, never derived. `Tools/TerminalProbes/` holds
//  the probes and `Tools/TerminalProbes/data/` the records; a model changed
//  without a record to point at is a guess wearing a number.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Terminal.app Cursor-Advance Quirks

extension Character {
    /// The number of columns Terminal.app's INTERNAL cursor moves when this
    /// character is printed — the DSR column, which is NOT always where the
    /// glyph or the next character is painted.
    ///
    /// ## Two counters, and which one this is
    ///
    /// Apple Terminal keeps two columns per row and they can disagree by nine:
    ///
    /// - **internal** (this property; DSR-measured): the terminal's own
    ///   bookkeeping. It decides **when the row wraps** and how far a write is
    ///   accepted before the terminal moves to the next row. A row whose
    ///   internal total exceeds the width wraps early, and the cells the wrap
    ///   abandoned keep the terminal's DEFAULT background — the
    ///   white-cells-at-the-end-of-the-row defect.
    /// - **paint** (``terminalAppPaintsShortOfClaim`` and the walk's per-class
    ///   table): where glyphs actually land. 🤙🏽 advances the internal column
    ///   4 while composing into 2 cells and painting the next character at 2.
    ///
    /// Compensation must end each cluster with BOTH counters at the claimed
    /// width. A briefly-shipped model returned paint from this property; the
    /// conservation test then verified paint and was blind to internal drift,
    /// and every full-width row carrying a skin tone wrapped. Everything here
    /// is the DSR measurement, and the walk closes the paint gap separately.
    public var terminalAppCursorAdvance: Int {
        // A ZWJ cluster first: its INTERNAL advance is the sum of its
        // segments', including their VS-16 under-advance — DSR-measured to
        // predict every corpus case exactly (👩‍🚀 2+1+2 = 5, 👨‍👩‍👧‍👦 11,
        // ❤️‍🔥 1+1+2 = 4, 👩🏽‍🚀 4+1+2 = 7). Unconditional, NOT gated on
        // ``TerminalWidthTraits``: the claim for this host is the composed
        // width, but the internal column decomposes regardless.
        if let summed = Self.summedInternalZWJAdvance(self, segmentAdvance: {
            $0.terminalAppCursorAdvance
        }) {
            return summed
        }
        let scalars = unicodeScalars

        // A tag-sequence flag — 🏴 followed by U+E00xx tag scalars (🏴󠁧󠁢󠁳󠁣󠁴󠁿):
        // the glyph composes into 2 cells while the internal column advances 2
        // plus one per tag scalar (Scotland = 2 + 6 = 8, DSR-measured). The
        // generic pull-back squares it: the move sweep measured CUB(6) landing
        // the next character's paint exactly at the claim.
        let tagCount = scalars.count { (0xE0020...0xE007F).contains($0.value) }
        if tagCount > 0, let first = scalars.first, first.properties.isEmoji {
            return 2 + tagCount
        }

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
        // (U+1F1E6…U+1F1FF): the INTERNAL advance is 2, matching the claim, so
        // the row never wraps because of one. (The PAINT of what follows lands
        // at 1 — the flag's second cell — which the walk nudges separately; an
        // earlier model returned that 1 from here and the injected CUF pushed
        // the internal column to 3, wrapping every full-width row with a flag.)
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

    /// The INTERNAL cursor advance Apple Terminal makes over a ZWJ cluster:
    /// the sum of its segments' advances plus one column per joiner, or `nil`
    /// for a cluster with no joiner.
    ///
    /// The same arithmetic as ``Swift/String/summedZWJAdvance(_:segmentAdvance:)``
    /// but NOT gated on ``TerminalWidthTraits``: that gate exists for hosts
    /// whose *claim* is widened to the decomposed width (Warp), and Apple
    /// Terminal is not one — its claim is the composed two cells while its
    /// internal column decomposes regardless. Gating this on the traits made
    /// the internal model silently revert to the claim when the widening was
    /// (correctly) turned off for this host.
    static func summedInternalZWJAdvance(
        _ character: Character, segmentAdvance: (Character) -> Int
    ) -> Int? {
        let scalars = character.unicodeScalars
        guard scalars.contains(where: { $0.value == 0x200D }),
            let first = scalars.first, first.properties.isEmoji
        else { return nil }
        var total = 0
        var joiners = 0
        var segment = String.UnicodeScalarView()
        for scalar in scalars {
            if scalar.value == 0x200D {
                joiners += 1
                total += segmentAdvance(Character(String(segment)))
                segment = String.UnicodeScalarView()
            } else {
                segment.append(scalar)
            }
        }
        total += segmentAdvance(Character(String(segment)))
        return total + joiners
    }

    /// `true` when, after this cluster's internal column has been pulled back
    /// to the claim with `CUB`, the next character still PAINTS one cell short
    /// of it — so the walk must go back one further and step forward.
    ///
    /// ## The two counters, and what was measured
    ///
    /// Apple Terminal's internal column (DSR — ``terminalAppCursorAdvance``)
    /// and its paint position diverge on composed clusters, and compensation
    /// must end with both at the claimed width: internal, or a full-width row
    /// wraps and its abandoned tail shows the terminal's default background;
    /// paint, or everything after the cluster shears. Measured with
    /// `landing_probe.py` and the move sweep (2026-08-26/27, Terminal.app
    /// 455.1, alternate screen), `CUB(internal − claim)` after the cluster
    /// brings BOTH counters to the claim for skin tones and emoji-led ZWJ
    /// sequences — the paint response to `CUB` is not linear, it *snaps* to
    /// the internal column:
    ///
    /// | cluster | internal | paint after cluster | after `CUB(int−2)` |
    /// |---|---|---|---|
    /// | 🤙🏽 ✊🏻 | 4 | 2 | internal 2, paint 2 |
    /// | ☝🏻 ✌🏼 | 3 | 1 | internal 2, paint 2 |
    /// | 👩‍🚀 👨‍👩‍👧‍👦 | 5, 11 | 2 | internal 2, paint 2 |
    ///
    /// Three classes are the exception — after the pull-back the next
    /// character still paints at 1, so they need `CUB(int−claim+1)` then
    /// `CUF(1)` (same net internal, one more paint cell):
    ///
    /// - a ZWJ sequence whose FIRST segment has no emoji presentation of its
    ///   own (❤️‍🔥, 🏳️‍🌈, ⛓️‍💥 — which is why 🏴‍☠️ behaves differently
    ///   from 🏳️‍🌈 despite looking like the same kind of thing),
    /// - flag pairs (internal already equals the claim; paint lands at 1),
    /// - keycap sequences (likewise).
    var terminalAppPaintsShortOfClaim: Bool {
        let scalars = unicodeScalars
        guard let first = scalars.first else { return false }
        if TerminalQuirks.isFlagPair(self) { return true }
        if scalars.contains(where: { $0.value == 0x20E3 }) { return true }
        // The first-scalar guard keeps `m🏻` (an SGR final byte fused with a
        // lone Fitzpatrick, which is Grapheme_Extend) out of here.
        return scalars.contains { $0.value == 0x200D }
            && first.properties.isEmoji
            && !first.properties.isEmojiPresentation
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
        // A ZWJ sequence whose FIRST segment is a VS-16 cluster — ❤️‍🔥 🏳️‍🌈 —
        // advances 1 against a claim of 2: the leading segment carries this
        // host's VS-16 under-advance and the rest folds into it. Long
        // documented as unhandled; measurable now that the emoji page draws
        // one. CUF closes it.
        if let joiner = unicodeScalars.firstIndex(where: { $0.value == 0x200D }),
            unicodeScalars[..<joiner].contains(where: { $0.value == 0xFE0F })
        {
            // The FIRST segment is what matters, not the base's plane: ❤️ is
            // BMP and 🏳️ is SMP, and both behave the same because both carry
            // the selector.
            return 1
        }
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
        // A skin-tone cluster on a BMP text-presentation base — ☝🏻 ✌🏼 ✍🏽 ⛹🏾 —
        // merges to ONE cell here, not two: the base is a 1-cell text glyph and
        // Ghostty keeps it that way with the modifier folded in. Claimed 2, so
        // a CUF is owed, exactly as for its SF Symbols — alignment bought with
        // a blank cell rather than a shear. Measured 2026-08-26 against every
        // cluster the Example emoji page draws.
        if unicodeScalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }),
            let base = unicodeScalars.first, base.value <= 0xFFFF,
            base.properties.isEmoji, !base.properties.isEmojiPresentation
        {
            return 1
        }
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
        if let summed = Self.summedZWJAdvance(self, segmentAdvance: { $0.warpCursorAdvance }) {
            return summed
        }
        // Plane-16 Private Use Area — SF Symbols. Warp advances 1 against the
        // 2-cell claim, exactly like the other four hosts, and this model was
        // the only one of the five that did not say so: it fell through to
        // `terminalWidth`, reported 2, and so emitted no CUF. Every SF Symbol
        // then sheared its row one cell left, which is why the Example emoji
        // page's SF Symbols panel drew its right border displaced and its
        // scrollbar jammed against it.
        //
        // Measured 2026-08-26 on the alternate screen: each symbol advances 1,
        // and a row claimed at 20 cells measured 16 — short by exactly one per
        // symbol.
        if unicodeScalars.count == 1, let only = unicodeScalars.first,
            (0x100000...0x10FFFD).contains(only.value)
        {
            return 1
        }
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
