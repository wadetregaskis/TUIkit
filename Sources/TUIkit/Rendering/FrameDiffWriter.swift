//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameDiffWriter.swift
//
//  Created by LAYERED.work
//  License: MIT  only the lines that changed since the previous frame.
//

import Foundation

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
    /// Whether the host terminal is macOS Terminal.app.
    ///
    /// Terminal.app has emoji cursor-advance and right-edge phantom-cell bugs
    /// that the output path works around (see ``buildOutputLines`` and
    /// ``repaintRightEdge``). EVERY other terminal — iTerm2, kitty, Alacritty,
    /// WezTerm, VS Code's terminal, and all Linux/BSD consoles — advances the
    /// cursor correctly, so applying those workarounds there does not merely
    /// waste time, it CORRUPTS output: it injects spurious `CUF` cursor moves
    /// (shifting everything after an emoji one cell right) and strips
    /// Fitzpatrick skin-tone modifiers. Detected once from `TERM_PROGRAM`;
    /// injectable so tests exercise both paths deterministically regardless of
    /// which terminal runs them.
    private let isAppleTerminal: Bool

    /// The previous frame's content lines (terminal-ready strings with ANSI codes).
    private var previousContentLines: [String] = []

    /// The previous frame's status bar lines.
    private var previousStatusBarLines: [String] = []

    /// The previous frame's app header lines.
    private var previousAppHeaderLines: [String] = []

    /// The three independently-diffed terminal regions. Each keeps its own
    /// previous built lines (above) and its own background colour, so the
    /// incremental builder's reuse state is tracked per region.
    enum OutputRegion {
        case content, statusBar, appHeader
    }

    /// The parameters that feed every built line. If any differ from the
    /// previous frame, no cached line can be reused (it would be stale).
    private struct LineParams: Equatable {
        let width: Int
        let bgCode: String
        let reset: String
    }

    /// Snapshot of one region's raw buffer input + build parameters from the
    /// previous frame, used by `buildOutputLines(…reusingFor:)` to decide which
    /// rows can reuse their previously-built line. `rawLines` is the buffer's
    /// own array (an O(1) copy-on-write reference, not a per-element copy).
    private struct LineReuseCache {
        var rawLines: [String] = []
        var rawHeight = 0
        var params: LineParams?
    }

    private var contentReuse = LineReuseCache()
    private var statusBarReuse = LineReuseCache()
    private var appHeaderReuse = LineReuseCache()

    /// Number of rows actually (re)built by the most recent
    /// `buildOutputLines(…reusingFor:)` call; the remainder were reused from the
    /// previous frame. Exposed for tests and profiling.
    private(set) var rowsBuiltInLastBuild = 0

    init(isAppleTerminal: Bool = FrameDiffWriter.detectAppleTerminal()) {
        self.isAppleTerminal = isAppleTerminal
    }

    /// `true` only when running under macOS Terminal.app
    /// (`TERM_PROGRAM == "Apple_Terminal"`). Compile-time `false` off macOS,
    /// where Terminal.app cannot run.
    static func detectAppleTerminal() -> Bool {
        #if os(macOS)
        return ProcessInfo.processInfo.environment["TERM_PROGRAM"] == "Apple_Terminal"
        #else
        return false
        #endif
    }
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
        let eraseLine = "\u{1B}[2K"
        let emptyLine = bgCode + eraseLine + reset

        var lines: [String] = []
        lines.reserveCapacity(terminalHeight)
        for row in 0..<terminalHeight {
            lines.append(buildLine(
                raw: row < buffer.height ? buffer.lines[row] : nil,
                terminalWidth: terminalWidth, bgCode: bgCode, reset: reset,
                eraseLine: eraseLine, emptyLine: emptyLine
            ))
        }
        return lines
    }

    /// Incremental twin of the pure builder that reuses the previous frame's
    /// built line for any row whose raw buffer content — and the render
    /// parameters (width, background, reset) — are unchanged.
    ///
    /// A built line is a pure function of `(rawLine, width, bgCode, reset,
    /// isAppleTerminal)`, so when all of those match the previous frame the
    /// previously-built line IS exactly what the builder would produce: output
    /// is byte-identical to ``buildOutputLines(buffer:terminalWidth:terminalHeight:bgCode:reset:)``.
    /// The downstream `writeXxxDiff` still compares the built lines to decide
    /// what to write, so write behaviour is unchanged; this only skips the
    /// per-line clip / compensation / pad work for rows that did not change —
    /// the win for partial-update frames (a cursor blink, a spinner tick, or a
    /// one-row selection move re-renders the whole screen but changes one row).
    ///
    /// Reuse state is keyed by `region` (each region has its own previous built
    /// lines and background colour). Must be paired every frame with the
    /// matching `writeXxxDiff`, which updates the built-line cache this reads —
    /// as it is in `RenderLoop`.
    func buildOutputLines(
        buffer: FrameBuffer,
        terminalWidth: Int,
        terminalHeight: Int,
        bgCode: String,
        reset: String,
        reusingFor region: OutputRegion
    ) -> [String] {
        let eraseLine = "\u{1B}[2K"
        let emptyLine = bgCode + eraseLine + reset
        let params = LineParams(width: terminalWidth, bgCode: bgCode, reset: reset)

        let previousBuilt = previousLines(for: region)
        let cache = reuseCache(for: region)
        // A row is reusable only when every parameter feeding `buildLine` is
        // unchanged; otherwise the cached built line is stale.
        let canReuse = cache.params == params

        var lines: [String] = []
        lines.reserveCapacity(terminalHeight)
        var builtCount = 0

        for row in 0..<terminalHeight {
            let isEmpty = row >= buffer.height
            let wasEmpty = row >= cache.rawHeight
            let rawUnchanged: Bool
            if isEmpty || wasEmpty {
                rawUnchanged = isEmpty && wasEmpty   // both empty → identical emptyLine
            } else {
                rawUnchanged = row < cache.rawLines.count && cache.rawLines[row] == buffer.lines[row]
            }

            if canReuse, rawUnchanged, row < previousBuilt.count {
                lines.append(previousBuilt[row])
            } else {
                lines.append(buildLine(
                    raw: isEmpty ? nil : buffer.lines[row],
                    terminalWidth: terminalWidth, bgCode: bgCode, reset: reset,
                    eraseLine: eraseLine, emptyLine: emptyLine
                ))
                builtCount += 1
            }
        }

        setReuseCache(
            LineReuseCache(rawLines: buffer.lines, rawHeight: buffer.height, params: params),
            for: region
        )
        rowsBuiltInLastBuild = builtCount
        return lines
    }

    /// Builds one terminal-ready output line from a raw buffer line (`nil` marks
    /// an empty row past the buffer's height). Pure given the writer's
    /// `isAppleTerminal`.
    private func buildLine(
        raw: String?,
        terminalWidth: Int,
        bgCode: String,
        reset: String,
        eraseLine: String,
        emptyLine: String
    ) -> String {
        guard let raw else { return emptyLine }
        // Neutralise any cursor-moving control character (a stray newline /
        // carriage return / tab in a buffer line — e.g. user data with an
        // embedded newline placed verbatim into a table cell) before it reaches
        // the terminal: such a character prints literally and shoves the cursor,
        // drawing outside the row's bounds and corrupting the rows below. A
        // buffer line is one terminal row by contract, so this is the single
        // boundary that guarantees no view can violate it. (No-op, no
        // allocation, for the clean lines that are virtually all of them; and
        // only changed lines are rebuilt here, unchanged ones are reused.)
        let sanitized = raw.sanitizedForTerminalRow()
        // Clip first so over-wide content (a layout that does not shrink to fit
        // a narrower terminal) cannot wrap past the right edge.  Cursor
        // compensation is applied AFTER clipping so any CUF sequences are scoped
        // to characters that actually survive the clip.
        // Terminal.app needs the cursor-aware clip + CUF / skin-tone compensation
        // for its emoji bugs; every other terminal advances correctly, so use the
        // plain clip and leave the line untouched (the compensation would corrupt
        // it there — see isAppleTerminal).
        // The clip returns its visible width (counted while clipping), so the
        // padding below needs no separate `strippedLength` re-scan of `clipped`
        // — which, for a styled line, would take the allocating ANSI-runs path.
        let (clipped, clippedWidth) = isAppleTerminal
            ? sanitized.ansiAwarePrefixForTerminalAppWithWidth(visibleCount: terminalWidth)
            : sanitized.ansiAwarePrefixWithWidth(visibleCount: terminalWidth)
        let compensated = isAppleTerminal
            ? clipped.withTerminalAppCursorCompensation()
            : clipped
        // Native Swift `replacing(_:with:)` — NOT Foundation's
        // `replacingOccurrences`, which bridges to `NSString` and was ~8% of the
        // render loop in a Mode-B (live-app) profile.
        let mainWithBg = compensated.replacing(reset, with: reset + bgCode)
        let padding = max(0, terminalWidth - clippedWidth)
        return bgCode + eraseLine + mainWithBg + String(repeating: " ", count: padding) + reset
    }

    private func previousLines(for region: OutputRegion) -> [String] {
        switch region {
        case .content: return previousContentLines
        case .statusBar: return previousStatusBarLines
        case .appHeader: return previousAppHeaderLines
        }
    }

    private func reuseCache(for region: OutputRegion) -> LineReuseCache {
        switch region {
        case .content: return contentReuse
        case .statusBar: return statusBarReuse
        case .appHeader: return appHeaderReuse
        }
    }

    private func setReuseCache(_ cache: LineReuseCache, for region: OutputRegion) {
        switch region {
        case .content: contentReuse = cache
        case .statusBar: statusBarReuse = cache
        case .appHeader: appHeaderReuse = cache
        }
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
        contentReuse = LineReuseCache()
        statusBarReuse = LineReuseCache()
        appHeaderReuse = LineReuseCache()
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
        // The right-edge phantom-cell repaint is a Terminal.app-only workaround;
        // on every other terminal the main pass already paints the edge.
        guard isAppleTerminal, terminalWidth > 1 else { return }
        // Terminal.app leaves the rightmost 2 cells of a row at the default
        // terminal background whenever the row contains an emoji whose glyph
        // width and cursor advance disagree — VS-16 pictographic emoji
        // (under-advance), or a Fitzpatrick skin-tone cluster whose modifier
        // survived ``withTerminalAppCursorCompensation`` (i.e. it was the
        // last visible character on the line).  ``containsTerminalAppCursorAdvanceQuirk``
        // identifies those rows; everything else has its right edge painted
        // correctly by the main pass.  A blanket repaint would be destructive
        // at narrower widths where a wide character (CJK, 🥳, etc.) straddles
        // the boundary — erasing the last 2 cells would destroy its right half.
        //
        // Two passes so borders and right-aligned text from the view system
        // are not permanently destroyed:
        //   1. ESC[K to erase the cells (with the bg colour active so they
        //      land on the app's background if step 2 fails).
        //   2. Re-write the actual content that belongs there using the
        //      accumulated SGR context so colours and styles are correct.
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
