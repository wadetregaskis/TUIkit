//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+CellSpanDiff.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Cell Span Diff

/// One contiguous run of a row that has to be rewritten, ready to write.
///
/// See ``String/ansiCellDiff(replacing:width:mergingGapsUpTo:)``.
public struct ANSICellSpan: Equatable, Sendable {
    /// The 0-based visible column the run starts at. Move the cursor there
    /// (`column + 1` in the terminal's 1-based coordinates) before writing.
    public let column: Int

    /// The bytes to write once the cursor is at ``column``: the styling this run
    /// needs, then its cells.
    ///
    /// Spans are written **in the order they appear** and carry SGR state
    /// between them, so a span's opening escape is a delta from where the
    /// previous one left the terminal. Writing them out of order, or writing
    /// anything else in between, breaks that chain.
    ///
    /// Who ends the chain with a reset depends on which entry point built these.
    /// ``String/ansiCellDiff(replacing:width:mergingGapsUpTo:)`` plans one
    /// row in isolation and closes it; ``ANSIRowCells/diff(replacing:mergingGapsUpTo:continuing:)``
    /// hands the running state back so a caller writing many rows can keep it,
    /// and that caller owes the terminal the closing reset.
    public let content: String
}

/// What a row needs written to bring it from one frame to the next.
public enum ANSICellDiff: Equatable, Sendable {
    /// The two rows paint the same cells in the same styling. Nothing to write —
    /// which is not the same as the two strings being equal, since two different
    /// escape spellings can land the terminal in the same place.
    case identical

    /// Rewrite these runs, in this order, and nothing else.
    case spans([ANSICellSpan])

    /// Column accounting is not reliable for one of these rows, so only a
    /// whole-line rewrite is safe. See the bail-outs in
    /// ``String/ansiCellDiff(replacing:width:mergingGapsUpTo:)``.
    case wholeLine

    /// This plan with a reset added to its last span, when `emitted` says the
    /// spans leave the terminal styled.
    ///
    /// The reset is load-bearing exactly as it is on the whole-line path: it is
    /// what stops this row's styling leaking into whatever is drawn next. What
    /// changes with ``ANSIRowCells/diff(replacing:mergingGapsUpTo:continuing:)``
    /// is only WHEN it is owed — once at the end of a run of rows rather than
    /// once per row.
    public func closingStyling(from emitted: SGRState?) -> Self {
        guard case .spans(var spans) = self, let last = spans.last,
            emitted?.isDefault == false
        else { return self }
        spans[spans.count - 1] = ANSICellSpan(
            column: last.column, content: last.content + "\u{1B}[0m")
        return .spans(spans)
    }
}

extension String {

    /// What has to be written to turn the row `previous` currently on screen
    /// into this one — as the **cell runs that actually differ**, rather than
    /// the whole row.
    ///
    /// ## Why
    ///
    /// `FrameDiffWriter` diffs by ROW: a row that differs anywhere is rewritten
    /// end to end. That is already the difference between repainting the screen
    /// and repainting a line, and for a spinner ticking on an otherwise still
    /// page it is the whole answer. It is a poor answer for a gesture that
    /// disturbs many rows a little — dragging a `NavigationSplitView` divider
    /// moves a boundary and shifts two panes, and measured at 140×42 that is
    /// **393 changed cells expressed in 10,747 bytes**: 28 rows rewritten in
    /// full, 3,906 cells written to say 393. Writes to a terminal block, so the
    /// frame rate a drag achieves is the terminal's drain rate divided by this
    /// number.
    ///
    /// ## What it compares
    ///
    /// Cells, not text: the pair `(character, netted SGR in force)` at each
    /// visible column. A pulsing cursor or a hover tint changes no character at
    /// all — only the styling — so a text diff would report the rows identical,
    /// and a byte diff would report a difference without being able to say
    /// where.
    ///
    /// Styling is compared by what it PAINTS, not by what it says: a cell
    /// holding a space shows its background and whatever draws ink on an empty
    /// cell, and nothing else — see
    /// ``SGRState/paintsBlankCellsIdentically(to:)``. Most of a
    /// terminal UI is blank cells, and comparing them strictly reports a row
    /// dirty for a foreground colour nobody can see.
    ///
    /// ## When it declines
    ///
    /// ``ANSICellDiff/wholeLine`` is returned rather than a wrong answer
    /// whenever the columns cannot be trusted:
    ///
    /// - **A cursor-moving escape.** The per-host emoji compensation injects
    ///   `CUF` into rows whose glyphs under-advance (see
    ///   `String+CursorCompensation.swift`), and a cursor move means a column's
    ///   identity no longer follows from counting characters. Only SGR and a
    ///   leading erase are tolerated.
    /// - **An erase anywhere but the head.** `ESC[2K` opens every built row and
    ///   is harmless there — the row is padded to its full width, so every
    ///   column is written explicitly afterwards. Mid-row it would clear cells
    ///   this diff has no way to account for.
    /// - **Any character this row claims more than one cell for.** This is the
    ///   important one, and it is not about splitting a wide glyph — that is
    ///   handled below. It is that a whole-row rewrite RE-ANCHORS at column 1
    ///   every time, so a terminal that advances a glyph differently from our
    ///   claim corrupts only that row, only until it next changes. A span write
    ///   has no anchor: it trusts our column count to say where the cursor
    ///   goes, and if the terminal disagrees the span lands in the wrong place
    ///   and the row never recovers. Every divergence in
    ///   `Documentation/Terminal-compatibility.md` is of exactly this shape — a
    ///   2-cell claim meeting a 1-cell advance (bare pictographs, lone regional
    ///   indicators, SF-Symbol PUA glyphs, the VS-15 chrome glyphs, skin-tone
    ///   clusters) — so declining every multi-cell claim declines every one of
    ///   them, including on hosts whose model we have not measured. Single-cell
    ///   characters have no such disagreement: box drawing, accented Latin,
    ///   Greek and Cyrillic advance one everywhere.
    /// - **A row that does not decompose to exactly `width` columns** — an empty
    ///   row against a full one, most often.
    ///
    /// - Parameters:
    ///   - previous: The row currently on screen.
    ///   - width: The terminal width both rows are built to.
    ///   - gap: How many unchanged columns may sit inside one span. Bridging a
    ///     short gap is cheaper than closing a span and opening another, which
    ///     costs a cursor move and a fresh statement of styling.
    public func ansiCellDiff(
        replacing previous: String,
        width: Int,
        mergingGapsUpTo gap: Int
    ) -> ANSICellDiff {
        guard width > 0,
            let new = ANSIRowCells(decomposing: self, width: width),
            let old = ANSIRowCells(decomposing: previous, width: width)
        else { return .wholeLine }
        // One row, planned on its own: nothing precedes it that we may assume,
        // and nothing follows it that will clean up — so it states itself from a
        // reset and closes with one.
        var emitted: SGRState?
        return new.diff(replacing: old, mergingGapsUpTo: gap, continuing: &emitted)
            .closingStyling(from: emitted)
    }
}

// MARK: - Row Decomposition

/// A built row taken apart into terminal cells: one entry per visible COLUMN,
/// with the netted styling in force where each is drawn.
///
/// Deliberately column-indexed rather than character-indexed. The question this
/// answers is "does the terminal show the same thing here as it did last
/// frame", and the terminal's unit for *here* is a column.
///
/// Public so a caller rendering frame after frame can take each row apart ONCE:
/// this frame's new row is next frame's previous row, and decomposing both sides
/// every frame doubles the work for no new information. Nothing about the
/// contents is exposed — the type exists to be handed back in.
public struct ANSIRowCells: Sendable {
    /// The scalar drawn at each column — exactly one per column, and exactly
    /// one scalar per character, because a row carrying anything that combines
    /// or claims more than one cell is declined outright.
    ///
    /// Scalars rather than `Character`s so the per-column comparison is a
    /// `UInt32` compare with no reference counting, and so the walk that builds
    /// this never has to segment the row into grapheme clusters.
    private var cells: [Unicode.Scalar] = []

    /// Which entry of ``styles`` is in force at each column.
    private var styleRun: [Int] = []

    /// The distinct styles the row passes through, in the order it reaches
    /// them. Indices into this, rather than a style per column: a row has a
    /// handful of runs and a hundred-odd columns.
    private var styles: [SGRState] = []

    /// Takes a built row apart, or returns `nil` when its columns cannot be
    /// trusted. See the bail-outs documented on
    /// ``String/ansiCellDiff(replacing:width:mergingGapsUpTo:)``.
    public init?(decomposing line: String, width: Int) {
        guard width > 0 else { return nil }
        cells.reserveCapacity(width)
        styleRun.reserveCapacity(width)
        var state = SGRState()
        styles.append(state)
        var currentRun = 0
        var stateChanged = false

        let scalars = line.unicodeScalars
        var index = scalars.startIndex

        while index < scalars.endIndex {
            let scalar = scalars[index]
            guard scalar.value == 0x1B else {
                // One scalar per column, taken without segmenting the row: a
                // scalar that ``Character/isStandaloneClusterScalar(_:)``
                // accepts is guaranteed to be its own grapheme cluster, so its
                // lone width IS its width. A scalar that might combine is an
                // emoji, a mark, a jamo or a flag — exactly the contentious
                // class this diff declines anyway — so the fast path is the
                // whole path, and the row bails rather than falling back to
                // segmentation. Anything not exactly one cell bails too: zero
                // belongs to no column, and more than one is a claim some
                // terminal may not honour with no way for a span to recover.
                guard Character.isStandaloneClusterScalar(scalar.value),
                    scalar.loneTerminalWidth == 1
                else { return nil }
                if stateChanged {
                    styles.append(state)
                    currentRun = styles.count - 1
                    stateChanged = false
                }
                cells.append(scalar)
                styleRun.append(currentRun)
                index = scalars.index(after: index)
                continue
            }
            var sequence = String.UnicodeScalarView()
            sequence.append(scalars[index])
            index = scalars.index(after: index)
            var final: UInt32 = 0
            // A string-terminated sequence — an OSC 8 hyperlink is the one this
            // framework emits — declines the row outright, and the `nil` is
            // deliberate rather than the fall-through it would otherwise be.
            // A hyperlink is state that spans cells, and a span write lands the
            // cursor in the MIDDLE of a row: writing three changed cells out of
            // a linked run would put them on screen outside the link that
            // covers them, so the run would have to be re-opened per span and
            // closed after it, and the previous frame's link state consulted
            // for every span that is not one. Declining costs a whole-row
            // rewrite on the rows that carry a link and only when they change;
            // `computeChangedRows` still skips a row whose bytes did not move.
            if index < scalars.endIndex,
                String.isStringFamilyIntroducer(scalars[index].value)
            {
                return nil
            }
            if index < scalars.endIndex, scalars[index].value == 0x5B {  // '['
                sequence.append(scalars[index])
                index = scalars.index(after: index)
                while index < scalars.endIndex, String.isCSIBodyByte(scalars[index].value) {
                    sequence.append(scalars[index])
                    index = scalars.index(after: index)
                }
                if index < scalars.endIndex, String.isCSIFinalByte(scalars[index].value) {
                    final = scalars[index].value
                    sequence.append(scalars[index])
                    index = scalars.index(after: index)
                }
            }
            switch final {
            case 0x6D:  // 'm' — styling, which is what we are here to track
                state.apply(String(sequence))
                stateChanged = true
            case 0x4B where cells.isEmpty:  // 'K' — the erase every row opens with
                break
            default:
                return nil  // a cursor move, or an erase we cannot account for
            }
        }
        guard cells.count == width else { return nil }
    }

    /// What has to be written to turn `previous` into this row, **given the
    /// styling the terminal is already in**. See
    /// ``String/ansiCellDiff(replacing:width:mergingGapsUpTo:)``, whose
    /// documentation this shares.
    ///
    /// `emitted` is the state this pass has left the terminal in — `nil` when
    /// that is not known, which is the only case where a span has to state
    /// itself from a reset. It is updated to whatever these spans leave behind,
    /// so a caller writing row after row can hand it straight back: rows are
    /// written in ascending order with only cursor moves between them, and a
    /// cursor move is not styling. Nothing is written to close the chain — see
    /// ``ANSICellDiff/closingStyling(from:)``, and note that a caller which
    /// writes anything else between rows must close it itself.
    public func diff(
        replacing previous: Self, mergingGapsUpTo gap: Int, continuing emitted: inout SGRState?
    ) -> ANSICellDiff {
        let width = cells.count
        guard previous.cells.count == width else { return .wholeLine }

        var differs = [Bool](repeating: false, count: width)
        var any = false
        // Style comparisons repeat for every column of a run, so the last
        // answer is kept: a row passes through a handful of distinct styles, not
        // one per cell. Two answers per pair, because what counts as the same
        // styling depends on whether the cell has a glyph in it —
        // ``SGRState/paintsBlankCellsIdentically(to:)``.
        var lastPair = (-1, -1)
        var lastPairEqual = true
        var lastPairBlankEqual = true
        for column in 0..<width {
            if cells[column] != previous.cells[column] {
                differs[column] = true
                any = true
                continue
            }
            let pair = (styleRun[column], previous.styleRun[column])
            if pair != lastPair {
                lastPair = pair
                lastPairEqual = styles[pair.0] == previous.styles[pair.1]
                lastPairBlankEqual =
                    lastPairEqual
                    || styles[pair.0].paintsBlankCellsIdentically(to: previous.styles[pair.1])
            }
            // A space shows only what its styling PAINTS, which is much less
            // than what its styling says. Most of a terminal UI is blank cells
            // carrying a foreground colour nobody can see.
            let same = cells[column] == " " ? lastPairBlankEqual : lastPairEqual
            if !same {
                differs[column] = true
                any = true
            }
        }
        guard any else { return .identical }
        return .spans(
            spans(covering: differs, width: width, mergingGapsUpTo: gap, emitted: &emitted))
    }

    /// The runs to write, from the columns that differ: consecutive differing
    /// columns, with runs less than `gap` apart joined into one.
    private func spans(
        covering differs: [Bool], width: Int, mergingGapsUpTo gap: Int, emitted: inout SGRState?
    ) -> [ANSICellSpan] {
        var bounds: [(lower: Int, upper: Int)] = []
        var column = 0
        while column < width {
            guard differs[column] else {
                column += 1
                continue
            }
            var upper = column
            var probe = column
            while probe < width {
                if differs[probe] {
                    upper = probe
                } else if probe - upper > gap {
                    break
                }
                probe += 1
            }
            bounds.append((column, upper))
            column = upper + 1
        }

        var spans: [ANSICellSpan] = []
        spans.reserveCapacity(bounds.count)
        // Spans are written back to back with only cursor moves between them,
        // and a cursor move is not styling — so the terminal's state carries
        // from one to the next and each opens by saying only what changed. The
        // caller's `emitted` extends that across rows for the same reason; only
        // a state nobody has established has to be stated from a reset.
        for (lower, upper) in bounds {
            var content = ""
            var run = -1
            for column in lower...upper {
                if styleRun[column] != run {
                    run = styleRun[column]
                    let style = styles[run]
                    if let emitted {
                        content += style.rendered(changingFrom: emitted)
                    } else {
                        content += style.isDefault
                            ? "\u{1B}[0m" : "\u{1B}[0;" + style.parameters + "m"
                    }
                    emitted = style
                }
                content.unicodeScalars.append(cells[column])
            }
            spans.append(ANSICellSpan(column: lower, content: content))
        }
        return spans
    }
}
