//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+ANSISplitting.swift
//
//  Splitting a styled line at a visible-cell boundary, and recovering the SGR
//  state that is in force there. Both are harder than they look: the split
//  point is counted in terminal CELLS, so the scan has to skip escape
//  sequences, treat a wide glyph as two columns, and refuse to cut one in
//  half — and the escapes themselves have to be carried across the cut or the
//  styling either vanishes or bleeds.
//
//  Split out of String+TerminalWidth.swift, which measures cells; these cut on
//  them. `FrameBuffer`'s compositing is the caller that exercises every corner.
//
//  Created by LAYERED.work
//  License: MIT

extension String {

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

    /// Like ``ansiAwarePrefix(visibleCount:)``, but the caller's
    /// already-computed ``strippedLength`` unlocks an O(excess) fast path for
    /// the commonest clip in the framework: a line assembled one padding cell
    /// wider than its slot (a list row's forced right-padding space meeting
    /// the scrollbar column, a padded row meeting a container clamp). When the
    /// excess is entirely trailing plain ASCII spaces, the answer is the
    /// string minus those bytes — no escape-aware forward walk, no per-cell
    /// append.
    ///
    /// Byte-identical to the walk by construction: the walk emits everything
    /// before the cut cell (escape sequences included, since they precede the
    /// cut character in the byte stream) and stops there, which for a cut
    /// inside a trailing run of plain spaces is exactly the original minus its
    /// last `excess` bytes. A space that is NOT a visible cell (an
    /// intermediate byte of an unterminated escape) would break that
    /// equivalence, so the result is verified by one (vectorised)
    /// ``strippedLength`` re-scan and anything surprising falls back to the
    /// exact walk.
    ///
    /// - Parameters:
    ///   - visibleCount: The number of terminal cells to include.
    ///   - knownVisibleWidth: This string's ``strippedLength``, which the
    ///     caller computed to decide the clip was needed at all.
    public func ansiAwarePrefix(visibleCount: Int, knownVisibleWidth: Int) -> String {
        ansiAwarePrefixWithWidth(
            visibleCount: visibleCount, knownVisibleWidth: knownVisibleWidth
        ).prefix
    }

    /// Like ``ansiAwarePrefix(visibleCount:knownVisibleWidth:)`` but also
    /// returns the visible cell width of the clipped result (see
    /// ``ansiAwarePrefixWithWidth(visibleCount:)`` for why the pair is worth
    /// having: it spares the caller a re-scan for right-padding arithmetic).
    public func ansiAwarePrefixWithWidth(
        visibleCount: Int, knownVisibleWidth: Int
    ) -> (prefix: String, visibleWidth: Int) {
        guard visibleCount > 0 else { return ("", 0) }
        let excess = knownVisibleWidth - visibleCount
        // Nothing to cut: the walk would emit the whole string unchanged.
        guard excess > 0 else { return (self, knownVisibleWidth) }

        let bytes = utf8
        if excess <= bytes.count {
            var tailIsPlainSpaces = true
            var cutIndex = bytes.endIndex
            for _ in 0..<excess {
                bytes.formIndex(before: &cutIndex)
                if bytes[cutIndex] != 0x20 {
                    tailIsPlainSpaces = false
                    break
                }
            }
            if tailIsPlainSpaces {
                // An ASCII space is always a full character, so `cutIndex` is
                // a character boundary and the slice is valid.
                let candidate = String(self[..<cutIndex])
                if candidate.strippedLength == visibleCount {
                    return (candidate, visibleCount)
                }
            }
        }
        return ansiAwarePrefixWithWidth(visibleCount: visibleCount)
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
    /// straddles either edge cannot be shown whole; its IN-WINDOW cells become
    /// spaces, so the gap it leaves still occupies its columns. (Dropping it with
    /// no gap — the old behaviour — let everything after a left-edge straddle
    /// render one cell left of its neighbours: aligned columns went ragged,
    /// jittering as each wide glyph crossed the window edge while scrolling.)
    /// The slice's visible width is therefore always
    /// `max(0, min(strippedLength − visibleStart, visibleCount))`.
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
                let charEnd = visible + charWidth
                if visible >= visibleStart && charEnd <= end {
                    body.append(character)
                } else if charEnd > visibleStart && visible < end {
                    // Straddles an edge: blank its in-window cells.
                    body += String(
                        repeating: " ",
                        count: min(charEnd, end) - max(visible, visibleStart))
                }
                visible = charEnd
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
    /// Used by `FrameDiffWriter.repaintRightEdge` to re-emit the last few cells of a
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
        leadingANSISplit().prefix
    }

    /// The leading ANSI sequences and everything after them, split at the
    /// exact SCALAR boundary after the last terminator.
    ///
    /// Scalar-level deliberately: grapheme segmentation can fuse a sequence's
    /// terminator letter with a combining mark that begins the visible text
    /// (`…m` + U+0308 is ONE `Character`), and a `Character`-level scan
    /// consumed the fused cluster whole — the combining mark vanished into
    /// the "styling" prefix, and any caller reassembling around a
    /// character-counted split point dropped it from the text too. Callers
    /// that need both halves take THIS, rather than re-deriving the remainder
    /// by count.
    public func leadingANSISplit() -> (prefix: String, remainder: String) {
        let scalars = unicodeScalars
        var index = scalars.startIndex

        while index < scalars.endIndex, scalars[index] == "\u{1B}" {
            // Consume the ANSI sequence (ESC [ params letter). Parameters and
            // terminators are ASCII by construction — these are our own
            // machine-generated SGRs, never text.
            var probe = scalars.index(after: index)
            if probe < scalars.endIndex, scalars[probe] == "[" {
                probe = scalars.index(after: probe)
                while probe < scalars.endIndex,
                    ("0"..."9").contains(scalars[probe]) || scalars[probe] == ";"
                {
                    probe = scalars.index(after: probe)
                }
                if probe < scalars.endIndex, scalars[probe].properties.isAlphabetic,
                    scalars[probe].isASCII
                {
                    probe = scalars.index(after: probe)
                }
            }
            index = probe
        }

        return (String(scalars[scalars.startIndex..<index]), String(scalars[index...]))
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
        sgrState(throughColumn: column, includingBoundary: false).rendered
    }

    /// The netted ``SGRState`` the terminal is in as it draws the cell at
    /// visible column `column`.
    ///
    /// One escape's worth more than ``ansiStateBefore(visibleColumn:)``, and the
    /// difference is the whole point: escapes sitting *immediately* before that
    /// cell — the `ESC[48;…m` a line opens with, say — style the cell itself, so
    /// they belong to it. `ansiStateBefore` excludes them because it answers a
    /// different question (what to restore where a suffix *begins*, which
    /// carries those escapes along with it), and at column 0 that makes its
    /// answer unconditionally empty.
    ///
    /// Wanted by anything that redraws a cell in place and has to land on the
    /// surface already under it. See ``FrameBuffer/patchingAnimatedCells(in:with:atColumn:width:)``.
    public func ansiSGRStateAt(visibleColumn column: Int) -> SGRState {
        sgrState(throughColumn: column, includingBoundary: true)
    }

    /// The shared walk behind the two state queries.
    private func sgrState(throughColumn column: Int, includingBoundary: Bool) -> SGRState {
        var visible = 0
        var state = SGRState()
        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                let reached = includingBoundary ? visible <= column : visible < column
                if isSGR && reached { state.apply(sequence) }
            case .visible(let character):
                visible += character.terminalWidth
            }
        }
        return state
    }

    /// Everything ``FrameBuffer``'s overlay insertion needs about a line, from
    /// ONE scan and with no intermediate array.
    ///
    /// The five calls it replaces — ``ansiAwarePrefixWithWidth(visibleCount:)``,
    /// ``ansiAwareSuffix(droppingVisible:)``, ``ansiStateBefore(visibleColumn:)``
    /// and two ``strippedLength`` reads — each walked the line through
    /// ``ansiSegments()``, which materialises one enum case per character.
    /// Compositing a child into a row therefore rescanned (and re-allocated) the
    /// whole line five times over, and a row's line grows with every styled child
    /// already written into it. An Instruments trace of a custom `Layout` placing
    /// 160 children put `insertOverlay` at 66.9% of the run, `ansiSegments` alone
    /// at 37.9%.
    ///
    /// The semantics of each field are exactly those of the function it replaces,
    /// including the ones that look like quirks and are not:
    /// - the prefix STOPS at the first visible character that would overrun
    ///   `prefixColumns`, and takes no further ANSI after that point;
    /// - the suffix keeps everything — ANSI included — from the first character
    ///   at or beyond `suffixDropColumns`, and nothing before it;
    /// - `styleBeforeSuffix` is the NETTED state at that column, not the
    ///   escapes concatenated. Concatenating is also correct — a terminal nets
    ///   an open/reset pair itself — but the answer is written back INTO the
    ///   line, so the next child's replay would contain this one's and the row
    ///   would double per child. See ``SGRState``.
    ///
    /// - Parameters:
    ///   - prefixColumns: Visible columns to keep at the front.
    ///   - suffixDropColumns: Visible columns to drop before the suffix begins.
    /// - Returns: The prefix and its width, the suffix and its width, the SGR
    ///   state active where the suffix begins, and the line's total visible width.
    func ansiOverlaySplit(prefixColumns: Int, suffixDropColumns: Int) -> (
        prefix: String, prefixWidth: Int, suffix: String, suffixWidth: Int,
        styleBeforeSuffix: String, totalWidth: Int
    ) {
        var prefix = ""
        var prefixWidth = 0
        var prefixOpen = prefixColumns > 0
        var suffix = ""
        var suffixWidth = 0
        var style = SGRState()
        var total = 0

        let scalars = unicodeScalars
        var index = scalars.startIndex
        var pending = Self.UnicodeScalarView()

        // Visible scalars are buffered so they can be grouped into Characters —
        // width is a per-CHARACTER property, and a grapheme may span scalars.
        func flushVisible() {
            guard !pending.isEmpty else { return }
            for character in String(pending) {
                let width = character.terminalWidth
                let keeping = total >= suffixDropColumns
                if prefixOpen {
                    if prefixWidth + width > prefixColumns {
                        prefixOpen = false
                    } else {
                        prefix.append(character)
                        prefixWidth += width
                    }
                }
                if keeping {
                    suffix.append(character)
                    suffixWidth += width
                }
                total += width
            }
            pending = Self.UnicodeScalarView()
        }

        while index < scalars.endIndex {
            guard scalars[index].value == 0x1B else {  // not ESC → visible
                pending.append(scalars[index])
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
                // One scalar for the final byte, so a trailing Extend scalar
                // stays visible rather than being swallowed by the escape.
                if index < scalars.endIndex, Self.isCSIFinalByte(scalars[index].value) {
                    isSGR = scalars[index].value == 0x6D  // 'm'
                    sequence.append(scalars[index])
                    index = scalars.index(after: index)
                }
            }
            let text = String(sequence)
            if prefixOpen { prefix += text }
            if total >= suffixDropColumns {
                suffix += text
            } else if isSGR {
                style.apply(text)
            }
        }
        flushVisible()

        return (prefix, prefixWidth, suffix, suffixWidth, style.rendered, total)
    }
}
