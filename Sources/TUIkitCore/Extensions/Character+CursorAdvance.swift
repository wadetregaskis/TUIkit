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
    /// ## Three facts per row, and which one this is
    ///
    /// Apple Terminal keeps three per-row facts that can disagree:
    ///
    /// - **internal** (this property; DSR-measured): the terminal's own
    ///   bookkeeping. It decides **when the row wraps** and how far a write is
    ///   accepted before the terminal moves to the next row. A row whose
    ///   internal total exceeds the width wraps early, and the cells the wrap
    ///   abandoned keep the terminal's DEFAULT background — the
    ///   white-cells-at-the-end-of-the-row defect. 🤙🏽 advances it 4 while
    ///   composing into 2 cells.
    /// - **paint**: where the glyph and its immediate follower land.
    /// - **stored width** (``terminalAppStoresWiderThanPainted``): how many
    ///   columns the row's text store keeps for the cluster, which decides
    ///   where everything LATER on the row paints — a store wider than the
    ///   paint displaces the whole tail left, cursor moves notwithstanding.
    ///
    /// Compensation must square all three with the claimed width. A
    /// briefly-shipped model returned paint from this property; the
    /// conservation test then verified paint and was blind to internal drift,
    /// and every full-width row carrying a skin tone wrapped. Everything here
    /// is the DSR measurement; the walk squares the other two per class.
    public var terminalAppCursorAdvance: Int {
        // A joined cluster first: its INTERNAL advance is the sum of its
        // segments' plus one column per joiner — ZWJ or ZWNJ — including the
        // segments' VS-16 under-advance. DSR-measured to predict every corpus
        // case exactly (👩‍🚀 2+1+2 = 5, 👨‍👩‍👧‍👦 11, ❤️‍🔥 1+1+2 = 4,
        // 👩🏽‍🚀 4+1+2 = 7), and the ZWNJ arm against the separated skin-tone
        // rewrite the walk emits (🤙+ZWNJ+🏽 = 2+1+2 = 5, ☝+ZWNJ+🏻 = 1+1+2 =
        // 4; 2026-08-27). Unconditional, NOT gated on ``TerminalWidthTraits``:
        // the claim varies with the traits, but the internal column decomposes
        // regardless.
        if let summed = Self.summedInternalJoinerAdvance(self, segmentAdvance: {
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
            Self.isPlaneSixteenGlyph(only.value)
        {
            return 1
        }

        guard scalars.count > 1, let first = scalars.first else { return terminalWidth }

        // A keycap — base + U+20E3, with or without VS-16 — advances 2
        // whatever the claim (DSR, the advance battery record). The FE0F form
        // matches its 2-cell claim and is repaired for its wide STORE by
        // surgery; the BARE form (1⃣) is claimed 1 — the base's own width —
        // so its 2 is an over-advance the walk pulls back with CUB(1).
        // Modelled explicitly because the fall-through used to report the
        // claim (1), and the stores-wider predicate then routed the bare form
        // into store surgery calibrated for a cluster it is not: the surgery
        // ends at the cursor's real column (2), one past the claim, shearing
        // every follower — and deleting a stored column never measured to be
        // surplus. (The bare form's paint and store remain unmeasured; the
        // pull-back is the alignment-safe treatment until a pixel card runs.)
        if scalars.contains(where: { $0.value == 0x20E3 }) {
            return 2
        }

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

    /// The INTERNAL cursor advance Apple Terminal makes over a joined cluster
    /// — ZWJ (U+200D) or ZWNJ (U+200C): the sum of its segments' advances plus
    /// one column per joiner, or `nil` for a cluster with neither.
    ///
    /// The same arithmetic as ``Swift/String/summedZWJAdvance(_:segmentAdvance:)``
    /// but NOT gated on ``TerminalWidthTraits``: that gate exists for hosts
    /// whose *claim* is widened to the decomposed width (Warp), and Apple
    /// Terminal's internal column decomposes regardless of the claim in force.
    /// Gating this on the traits made the internal model silently revert to
    /// the claim when the widening was (correctly) turned off for this host.
    ///
    /// The ZWNJ arm is what prices the separated skin-tone rewrite the walk
    /// emits for this host: the joiner occupies its own internal column
    /// (measured 2026-08-27 — 🤙+ZWNJ+🏽 advances 5), which is also why the
    /// separated cluster CLAIMS base + 3 rather than base + 2.
    static func summedInternalJoinerAdvance(
        _ character: Character, segmentAdvance: (Character) -> Int
    ) -> Int? {
        let scalars = character.unicodeScalars
        guard scalars.contains(where: { $0.value == 0x200D || $0.value == 0x200C }),
            let first = scalars.first, first.properties.isEmoji
        else { return nil }
        var total = 0
        var joiners = 0
        var segment = String.UnicodeScalarView()
        for scalar in scalars {
            if scalar.value == 0x200D || scalar.value == 0x200C {
                // A leading, trailing, or doubled joiner leaves an empty
                // segment — `Character("")` is a fatalError, and such clusters
                // are ordinary data (a family emoji truncated at a byte limit,
                // a stray joiner pasted from the web). Same answer as
                // ``emojiZWJSegments``: not a sequence this sums; the caller
                // falls through to composed pricing.
                guard !segment.isEmpty else { return nil }
                joiners += 1
                total += segmentAdvance(Character(String(segment)))
                segment = String.UnicodeScalarView()
            } else {
                segment.append(scalar)
            }
        }
        guard !segment.isEmpty else { return nil }
        total += segmentAdvance(Character(String(segment)))
        return total + joiners
    }

    /// `true` for the clusters Apple Terminal STORES one column wider than it
    /// paints them — flag pairs and keycap sequences — which the walk repairs
    /// with store surgery: the cluster, then `CUB(1)`, `DCH(1)`, `CUF(1)`.
    ///
    /// ## Stored width is a third fact, and it poisons the row
    ///
    /// Apple Terminal's internal column (DSR — ``terminalAppCursorAdvance``)
    /// says when the row wraps; its paint position says where ink lands; and
    /// the row's STORED content decides where every *later* write on the row —
    /// sequential or absolutely addressed — actually paints. A cluster whose
    /// stored width differs from its painted width displaces everything to
    /// its right by the difference, and no cursor move can repair that,
    /// because cursor moves do not edit the store.
    ///
    /// Flag pairs and keycaps advance the internal column exactly their
    /// 2-cell claim, paint their glyph into those 2 cells — and still paint
    /// every follower one cell left (measured 2026-08-27, treatment cards 2–4,
    /// Terminal.app 455.1: `abc` and an absolutely-placed probe column both
    /// shifted −1 after 🇺🇸 under the previous pull-back-and-step emission).
    /// Deleting one stored column from inside the cluster is the only measured
    /// repair: `CUB(1)` steps into the cluster, `DCH(1)` removes the surplus
    /// stored column (the follower probes then land exactly), and `CUF(1)`
    /// restores the cursor the deletion left one short. The DCH shifts and
    /// backfills everything right of the cursor, which is safe here because
    /// `FrameDiffWriter` always emits whole rows left to right — everything
    /// right of the cluster is rewritten after it in the same emission.
    ///
    /// ZWJ sequences led by a text-presentation segment (❤️‍🔥 🏳️‍🌈) used to
    /// be the third member of this class; the walk now decomposes ZWJ
    /// sequences for this host instead, so they never reach it.
    var terminalAppStoresWiderThanPainted: Bool {
        let scalars = unicodeScalars
        if TerminalQuirks.isFlagPair(self) { return true }
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        // The FE0F form only: the surgery's card battery measured base +
        // U+FE0F + U+20E3, whose advance (2) equals its claim. A BARE keycap
        // (1⃣, claimed 1, advance 2) is an over-advancer with an UNMEASURED
        // store — including it here fired the surgery with the wrong balance,
        // ending one column past the claim.
        return scalars.contains { $0.value == 0x20E3 }
            && scalars.contains { $0.value == 0xFE0F }
    }

    /// This cluster's ZWJ-separated segments as independent clusters — the
    /// software decomposition the Apple Terminal walk emits in place of an
    /// emoji ZWJ sequence — or `nil` when this is not one.
    ///
    /// Splits on U+200D only, never U+200C: a separated skin-tone cluster
    /// (🤙+ZWNJ+🏽) is a finished emission, not something to take further
    /// apart. The joiners themselves are dropped — that is the point: Apple
    /// Terminal stores a column for every joiner it is sent while painting
    /// none, and every cursor-move repair for that mismatch was measured to
    /// displace later absolute positioning on the row (treatment cards 2–3,
    /// 2026-08-27). The `isEmoji` guard keeps `m🏻` — an SGR final byte fused
    /// with a Grapheme_Extend scalar — out, exactly as in the advance model.
    var emojiZWJSegments: [Character]? {
        let scalars = unicodeScalars
        guard scalars.contains(where: { $0.value == 0x200D }),
            let first = scalars.first, first.properties.isEmoji
        else { return nil }
        var segments: [Character] = []
        var segment = String.UnicodeScalarView()
        for scalar in scalars {
            if scalar.value == 0x200D {
                guard !segment.isEmpty else { return nil }
                segments.append(Character(String(segment)))
                segment = String.UnicodeScalarView()
            } else {
                segment.append(scalar)
            }
        }
        guard !segment.isEmpty else { return nil }
        segments.append(Character(String(segment)))
        return segments
    }

    /// This skin-tone cluster rewritten as base + ZWNJ + modifier — the
    /// separated form the Apple Terminal walk emits for every Fitzpatrick
    /// cluster — or `nil` for anything that is not one.
    ///
    /// The ZWNJ stops the terminal re-joining the pair: every other separator
    /// measured (save/restore-cursor, an SGR, an 80 ms flush gap, absolute
    /// re-positioning) left base and modifier adjacent in the row's stored
    /// text, and Terminal.app composed them again, paint displacement and all.
    /// ZWNJ is the one that sticks, at the cost of one blank column — painted
    /// mid-pair after an emoji-presentation base, trailing the swatch after a
    /// VS-16-promoted one (treatment cards 1–3 2026-08-27; point-up and
    /// adjacency cards 2026-08-28, which also ruled out every alternative:
    /// ZWSP/WJ/SHY/BOM-class separators each cost the same column, CGJ
    /// composes straight through into the displacing raw-cluster profile, and
    /// a reversed pair could soak up tone from whatever precedes it).
    ///
    /// A text-presentation base (☝🏻 ✍🏿 ⛹🏾) is **promoted with VS-16**: the
    /// bare rewrite was measured to misalign (☝+ZWNJ+🏻 paints wrong), and the
    /// old pull-back re-rendered the cluster as its bare narrow monochrome
    /// glyph — tone lost AND a blank cell beside it (user-reported
    /// 2026-08-28). The promoted form stays a single grapheme whose internal
    /// advance (base 1 + ZWNJ 1 + modifier 2) falls one short of its claim
    /// (2 + 1 + 2), so the caller's ordinary under-advance arm finishes the
    /// job — `ECH(5)` + cluster + `CUF(1)`, card-measured aligned with the
    /// tone kept as a swatch. An emoji-presentation base needs no promotion
    /// and lands exactly on its claim, appended plain.
    ///
    /// Idempotent: an already-separated cluster reproduces itself, because the
    /// base reconstruction skips any U+200C already present and keeps an
    /// existing VS-16.
    var separatedSkinToneEmission: String? {
        let scalars = unicodeScalars
        guard scalars.count > 1, let first = scalars.first,
            first.properties.isEmojiModifierBase,
            scalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }),
            // A ZWJ sequence carrying a tone (👩🏽‍🚀) is not a plain tone
            // cluster: separating it whole would splice the ZWNJ into the
            // middle of the sequence. It decomposes first where decomposition
            // is on, and stays a pull-back cluster where it is not.
            !scalars.contains(where: { $0.value == 0x200D })
        else { return nil }
        var base = String.UnicodeScalarView()
        var modifiers = String.UnicodeScalarView()
        for scalar in scalars {
            if (0x1F3FB...0x1F3FF).contains(scalar.value) {
                modifiers.append(scalar)
            } else if scalar.value != 0x200C {
                base.append(scalar)
            }
        }
        if !first.properties.isEmojiPresentation,
            !base.contains(where: { $0.value == 0xFE0F })
        {
            base.append(Unicode.Scalar(0xFE0F)!)
        }
        var result = String(base)
        for modifier in modifiers {
            result.unicodeScalars.append(Unicode.Scalar(0x200C)!)
            result.unicodeScalars.append(modifier)
        }
        return result
    }

    /// This Fitzpatrick cluster with its redundant emoji-presentation selector
    /// removed — ☝️🏽 (U+261D U+FE0F U+1F3FD) becomes ☝🏽 — or `nil` when there
    /// is no selector to remove or this is not a plain tone cluster.
    ///
    /// UTS #51 has the modifier itself force emoji presentation, so
    /// `base + VS-16 + modifier` is a non-RGI spelling of `base + modifier`:
    /// the same emoji, one scalar shorter — and the spelled form is the one
    /// the terminals mishandle, where the plain form is measured on every
    /// host (ledger rows `tone_point_up_vs16` vs `tone_point_up`):
    ///
    /// - **Ghostty** detaches ☝️🏽 across 4 cells (the selector defeats its
    ///   merge) but merges ☝🏽 at advance 1 — which the ordinary
    ///   `ECH(2)`+`CUF(1)` under-advance repair lands exactly on the 2-cell
    ///   claim, tone kept.
    /// - **iTerm2** renders ☝️🏽 in 3 cells against the old promoted claim of
    ///   4 (a one-cell hole) and ☝🏽 in exactly the 3 the bare-base claim
    ///   allocates — aligned verbatim.
    /// - **Warp** gives the pair 4 cells spelled, 3 normalized — aligned
    ///   either way, one cell tighter without the selector.
    /// - **Apple Terminal** does not use this: both spellings measure
    ///   identically there (advance 3, land 1), its separation rewrite
    ///   already treats the spelled form (the base reconstruction keeps the
    ///   selector separation would otherwise re-add), and under the pull-back
    ///   fallback a strip would discard the author's scalar for no rendering
    ///   gain.
    ///
    /// The shared forward-compensation walk (iTerm2, Ghostty, Warp, tmux)
    /// emits the normalized form and `String.detachedSkinToneWidth` prices
    /// it, which closed what the conformance suite recorded as "one cluster,
    /// two hosts, two answers".
    /// The raw models keep explicit arms for the spelled form, because a raw
    /// cluster the user's terminal receives un-normalized still advances the
    /// measured way.
    ///
    /// ZWJ- and ZWNJ-carrying clusters are left alone: a selector inside a
    /// sequence is not redundant in the same way (the sequence's segments
    /// normalize individually after decomposition where decomposition is on),
    /// and an already-separated base+ZWNJ+modifier pair is a finished
    /// emission.
    var withoutRedundantToneVS16: Character? {
        let scalars = unicodeScalars
        guard scalars.count > 1, let first = scalars.first,
            first.properties.isEmojiModifierBase,
            scalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }),
            scalars.contains(where: { $0.value == 0xFE0F }),
            !scalars.contains(where: { $0.value == 0x200D || $0.value == 0x200C })
        else { return nil }
        var result = String.UnicodeScalarView()
        for scalar in scalars where scalar.value != 0xFE0F {
            result.append(scalar)
        }
        // Base scalars plus Extend-class modifiers: one grapheme by
        // construction.
        return Character(String(result))
    }

    /// `true` when the Apple Terminal walk rewrites this cluster into a form
    /// whose emission lands the cursor exactly on its claim — an emoji ZWJ
    /// sequence it will decompose, or a skin-tone cluster it will separate —
    /// under the ``TerminalWidthTraits`` in force.
    ///
    /// The right-edge clip (`ansiAwarePrefixForTerminalApp`) budgets each
    /// cluster's cursor cost to decide what fits a row without wrapping. For
    /// these clusters the RAW internal advance (👨‍👩‍👧‍👦: 11) is not what
    /// the walk emits — the rewritten form lands on the claim (8),
    /// monotonically (a VS-16-promoted separated tone gets there via its
    /// trailing `CUF`) — so budgeting the raw number would replace clusters
    /// with spaces that actually fit.
    var terminalAppWalkRewritesToClaim: Bool {
        let traits = TerminalWidthTraits.current
        if traits.zwjSequences == .decomposedDroppingJoiners, emojiZWJSegments != nil {
            return true
        }
        return traits.skinTone == .separated
            && separatedSkinToneEmission != nil
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
    /// advance 2, and ZWJ sequences mostly advance 2 — except VS-16-leading
    /// ones like ❤️‍🔥, which advance 1 and are modelled below (the arm was
    /// long documented as unhandled; the ordinary ECH+CUF closes it).
    /// Fitzpatrick skin tones split by base: SMP bases merge to 2, BMP
    /// bases draw base + swatch — and since the detached-claim widening
    /// (`TerminalWidthTraits`, `.detachedOnBMPBases`) the layout claims the
    /// cells that rendering occupies, so the clusters pass through the walk
    /// un-stripped and mostly aligned. The strip
    /// (``String/withSkinToneFallback(scope:)``) fires only for a caller
    /// that never published the host's traits. The odd members are modelled
    /// explicitly below: a text-presentation base with a redundant VS-16
    /// advances 3 (raw truth — the walk normalizes it away), and the SMP
    /// text-presentation pair 🏋🏽 merges NARROW at 1 against its composed
    /// claim of 2, closed by ECH(2)+CUF(1).
    public var iTerm2CursorAdvance: Int {
        // A ZWJ sequence whose FIRST segment is a VS-16 cluster — ❤️‍🔥 🏳️‍🌈 —
        // advances 1 against a claim of 2: the leading segment carries this
        // host's VS-16 under-advance and the rest folds into it. Long
        // documented as unhandled; measurable now that the emoji page draws
        // one. CUF closes it.
        if leadsWithVS16Segment {
            return 1
        }
        let scalars = unicodeScalars
        if scalars.contains(where: { $0.value == 0x20E3 }) {
            return 1
        }
        if scalars.count == 1, let only = scalars.first,
            Self.isPlaneSixteenGlyph(only.value)
        {
            return 1
        }
        // Fitzpatrick tones on a TEXT-presentation base, both planes (DSR
        // sweep 2026-08-28, committed advance record):
        //
        // - Spelled with a redundant FE0F (☝️🏽 3, 🏋️🏽 3): narrow base 1 +
        //   swatch 2, whatever the plane. Raw-cluster truth only — the walk
        //   strips the selector before this host sees it.
        // - The bare SMP form (🏋🏽): 1 — merged NARROW, unlike a BMP base
        //   (☝🏽), which detaches at 3, exactly the widened claim, and so
        //   falls through below. Claimed 2 (`.detachedOnBMPBases` widens
        //   only BMP bases), so the ordinary ECH(2)+CUF(1) closes it.
        if scalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }),
            let first = scalars.first, first.properties.isEmojiModifierBase,
            !first.properties.isEmojiPresentation,
            !scalars.contains(where: { $0.value == 0x200D || $0.value == 0x200C })
        {
            if scalars.contains(where: { $0.value == 0xFE0F }) { return 3 }
            if first.value > 0xFFFF { return 1 }
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
        // A skin-tone cluster on a text-presentation base — ☝🏻 ✌🏼 ✍🏽 ⛹🏾, and
        // the SMP flavour 🏋🏽 — merges to ONE cell here, not two: the base is
        // a 1-cell text glyph and Ghostty keeps it that way with the modifier
        // folded in, whatever the base's plane (BMP measured 2026-08-26
        // against every cluster the Example emoji page draws; SMP by the
        // 2026-08-28 DSR sweep, committed advance record). Claimed 2, so a
        // CUF is owed, exactly as for its SF Symbols — alignment bought with
        // a blank cell rather than a shear. A ZWJ sequence is excluded:
        // Ghostty composes those (every measured toned sequence advances 2),
        // and no text-presentation-base toned sequence has been measured, so
        // one falls through to the claim like any other assumed-correct
        // cluster.
        if unicodeScalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }),
            !unicodeScalars.contains(where: { $0.value == 0x200D }),
            let base = unicodeScalars.first, base.properties.isEmojiModifierBase,
            !base.properties.isEmojiPresentation
        {
            // …unless a redundant VS-16 rides along (☝️🏽 🏋️🏽): the selector
            // defeats the merge, and Ghostty detaches the promoted 2-cell
            // base plus a 2-cell swatch — advance 4 on both planes (ledger
            // row tone_point_up_vs16; the 2026-08-28 DSR sweep for the
            // siblings). Raw-cluster truth only: the walk strips the selector
            // (`withoutRedundantToneVS16`), so what Ghostty receives is the
            // merging pair above.
            if unicodeScalars.contains(where: { $0.value == 0xFE0F }) {
                return 4
            }
            return 1
        }
        let scalars = unicodeScalars
        if scalars.count == 1, let only = scalars.first,
            Self.isPlaneSixteenGlyph(only.value)
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
    ///   (3 for BMP bases) — the same shape as Terminal.app's Bug B. The
    ///   published traits (`skinTone: .detached`) claim those cells, so the
    ///   swatch passes through; the strip
    ///   (``String/withSkinToneFallback()``) fires only when no traits were
    ///   published and the old 2-cell claim is in force.
    /// - **Lone regional indicators** (🇦 alone) advance 1 against a claim of
    ///   2 — same as Terminal.app; ECH(2)+CUF(1) fixes it (the erase since
    ///   2026-08-28: the second cell kept the default background under the
    ///   glyph's right half with CUF alone).
    /// - **ZWJ sequences** advance the segment sum plus one column per kept
    ///   joiner (👩‍🚀 5, 👩🏽‍🚀 7 raw) — Warp draws the components with the
    ///   joiner's column blank between them. Since 2026-08-28 the walk drops
    ///   the joiners (`decomposedDroppingJoiners`), so what is emitted are
    ///   the segments themselves and this summed rule describes only a RAW
    ///   cluster.
    /// - **Keycaps** (1️⃣, advance 3) and **〰️/〽️** (advance 3) OVER-advance.
    ///   CUF cannot claw a cursor back and these paint wider than any claim,
    ///   so they are left alone and documented.
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
            Self.isPlaneSixteenGlyph(only.value)
        {
            return 1
        }
        if isLoneRegionalIndicator || isBarePictographUnderAdvancer {
            return 1
        }
        // Unicode 16.0's seven emoji singletons: Warp's width table is
        // Unicode 15.1, so it advances each of these 1 against the 2-cell
        // claim — user-reported on U+1FAE9 (every later character on the row
        // shifted one left), then the whole 1FA70–1FAFF block swept by DSR
        // (recent_emoji_sweep.py, 2026-08-28): exactly these seven advance 1;
        // all 106 other emoji-presentation scalars in the block advance 2,
        // and Apple Terminal, iTerm2 and Ghostty advance all 113 by 2. The
        // ECH+CUF under-advance repair covers them like any other.
        if isUnicode16EmojiOlderTablesMiss {
            return 1
        }
        // Fitzpatrick tones: Warp detaches every one, and the composition is
        // exactly "however far the bare base advances, plus 2 per swatch".
        // That one rule predicts every measured row (DSR sweeps 2026-08-28 +
        // the landing ledger): 👍🏽 = 2+2, ✊🏻 = 2+2, ☝🏽 = 1+2, 🏋🏽 = 1+2
        // (the bare SMP pictograph base itself advances 1 here), and with a
        // redundant FE0F kept the base is promoted to 2: ☝️🏽 = 🏋️🏽 = 4 —
        // raw-cluster truth only, since the walk strips the selector before
        // Warp sees it. Stating the composition instead of falling through to
        // `terminalWidth` is what keeps this raw truth out of the claim's
        // trait-coupling.
        if unicodeScalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }),
            let first = unicodeScalars.first, first.properties.isEmojiModifierBase,
            !unicodeScalars.contains(where: { $0.value == 0x200D || $0.value == 0x200C })
        {
            var base = String.UnicodeScalarView()
            var modifiers = 0
            for scalar in unicodeScalars {
                if (0x1F3FB...0x1F3FF).contains(scalar.value) {
                    modifiers += 1
                } else {
                    base.append(scalar)
                }
            }
            return Character(String(base)).warpCursorAdvance + 2 * modifiers
        }
        return terminalWidth
    }

    /// One of Unicode 16.0's new emoji (2024) — 🪉 harp, 🪏 shovel, 🪾 leafless
    /// tree, 🫆 fingerprint, 🫜 root vegetable, 🫟 splatter, 🫩 face with bags
    /// under eyes — which a width table cut before that release scores as
    /// narrow, advancing 1 against a 2-cell claim.
    ///
    /// Named for the class rather than the host: Warp is the only terminal
    /// measured to have it (v0.2026.07.08 and still v0.2026.08.26.17.59, the
    /// self-update measured 2026-08-28 — committed advance record, zero drift
    /// on any other battery row either), but any terminal carrying a
    /// pre-16.0 table would, which is why ``TerminalQuirks`` offers it as a
    /// switch. Apple Terminal, iTerm2 and Ghostty advance all seven by 2.
    public var isUnicode16EmojiOlderTablesMiss: Bool {
        // Range guard before the set: the seven all sit in 1FA89…1FAE9, so
        // every other single-scalar character skips the set hash.
        guard unicodeScalars.count == 1, let only = unicodeScalars.first,
            (0x1FA89...0x1FAE9).contains(only.value)
        else { return false }
        return Self.unicode16Emoji.contains(only.value)
    }

    private static let unicode16Emoji: Set<UInt32> = [
        0x1FA89, 0x1FA8F, 0x1FABE, 0x1FAC6, 0x1FADC, 0x1FADF, 0x1FAE9,
    ]

    /// An emoji ZWJ sequence whose FIRST segment carries a VS-16 — ❤️‍🔥 🏳️‍🌈
    /// ⛓️‍💥. On a host that under-advances standalone VS-16 clusters the
    /// leading segment carries that defect and the rest of the sequence folds
    /// into it, so the whole cluster advances 1 against a 2-cell claim.
    ///
    /// The first segment is what matters, not the base's plane: ❤️ is BMP and
    /// 🏳️ is SMP, and both behave the same because both carry the selector.
    public var leadsWithVS16Segment: Bool {
        guard let joiner = unicodeScalars.firstIndex(where: { $0.value == 0x200D }) else {
            return false
        }
        return unicodeScalars[..<joiner].contains { $0.value == 0xFE0F }
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
    /// flag pairs 2, NFD 1, powerline 1, blocks 1.
    ///
    /// Skin-tone clusters split **per base codepoint**
    /// (``tmuxMergedToneBases``): 70 of the 134 modifier bases merge to the
    /// 2-cell claim, the other 64 DETACH at 4 — the full sweep, 2026-08-28,
    /// which replaced two successive wrong generalizations (a by-plane rule,
    /// then a by-Unicode-era one). The detaching clusters never reach tmux:
    /// the output path strips the modifier via
    /// ``String/withSkinToneFallback(scope:)`` first (its one remaining live
    /// customer — iTerm2 and Warp moved to detached claims), after which the
    /// base advances 2 as claimed. The one uncorrectable divergence is a
    /// bare ☝ (U+261D with no selector): tmux advances 2 against a 1-cell
    /// claim, and CUF cannot claw a cursor back. It is left alone and
    /// documented, as ZWJ is on Terminal.app.
    public var tmuxCursorAdvance: Int {
        let scalars = unicodeScalars
        if scalars.count == 1, let only = scalars.first {
            // Plane-16 PUA — SF Symbols.
            if Self.isPlaneSixteenGlyph(only.value) { return 1 }
        }
        // Bare pictographs. This rule used to be broader — any lone
        // non-emoji-presentation SMP pictograph, dominoes and cards included —
        // because ``terminalWidth`` claimed 2 for those and something had to
        // make up the difference. The claim was the defect: they paint and
        // advance 1 on every host. With it corrected, the set that still needs
        // a CUF here is exactly the set the predicate names.
        if isBarePictographUnderAdvancer { return 1 }
        if isLoneRegionalIndicator { return 1 }
        // Fitzpatrick tones: 2 on a base tmux merges, 4 on one it detaches —
        // per codepoint, the full modifier-base sweep (2026-08-28). The
        // detaching ones are stripped before tmux ever sees them; this raw
        // truth is for the oracles and the record-conformance test.
        if scalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }),
            let first = scalars.first, first.properties.isEmojiModifierBase,
            !scalars.contains(where: { $0.value == 0x200D || $0.value == 0x200C })
        {
            return Self.tmuxMergedToneBases.contains(first.value) ? 2 : 4
        }
        return terminalWidth
    }

    /// The Emoji_Modifier_Base codepoints tmux 3.7b MERGES with a following
    /// Fitzpatrick modifier into the 2 cells TUIkit claims — 70 of the
    /// toolchain's 134 — measured 2026-08-28 by
    /// `advance_probe.py --modifier-bases` over the whole set, inside a
    /// headless tmux with no client attached (safe because tmux's grid is
    /// client-independent: five-way measured identical, 2026-07-15). The
    /// committed record is `Tools/TerminalProbes/data/tmux-3.7b-tonebases.json`,
    /// and `TmuxCompatibilityTests` pins this set against it row for row.
    ///
    /// The other 64 bases DETACH (advance 4 against the 2-cell claim), and
    /// the strip (``String/withSkinToneFallback(scope:)``,
    /// `.keepingTmuxMerged`) removes exactly those. The split is a
    /// per-codepoint fact with no clean rule — TWO tidy generalizations
    /// preceded this sweep and both were wrong: it is not by plane (🤙
    /// U+1F919, SMP, detaches; 🧑 U+1F9D1, SMP, merges — which sank
    /// `.detachedOnBMPBases` for tmux on 2026-08-26) and not by Unicode era
    /// (🎅 U+1F385 of Unicode 6.0 detaches while 🤦 U+1F926 of 9.0 and the
    /// whole 🧍…🧝 U+1F9CD–1F9DD run of 10.0+ merge, which sinks the
    /// "tmux's tables predate the newer bases" hypothesis recorded with that
    /// commit). The measured set is the rule.
    static let tmuxMergedToneBases: Set<UInt32> = [
        0x1F44B, 0x1F44C, 0x1F44D, 0x1F44E, 0x1F44F, 0x1F450,
        0x1F466, 0x1F467, 0x1F468, 0x1F469, 0x1F46E, 0x1F470,
        0x1F471, 0x1F472, 0x1F473, 0x1F474, 0x1F475, 0x1F476,
        0x1F477, 0x1F478, 0x1F47C, 0x1F481, 0x1F482, 0x1F483,
        0x1F485, 0x1F486, 0x1F487, 0x1F4AA, 0x1F575, 0x1F57A,
        0x1F590, 0x1F595, 0x1F596, 0x1F645, 0x1F646, 0x1F647,
        0x1F64B, 0x1F64C, 0x1F64D, 0x1F64E, 0x1F64F, 0x1F6B4,
        0x1F6B5, 0x1F6B6, 0x1F926, 0x1F937, 0x1F938, 0x1F939,
        0x1F93D, 0x1F93E, 0x1F9B5, 0x1F9B6, 0x1F9B8, 0x1F9B9,
        0x1F9CD, 0x1F9CE, 0x1F9CF, 0x1F9D1, 0x1F9D2, 0x1F9D3,
        0x1F9D4, 0x1F9D5, 0x1F9D6, 0x1F9D7, 0x1F9D8, 0x1F9D9,
        0x1F9DA, 0x1F9DB, 0x1F9DC, 0x1F9DD,
    ]

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
