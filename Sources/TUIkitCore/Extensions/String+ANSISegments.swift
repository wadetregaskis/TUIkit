//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+ANSISegments.swift
//
//  Where an escape sequence ends, and what a styled line is made of.
//
//  Split out of String+TerminalWidth.swift, which measures cells: these answer
//  the question every measurer and every splitter has to answer first — which
//  bytes the terminal paints and which it consumes. One walker rather than the
//  six that had grown, because a class of sequence understood by some of them
//  and not others is how a line comes to measure a width nothing paints.
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

extension String {

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
    ///
    /// Prefer ``forEachANSISegment(_:)`` on a render path: this builds — and a
    /// moment later throws away — one array element per CHARACTER of the line,
    /// and it cannot stop early for a caller that only wants the first few
    /// cells. The array form stays for the tests that use it as an oracle and
    /// for callers that genuinely want a collection.
    public func ansiSegments() -> [ANSISegment] {
        var segments: [ANSISegment] = []
        segments.reserveCapacity(utf8.count)
        forEachANSISegment { segment in
            segments.append(segment)
            return true
        }
        return segments
    }

    /// ``ansiSegments()`` without the array: yields the same segments, in the
    /// same order, and stops the moment `body` returns `false`.
    ///
    /// Both halves of that matter, and the second one more. A clip to N cells
    /// wants the first N cells and nothing else, and the array form gave it the
    /// whole line — so clipping a 2,048-cell line to 12 cells cost 71 µs, of
    /// which 69 µs was materialising 2,036 segments the caller returned before
    /// reading. Every walk in `String+ANSISplitting.swift` had that shape.
    ///
    /// Visible runs are yielded character by character without copying the run
    /// out into a `String` first, whenever the characters are plain ASCII. Two
    /// consecutive ASCII scalars always have a grapheme break between them —
    /// the only ASCII pair that does not is CR LF, and nothing that extends a
    /// cluster (`Extend`, ZWJ, `SpacingMark`, a regional indicator) is ASCII —
    /// so such a scalar is a whole `Character` on its own and can be handed
    /// over as one. The moment that stops holding, the rest of the run is
    /// copied out and grapheme-clustered as before, which is what the doc
    /// comment above is about: a run is clustered on its own, never across an
    /// escape.
    ///
    /// - Parameter body: Receives each segment; returns `false` to stop.
    /// - Returns: `true` if the walk reached the end of the string, `false` if
    ///   `body` stopped it.
    @discardableResult
    public func forEachANSISegment(_ body: (ANSISegment) -> Bool) -> Bool {
        let scalars = unicodeScalars
        var index = scalars.startIndex
        var runStart = index
        var hasRun = false

        /// Yields the visible run `[runStart, end)`; `false` if `body` stopped.
        func flushVisible(before end: UnicodeScalarView.Index) -> Bool {
            guard hasRun else { return true }
            hasRun = false
            var cursor = runStart
            while cursor < end {
                let value = scalars[cursor].value
                let next = scalars.index(after: cursor)
                guard value < 0x80, next == end || scalars[next].value < 0x80,
                    !(value == 0x0D && next < end && scalars[next].value == 0x0A)
                else {
                    // Not provably a standalone cluster: cluster the remainder
                    // the general way. Safe to split here because the previous
                    // iteration proved a break at `cursor` (or `cursor` is the
                    // start of the run, which is a break by construction).
                    //
                    // `body` is called in the `where` — once per character, as
                    // it would be in the loop body — and the loop body is
                    // reached only when it asked to stop.
                    for character in String(scalars[cursor..<end])
                    where !body(.visible(character)) {
                        return false
                    }
                    return true
                }
                let scalar = Unicode.Scalar(UInt8(truncatingIfNeeded: value))
                if !body(.visible(Character(scalar))) { return false }
                cursor = next
            }
            return true
        }

        while index < scalars.endIndex {
            guard scalars[index].value == 0x1B else {  // not ESC → visible
                if !hasRun {
                    runStart = index
                    hasRun = true
                }
                index = scalars.index(after: index)
                continue
            }
            guard flushVisible(before: index) else { return false }
            let (end, isSGR) = Self.escapeSequenceEnd(startingAt: index, in: scalars)
            guard body(.ansi(String(scalars[index..<end]), isSGR: isSGR)) else { return false }
            index = end
        }
        return flushVisible(before: index)
    }
}
