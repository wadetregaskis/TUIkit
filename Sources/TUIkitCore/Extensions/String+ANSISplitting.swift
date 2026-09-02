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
        return exactAnsiAwarePrefixWithWidth(visibleCount: visibleCount)
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

        // The commonest case on the emission path by a wide margin: the line
        // already fits, so the walk would materialize a segment per character
        // only to hand back the string it was given. `strippedLength` answers
        // "does it fit" without allocating, and has its own byte-wise fast
        // path for the plain-ASCII majority.
        //
        // Equivalent by construction: the walk emits every segment in order
        // and only stops early at a cut, so with no cut it reassembles the
        // original and reports `strippedLength`. `ANSIPrefixKnownWidthTests`
        // pins that against ``exactAnsiAwarePrefixWithWidth(visibleCount:)``
        // rather than leaving it as an argument.
        let width = strippedLength
        if width <= visibleCount { return (self, width) }

        return exactAnsiAwarePrefixWithWidth(visibleCount: visibleCount)
    }

    /// The clip with no fast path at all — the segment walk itself.
    ///
    /// Kept reachable so the fast paths in front of it have an oracle to be
    /// pinned against. Both public entry points are required to be
    /// byte-identical to this for every input at every cut point, and a test
    /// that could only compare one fast path to another would not be checking
    /// anything.
    func exactAnsiAwarePrefixWithWidth(visibleCount: Int) -> (prefix: String, visibleWidth: Int) {
        guard visibleCount > 0 else { return ("", 0) }

        var result = ""
        var visible = 0
        var link = HyperlinkScan()

        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                result += sequence
                // SGR is the escape a styled line is made of and can never be
                // a hyperlink, so the scan is asked only about the rest.
                if !isSGR { link.note(sequence) }
            case .visible(let character):
                let charWidth = character.terminalWidth
                // A cut, and the only place one happens here — so the only
                // place a hyperlink can be left open. The natural end of the
                // walk deliberately does NOT close: there the result is the
                // caller's own string reassembled, and adding a sequence it
                // did not contain would break the identity the fast path in
                // front of this relies on (it returns `self` untouched).
                if visible + charWidth > visibleCount {
                    return (result + link.closingIfOpen, visible)
                }
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
        // A hyperlink is carried across the left edge for the same reason the
        // styling is — it is state the dropped columns established and the
        // window's cells are still inside — and closed at the right edge for a
        // stronger one: a window that keeps an opening sequence and drops the
        // closing one hands the link to every cell drawn after it.
        //
        // It cannot ride along in `carriedStyle`, which accumulates: a link
        // opened and closed before the window would be replayed as an open.
        // The scan holds the state instead, and the sequence is restated ONCE,
        // as the window is entered.
        var link = HyperlinkScan()
        var enteredWindow = false
        func enterWindow() {
            guard !enteredWindow else { return }
            enteredWindow = true
            body += link.reopening
        }

        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                if visible < visibleStart {
                    if isSGR { carriedStyle += sequence } else { link.note(sequence) }
                } else if visible < end {
                    enterWindow()
                    body += sequence
                    if !isSGR { link.note(sequence) }
                }
            case .visible(let character):
                let charWidth = character.terminalWidth
                let charEnd = visible + charWidth
                if visible >= visibleStart && charEnd <= end {
                    enterWindow()
                    body.append(character)
                } else if charEnd > visibleStart && visible < end {
                    // Straddles an edge: blank its in-window cells.
                    enterWindow()
                    body += String(
                        repeating: " ",
                        count: min(charEnd, end) - max(visible, visibleStart))
                }
                visible = charEnd
            }
        }
        return carriedStyle + body + link.closingIfOpen
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

        // Same "it already fits" short-cut as the plain clip, but it needs a
        // STRICTER guard, because this walk does a second thing: it replaces
        // an over-advancer whose mid-emission peak would cross the right edge
        // with plain spaces. That can fire on a line that fits — a skin tone
        // claiming 2 at column 77 of an 80-cell row peaks at 81 — so "fits"
        // alone is not enough to skip the walk.
        //
        // `utf8MayNeedCompensation` is exactly the missing half: false means
        // the line holds no cluster any advance model acts on, so no character
        // can have an advance wider than its claim, so no substitution can
        // fire. That covers the case this is for — a bordered, otherwise-ASCII
        // row, which is most rows of most TUIkit apps and the same rows the
        // compensation walks now skip.
        if !utf8MayNeedCompensation {
            let width = strippedLength
            if width <= visibleCount { return (self, width) }
        }

        return exactAnsiAwarePrefixForTerminalAppWithWidth(visibleCount: visibleCount)
    }

    /// The Terminal.app clip with no fast path — the walk itself, kept
    /// reachable as the oracle its fast path is pinned against. See
    /// ``exactAnsiAwarePrefixWithWidth(visibleCount:)``.
    func exactAnsiAwarePrefixForTerminalAppWithWidth(
        visibleCount: Int
    ) -> (prefix: String, visibleWidth: Int) {
        guard visibleCount > 0 else { return ("", 0) }

        var result = ""
        var visible = 0
        var link = HyperlinkScan()

        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                result += sequence
                if !isSGR { link.note(sequence) }
            case .visible(let character):
                let charWidth = character.terminalWidth
                // The cut, and the only one: see the twin walk's note on why
                // the natural end of the string does not close.
                if visible + charWidth > visibleCount {
                    return (result + link.closingIfOpen, visible)
                }
                // The walk nets every emitted cluster back to its claim (the
                // conservation law: under-advancers are CUF'd up, over-
                // advancers CUB'd back, rewrites land there by construction),
                // so the internal column at every cluster BOUNDARY is the sum
                // of claims — `visible` — whatever raw advances came before.
                // What can still overflow is one cluster's own mid-emission
                // peak: an over-advancer reaches its raw internal advance
                // before its repair pulls the column back, and the wrap fires
                // at the peak, mid-cluster, before any compensation runs.
                //
                // (An earlier version kept a second accumulator of raw
                // advances instead, which was wrong in both directions: eight
                // compensated ⚙️ read as column 8 when the walk had really
                // netted 16, letting a tag flag through whose peak wrapped
                // the row — and a kept tag flag inflated the tally by its
                // pre-CUB surplus, substituting later clusters that fit.)
                //
                // Clusters the walk rewrites (separated skin tones, decomposed
                // ZWJ sequences) peak at their claim, monotonically — the raw
                // internal advance (👨‍👩‍👧‍👦: 11) never happens, so
                // budgeting it would replace clusters that actually fit.
                let advance = character.terminalAppWalkRewritesToClaim
                    ? charWidth : character.terminalAppCursorAdvance
                if advance > charWidth && visible + advance > visibleCount {
                    // Over-advancer whose peak would push Terminal.app's
                    // cursor past the right edge.  Replace with `charWidth`
                    // plain spaces to preserve the layout but avoid the
                    // wrap-to-next-row bug.  Skin tone is sacrificed in this
                    // narrow case.
                    if charWidth > 0 {
                        result.append(String(repeating: " ", count: charWidth))
                    }
                } else {
                    result.append(character)
                }
                visible += charWidth
            }
        }

        return (result, visible)
    }

    /// Returns the accumulated SGR (colour/style) state as of `visibleOffset` visible cells,
    /// concatenated with the remaining visible content and SGR sequences — with cursor-
    /// moving and line-scoped ANSI sequences stripped from both the context scan *and*
    /// the returned suffix, but `ECH` kept in the suffix.
    ///
    /// Used by `FrameDiffWriter.repaintRightEdge` to re-emit the last few cells of a
    /// line with the correct SGR context: the caller positions the terminal cursor
    /// explicitly before writing the result, so any CUF / EL / other cursor-movement
    /// sequence left in the string would displace the cursor from where the caller put
    /// it and write subsequent characters in the wrong terminal column.
    ///
    /// `ECH` (`CSI n X`) is the one exception, kept in the SUFFIX only: it paints n
    /// cells from the cursor **without moving it**, and it is the measured background
    /// repair for an under-advancing glyph — the walk emits `ECH(2)`+glyph+`CUF(1)`,
    /// and re-writing that glyph here without its erase left the cell its cursor
    /// advance skips at pass 1's app background instead of the run's: a one-cell
    /// version of the comb the erase was added for, at exactly the right edge this
    /// function serves. In the CONTEXT half it stays dropped — there it is positional
    /// state from cells the caller is not rewriting.
    ///
    /// - Parameter visibleOffset: The number of visible terminal cells to skip.
    /// - Returns: Accumulated SGR state + visible content from `visibleOffset` onward,
    ///   or `nil` if the string has fewer than `visibleOffset` visible cells.
    public func ansiSGRContextAndCleanSuffix(from visibleOffset: Int) -> String? {
        var sgrContext = ""
        var suffix = ""
        var visible = 0
        // A hyperlink is entry state exactly as the colour is — the cells being
        // re-emitted are inside it — but it is not SGR, so it needs saying
        // separately. It is also cursor-neutral, which is the property this
        // function's suffix filter is really testing, so the suffix keeps its
        // sequences alongside the `ECH`.
        var link = HyperlinkScan()

        for segment in ansiSegments() {
            // Before the offset is reached we're accumulating the entry
            // colour state; at or after it, content belongs in the suffix.
            let inSuffix = visible >= visibleOffset
            switch segment {
            case .ansi(let sequence, let isSGR):
                if inSuffix {
                    // SGR, plus the cursor-neutral ECH the under-advance
                    // treatment depends on. Movers (CUF, CUB, …) and
                    // line-scoped erases (EL) stay dropped: the caller
                    // positions the cursor explicitly.
                    let isECH = sequence.last == "X" && sequence.hasPrefix("\u{1B}[")
                        && sequence.dropFirst(2).dropLast().allSatisfy(\.isNumber)
                    guard isSGR || isECH || TerminalHyperlink.isHyperlink(sequence) else {
                        continue
                    }
                    suffix += sequence
                } else {
                    guard isSGR else {
                        link.note(sequence)
                        continue
                    }
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
        return sgrContext + link.reopening + suffix
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
        var link = HyperlinkScan()

        for segment in ansiSegments() {
            // Everything at or after the drop boundary is kept verbatim
            // (ANSI included); everything before it is discarded.
            let keeping = visible >= dropCount
            switch segment {
            case .ansi(let sequence, let isSGR):
                if keeping {
                    result += sequence
                } else if !isSGR {
                    link.note(sequence)
                }
            case .visible(let character):
                if keeping {
                    result.append(character)
                } else {
                    visible += character.terminalWidth
                }
            }
        }

        // The dropped columns may have opened a hyperlink these cells are
        // inside. Restating it is the quiet obligation of the pair — nothing
        // looks broken when it is missed, the link is simply shorter than the
        // label it belongs to.
        return link.reopening + result
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
            // The shared walker, so this agrees with every other scan about
            // where a sequence ends. It hand-rolled the CSI rule as "digits and
            // `;` then a letter", which stops at the `?` of `ESC[?25l` and — far
            // worse here — at the `]` of an OSC 8 hyperlink: the split then fell
            // between the ESC and its own introducer, handing the caller a
            // bare ESC to replay as "styling" and a remainder beginning inside
            // a sequence. A link opening a line is exactly where that happens.
            let (end, _) = Self.escapeSequenceEnd(startingAt: index, in: scalars)
            guard end > index else { break }
            index = end
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
    /// - Returns: Everything ``FrameBuffer/insertOverlay(base:overlay:atColumn:)``
    ///   needs from this line, in one scan — see ``ANSIOverlaySplit``.
    func ansiOverlaySplit(prefixColumns: Int, suffixDropColumns: Int) -> ANSIOverlaySplit {
        var prefix = ""
        var prefixWidth = 0
        var prefixOpen = prefixColumns > 0
        var suffix = ""
        var suffixWidth = 0
        var style = SGRState()
        // The state where the overlay LANDS — what the covered cells are
        // painted on, so an overlay cell that states no background of its own
        // can keep this one.
        //
        // A COPY of `style`, taken at the overlay's column, rather than a
        // second accumulator netted alongside it. Every sequence before the
        // overlay is also before the suffix, so `style` has already applied
        // every one of them, in order — and `SGRState.apply` splits the
        // parameters and allocates a `String` per code, which is far more than
        // a struct copy. Netting them twice made compositing a `Layout`'s
        // children quadratic in escapes all over again, which is the very
        // thing this one-scan split exists to have fixed.
        var under: SGRState?
        var total = 0
        // Two scans, because the two halves are cut at different columns: the
        // prefix ends at `prefixColumns` and owes a close there, the suffix
        // begins at `suffixDropColumns` and owes the opening sequence. One
        // scan could only ever be right about one of them.
        var prefixLink = HyperlinkScan()
        var suffixLink = HyperlinkScan()

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
                        // The cut. An overlay is composited straight after
                        // this, so a link left open would run underneath it.
                        prefix += prefixLink.closingIfOpen
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
            let (end, isSGR) = Self.escapeSequenceEnd(startingAt: index, in: scalars)
            let text = String(scalars[index..<end])
            index = end
            if prefixOpen {
                prefix += text
                if !isSGR { prefixLink.note(text) }
            }
            if total >= suffixDropColumns {
                suffix += text
            } else if isSGR {
                style.apply(text)
                if total <= prefixColumns { under = style }
            } else {
                suffixLink.note(text)
            }
        }
        flushVisible()

        // A line SHORTER than the overlay's column never reaches the cut in
        // `flushVisible`, so its link is still open here — and the overlay is
        // composited straight after it either way.
        prefix += prefixLink.closingIfOpen
        // The suffix begins inside whatever link the dropped columns opened,
        // and carries no width, so it goes in front of the content rather than
        // into a field of its own: `suffixWidth` is unchanged by construction.
        let resumedSuffix = suffixLink.reopening + suffix

        return ANSIOverlaySplit(
            prefix: prefix, prefixWidth: prefixWidth, suffix: resumedSuffix,
            suffixWidth: suffixWidth,
            styleBeforeSuffix: style.rendered,
            backgroundUnderOverlay: under?.renderedBackground ?? "",
            totalWidth: total)
    }
}

// MARK: - The split itself

/// One line cut for compositing, from a single scan.
///
/// A struct rather than a tuple because there are seven answers and they are
/// not interchangeable; the fields carry the names the call site reads.
struct ANSIOverlaySplit {
    /// The visible columns before the overlay, with their styling.
    let prefix: String
    /// How wide ``prefix`` actually came out — short of the requested column
    /// when a wide character straddles it.
    let prefixWidth: Int
    /// Everything from the first character at or past the overlay's right edge.
    let suffix: String
    /// How wide ``suffix`` is.
    let suffixWidth: Int
    /// The NETTED styling where the suffix begins, ready to re-emit.
    let styleBeforeSuffix: String
    /// The background in force where the overlay lands (`""` for the
    /// terminal's own) — what an overlay cell that names none is drawn over.
    let backgroundUnderOverlay: String
    /// The line's whole visible width.
    let totalWidth: Int
}

// MARK: - Painting a line over a field it did not ask about

extension String {
    /// This line with `background` in force wherever it states none of its own.
    ///
    /// A cell has a glyph and a field, and the two are separate statements: a
    /// styled string that sets only a foreground has said nothing about the
    /// field, so it can be drawn over one. That is what lets
    /// `ZStack { Color.red; Text("hi") }` put the letters ON the red instead of
    /// punching a hole in it — see ``FrameBuffer/composited(with:at:)``.
    ///
    /// The escape is emitted lazily, immediately before the first visible cell
    /// of each run that would otherwise have no background, so a line that
    /// states its own background everywhere comes back byte-identical and a
    /// line that states none takes exactly one escape. Nothing is emitted after
    /// the last visible character.
    ///
    /// - Parameter background: A background escape (`SGRState.renderedBackground`),
    ///   or `""` to leave the line alone.
    /// - Returns: The line, painted over that field.
    func paintedOver(background: String) -> String {
        guard !background.isEmpty else { return self }

        var state = SGRState()
        var needsBackground = true
        var result = ""
        result.reserveCapacity(utf8.count + background.utf8.count * 2)

        let scalars = unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            guard scalars[index].value == 0x1B else {  // not ESC → visible
                if needsBackground {
                    result += background
                    needsBackground = false
                }
                result.unicodeScalars.append(scalars[index])
                index = scalars.index(after: index)
                continue
            }
            let (end, isSGR) = Self.escapeSequenceEnd(startingAt: index, in: scalars)
            let text = String(scalars[index..<end])
            index = end
            result += text
            if isSGR {
                state.apply(text)
                needsBackground = !state.namesBackground
            }
        }
        return result
    }
}
