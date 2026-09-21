//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+ANSIRunSlicing.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Cutting a row into runs, once

extension String {

    /// Cuts this row into consecutive runs and hands each piece to `receive`,
    /// in one pass over the row.
    ///
    /// Each piece is exactly what ``ansiAwareSlice(visibleStart:visibleCount:)``
    /// returns for that run, and `ANSIRunSlicingTests` pins it against that
    /// function over a corpus of styled, linked and wide-glyph rows rather than
    /// restating the rules here. What differs is the cost. The slice function
    /// rebuilds this row's whole segment list and rescans it from the first byte
    /// on every call, so cutting a row into *n* runs walked it *n* times — and a
    /// gradient background cuts at every colour change, which for a smooth ramp
    /// is one run per column. (Measured on the `gradients` stress page:
    /// `ansiAwareSlice` and `ansiSegments` were 14% of the frame between them.)
    ///
    /// The runs are described by a count and a width function rather than an
    /// array, and the pieces are handed over one at a time rather than returned
    /// together, so a caller that consumes each piece as it arrives — painting
    /// it and appending it to a row — allocates nothing per row but its own
    /// output. Runs tile the row from column zero: these are widths, not
    /// positions, and a width of zero yields an empty piece, as the slice
    /// function does for a zero-cell window.
    ///
    /// - Parameters:
    ///   - runCount: How many runs the row is cut into.
    ///   - width: The cell width of the run at an index, left to right.
    ///   - receive: Called once per run, in order, with the run's index and its
    ///     piece of this row.
    public func ansiAwareSlicedRuns(
        runCount: Int,
        width: (Int) -> Int,
        receive: (Int, String) -> Void
    ) {
        guard runCount > 0 else { return }
        // Two shapes are the slice function's own and are delegated rather than
        // reproduced: a single run (nothing to amortise), and a row no wider
        // than the run starting at column zero — where that function returns the
        // whole string verbatim, trailing sequences and an unclosed hyperlink
        // included, and every later piece is empty anyway. (The run at column
        // zero is the first one with any width; leading empty runs do not move
        // the start.)
        var firstPositive = 0
        for index in 0..<runCount where width(index) > 0 {
            firstPositive = width(index)
            break
        }
        if runCount == 1 || strippedLength <= firstPositive {
            var start = 0
            for index in 0..<runCount {
                let runWidth = width(index)
                receive(index, ansiAwareSlice(visibleStart: start, visibleCount: runWidth))
                start += max(0, runWidth)
            }
            return
        }

        // A piece is `the style in force where it starts` + `what it holds` +
        // `what it owes an open hyperlink`. The walk is in column order, so the
        // first is a snapshot taken as the piece begins and the last is the link
        // scan's state as the walk leaves it — which is why one pass can answer
        // for every piece, and why each can be handed over the moment its last
        // column goes by.
        var scratch = ""
        var index = 0
        var start = 0
        var end = max(0, width(0))
        var entered = false
        var prefix = ""
        var styleSoFar = ""
        var link = HyperlinkScan()
        var visible = 0

        func finishPiece() {
            receive(index, width(index) > 0 ? prefix + scratch + link.closingIfOpen : "")
            index += 1
            scratch.removeAll(keepingCapacity: true)
            entered = false
            prefix = styleSoFar
            start = end
            end = start + (index < runCount ? max(0, width(index)) : 0)
        }
        /// Hands over every piece the walk has now passed the end of.
        func finishPieces(passing columnNow: Int) {
            while index < runCount, end <= columnNow { finishPiece() }
        }
        /// The hyperlink in force is restated once, as a piece is entered — the
        /// same rule the single-slice walk applies, and for the same reason: the
        /// columns that opened it are on the other side of the cut.
        func enterPiece() {
            guard !entered else { return }
            entered = true
            scratch += link.reopening
        }

        forEachANSISegment { segment in
            finishPieces(passing: visible)
            // Every piece is done: the two loops after the walk are then no-ops
            // (both are `while index < runCount`), so stopping here and falling
            // out are the same thing.
            guard index < runCount else { return false }
            switch segment {
            case .ansi(let sequence, let isSGR):
                if start <= visible, visible < end {
                    enterPiece()
                    scratch += sequence
                }
                if isSGR {
                    styleSoFar += sequence
                } else {
                    link.note(sequence)
                }
            case .visible(let character):
                let charWidth = character.terminalWidth
                let charEnd = visible + charWidth
                while index < runCount, start < charEnd {
                    if end > visible {
                        enterPiece()
                        if visible >= start && charEnd <= end {
                            scratch.append(character)
                        } else {
                            // Straddles this piece's edge: its in-window cells
                            // are blanked, so the piece is the width it claims.
                            scratch += String(
                                repeating: " ", count: min(charEnd, end) - max(visible, start))
                        }
                    }
                    guard end <= charEnd else { break }
                    finishPiece()
                }
                visible = charEnd
            }
            return true
        }
        finishPieces(passing: visible)
        // Whatever is left starts past the end of the row: all style, no cells.
        while index < runCount { finishPiece() }
    }

    /// The pieces this row cuts into at the given run widths, gathered up.
    ///
    /// The array form of ``ansiAwareSlicedRuns(runCount:width:receive:)`` — for
    /// callers that want the pieces rather than a stream of them, and the form
    /// the equivalence test states its property over.
    ///
    /// - Parameter runWidths: The cell width of each run, left to right.
    /// - Returns: One piece per run, in the same order.
    public func ansiAwareSlices(runWidths: [Int]) -> [String] {
        var pieces: [String] = []
        pieces.reserveCapacity(runWidths.count)
        ansiAwareSlicedRuns(
            runCount: runWidths.count,
            width: { runWidths[$0] },
            receive: { _, piece in pieces.append(piece) })
        return pieces
    }
}
