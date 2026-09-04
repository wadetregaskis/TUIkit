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

// MARK: - Escape scanning

/// Where a streaming escape scan sits.
///
/// Shared by the three scanners that stream rather than index —
/// ``Swift/String/asciiStrippedLength()`` over bytes,
/// ``Swift/String/forEachVisibleANSIRun(_:)`` over scalars, and
/// ``Swift/String/sanitizedForTerminal`` — so the one thing they must agree
/// about, where a sequence ends, has one vocabulary. They do not all reach
/// every state: only the sanitizer enters ``escIntermediate``, because only it
/// has to account for escape families this framework never emits. What matters
/// is that where two of them DO handle a family, they handle it identically.
enum EscapeScanState {
    /// Inside (or about to start) a visible run.
    case normal
    /// Just saw `ESC`; the next byte selects the family.
    case sawESC
    /// Inside an nF escape's run of intermediate bytes (`ESC ( B`, `ESC % G`),
    /// which ends at the first final byte.
    case escIntermediate
    /// Inside `ESC [ … final`.
    case csi
    /// Inside a string-terminated family (OSC / DCS / APC / PM / SOS).
    case string
    /// Inside such a family, having just seen an `ESC` that may open `ST`.
    case stringSawESC
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
    /// Whether `scalar` adds no cells — the range check above, plus the
    /// general rule it only ever approximated.
    ///
    /// Unicode's answer to "does this mark occupy a column" is its general
    /// category: `Mn` (nonspacing) and `Me` (enclosing) do not, `Mc` (spacing
    /// combining) does. The ranges above name five blocks; there are dozens,
    /// and the ones they miss are not exotic — Hebrew points (U+0591…),
    /// Arabic vowels (U+0610…, U+06D6…), Cyrillic (U+0483…), Devanagari
    /// (U+0951…), Syriac, Thai, Tibetan, and the CJK tone and kana voicing
    /// marks that sit INSIDE the East-Asian-Wide ranges and were scored two
    /// cells each.
    ///
    /// A line carrying one measured wider than it painted, so every column
    /// after it landed short — the same defect the bidi controls had, found
    /// the same way. This is not a hypothetical script: it is any Hebrew or
    /// Arabic text with points, which is most religious, pedagogical and
    /// poetic text in both languages, and it is what
    /// `Tools/TerminalProbes/bidi_card.py` draws.
    ///
    /// The category lookup is not free, which is why the ranges above stay:
    /// they take ASCII, the selectors and the Latin marks — the overwhelming
    /// majority of what a terminal UI contains — without one.
    static func isWidthNeutralExtra(_ scalar: Unicode.Scalar) -> Bool {
        isWidthNeutralExtraScalar(scalar.value) || isNonAdvancingMark(scalar.value)
    }

    /// Whether `value` is a nonspacing (`Mn`) or enclosing (`Me`) mark, and so
    /// occupies no column.
    ///
    /// A binary search over `combiningMarkRanges` rather than
    /// `Unicode.Scalar.Properties.generalCategory`, which is what this
    /// originally asked. The property is a second standard-library lookup for
    /// every non-ASCII scalar that the earlier fast paths do not take — in a
    /// terminal UI that is every arrow, bullet, ellipsis, braille cell and
    /// spinner frame — and it cost a measured 2–3% on four Stress scenarios
    /// (`table` +2.0%, `dashboard` +2.8%, `kitchensink` +1.0%, `customlayout`
    /// +2.6%, all outside the interval). The table is generated FROM that
    /// property and a test re-derives it, so this is the same answer arrived
    /// at cheaply rather than a hand-written approximation of it.
    ///
    /// The floor and ceiling are the point: the common answer is "no", and it
    /// costs two comparisons.
    static func isNonAdvancingMark(_ value: UInt32) -> Bool {
        guard value >= combiningMarkFloor, value <= combiningMarkCeiling else { return false }
        var low = 0
        var high = combiningMarkRanges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = combiningMarkRanges[middle]
            if value < range.0 {
                high = middle - 1
            } else if value > range.1 {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }

    static func isWidthNeutralExtraScalar(_ sv: UInt32) -> Bool {
        switch sv {
        case 0x200B, 0x200C, 0x200D, 0xFEFF, 0x00AD:  // ZWSP/ZWNJ/ZWJ/BOM, soft hyphen
            return true
        // The bidi controls: marks (LRM/RLM/ALM) and the explicit directional
        // embeddings, overrides and isolates. Every one is
        // Default_Ignorable_Code_Point with no advance — they tell a renderer
        // how to ORDER what is around them and occupy nothing themselves.
        //
        // They were counted as one cell each, which is why nothing could use
        // them: a line carrying one measured a cell wider than it drew, so
        // every column after it was placed wrong. Text pasted from a
        // bidirectional document already carried them.
        case 0x200E, 0x200F, 0x061C:  // LRM, RLM, ALM
            return true
        case 0x202A...0x202E:  // LRE, RLE, PDF, LRO, RLO
            return true
        case 0x2066...0x2069:  // LRI, RLI, FSI, PDI
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
            // …but NOT the image placeholder, which is the one codepoint in
            // that plane that combines: it carries its row and column in
            // combining diacritics. Answering `true` for it would let the
            // cell-span differ (``String/ANSIRowCells``) accept an image row
            // and rewrite part of it, and a placeholder written out of
            // sequence is a cell that no longer knows which part of the
            // picture it is.
            return sv != Unicode.Scalar.terminalImagePlaceholder.value
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
            !Self.isWidthNeutralExtra(scalar)
        }
        if hasWidthAddingExtras {
            // True multi-character sequence (ZWJ, flags, keycaps, skin tones).
            // Two cells on a host that composes them, which is the default and
            // was once the only answer. A host that draws the components
            // separately gets the width it actually uses, so that the layout
            // can allocate it rather than the cluster being substituted down to
            // something that fits — see ``TerminalWidthTraits``.
            //
            // Two cells on a host that composes, which is the default. The
            // widening case is an out-of-line call so that THIS function's
            // inlinable body barely grows: `terminalWidth` is inlined into the
            // width scanners, and this repo has twice measured a phantom
            // regression from a hot function growing past an inlining
            // threshold on a path that never executes.
            return Self.hostWidenedWidth(scalars) ?? 2
        }
        // Base + variation selector(s).  If the selector is U+FE0F and
        // the base can be rendered as emoji, the cluster is 2 cells.
        // Otherwise the cluster is exactly as wide as its base.
        if scalars.contains(where: { $0.value == 0xFE0F }) && first.properties.isEmoji {
            return 2
        }
        return first.loneTerminalWidth
    }

    /// The cells this cluster occupies if the host widens it, or `nil` — which
    /// is the answer for every host that composes, and so the common one.
    ///
    /// Out of line deliberately: see the call site.
    @inline(never)
    static func hostWidenedWidth(_ scalars: String.UnicodeScalarView) -> Int? {
        // Only a joiner or a Fitzpatrick modifier can make a host widen a
        // cluster, and testing two scalar ranges is cheaper than reading the
        // traits, which is a task-local lookup rather than a plain load. Flags,
        // keycaps and RI pairs answer nil without paying for a question whose
        // answer cannot affect them.
        let mayWiden = scalars.contains { scalar in
            scalar.value == 0x200D || (0x1F3FB...0x1F3FF).contains(scalar.value)
        }
        guard mayWiden else { return nil }
        let traits = TerminalWidthTraits.current
        guard traits != .composing else { return nil }
        return decomposedWidth(scalars, traits: traits)
    }

    /// The cells a composed cluster occupies on a host that does NOT compose
    /// it, or `nil` if these traits leave this cluster alone.
    ///
    /// Only reached for multi-scalar clusters on a non-composing host, so the
    /// allocations here are off every hot path.
    static func decomposedWidth(
        _ scalars: String.UnicodeScalarView, traits: TerminalWidthTraits
    ) -> Int? {
        if scalars.contains(where: { $0.value == 0x200D }) {
            // Sum of the ZWJ-separated segments, plus one cell per joiner on a
            // host whose own renderer draws the joiner as a column (Warp —
            // measured to predict every case exactly: 👩‍🚀 = 2+1+2 = 5,
            // 👨‍👩‍👧‍👦 = 2+1+2+1+2+1+2 = 11, 👩🏽‍🚀 = 4+1+2 = 7) and
            // nothing for the joiners where the output walk removes them
            // before the host ever sees one (Apple Terminal: 👨‍👩‍👧‍👦 = 8,
            // ❤️‍🔥 = 4). The skin-toned segment resolves through this same
            // function, which is why the two rules compose instead of
            // duplicating each other.
            //
            // The gates mirror the walk's ``Character/emojiZWJSegments``
            // exactly — emoji-led, no empty segment — because the claim must
            // price what the walk will EMIT: a non-emoji ZWJ cluster ("x‍y")
            // or a malformed one (trailing/doubled joiner) goes out verbatim,
            // so it keeps its composed claim. Falling through to the
            // skin-tone arm instead would price a ZWJ cluster the walk never
            // separates, so a ZWJ cluster answers here or not at all. (And
            // `Character("")` on the empty segment is a fatalError — such
            // clusters are ordinary truncated/stray-joiner data.)
            guard traits.zwjSequences != .composed,
                let first = scalars.first, first.properties.isEmoji
            else { return nil }
            var total = 0
            var joiners = 0
            var segment = String.UnicodeScalarView()
            for scalar in scalars {
                if scalar.value == 0x200D {
                    guard !segment.isEmpty else { return nil }
                    joiners += 1
                    total += Character(String(segment)).terminalWidth
                    segment = String.UnicodeScalarView()
                } else {
                    segment.append(scalar)
                }
            }
            guard !segment.isEmpty else { return nil }
            total += Character(String(segment)).terminalWidth
            return total + (traits.zwjSequences == .decomposedKeepingJoiners ? joiners : 0)
        }
        return detachedSkinToneWidth(scalars, traits: traits)
    }

    /// The cursor advance a host makes over a decomposed ZWJ cluster: the sum of
    /// what it advances over each ZWJ-separated segment, plus one per joiner.
    ///
    /// The same shape as the CLAIM rule in ``decomposedWidth(_:traits:)``, but
    /// measured with the host's own per-segment advance instead of the claim —
    /// which is where the two can differ. On Apple Terminal a VS-16 segment
    /// under-advances (❤️ moves the cursor 1 while claiming 2), so ❤️‍🔥
    /// advances 4 where the claim is 5. Reporting that honestly is what lets
    /// the existing CUF close the gap, exactly as it does for a Ghostty SF
    /// Symbol that paints narrower than the layout allocated.
    ///
    /// Deliberately NOT gated on ``TerminalWidthTraits``: the raw cluster
    /// advances this way on the host regardless of what the walk chooses to
    /// emit for it, and an earlier traits-gated Apple sibling silently
    /// reverted the model when the claim-widening was turned off. The caller
    /// (a per-host advance model) is the gate.
    ///
    /// `nil` when this cluster is not a ZWJ sequence.
    static func summedZWJAdvance(
        _ character: Character, segmentAdvance: (Character) -> Int
    ) -> Int? {
        let scalars = character.unicodeScalars
        // The `isEmoji` lead guard matches ``Character/emojiZWJSegments`` and
        // the Apple sibling: a non-emoji ZWJ cluster ("x‍y", Arabic text using
        // ZWJ to force joining forms) is not something any host was measured
        // to decompose — and summing it would crash below on the empty
        // segment a stray joiner leaves.
        guard scalars.contains(where: { $0.value == 0x200D }),
            let first = scalars.first, first.properties.isEmoji
        else { return nil }
        var total = 0
        var joiners = 0
        var segment = String.UnicodeScalarView()
        for scalar in scalars {
            if scalar.value == 0x200D {
                // Empty segment (leading/trailing/doubled joiner):
                // `Character("")` traps, and the cluster is malformed data,
                // not a sequence — same answer as ``Character/emojiZWJSegments``.
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

    /// The cells a Fitzpatrick cluster occupies where the host draws the
    /// modifier as a swatch beside the base rather than merging it in.
    ///
    /// The base's own width **plus two** for the swatch, which is what every
    /// measurement shows: 👍🏽 and ✊🏻 at 4 (2-cell bases), ☝🏽 at 3 (a 1-cell
    /// text-presentation base). A redundant VS-16 on the base (☝️🏽) does not
    /// widen the detached claim: the walks strip it before emission
    /// (``Swift/Character/withoutRedundantToneVS16`` — the modifier alone
    /// forces emoji presentation, and the normalized pair is the measured-
    /// aligned one on iTerm2 and Warp at exactly this bare-base + 2), so the
    /// claim prices what actually goes out. Only the SEPARATED claim keeps
    /// the selector, because the Apple walk re-promotes the base itself.
    static func detachedSkinToneWidth(
        _ scalars: String.UnicodeScalarView, traits: TerminalWidthTraits
    ) -> Int? {
        guard traits.skinTone != .merged,
            let first = scalars.first,
            scalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) })
        else { return nil }
        // iTerm2 and tmux merge an SMP base and detach only a BMP one.
        if traits.skinTone == .detachedOnBMPBases, first.value > 0xFFFF { return nil }
        if traits.skinTone == .separated {
            // The walk only separates a plain Fitzpatrick cluster — the first
            // scalar must be a modifier base. A ZWJ sequence carrying a tone
            // (👩🏽‍🚀) stays at its composed claim when ZWJ decomposition is
            // off: the walk cannot separate it without splicing the ZWNJ into
            // the sequence, so it pulls back instead. (Under this host's real
            // traits decomposition is on, and the toned SEGMENT resolves
            // through this rule after the split.)
            guard first.properties.isEmojiModifierBase,
                !scalars.contains(where: { $0.value == 0x200D })
            else { return nil }
        }
        var base = String.UnicodeScalarView()
        for scalar in scalars
        where !(0x1F3FB...0x1F3FF).contains(scalar.value) && scalar.value != 0x200C {
            // The detached claims price the normalized emission — the walk
            // strips a redundant VS-16 before the host sees the cluster — so
            // the selector is excluded here too. The separated claim keeps
            // it: the Apple walk prices the PROMOTED base (see below).
            if scalar.value == 0xFE0F, traits.skinTone != .separated { continue }
            base.append(scalar)
        }
        // The walk promotes a text-presentation base (☝🏻 ✍🏿 ⛹🏾) with VS-16
        // before separating — the bare rewrite was measured to misalign — so
        // the claim must price the base the same way the walk emits it: the
        // promoted 2-cell form, not the bare 1-cell one. An already-promoted
        // cluster (☝️🏻) keeps its selector through the reconstruction above
        // and needs nothing added.
        if traits.skinTone == .separated, !first.properties.isEmojiPresentation,
            !base.contains(where: { $0.value == 0xFE0F }) {
            base.append(Unicode.Scalar(0xFE0F)!)
        }
        // Detached: base + 2-cell swatch. Separated: the walk's ZWNJ occupies
        // its own column between them (measured — Apple Terminal advances
        // 🤙+ZWNJ+🏽 by 5), so base + separator + swatch. Excluding U+200C from
        // the base reconstruction above makes the already-rewritten cluster
        // measure the same as the original it replaces.
        //
        // PER MODIFIER, not a constant: a degenerate cluster carrying two
        // Fitzpatrick scalars (👍🏽🏽 — invalid emoji, one valid grapheme,
        // possible in arbitrary user data) is separated by the Apple walk
        // into base + (ZWNJ + modifier) × 2, whose internal advance is the
        // base plus 3 per modifier — a constant swatch priced it 3 short and
        // the conservation gap came out as an uncarded CUB(3), a backward
        // move of a size never measured, into the cluster class where
        // backward moves re-render. No host's rendering of the doubled form
        // is measured; what the per-modifier claim buys is that the claim
        // equals the emission's own arithmetic by construction, so the walk
        // emits it with no cursor moves at all.
        let swatch = traits.skinTone == .separated ? 3 : 2
        let modifiers = scalars.count { (0x1F3FB...0x1F3FF).contains($0.value) }
        return Character(String(base)).terminalWidth + swatch * modifiers
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
        // Every other non-advancing mark, by its Unicode category rather than
        // by a block this file happened to list. Placed here, after the two
        // fast paths and the emoji property that every scalar reaching this
        // point has already paid for, and BEFORE the East Asian ranges — which
        // contain marks of their own (U+302A…U+302D CJK tone marks, U+3099 and
        // U+309A kana voicing) that those ranges were scoring two cells.
        //
        // `Mc` — a spacing combining mark, such as a Devanagari matra — is
        // deliberately not here: it does advance.
        if Character.isNonAdvancingMark(scalarValue) { return 0 }

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
        if Character.isPlaneSixteenGlyph(scalarValue) { return 2 }  // Plane-16 PUA — SF Symbols (SF Mono: 2 cells)
        // The one Plane-16 codepoint that is not a glyph: no font draws it and
        // a terminal implementing the graphics protocol paints a piece of a
        // picture there instead, one cell wide. See
        // ``Unicode/Scalar/terminalImagePlaceholder``.
        if scalarValue == Unicode.Scalar.terminalImagePlaceholder.value { return 1 }

        return 1
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

    /// The state after `value` when a scan has just seen an `ESC`, and whether
    /// `value` is visible text rather than part of a sequence.
    ///
    /// Shared by the two MEASURING scanners, and not by
    /// ``sanitizedForTerminal``, which parts company here on purpose: it reads
    /// `ESC c` and `ESC 7` as two-byte escapes and drops both bytes, while a
    /// measure treats a bare `ESC` as dropped and the byte after it as visible.
    /// A measure runs on output this framework generated, which contains no
    /// two-byte escape, so widening the rule would change only what a STRAY
    /// `ESC` measures — for no sequence that needs it.
    static func escapeIntroducerScan(on value: UInt32) -> (state: EscapeScanState, visible: Bool) {
        if value == 0x5B { return (.csi, false) }  // '[' → CSI introducer
        if isStringFamilyIntroducer(value) { return (.string, false) }
        if (0x20...0x2F).contains(value) { return (.escIntermediate, false) }  // `ESC ( B`
        if value == 0x1B { return (.sawESC, false) }  // ESC ESC → drop the first, restart
        return (.normal, true)
    }

    /// The state after `value`, for a scan already inside an escape sequence
    /// that is **not** a CSI — an nF escape's run of intermediates, or a
    /// string-terminated family's payload.
    ///
    /// One rule, called from all three streaming scanners. An `ESC ]` payload
    /// is arbitrary text: two scanners disagreeing by a byte about where it
    /// stops is a width that does not match the bytes that produced it, and a
    /// sanitizer that stops in a different place from the measurer is a leak.
    ///
    /// A string family ends at `BEL` (xterm's older spelling, still the one
    /// several hosts prefer), at an 8-bit `ST`, or at `ESC \`; any other `ESC`
    /// was inside the payload and the string continues. An nF escape's
    /// intermediates end at the first byte that is not one, and that byte is
    /// the sequence's final byte — part of it, not visible text.
    static func escapeBodyScan(_ state: EscapeScanState, on value: UInt32) -> EscapeScanState {
        switch state {
        case .escIntermediate:
            (0x20...0x2F).contains(value) ? .escIntermediate : .normal
        case .string:
            if value == 0x07 || value == 0x9C {  // BEL, or 8-bit ST
                .normal
            } else {
                value == 0x1B ? .stringSawESC : .string
            }
        default:
            value == 0x5C ? .normal : .string  // `ESC \` is ST
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
        var state = EscapeScanState.normal
        var width = 0
        for byte in utf8 {
            if byte >= 0x80 { return nil }
            switch state {
            case .normal:
                if byte == 0x1B { state = .sawESC } else { width += 1 }

            case .sawESC:
                let seen = Self.escapeIntroducerScan(on: UInt32(byte))
                state = seen.state
                if seen.visible { width += 1 }

            case .csi:
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

            case .escIntermediate, .string, .stringSawESC:
                // The payload is arbitrary text and none of it is visible. A
                // hyperlink's URI is percent-encoded, hence ASCII, hence it
                // reaches this path rather than falling to the general one —
                // which is why the fast path has to know the family too, not
                // merely tolerate it.
                state = Self.escapeBodyScan(state, on: UInt32(byte))
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

        var state = EscapeScanState.normal

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
                let seen = Self.escapeIntroducerScan(on: value)
                state = seen.state
                if seen.visible {  // the ESC is dropped; this scalar starts a run
                    runStart = index
                    hasRun = true
                }

            case .escIntermediate, .string, .stringSawESC:
                state = Self.escapeBodyScan(state, on: value)

            case .csi:
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

    /// Whether `value` introduces a **string-terminated** escape family — OSC
    /// (`ESC ]`), DCS (`ESC P`), APC (`ESC _`), PM (`ESC ^`), SOS (`ESC X`).
    ///
    /// These do not end at a final byte the way a CSI does. They carry an
    /// arbitrary payload and run to a `BEL` or an `ST` (`ESC \`), which is why
    /// a scanner that knows only CSI does not merely fail to skip one: it takes
    /// the payload for TEXT. `ESC]8;;https://example.com` measures 22 cells and
    /// paints none, so a line carrying a hyperlink is budgeted 22 columns it
    /// does not occupy, and everything sharing its row is laid out around the
    /// gap.
    ///
    /// TUIkit emits exactly one member of the family — OSC 8, the hyperlink
    /// (``TerminalHyperlink``) — and every scanner recognises all five, because
    /// the skipping rule is the same for all five and a rule written for one
    /// sequence is the kind that gets found again by the next.
    public static func isStringFamilyIntroducer(_ value: UInt32) -> Bool {
        switch value {
        case 0x5D, 0x50, 0x5F, 0x5E, 0x58: true  // ] P _ ^ X
        default: false
        }
    }

    /// The index just past the complete escape sequence beginning at `index`
    /// — which must address an `ESC` in `scalars` — and whether it was SGR.
    ///
    /// The one scalar-level escape walker. Four copies of this loop had grown
    /// (here, both splitters in `String+ANSISplitting.swift`, and the row
    /// decomposer), which is how a class of sequence comes to be understood in
    /// some of them and not others — the same way the CSI parameter rule was
    /// wrong in five of six walkers before ``escapeSequenceEnd(from:)`` collected
    /// them. Its counterpart on `String.Index` is that function; this one works
    /// in scalars because its callers do.
    ///
    /// Three shapes, and the third is the one worth stating:
    ///
    /// - `ESC [ … final` — a CSI, ending at its final byte. `isSGR` is true
    ///   when that byte is `m`.
    /// - `ESC ] … ST` — a string-terminated family (see
    ///   ``isStringFamilyIntroducer(_:)``), ending at a `BEL` or an `ST`, both
    ///   consumed. **Unterminated, it runs to the end of the string**: the
    ///   payload is inside the sequence as far as the terminal is concerned, so
    ///   treating the tail as visible would be a width for cells nothing paints.
    /// - `ESC` followed by anything else — the ESC ALONE is the sequence, and
    ///   the byte after it stays visible. That is what every caller did before
    ///   this walker existed and it is left alone deliberately: `ESC 7` and its
    ///   two-byte siblings are not emitted here, and widening the rule to
    ///   swallow the following byte would change what existing callers measure
    ///   for a stray ESC without any sequence needing it.
    ///
    /// Exactly one scalar is consumed for a CSI's final byte, so a following
    /// `Extend` scalar — a lone skin-tone modifier, VS-16, a combining mark —
    /// stays visible instead of fusing onto the terminator; see
    /// ``ansiSegments()``.
    static func escapeSequenceEnd(
        startingAt index: UnicodeScalarView.Index, in scalars: UnicodeScalarView
    ) -> (end: UnicodeScalarView.Index, isSGR: Bool) {
        var cursor = scalars.index(after: index)
        guard cursor < scalars.endIndex else { return (cursor, false) }
        let introducer = scalars[cursor].value

        if introducer == 0x5B {  // '[' — CSI
            cursor = scalars.index(after: cursor)
            while cursor < scalars.endIndex, isCSIBodyByte(scalars[cursor].value) {
                cursor = scalars.index(after: cursor)
            }
            guard cursor < scalars.endIndex, isCSIFinalByte(scalars[cursor].value) else {
                return (cursor, false)
            }
            let isSGR = scalars[cursor].value == 0x6D  // 'm'
            return (scalars.index(after: cursor), isSGR)
        }

        // `ESC ( B` and its family: intermediates, then one final — the same
        // shape `escapeIntroducerScan`/`escapeBodyScan` consume as zero
        // cells. This walker never had the arm, so the measurers said 0 and
        // the segment walkers said 2 for the same bytes.
        if (0x20...0x2F).contains(introducer) {
            cursor = scalars.index(after: cursor)
            while cursor < scalars.endIndex, (0x20...0x2F).contains(scalars[cursor].value) {
                cursor = scalars.index(after: cursor)
            }
            if cursor < scalars.endIndex { cursor = scalars.index(after: cursor) }
            return (cursor, false)
        }

        guard isStringFamilyIntroducer(introducer) else { return (cursor, false) }
        cursor = scalars.index(after: cursor)
        while cursor < scalars.endIndex {
            let value = scalars[cursor].value
            cursor = scalars.index(after: cursor)
            if value == 0x07 || value == 0x9C { return (cursor, false) }  // BEL, or 8-bit ST
            if value == 0x1B, cursor < scalars.endIndex, scalars[cursor].value == 0x5C {
                return (scalars.index(after: cursor), false)  // ESC \ — ST
            }
        }
        return (cursor, false)  // unterminated: the payload runs to the end
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
    /// A string-terminated introducer (`ESC ]` and its siblings — see
    /// ``isStringFamilyIntroducer(_:)``) is followed to its `BEL` or `ST`, and
    /// to the end of the string if it has neither. That matters most to the
    /// cursor-compensation walks, which are this function's callers: they copy
    /// escapes through and PRICE everything else as a grapheme cluster, so an
    /// OSC 8 URI walked as text would be measured, erased and `CUF`-repaired
    /// character by character.
    ///
    /// A lone ESC, or an ESC followed by something that is neither, yields the
    /// index just past the ESC — the callers all treat the remainder as
    /// ordinary content, which is the safe reading for a byte we cannot
    /// account for.
    func escapeSequenceEnd(from index: Index) -> Index {
        var cursor = self.index(after: index)
        guard cursor < endIndex else { return cursor }
        func classify(_ test: (UInt32) -> Bool) -> Bool {
            guard cursor < endIndex else { return false }
            let scalars = self[cursor].unicodeScalars
            guard scalars.count == 1, let value = scalars.first?.value else { return false }
            return test(value)
        }
        if classify(Self.isStringFamilyIntroducer) {
            cursor = self.index(after: cursor)
            while cursor < endIndex {
                let character = self[cursor]
                cursor = self.index(after: cursor)
                if character == "\u{07}" || character == "\u{9C}" { return cursor }  // BEL, or 8-bit ST
                if character == "\u{1B}", cursor < endIndex, self[cursor] == "\\" {
                    return self.index(after: cursor)  // ESC \ — ST
                }
            }
            return cursor  // unterminated: the payload runs to the end
        }
        // The nF family (`ESC ( B`): intermediates, then one final. See the
        // scalar walker above; the rule is the measurers'.
        if classify({ (0x20...0x2F).contains($0) }) {
            while classify({ (0x20...0x2F).contains($0) }) { cursor = self.index(after: cursor) }
            if cursor < endIndex { cursor = self.index(after: cursor) }
            return cursor
        }
        guard self[cursor] == "[" else { return cursor }
        cursor = self.index(after: cursor)
        while classify(Self.isCSIBodyByte) { cursor = self.index(after: cursor) }
        if classify(Self.isCSIFinalByte) { cursor = self.index(after: cursor) }
        return cursor
    }

    /// Splits the string into ordered segments — each either a complete
    /// ANSI escape sequence or a single visible grapheme cluster.
    ///
    /// "Complete" includes a string-terminated sequence such as an OSC 8
    /// hyperlink, which ends at its `ST` rather than at a final byte: see
    /// ``escapeSequenceEnd(startingAt:in:)``. Every splitter in
    /// `String+ANSISplitting.swift` is built on these segments and copies an
    /// `.ansi` one through untouched, so recognising the family here is what
    /// carries a hyperlink across a cut rather than shredding it.
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
            let (end, isSGR) = Self.escapeSequenceEnd(startingAt: index, in: scalars)
            segments.append(.ansi(String(scalars[index..<end]), isSGR: isSGR))
            index = end
        }
        flushVisible()
        return segments
    }
    /// The string with all ANSI escape codes removed — CSI and the
    /// string-terminated families alike.
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
