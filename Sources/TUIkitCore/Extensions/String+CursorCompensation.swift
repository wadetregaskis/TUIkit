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
    ///   ``Swift/Character/terminalAppCursorAdvance`` and its siblings, or
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
            index = csiSequenceEnd(from: index)
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
                // Skip ANSI escape sequences — `csiSequenceEnd(from:)`, shared by every escape walk. The
                // copies that used to sit in this file accepted only digits
                // and `;` between the `[` and the terminator, which stops at
                // the `?` of `ESC[?25l` and counts the rest as visible text.
                index = csiSequenceEnd(from: index)
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
    /// - the **internal** column (``Swift/Character/terminalAppCursorAdvance``,
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
    ///   ``TUIkitCore/TerminalWidthTraits`` claims the separated width:
    ///   rewritten as base + ZWNJ + modifier
    ///   (``Swift/Character/separatedSkinToneEmission``) and emitted with no
    ///   moves at all — the host renders base, one blank column (the ZWNJ's
    ///   own), then the swatch, and internal, paint and store all land on the
    ///   claim of base + 3. The tone survives on screen, which the composed
    ///   cluster plus any cursor repair measured could not do: every backward
    ///   move re-renders the cluster as its bare base.
    /// - **Skin tones on a text-presentation base** (☝🏻 ✍🏿): the same rewrite
    ///   measured MISALIGNED for these, so they keep `CUB(internal − claim)` —
    ///   aligned, tone shown only if the terminal ever repaints the cluster
    ///   unmoved.
    /// - **Emoji ZWJ sequences** (👨‍👩‍👧‍👦 ❤️‍🔥 👩🏽‍🚀), when the traits
    ///   claim the decomposed width: decomposed into their segments
    ///   (``Swift/Character/emojiZWJSegments``), each segment then compensated
    ///   by its own class — so ❤️‍🔥 becomes an `ECH`'d ❤️ plus a bare 🔥, and
    ///   👩🏽‍🚀 a separated 👩+ZWNJ+🏽 plus a bare 🚀. Every cursor-move
    ///   repair that kept the composed glyph left later absolute positioning
    ///   on the row displaced by 1–2 cells (stored-width mismatch), and the
    ///   full-width DCH variants wrapped; decomposition is the treatment with
    ///   nothing wrong with it, at the cost the user accepted: component
    ///   glyphs instead of the composed one.
    /// - **Flag pairs and keycaps**
    ///   (``Swift/Character/terminalAppStoresWiderThanPainted``): internal
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
        // 8 at a time (see `utf8ContainsNonASCII`).
        guard utf8ContainsNonASCII else { return self }

        let traits = TerminalWidthTraits.current
        var result = ""
        result.reserveCapacity(self.count + 8)

        // One cluster's emission — shared between the direct path and the
        // per-segment recursion of a decomposed ZWJ sequence (whose segments
        // never contain a further joiner, so this never recurses deeper).
        func appendCompensated(_ character: Character) {
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
                // Over-advancer (text-presentation skin tones, tag flags):
                // pull the internal column back to the claim; the paint
                // position — measured, not assumed — snaps with it.
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
                index = csiSequenceEnd(from: index)
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

    /// Which skin-tone clusters ``withSkinToneFallback(basePlane:)`` strips,
    /// selected by the Unicode plane of the cluster's BASE scalar.
    ///
    /// The distinction exists because terminals differ in *which* skin-tone
    /// clusters they fail to join, and stripping one a terminal handles
    /// correctly is a real loss: the user asked for 👍🏽 and gets 👍.
    ///
    /// - ``all``: every skin-tone cluster (iTerm2, Warp — they split all of them).
    /// - ``bmpOnly``: only clusters whose base is a BMP scalar (✊🏻 ☝🏽). This is
    ///   tmux, which joins an SMP-based cluster (👍🏽 👩🏽‍🚀) into the 2 cells we
    ///   claim — DSR-measured — and only over-advances (4 cells) on BMP bases.
    public enum SkinToneBasePlane: Sendable {
        /// Strip every skin-tone cluster, whatever its base.
        case all
        /// Strip only clusters whose base scalar is in the BMP (below U+10000).
        case bmpOnly
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
    /// - Parameter basePlane: which bases to strip. `.all` (the default) is the
    ///   iTerm2/Warp behaviour: those terminals split EVERY skin-tone cluster,
    ///   so every one must go. `.bmpOnly` strips only clusters whose base is a
    ///   BMP scalar (✊🏻 ☝🏽), which is what tmux needs — tmux joins an
    ///   SMP-based cluster (👍🏽 👩🏽‍🚀) into the 2 cells we claim and only
    ///   fails on BMP bases, so stripping those it gets right would throw away
    ///   skin tones the user asked for and the client renders correctly.
    public func withSkinToneFallback(basePlane: SkinToneBasePlane = .all) -> String {
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
                index = csiSequenceEnd(from: index)
                result += self[seqStart..<index]
                continue
            }

            let scalars = c.unicodeScalars
            let baseIsBMP = (scalars.first?.value ?? 0) < 0x10000
            let isModifiedCluster =
                scalars.count > 1
                && scalars.first!.properties.isEmojiModifierBase
                && scalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
                && (basePlane == .all || baseIsBMP)
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
    /// styled-space variants filled it. Warp's other divergences are
    /// OVER-advances (keycaps, 〰️/〽️) which no CUF can correct, or
    /// skin-tone clusters — stripped first by ``withSkinToneFallback()``
    /// when the claim in force cannot hold them.
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
    ///   - advance: The host's cursor advance for a character.
    func withCursorForwardCompensation(
        erasingUnderGlyph: Bool = false,
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
                index = csiSequenceEnd(from: index)
                result += self[seqStart..<index]
                continue
            }

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
            index = self.index(after: index)
        }

        return result
    }
}
