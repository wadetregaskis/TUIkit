//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationStencil.swift
//
//  A stored buffer's animated cells cut out of its lines, so the buffer can be
//  drawn at a later instant by putting that instant's frames where the drawn
//  ones were, instead of by drawing the views that made it.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The stencil

/// A buffer's lines cut around the frame each of its ``AnimatedCellRun``s was
/// drawn at, so the buffer can be drawn at another instant by putting each run's
/// frame for that instant back in the cut.
///
/// ## Why
///
/// A memoized subtree whose only motion is in runs — a ``FrameBuffer`` holding a
/// spinner — is stored, and its buffer shows each run at the frame of the instant
/// it was drawn. Served later as it stands, it would put that old frame back on
/// screen, so a lookup misses once a run has moved on, and the whole subtree is
/// drawn again to change one cell. A row of a job queue is walked, measured and
/// composed about once per step of its spinner, and that was the price of every
/// memoized row with a moving spinner. The run already carries every frame it
/// can show, so the one thing the redraw finds out is which of them to write;
/// a stencil writes it without the redraw.
///
/// ## What "the same as a redraw" rests on
///
/// A stamped buffer is served where a fresh render would have been, so it has to
/// be that render, byte for byte — `TUIKIT_VERIFY_RENDER_MEMO` compares bytes, and
/// so does every line cache after it. A splice in the style of the run loop's
/// replay (``FrameBuffer/patchingAnimatedCells(in:with:atColumn:width:)``) is right
/// on screen and wrong in bytes: it restates the styling either side of the cut.
/// So a stencil is cut only where putting another frame in the cut IS the fresh
/// render, and ``init(cutting:drawnAt:)`` returns `nil` everywhere else, which
/// leaves the buffer to miss as it did before stencils:
///
/// - **The drawn frame is in the line, whole and unchanged**, starting at the
///   run's column: its exact bytes, on grapheme boundaries, after exactly
///   `offsetX` cells. So nothing between the view that drew the run and the memo
///   that stored the buffer rewrote those bytes — a background restated after a
///   reset inside the frame, a colour effect, a fade — or a different frame from
///   the one the run's clock names was drawn there.
/// - **Every frame is the drawn one with other glyphs.** The same escapes, byte for
///   byte, in the same places, and in each place a glyph of the same width that is
///   blank exactly where the drawn one is. Whatever left the drawn frame's bytes
///   alone did so on the strength of its escapes and its cells' widths and kinds,
///   which every frame shares, so it leaves each of them alone too. A spinner is
///   this: one colour, a different glyph each frame. A breath, a sweep, a blinking
///   caret — frames whose colours or attributes differ — is not, and misses.
/// - **No run owes a per-frame alpha, and no opacity region cycles.** Each records
///   which frame or phase the LINES were drawn at (``AnimatedRunAlpha``'s drawn
///   index, a cycling ``OpacityRegion/opacity``), so moving the lines on would
///   leave the record behind.
/// - **The runs' cuts do not overlap.**
///
/// Runs whose frames are all one picture are left out: nothing about them moves.
///
/// What it does not check, and cannot, is that the subtree's only dependence on
/// time is its runs. That premise is the stored buffer's, not the stencil's: the
/// memo serves a buffer whose runs show what they showed on exactly that ground.
package struct AnimationStencil: Sendable {
    /// One line with runs on it, cut around each of their drawn frames.
    struct Row: Sendable {
        /// The line's row in the buffer.
        let row: Int
        /// The line between the cuts, left to right: one more piece than runs.
        let pieces: [Substring]
        /// Each cut's run, as an index into the buffer's ``FrameBuffer/animatedCells``,
        /// left to right.
        let runs: [Int]
        /// The frame index each of those runs was drawn at.
        let drawn: [Int]
    }

    /// Every line a run moves on, in row order.
    let rows: [Row]

    /// Cuts `buffer`'s lines around its runs as they were drawn at `instant`, or
    /// `nil` when another frame in a cut would not be the buffer drawn afresh —
    /// see the conditions above.
    package init?(cutting buffer: FrameBuffer, drawnAt instant: AnimationInstant) {
        guard !buffer.animatedCells.isEmpty,
            !buffer.opacityRegions.contains(where: { $0.cycle != nil })
        else { return nil }
        var cutsByRow: [Int: [(run: Int, drawn: Int, range: Range<String.Index>)]] = [:]
        for (index, run) in buffer.animatedCells.enumerated() {
            guard run.alpha == nil else { return nil }
            let drawn = run.index(atElapsed: instant.elapsed(on: run.clock))
            let frame = run.frame(atIndex: drawn)
            guard run.frames.contains(where: { $0 != frame }) else { continue }
            guard buffer.lines.indices.contains(run.offsetY),
                Self.everyFrame(of: run, isARestyling: frame),
                let range = Self.cut(of: frame, atColumn: run.offsetX, in: buffer.lines[run.offsetY])
            else { return nil }
            cutsByRow[run.offsetY, default: []].append((index, drawn, range))
        }
        guard !cutsByRow.isEmpty else { return nil }
        var rows: [Row] = []
        rows.reserveCapacity(cutsByRow.count)
        for row in cutsByRow.keys.sorted() {
            let line = buffer.lines[row]
            let cuts = cutsByRow[row, default: []].sorted { $0.range.lowerBound < $1.range.lowerBound }
            var pieces: [Substring] = []
            pieces.reserveCapacity(cuts.count + 1)
            var from = line.startIndex
            for cut in cuts {
                guard cut.range.lowerBound >= from else { return nil }  // two runs in one cut
                pieces.append(line[from..<cut.range.lowerBound])
                from = cut.range.upperBound
            }
            pieces.append(line[from...])
            rows.append(Row(row: row, pieces: pieces, runs: cuts.map(\.run), drawn: cuts.map(\.drawn)))
        }
        self.rows = rows
    }

    /// `buffer` — the buffer this stencil was cut from — as drawn at `instant`: each
    /// line whose runs show another picture there rebuilt from its pieces and those
    /// pictures, every other line and everything else about the buffer as it was.
    /// `nil` when every run still shows the picture it was drawn with, so the buffer
    /// itself is the answer and nothing was built.
    package func stamping(_ buffer: FrameBuffer, at instant: AnimationInstant) -> FrameBuffer? {
        var lines: [String]?
        let runs = buffer.animatedCells
        for row in rows {
            // Which frame each run shows now, and whether any is a different picture.
            var moved = false
            for (cut, runIndex) in row.runs.enumerated() {
                let run = runs[runIndex]
                let now = run.index(atElapsed: instant.elapsed(on: run.clock))
                if now != row.drawn[cut], run.frames[now] != run.frames[row.drawn[cut]] {
                    moved = true
                    break
                }
            }
            guard moved else { continue }
            let old = buffer.lines[row.row]
            var line = ""
            line.reserveCapacity(old.utf8.count)
            line.append(contentsOf: row.pieces[0])
            for (cut, runIndex) in row.runs.enumerated() {
                let run = runs[runIndex]
                line.append(run.frame(atElapsed: instant.elapsed(on: run.clock)))
                line.append(contentsOf: row.pieces[cut + 1])
            }
            if lines == nil { lines = buffer.lines }
            lines?[row.row] = line
        }
        guard let lines else { return nil }
        // Every frame of a cut run is as wide as the drawn one, cell for cell, so the
        // buffer's widths are the stamped lines' too.
        return buffer.replacingLines(
            lines, width: buffer.width, uniformWidth: buffer.linesAreUniformWidth,
            lineWidths: buffer.lineWidths)
    }
}

// MARK: - The conditions

extension AnimationStencil {
    /// One piece of a styled string with its glyphs taken out: an escape, byte for
    /// byte, or a cell of some width that is blank or is not.
    private enum Stroke: Equatable {
        case escape(String)
        case cell(width: Int, blank: Bool)

        init(_ segment: ANSISegment) {
            switch segment {
            case .ansi(let sequence, _): self = .escape(sequence)
            case .visible(let character):
                self = .cell(width: character.terminalWidth, blank: character.isWhitespace)
            }
        }
    }

    /// Whether every frame of `run` is `drawn` with other glyphs in its cells: the
    /// same escapes in the same places, and in each place a glyph as wide as the
    /// drawn one's, blank exactly where it is blank. The drawn frame is as wide as the
    /// run, too, so a stamped line is as wide as the line it replaces.
    private static func everyFrame(of run: AnimatedCellRun, isARestyling drawn: String) -> Bool {
        var strokes: [Stroke] = []
        var width = 0
        drawn.forEachANSISegment { segment in
            let stroke = Stroke(segment)
            if case .cell(let cells, _) = stroke { width += cells }
            strokes.append(stroke)
            return true
        }
        guard width == run.width else { return false }
        return run.frames.allSatisfy { frame in
            guard frame != drawn else { return true }
            var next = 0
            let reachedTheEnd = frame.forEachANSISegment { segment in
                guard next < strokes.count, Stroke(segment) == strokes[next] else { return false }
                next += 1
                return true
            }
            return reachedTheEnd && next == strokes.count
        }
    }

    /// Where `frame` sits in `line` with its first cell at column `column`: the first
    /// place its bytes appear whole, beginning and ending on grapheme boundaries and
    /// outside any escape sequence, with exactly `column` cells before it. `nil` when
    /// there is none.
    ///
    /// Outside an escape, because a frame with no escape of its own — a bare glyph
    /// under `NO_COLOR`, or an `.animatedCells` run of plain characters — can match
    /// bytes inside one: the `0` of a reset's `ESC[0m`, the `\` that ends a
    /// hyperlink's `ESC]8;;ESC\`. Every ASCII byte is a grapheme boundary and an
    /// escape adds no cells, so neither of the other tests rejects such a place, and
    /// stamping there wrote over the escape: an unterminated hyperlink, a bold never
    /// reset, and a glyph that never moved.
    private static func cut(of frame: String, atColumn column: Int, in line: String) -> Range<String.Index>? {
        let needle = Array(frame.utf8)
        guard !needle.isEmpty else { return nil }
        let bytes = Array(line.utf8)
        let found = offsets(of: needle, in: bytes)
        guard !found.isEmpty else { return nil }
        let outside = outsideEscapes(bytes)
        let utf8 = line.utf8
        for offset in found where outside[offset] && outside[offset + needle.count] {
            let start = utf8.index(utf8.startIndex, offsetBy: offset)
            let end = utf8.index(start, offsetBy: needle.count)
            guard start.samePosition(in: line) != nil, end.samePosition(in: line) != nil,
                String(line[..<start]).strippedLength == column
            else { continue }
            return start..<end
        }
        return nil
    }

    /// For each position between the bytes of `bytes` — before the first through after
    /// the last — whether it lies outside an escape sequence: where a cut may begin or
    /// end. A position at an ESC is outside (a frame may begin with its own escape);
    /// one after the ESC and up to the sequence's last byte is inside. CSI ends at its
    /// final byte (0x40–0x7E); OSC, DCS, SOS, PM and APC at BEL or ST; any other ESC
    /// takes one byte more.
    private static func outsideEscapes(_ bytes: [UInt8]) -> [Bool] {
        var outside = [Bool](repeating: true, count: bytes.count + 1)
        var index = 0
        while index < bytes.count {
            guard bytes[index] == 0x1B, index + 1 < bytes.count else {
                index += 1
                continue
            }
            var end = index + 2
            switch bytes[index + 1] {
            case 0x5B:
                // Parameters and intermediates, then one final byte.
                var cursor = index + 2
                while cursor < bytes.count, !(0x40...0x7E).contains(bytes[cursor]) { cursor += 1 }
                end = cursor + 1
            case 0x5D, 0x50, 0x58, 0x5E, 0x5F:
                while end < bytes.count {
                    if bytes[end] == 0x07 {
                        end += 1
                        break
                    }
                    if bytes[end] == 0x1B, end + 1 < bytes.count, bytes[end + 1] == 0x5C {
                        end += 2
                        break
                    }
                    end += 1
                }
            default:
                break
            }
            end = min(end, bytes.count)
            for position in (index + 1)..<end { outside[position] = false }
            index = end
        }
        return outside
    }

    /// Every byte offset at which `needle` occurs in `haystack`, in order —
    /// overlapping occurrences included.
    private static func offsets<Bytes: RandomAccessCollection<UInt8>>(
        of needle: [UInt8], in haystack: Bytes
    ) -> [Int] where Bytes.Index == Int {
        guard let first = needle.first, haystack.count >= needle.count else { return [] }
        var found: [Int] = []
        var offset = haystack.startIndex
        while offset <= haystack.endIndex - needle.count {
            if haystack[offset] == first, haystack[offset..<(offset + needle.count)].elementsEqual(needle) {
                found.append(offset - haystack.startIndex)
            }
            offset += 1
        }
        return found
    }
}
