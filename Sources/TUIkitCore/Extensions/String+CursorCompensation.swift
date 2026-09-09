//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// `true` if this line contains any byte a per-host advance model could
    /// act on — the narrower second gate behind ``utf8ContainsNonASCII``.
    ///
    /// The first gate asks "is this pure ASCII", which the framework's OWN
    /// chrome defeats: a box-drawing border (U+2500 block) is non-ASCII, so
    /// every bordered row — most rows of most TUIkit apps — took the full
    /// per-`Character` walk, reading Unicode properties for a row that could
    /// not possibly need compensating.
    ///
    /// Every scalar any model reads is either **above the BMP** (skin tones,
    /// regional indicators, bare pictographs, Plane-16 PUA, tag scalars, the
    /// Unicode 16.0 additions — all 4-byte UTF-8, lead `0xF0`–`0xF4`) or one
    /// of exactly four BMP scalars: U+FE0E and U+FE0F (the variation
    /// selectors, lead `0xEF`) and U+200C and U+200D (the joiners, `E2 80`)
    /// plus U+20E3 (the keycap, `E2 83`). So the test is: any byte ≥ `0xEF`,
    /// or an `E2` followed by `80` or `83`.
    ///
    /// Box drawing and block elements are `E2 94`–`E2 96`, and CJK is `E3`–
    /// `E9`; none of them match, which is the point.
    ///
    /// The one exception is the chrome-overhang tables
    /// (`ChromeOverhang.swift`), whose glyphs ARE ordinary BMP chrome:
    /// widening their claim gives them a shortfall to compensate, so the gate
    /// has to admit them or the walk never sees them and the widened claim
    /// shears the row. Their second bytes come from
    /// ``chromeOverhangGateMask``, derived from the tables themselves so the
    /// two cannot drift, and it is the UNION of every host's set even though
    /// the claim is per host: this gate decides only whether the walk runs, and
    /// the walk asks the claim in force per character. Admitting a row whose
    /// glyph does not overhang on THIS host costs a walk that changes nothing;
    /// skipping one that does shears the row.
    ///
    /// This is an over-approximation on purpose — `0xEF` admits all of
    /// U+F000–U+FFFF and the joiner pair admits U+2000–U+20FF — because a
    /// gate that is too eager only costs a walk that finds nothing, while one
    /// that is too clever silently skips a cluster that needed repair. That
    /// direction is pinned by `CompensationGateTests`, which sweeps the
    /// corpus and a generated range and fails if any string the walks
    /// actually change is one this gate would have skipped.
    ///
    /// Byte-at-a-time rather than 8-at-a-time (the SWAR "any byte ≥ N" trick
    /// needs N ≤ 128) — but it only runs on lines the first gate already
    /// found non-ASCII, and its per-byte work is a comparison where the walk's
    /// is grapheme breaking plus Unicode property lookups.
    var utf8MayNeedCompensation: Bool {
        // Hoisted out of the byte loop on purpose: reading a global costs a
        // one-time-initialization check, and this loop runs per byte of every
        // rebuilt row. Once, per row, it is free.
        let overhangMask = chromeOverhangGateMask
        return utf8.withContiguousStorageIfAvailable { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            let count = buffer.count
            var i = 0
            while i < count {
                let byte = base[i]
                if byte >= 0xEF { return true }
                if byte == 0xE2, i + 1 < count {
                    let next = base[i + 1]
                    if next == 0x80 || next == 0x83 { return true }
                    if overhangMask & (1 &<< UInt64(next & 0x3F)) != 0 { return true }
                }
                i += 1
            }
            return false
        } ?? true
    }

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
            // C0 (bar the ESC that introduces a sequence), DEL, and the C1
            // controls: a pasted U+009B is an 8-bit CSI and a U+0085 a NEL on
            // any host that decodes them, and neither is content in a cell.
            (value < 0x20 && value != 0x1B) || value == 0x7F || (0x80...0x9F).contains(value)
        }
        // Fast reject for the clean line that virtually every line is, and which
        // runs once per *changed* terminal row per frame: every byte we'd
        // replace is single-byte UTF-8 (< 0x80), so a raw contiguous-byte scan is
        // correct and far cheaper than walking the `UnicodeScalarView` (whose
        // per-element index validation showed up in render profiling).
        // A C1 scalar encodes as `C2 8x`/`C2 9x`, so its lead byte is what the
        // byte scan can see; `C2` also leads U+00A0…U+00BF (a no-break space,
        // `©`, `°`), which merely sends such a line down the scalar walk.
        let hasStray =
            utf8.withContiguousStorageIfAvailable { buffer -> Bool in
                for byte in buffer where (byte < 0x20 && byte != 0x1B) || byte == 0x7F || byte == 0xC2 {
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

    /// Where the cursor lands after a terminal whose model is `advance`
    /// processes this string — the *emitted-output* counterpart of
    /// ``strippedLength``, which counts the cells the visible characters claim
    /// and knows nothing about escapes.
    ///
    /// This is the number the compensation walks exist to control, so it is the
    /// number a test has to be able to ask for. A walk that emits a cluster
    /// unchanged, a walk that pushes the cursor forward past a narrow glyph and
    /// a walk that rewrites the cluster into something else entirely all end
    /// somewhere, and only this says where: `CUF` counts forward, `CUB` counts
    /// back, and every other escape — `SGR`, `ECH`, anything at all that paints
    /// or colours without moving — contributes nothing, because it moves
    /// nothing.
    ///
    /// The contract every host's output path owes the layout is that this,
    /// measured on the compensated row, equals the ``strippedLength`` of the
    /// row that went in. `CursorAdvanceConservationTests` is that sentence as
    /// an assertion.
    ///
    /// - Parameter advance: the host's cursor advance for one character —
    ///   ``Character/terminalAppCursorAdvance`` and its siblings, or
    ///   ``TerminalQuirks/cursorAdvance(of:)`` for a terminal being explored.
    public func cursorAdvance(perCharacter advance: (Character) -> Int) -> Int {
        var total = 0
        var index = startIndex

        while index < endIndex {
            guard self[index] == "\u{1B}" else {
                total += advance(self[index])
                index = self.index(after: index)
                continue
            }
            let start = index
            index = escapeSequenceEnd(from: index)
            let sequence = self[start..<index]
            // CSI Ps C / CSI Ps D — the only two escapes any walk here emits
            // that move the cursor. The parameter defaults to 1 when omitted,
            // per ECMA-48.
            guard let final = sequence.last, final == "C" || final == "D",
                sequence.hasPrefix("\u{1B}[")
            else { continue }
            let digits = sequence.dropFirst(2).dropLast()
            guard digits.allSatisfy(\.isNumber) else { continue }
            let count = digits.isEmpty ? 1 : (Int(digits) ?? 0)
            total += (final == "C") ? count : -count
        }

        return total
    }

    /// Returns `true` if any character in this string has a Terminal.app
    /// cursor advance that differs from its visible cell width. These rows
    /// trip Terminal.app's right-edge phantom-cell bug;
    /// `FrameDiffWriter.repaintRightEdge` uses this check to scope its
    /// two-pass repaint to only the rows that need it.
    ///
    /// It runs on the COMPENSATED line, so what it flags are the emitted
    /// clusters whose advance still disagrees with their claim around the
    /// injected escapes: the `ECH`/`CUF` under-advancers (a VS-16 ❤️, a bare
    /// 🖥, an SF Symbol, a VS-16-promoted separated tone) and the
    /// `CUB`-repaired over-advancers (tag flags, bare keycaps). A plain
    /// separated tone pair drops OUT of the repaint's scope here — its
    /// rewritten cluster advances exactly its claim, and its card measured
    /// the right edge clean. (An earlier note described a strip-era pipeline
    /// in which a modifier could only "survive" as the line's last visible
    /// character; since 2026-08-27 every modifier survives, via separation.)
    public var containsTerminalAppCursorAdvanceQuirk: Bool {
        // Every quirk cluster is non-ASCII, so a pure-ASCII row cannot
        // contain one — the same byte gate as the walks, which this check
        // lacked: it ran the full per-Character advance-model walk over
        // every changed row on Apple Terminal, including the plain-ASCII
        // majority.
        guard utf8ContainsNonASCII, utf8MayNeedCompensation else { return false }
        var index = startIndex
        while index < endIndex {
            if self[index] == "\u{1B}" {
                // Skip ANSI escape sequences — `escapeSequenceEnd(from:)`, shared by every escape walk. The
                // copies that used to sit in this file accepted only digits
                // and `;` between the `[` and the terminator, which stops at
                // the `?` of `ESC[?25l` and counts the rest as visible text.
                index = escapeSequenceEnd(from: index)
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
    /// quirks worked around — every scalar the caller wrote reaches the
    /// screen, some rearranged so the row stays true.
    ///
    /// Apple Terminal keeps THREE facts per row and compensation must square
    /// all of them with the claim:
    ///
    /// - the **internal** column (``Character/terminalAppCursorAdvance``,
    ///   what DSR reports) decides when the row WRAPS. A cluster that leaves it
    ///   past the claim makes a full-width row wrap before its tail is written,
    ///   and the abandoned cells keep the terminal's default background — blank
    ///   white cells at the end of the row.
    /// - the **paint** position decides where the glyph and its immediate
    ///   follower land.
    /// - the row's **stored width** for the cluster decides where EVERYTHING
    ///   later on the row paints, absolutely-addressed writes included: a
    ///   cluster stored wider than it paints displaces the whole tail left by
    ///   the difference, and no cursor move repairs that, because cursor moves
    ///   do not edit the store.
    ///
    /// The measured treatments (treatment cards 1–4 + DSR probes, Terminal.app
    /// 455.1, alternate screen, 2026-08-27 — each verified for follower
    /// alignment, absolute-move alignment, background integrity, and a
    /// full-width row ending in the cluster with no wrap):
    ///
    /// - **Under-advancers** (VS-16 pictographs 🖥️ ❤️, bare SMP pictographs,
    ///   lone regional indicators, SF Symbols): internal and paint both stop 1
    ///   short. `ECH(2)` to paint the claimed cells in the current background,
    ///   the glyph, then `CUF(1)`. Unchanged for years and measured clean.
    /// - **Skin tones on an emoji-presentation base** (🤙🏽 ✊🏿 👍🏽), when
    ///   ``TerminalWidthTraits`` claims the separated width:
    ///   rewritten as base + ZWNJ + modifier
    ///   (`Character.separatedSkinToneEmission`) and emitted with no
    ///   moves at all — the host renders base, one blank column (the ZWNJ's
    ///   own), then the swatch, and internal, paint and store all land on the
    ///   claim of base + 3. The tone survives on screen, which the composed
    ///   cluster plus any cursor repair measured could not do: every backward
    ///   move re-renders the cluster as its bare base.
    /// - **Skin tones on a text-presentation base** (☝🏻 ✍🏿 ⛹🏾): the bare
    ///   rewrite measured MISALIGNED for these, so the base is **promoted
    ///   with VS-16 first** and then separated the same way (2026-08-28,
    ///   superseding a `CUB(internal − claim)` pull-back that re-rendered
    ///   the bare narrow monochrome glyph beside a blank cell, tone lost —
    ///   user-reported). The promoted base is a VS-16 under-advancer on this
    ///   host, so the rewritten cluster takes the ordinary erase-and-push:
    ///   `ECH(5)` ☝️‌🏻 `CUF(1)`, claim 2 + 1 + 2 — card-measured aligned with
    ///   the tone kept, the pair adjacent, and the spare column trailing the
    ///   swatch.
    /// - **Emoji ZWJ sequences** (👨‍👩‍👧‍👦 ❤️‍🔥 👩🏽‍🚀), when the traits
    ///   claim the decomposed width: decomposed into their segments
    ///   (`Character.emojiZWJSegments`), each segment then compensated
    ///   by its own class — so ❤️‍🔥 becomes an `ECH`'d ❤️ plus a bare 🔥, and
    ///   👩🏽‍🚀 a separated 👩+ZWNJ+🏽 plus a bare 🚀. Every cursor-move
    ///   repair that kept the composed glyph left later absolute positioning
    ///   on the row displaced by 1–2 cells (stored-width mismatch), and the
    ///   full-width DCH variants wrapped; decomposition is the treatment with
    ///   nothing wrong with it, at the cost the user accepted: component
    ///   glyphs instead of the composed one.
    /// - **Flag pairs and keycaps**
    ///   (`Character.terminalAppStoresWiderThanPainted`): internal
    ///   already equals the claim, the glyph paints into it — and the store
    ///   keeps one extra column that shifts every follower a cell left. Store
    ///   surgery: the cluster, `CUB(1)` into it, `DCH(1)` to delete the
    ///   surplus stored column, `CUF(1)` to restore the cursor. The one
    ///   emission of ten card variants whose sequential AND absolutely-placed
    ///   followers both land true.
    /// - **Tag-sequence flags** (🏴󠁧󠁢󠁳󠁣󠁴󠁿): `CUB(tag count)` — measured aligned,
    ///   store included.
    ///
    /// ANSI escape sequences in the input are preserved.
    public func withTerminalAppCursorCompensation() -> String {
        // Fast path: every cursor-advance quirk is an emoji cluster, which is
        // always non-ASCII, so a line whose bytes are all < 0x80 cannot need
        // compensation — return it untouched and skip the char-by-char rebuild.
        // `FrameDiffWriter.buildOutputLines` runs this on EVERY output line
        // every frame (on Apple_Terminal — it is gated off elsewhere), and most
        // lines of a non-emoji UI are pure ASCII (text + ANSI escapes, which are
        // also ASCII). The gate reads no Unicode properties and scans the bytes
        // 8 at a time (see `utf8ContainsNonASCII`), and a second, narrower
        // gate then rejects the rows that are non-ASCII only because of the
        // framework's own box-drawing chrome (see `utf8MayNeedCompensation`).
        guard utf8ContainsNonASCII, utf8MayNeedCompensation else { return self }

        let traits = TerminalWidthTraits.current
        var result = ""
        result.reserveCapacity(self.count + 8)

        // One cluster's emission — shared between the direct path and the
        // per-segment recursion of a decomposed ZWJ sequence (whose segments
        // never contain a further joiner, so this never recurses deeper).
        func appendCompensated(_ character: Character) {
            // No `withoutRedundantToneVS16` here, unlike the shared walk: on
            // this host both spellings of a VS-16-carrying tone cluster
            // measure identically (☝️🏽 and ☝🏽 advance 3, land 1 — ledger),
            // so under the separated traits the rewrite below already treats
            // the spelled form (its base reconstruction keeps the selector
            // separation would otherwise re-add), and under the pull-back
            // fallback a strip would discard the author's scalar for no
            // rendering gain at all.
            var c = character
            if traits.skinTone == .separated,
                let separated = c.separatedSkinToneEmission
            {
                // The rewrite is a single grapheme by construction (base
                // scalars plus an Extend-only tail), and it falls THROUGH to
                // the arms below rather than being appended verbatim: an
                // emoji-presentation base lands exactly on its claim and goes
                // out plain, while a VS-16-promoted text-presentation base
                // under-advances by one and takes the same ECH + CUF as the
                // standalone VS-16 class — ECH(5) ☝️‌🏻 CUF(1), card-measured.
                c = Character(separated)
            }
            let claimed = c.terminalWidth
            let internalAdvance = c.terminalAppCursorAdvance
            if c.terminalAppStoresWiderThanPainted, internalAdvance == claimed {
                // Store surgery presumes the cursor maths already balance —
                // measured true for this host's flags and keycaps. (The guard
                // matters for the quirks mirror, where an explorer can combine
                // this with an under-advance switch; keeping it here keeps the
                // two walks textually identical.)
                result.append(c)
                result += "\u{1B}[1D\u{1B}[1P\u{1B}[1C"
                return
            }
            if claimed > internalAdvance {
                // Under-advancer. The cursor has to reach the glyph's visual
                // end, and the cells the glyph covers have to carry whatever
                // background is in force — which CUF alone cannot do, because
                // it MOVES the cursor without painting anything.
                //
                // So the cells are ERASED first — ECH (CSI n X) paints n cells
                // from the cursor in the current background and does not move
                // it — and then the glyph is drawn over them. The one the
                // cursor never returns to keeps the paint.
                //
                // ECH rather than spaces-and-backtrack, which also works: ECH
                // writes no visible CHARACTERS, so `strippedLength` still
                // counts the cells the row occupies. Spaces would inflate every
                // width measurement taken after compensation by the width of
                // each emoji on the line.
                //
                // Measured on Terminal.app 455.1, alternate screen, ⚙️ 🖥️ and
                // an SF Symbol, eight in a row on a coloured run: with CUF
                // alone every second cell keeps the terminal's default and the
                // row reads as a comb; with the erase first, the run is
                // unbroken and the glyph is not clipped.
                // (`Tools/TerminalProbes/background_probe.py`.)
                result += "\u{1B}[\(claimed)X"
                result.append(c)
                result += "\u{1B}[\(claimed - internalAdvance)C"
            } else if internalAdvance > claimed {
                // Over-advancer (text-presentation skin tones under the
                // pull-back fallback, tag flags, bare keycaps): pull the
                // internal column back to the claim; the paint position —
                // measured for the first two classes, not yet for bare
                // keycaps — snaps with it.
                result.append(c)
                result += "\u{1B}[\(internalAdvance - claimed)D"
            } else {
                result.append(c)
            }
        }

        var index = startIndex
        while index < endIndex {
            let c = self[index]

            if c == "\u{1B}" {
                // Preserve an entire ANSI escape sequence: ESC [ params letter
                let seqStart = index
                index = escapeSequenceEnd(from: index)
                result += self[seqStart..<index]
                continue
            }

            if traits.zwjSequences == .decomposedDroppingJoiners,
                let segments = c.emojiZWJSegments
            {
                for segment in segments {
                    appendCompensated(segment)
                }
            } else {
                appendCompensated(c)
            }
            index = self.index(after: index)
        }

        return result
    }

    /// Which skin-tone clusters ``withSkinToneFallback(scope:)`` strips.
    ///
    /// The distinction exists because tmux differs per BASE CODEPOINT in
    /// which skin-tone clusters it joins, and stripping one it handles
    /// correctly is a real loss: the user asked for 👍🏽 and gets 👍.
    ///
    /// - ``all``: every skin-tone cluster — the safe answer, and the right
    ///   one whenever any attached client mis-renders a kept tone.
    /// - ``keepingTmuxMerged``: strip only the clusters tmux DETACHES,
    ///   keeping the 70 bases it was measured to merge into the 2-cell claim
    ///   (`Character.tmuxMergedToneBases`). This replaced a by-plane
    ///   rule (`bmpOnly`) on 2026-08-28, when the full modifier-base sweep
    ///   showed the split is per-codepoint: 🤙 (SMP) detaches while 🧑 (also
    ///   SMP) merges, so a plane test kept clusters tmux shears and the
    ///   Fitzpatrick row rendered short exactly as before the strip existed.
    public enum SkinToneFallbackScope: Sendable {
        /// Strip every skin-tone cluster, whatever its base.
        case all
        /// Strip only clusters whose base tmux was measured to detach.
        case keepingTmuxMerged
    }

    /// Returns a copy of this string with Fitzpatrick skin-tone modifiers
    /// stripped from their clusters — falling back to the generic-yellow base
    /// emoji.
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
    ///
    /// Since the detached-claim widening (`TerminalWidthTraits`) this fires on
    /// no native host: iTerm2 and Warp claim the cells their detached
    /// renderings occupy, so their modifiers pass through, and the strip is
    /// their no-traits-published fallback only. Its remaining live customer
    /// is tmux, whose compositor grid the claims cannot follow per-client.
    ///
    /// - Parameter scope: which bases to strip. `.all` (the default) is the
    ///   safe fallback. `.keepingTmuxMerged` keeps the bases tmux was
    ///   measured to merge into the claim — used when every attached client
    ///   also renders tmux's re-emission of them correctly.
    public func withSkinToneFallback(scope: SkinToneFallbackScope = .all) -> String {
        // Fast path: a skin-tone cluster is always non-ASCII, so a line whose
        // bytes are all < 0x80 cannot need the fallback (same gate as
        // `withTerminalAppCursorCompensation` — this too runs on every
        // (re)built output line on the terminals it applies to), and a
        // bordered row is rejected by the narrower second gate.
        guard utf8ContainsNonASCII, utf8MayNeedCompensation else { return self }

        var result = ""
        result.reserveCapacity(self.count)
        var index = startIndex

        while index < endIndex {
            let c = self[index]

            if c == "\u{1B}" {
                // Preserve an entire ANSI escape sequence: ESC [ params letter
                let seqStart = index
                index = escapeSequenceEnd(from: index)
                result += self[seqStart..<index]
                continue
            }

            let scalars = c.unicodeScalars
            // Cheapest test first: the Fitzpatrick range scan is plain
            // integer compares, where `isEmojiModifierBase` is an ICU
            // property lookup — and most multi-scalar clusters on a line
            // (CJK+VS, NFD text) have no modifier at all.
            let isModifiedCluster =
                scalars.count > 1
                && scalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
                && scalars.first!.properties.isEmojiModifierBase
                && (scope == .all
                    || !Character.tmuxMergedToneBases.contains(scalars.first!.value))
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
    /// worked around: each cluster whose painted width exceeds its
    /// ``Character/iTerm2CursorAdvance`` (VS-16 pictographs, keycap
    /// sequences and Plane-16 PUA glyphs — SF Symbols) is erased into the
    /// background with `ECH`, drawn, then pushed to its visual end with
    /// `CUF`, exactly as ``withTerminalAppCursorCompensation()`` does for
    /// Terminal.app's (larger) set of under-advancers.
    ///
    /// The erase is measured, not precautionary (2026-08-28): with `CUF`
    /// alone, iTerm2 paints the background of only the single cell the
    /// glyph's cursor advance covers, so on a coloured run every SF
    /// Symbol, keycap and VS-16 cluster left its second cell at the
    /// terminal's default background — user-reported under SF Symbols,
    /// card-confirmed for all three classes, and `ECH` (like a styled
    /// space) fills the hole. ANSI escape sequences are preserved.
    public func withITerm2CursorCompensation() -> String {
        withCursorForwardCompensation(erasingUnderGlyph: true) { $0.iTerm2CursorAdvance }
    }

    /// Returns a copy of this string with Ghostty's two cursor-advance quirks
    /// worked around, by the same `ECH` + `CUF` treatment
    /// ``withITerm2CursorCompensation()`` uses: the VS-15 chrome glyphs
    /// (⬛︎ ⬜︎ — painted 2 cells, advanced 1, so an uncompensated label
    /// collides with the glyph) and Plane-16 PUA SF Symbols (rendered
    /// grid-strictly at 1 cell against a 2-cell claim). The erase is for
    /// the SF Symbols (measured 2026-08-28): the claimed second cell is one
    /// the glyph never paints, so with `CUF` alone it kept the terminal's
    /// default background on a coloured run. Ghostty has no
    /// over-advancers in any class TUIkit emits — it is the only measured
    /// terminal that advances VS-16, ZWJ, keycaps, flags and skin tones
    /// exactly as claimed, so nothing else is rewritten on this path.
    /// ANSI escape sequences are preserved.
    public func withGhosttyCursorCompensation() -> String {
        withCursorForwardCompensation(erasingUnderGlyph: true) { $0.ghosttyCursorAdvance }
    }

    /// Returns a copy of this string with Warp's under-advances (lone
    /// regional indicators, SF Symbols, bare pictographs) worked around by
    /// the same `ECH` + glyph + `CUF` treatment as the other hosts. The
    /// erase is measured here too (2026-08-28): a lone 🇦's ink spans both
    /// claimed cells but its cursor advance covers one, and with `CUF`
    /// alone the second cell kept the default background under the glyph's
    /// right half — the iTerm2 SF Symbol shape exactly; both the `ECH` and
    /// styled-space variants filled it. Skin tones pass through whole: the
    /// published `.detached` claims cover Warp's base+swatch rendering (the
    /// ``withSkinToneFallback(scope:)`` strip fires only for a caller that
    /// never published traits), and the walk drops ZWJ joiners and the
    /// redundant tone VS-16 exactly as the traits describe. Warp's remaining
    /// divergences are OVER-advances (keycaps, 〰️/〽️) which no CUF can
    /// correct; they are left alone and documented.
    /// ANSI escape sequences are preserved.
    public func withWarpCursorCompensation() -> String {
        withCursorForwardCompensation(erasingUnderGlyph: true) { $0.warpCursorAdvance }
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
    /// tmux's detached-base skin tones are handled upstream by
    /// ``withSkinToneFallback(scope:)`` — the last live customer of the
    /// strip, per the measured ``Character/tmuxMergedToneBases`` set; a bare
    /// ☝ remains uncorrectable (see ``Character/tmuxCursorAdvance``).
    /// ANSI escape sequences are preserved.
    public func withTmuxCursorCompensation() -> String {
        withCursorForwardCompensation { $0.tmuxCursorAdvance }
    }

    /// Returns a copy of this string with the chrome-overhang class — and
    /// nothing else — compensated: the treatment an UNIDENTIFIED host gets.
    ///
    /// Every other class on this path is a host's own defect, and an
    /// unidentified host is assumed to have none, which is why it is otherwise
    /// emitted verbatim. This class is not a defect: TUIkit widened the claim
    /// on these glyphs to the two cells their ink covers
    /// (`ChromeOverhang.swift`), and every host measured still advances them
    /// one — so the shortfall belongs to the claim, not to the terminal, and
    /// is owed wherever the claim is in force. Without it the widened claim
    /// would shear a row on the one kind of host that cannot be measured, and
    /// chrome repeats many times per row.
    ///
    /// The erase rides along for the reason it does everywhere else: with
    /// `CUF` alone the cell the cursor skips keeps the terminal's default
    /// background, which was measured on all four native hosts (2026-08-28)
    /// and read as a comb across a coloured run. It is `ECH`, not a space, so
    /// nothing visible is added and every width measured afterwards still
    /// counts the row correctly.
    ///
    /// It compensates and does NOT normalize (`normalizing: false`), which is
    /// the difference from every other caller of the shared walk. The walk's
    /// redundant-VS-16 strip and its ZWJ decomposition are repairs calibrated
    /// against four measured hosts; running them here would silently rewrite an
    /// unidentified host's content — `☝️🏽` came out as `☝🏽` — which is exactly
    /// the thing this client is documented never to do.
    ///
    /// An unidentified host's OWN traits widen nothing
    /// (``TerminalWidthTraits/ChromeOverhang/contained``), so in an ordinary
    /// unidentified process this is the identity function on every input — and
    /// the first line is what makes that true rather than merely likely: the
    /// walk's own gate admits any line carrying an emoji, so without the
    /// short-circuit an unidentified host would still rebuild every such row
    /// to produce the same bytes. It has work to do when the claim in force
    /// came from somewhere else — a diagnostic pinning a measured host's
    /// traits while emitting through this path — which is why the guard asks
    /// the traits rather than assuming them.
    public func withChromeOverhangCompensation() -> String {
        guard !TerminalWidthTraits.current.chromeOverhang.codepoints.isEmpty else { return self }
        return withCursorForwardCompensation(erasingUnderGlyph: true, normalizing: false) {
            $0.unidentifiedHostCursorAdvance
        }
    }

    /// Shared CUF-injection walk: appends each character, then pushes the
    /// cursor forward by the shortfall whenever the host advances it less
    /// than the character's painted ``Character/terminalWidth``.
    ///
    /// One walk serves every host whose treatments are rewrite-free apart
    /// from the shared normalization (iTerm2, Ghostty, Warp, tmux); only the
    /// per-host advance model differs, so it is the parameter. Terminal.app
    /// keeps its own walk — its treatments rewrite content (tone separation
    /// with VS-16 promotion) and repair the row STORE (`CUB`/`DCH` surgery),
    /// which this cannot express. ANSI escape sequences are copied through
    /// untouched.
    ///
    /// - Parameters:
    ///   - erasingUnderGlyph: Emit `ECH` for the glyph's claimed cells before
    ///     drawing it, so those cells take the background in force.
    ///     Terminal.app was the first host measured to need it — with CUF
    ///     alone, eight under-advancing glyphs on a coloured run leave every
    ///     second cell at the terminal's default and the row reads as a comb.
    ///     iTerm2 and Ghostty were then measured (2026-08-28) to leave the
    ///     same hole under the cells their under-advancers skip — every SF
    ///     Symbol on both, plus keycaps and VS-16 clusters on iTerm2 — so the
    ///     earlier claim that only Terminal.app needed the erase was wrong: it
    ///     had simply never been measured on a coloured run elsewhere. Warp
    ///     followed the same day (a lone 🇦 left the default background under
    ///     the glyph's right half). It stays a parameter because tmux remains
    ///     unmeasured, and an unmeasured terminal is assumed to paint
    ///     correctly.
    ///   - normalizing: Whether the walk may also REWRITE what it emits — the
    ///     redundant-VS-16 strip on a tone cluster and the traits-driven ZWJ
    ///     decomposition. Every identified host wants both, because both were
    ///     calibrated against that host's own measurements. The chrome-overhang
    ///     walk passes `false`: it serves a host TUIkit could not name, whose
    ///     documented treatment is "change nothing", and a rewrite calibrated
    ///     for four measured hosts is not something an unmeasured one consented
    ///     to. Left `true` by default so no existing caller changes.
    ///   - advance: The host's cursor advance for a character.
    func withCursorForwardCompensation(
        erasingUnderGlyph: Bool = false,
        normalizing: Bool = true,
        advance: (Character) -> Int
    ) -> String {
        // Fast path: every quirk cluster is non-ASCII (same reasoning and
        // same gates as the Terminal.app walk, the second of which is what
        // keeps a box-drawing border off this path).
        guard utf8ContainsNonASCII, utf8MayNeedCompensation else { return self }

        let traits = TerminalWidthTraits.current
        var result = ""
        result.reserveCapacity(self.count + 8)
        var index = startIndex

        func appendCompensated(_ character: Character) {
            // A redundant VS-16 on a tone cluster (☝️🏽) is stripped first:
            // the modifier alone forces emoji presentation (UTS #51), and the
            // normalized pair is the one every host was measured to handle —
            // Ghostty merges it (the selector defeated the merge, detaching
            // 4 cells against a 2-cell claim), iTerm2 and Warp render it in
            // exactly the bare-base + swatch cells the claim allocates. See
            // ``Character/withoutRedundantToneVS16`` for the per-host numbers.
            let c = normalizing ? (character.withoutRedundantToneVS16 ?? character) : character
            let claimed = c.terminalWidth
            let actual = advance(c)
            if claimed > actual, erasingUnderGlyph {
                // ECH (CSI n X) paints n cells from the cursor in the current
                // background WITHOUT moving it, so the glyph then draws over
                // them. It writes no visible characters, which is why
                // `strippedLength` still counts the row correctly — spaces and
                // a backtrack would work on screen and inflate every width
                // measured afterwards.
                result += "\u{1B}[\(claimed)X"
            }
            result.append(c)
            if claimed > actual {
                result += "\u{1B}[\(claimed - actual)C"
            }
        }

        while index < endIndex {
            let c = self[index]

            if c == "\u{1B}" {
                let seqStart = index
                index = escapeSequenceEnd(from: index)
                result += self[seqStart..<index]
                continue
            }

            // Software ZWJ decomposition, exactly as in the Apple walk: when
            // the host's traits say the walk drops the joiners (Warp,
            // 2026-08-28 — the joiner columns were the gaps between the
            // components it draws anyway, and the dropped forms measured
            // aligned for sequential AND absolute followers), each segment is
            // emitted and compensated on its own. Hosts whose traits compose
            // (iTerm2, Ghostty, tmux) never enter this branch — nor does the
            // chrome-overhang walk, which rewrites nothing.
            if normalizing, traits.zwjSequences == .decomposedDroppingJoiners,
                let segments = c.emojiZWJSegments
            {
                for segment in segments {
                    appendCompensated(segment)
                }
            } else {
                appendCompensated(c)
            }
            index = self.index(after: index)
        }

        return result
    }
}

// MARK: - Un-compensating a span

extension String {
    /// Whether this line carries any `ECH` or `CUF` — the two escapes a
    /// cursor-advance compensation emits, and the only ones
    /// ``removingCursorCompensation(coveringColumns:)`` can have work to do on.
    ///
    /// A byte scan, so a line with no compensation (which is nearly every line,
    /// on nearly every host) costs one pass and no allocation.
    var containsCursorCompensation: Bool {
        utf8.withContiguousStorageIfAvailable { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var index = 0
            while index + 2 < buffer.count {
                guard base[index] == 0x1B, base[index + 1] == UInt8(ascii: "[") else {
                    index += 1
                    continue
                }
                var scan = index + 2
                while scan < buffer.count, base[scan] >= 0x30, base[scan] <= 0x39 { scan += 1 }
                if scan < buffer.count,
                    base[scan] == UInt8(ascii: "X") || base[scan] == UInt8(ascii: "C")
                        || base[scan] == UInt8(ascii: "D") || base[scan] == UInt8(ascii: "P")
                {
                    return true
                }
                index += 2
            }
            return false
        } ?? true
    }

    /// This line with the cursor-advance compensation for `columns` removed.
    ///
    /// A host that under-advances a cluster is given `ECH(n)` before it and
    /// `CUF(m)` after — see ``withTerminalAppCursorCompensation()`` and its
    /// siblings. The pair belongs to the cluster between them, and when
    /// something replaces that cluster the pair has to go with it.
    ///
    /// That is what the animation replay does: it splices a freshly-compensated
    /// frame over a run's cells, and those cells were compensated too, by
    /// `buildLine`, when the row was rendered. The splice works in COLUMNS and
    /// an escape claims no column, so the pair survived on either side of the
    /// new frame — which brought its own — and the row was left one `CUF` long.
    /// Every cell after the run then sat one place to the right, on the one host
    /// that compensates the glyph in question. Reported against a focused
    /// `Toggle`'s `⬜︎` in Ghostty, appearing and disappearing as renders and
    /// replays alternated on the same row.
    ///
    /// Which side a pair belongs to is decided by KIND, not by position alone,
    /// because both can sit at the span's far edge and mean opposite things: an
    /// `ECH` there introduces the cluster AFTER the span and must stay, while a
    /// `CUF` there closes the last cluster INSIDE it and must go. Hence the
    /// half-open range for one and its mirror for the other.
    ///
    /// Columns are the LAYOUT's, which is the space the caller's `column` and
    /// `width` are in: a visible character advances by its
    /// ``Character/terminalWidth`` and the compensation escapes advance by
    /// nothing, since reconciling the host's advance with that width is the
    /// whole of what they are for.
    func removingCursorCompensation(coveringColumns columns: Range<Int>) -> String {
        guard !columns.isEmpty, containsCursorCompensation else { return self }
        var result = ""
        result.reserveCapacity(count)
        var column = 0
        var index = startIndex
        while index < endIndex {
            guard self[index] == "\u{1B}" else {
                result.append(self[index])
                column += self[index].terminalWidth
                index = self.index(after: index)
                continue
            }
            let start = index
            index = escapeSequenceEnd(from: index)
            let sequence = self[start..<index]
            let final = sequence.last
            // Every shape the compensation walks emit, not only the ECH+CUF
            // pair: Terminal.app's store surgery (`glyph CUB(1) DCH(1) CUF(1)`,
            // for a flag pair or an FE0F keycap) and its pull-back (`glyph
            // CUB(n)`, for a tag flag or a bare keycap) both trail the glyph,
            // and a walk that recognised only `X` and `C` left the `D` and the
            // `P` behind at the span's trailing edge — where the replay then
            // re-emitted them AFTER the frame's own fresh trio, pulling the
            // cursor back and deleting a stored column on every tick.
            let drop =
                switch final {
                case "X": columns.contains(column)
                case "C", "D", "P": column > columns.lowerBound && column <= columns.upperBound
                default: false
                }
            if !drop { result += sequence }
        }
        return result
    }
}
