//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameDiffWriter.swift
//
//  Created by LAYERED.work
//  License: MIT  only the lines that changed since the previous frame.
//

// MARK: - Frame Diff Writer

/// Compares rendered frames and writes only changed lines to the terminal.
///
/// `FrameDiffWriter` is the core of TUIKit's render optimization. Instead
/// of rewriting every terminal line on every frame, it stores the previous
/// frame's output and only writes lines that actually differ.
///
/// For a mostly-static UI (e.g. a menu with one animating spinner), this
/// reduces terminal writes from ~50 lines per frame to just 1–3 lines
/// (~94% reduction).
///
/// ## Usage
///
/// ```swift
/// let writer = FrameDiffWriter()
///
/// // Each frame:
/// let outputLines = writer.buildOutputLines(buffer: buffer, ...)
/// writer.writeContentDiff(newLines: outputLines, terminal: terminal, startRow: 1)
///
/// // On terminal resize:
/// writer.invalidate()
/// ```
@MainActor
final class FrameDiffWriter {
    /// The previous frame's content lines (terminal-ready strings with ANSI codes).
    private var previousContentLines: [String] = []

    /// The previous frame's status bar lines.
    private var previousStatusBarLines: [String] = []

    /// The previous frame's app header lines.
    private var previousAppHeaderLines: [String] = []

}

// MARK: - Internal API

extension FrameDiffWriter {
    /// Converts a ``FrameBuffer`` into terminal-ready output lines.
    ///
    /// Each output line begins with the background color followed by `ESC[2K`
    /// (Erase Entire Line). This fills the terminal line with the app background
    /// before any content is drawn, preventing stale content from previous pages
    /// from showing through when `strippedLength` miscalculates padding.
    ///
    /// This is a **pure function** — no side effects.
    ///
    /// - Parameters:
    ///   - buffer: The rendered frame buffer.
    ///   - terminalWidth: The terminal width in characters.
    ///   - terminalHeight: The number of rows to fill.
    ///   - bgCode: The ANSI background color code.
    ///   - reset: The ANSI reset code.
    /// - Returns: An array of terminal-ready strings, one per row.
    func buildOutputLines(
        buffer: FrameBuffer,
        terminalWidth: Int,
        terminalHeight: Int,
        bgCode: String,
        reset: String
    ) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(terminalHeight)

        let eraseLine = "\u{1B}[2K"
        let emptyLine = bgCode + eraseLine + reset

        for row in 0..<terminalHeight {
            if row < buffer.height {
                // Clip first so over-wide content (a layout that does not
                // shrink to fit a narrower terminal) cannot wrap past the
                // right edge.  Cursor compensation is applied AFTER clipping
                // so any CUF/CUB sequences are scoped to characters that
                // actually survive the clip.
                let clipped = buffer.lines[row].ansiAwarePrefixForTerminalApp(visibleCount: terminalWidth)
                let line = clipped.withTerminalAppCursorCompensation()
                let lineWithBg = line.replacingOccurrences(of: reset, with: reset + bgCode)
                let padding = max(0, terminalWidth - line.strippedLength)
                let paddedLine = bgCode + eraseLine + lineWithBg + String(repeating: " ", count: padding) + reset
                lines.append(paddedLine)
            } else {
                lines.append(emptyLine)
            }
        }

        return lines
    }

    /// Compares new content lines with the previous frame and writes only changed lines.
    func writeContentDiff(
        newLines: [String],
        terminal: any TerminalProtocol,
        startRow: Int,
        terminalWidth: Int,
        bgCode: String,
        reset: String
    ) {
        let changedRows = writeDiff(newLines: newLines, previousLines: previousContentLines, terminal: terminal, startRow: startRow)
        repaintRightEdge(
            changedRows: changedRows,
            in: newLines,
            terminal: terminal,
            startRow: startRow,
            terminalWidth: terminalWidth,
            bgCode: bgCode,
            reset: reset
        )
        previousContentLines = newLines
    }

    /// Compares new status bar lines with the previous frame and writes only changed lines.
    func writeStatusBarDiff(
        newLines: [String],
        terminal: any TerminalProtocol,
        startRow: Int,
        terminalWidth: Int,
        bgCode: String,
        reset: String
    ) {
        let changedRows = writeDiff(newLines: newLines, previousLines: previousStatusBarLines, terminal: terminal, startRow: startRow)
        repaintRightEdge(
            changedRows: changedRows,
            in: newLines,
            terminal: terminal,
            startRow: startRow,
            terminalWidth: terminalWidth,
            bgCode: bgCode,
            reset: reset
        )
        previousStatusBarLines = newLines
    }

    /// Compares new app header lines with the previous frame and writes only changed lines.
    func writeAppHeaderDiff(
        newLines: [String],
        terminal: any TerminalProtocol,
        startRow: Int,
        terminalWidth: Int,
        bgCode: String,
        reset: String
    ) {
        let changedRows = writeDiff(newLines: newLines, previousLines: previousAppHeaderLines, terminal: terminal, startRow: startRow)
        repaintRightEdge(
            changedRows: changedRows,
            in: newLines,
            terminal: terminal,
            startRow: startRow,
            terminalWidth: terminalWidth,
            bgCode: bgCode,
            reset: reset
        )
        previousAppHeaderLines = newLines
    }

    /// Invalidates all cached previous frames, forcing a full repaint on the next render.
    func invalidate() {
        previousContentLines = []
        previousStatusBarLines = []
        previousAppHeaderLines = []
    }

    /// Computes which row indices have changed between two frames.
    ///
    /// Core diff algorithm, extracted as a static pure function for testability.
    static func computeChangedRows(newLines: [String], previousLines: [String]) -> [Int] {
        var changedRows: [Int] = []
        for row in 0..<newLines.count {
            if row >= previousLines.count || previousLines[row] != newLines[row] {
                changedRows.append(row)
            }
        }
        return changedRows
    }
}

// MARK: - Private Helpers

extension FrameDiffWriter {
    /// Writes only the lines that differ between two frames.
    ///
    /// - Returns: The row indices that were actually written (needed by
    ///   ``repaintRightEdge`` to scope its workaround to only changed rows).
    @discardableResult
    fileprivate func writeDiff(newLines: [String], previousLines: [String], terminal: any TerminalProtocol, startRow: Int) -> [Int] {
        let changedRows = Self.computeChangedRows(newLines: newLines, previousLines: previousLines)

        for row in changedRows {
            terminal.moveCursor(toRow: startRow + row, column: 1)
            terminal.write(newLines[row])
        }

        // Clear excess old lines when the previous frame had more rows.
        // Each output line already contains ESC[2K (from buildOutputLines),
        // but these extra rows have no corresponding new line, so we erase
        // them explicitly with the terminal's default background.
        if previousLines.count > newLines.count {
            let eraseEntireLine = "\u{1B}[2K"
            for row in newLines.count..<previousLines.count {
                terminal.moveCursor(toRow: startRow + row, column: 1)
                terminal.write(eraseEntireLine)
            }
        }

        return changedRows
    }

    /// Workaround for a Terminal.app rendering quirk: when a skin-tone-
    /// modified emoji (e.g. 🤙🏽 = U+1F919 U+1F3FD) appears on a line that
    /// fills to the terminal's right edge, Terminal.app leaves the last 2
    /// cells of that row at the default terminal background. They cannot be
    /// repainted by normal in-line output (the emoji apparently consumes 2
    /// phantom cells of line budget that `strippedLength` doesn't track,
    /// causing the line to wrap and the cursor to end up on the next row).
    ///
    /// The fix is to reposition the cursor by absolute (row, column) and
    /// emit `ESC[K` with the background colour active. Only applied to rows
    /// that were actually written this frame — it's only 2 cells of overdraw
    /// per changed row.
    fileprivate func repaintRightEdge(
        changedRows: [Int],
        in lines: [String],
        terminal: any TerminalProtocol,
        startRow: Int,
        terminalWidth: Int,
        bgCode: String,
        reset: String
    ) {
        guard terminalWidth > 1 else { return }
        // Terminal.app has a cluster of right-edge rendering bugs triggered by
        // any emoji whose glyph width and cursor advance differ — skin-tone
        // sequences (phantom-cell budget) and VS-16 pictographic emoji (cursor
        // under-advance).  Both produce phantom cells at the right edge that
        // sit at the default terminal background instead of the app's.
        //
        // Cursor compensation in `withTerminalAppCursorCompensation` (CUF for
        // VS-16, CUB for skin-tone) keeps the post-emoji cursor in sync, so on
        // rows that don't contain such emoji the right edge is already painted
        // correctly and a blanket repaint would be destructive — at narrower
        // widths the line is clipped and a wide character (e.g. CJK or a 2-cell
        // emoji like 🥳) often straddles the boundary, and erasing the last 2
        // cells destroys its right half.  So we restrict the repaint to rows
        // whose cursor compensation actually injected a sequence.
        //
        // Two passes are used so that borders and right-aligned text written by
        // the view system are not permanently destroyed:
        //   1. ESC[K to erase/unlock the cells (with the bg colour active so
        //      they at least land on the correct background if step 2 fails).
        //   2. Re-write the actual content that belongs there (border, text,
        //      or background space) using the accumulated SGR context so the
        //      colours and styles are correct.
        let repaintCol = terminalWidth - 1  // 1-indexed; covers last 2 cells
        let splitAt    = terminalWidth - 2  // visible-cell offset of repaintCol

        for row in changedRows where row < lines.count {
            guard lines[row].containsTerminalAppCursorAdvanceQuirk else { continue }

            // Pass 1: erase with bg to unlock any phantom cells.
            terminal.moveCursor(toRow: startRow + row, column: repaintCol)
            terminal.write(bgCode + "\u{1B}[K" + reset)

            // Pass 2: re-write the correct content now that the cells are unlocked.
            // Use ansiSGRContextAndCleanSuffix (not ansiSGRContextAndSuffix) so that
            // any CUF sequences injected by withTerminalAppCursorCompensation are
            // stripped from the suffix — writing a CUF at repaintCol would push the
            // cursor past the terminal edge, wrapping subsequent characters to the
            // next row and causing content to appear in the wrong place.
            if let suffix = lines[row].ansiSGRContextAndCleanSuffix(from: splitAt) {
                terminal.moveCursor(toRow: startRow + row, column: repaintCol)
                terminal.write(suffix)
            }
        }
    }
}
