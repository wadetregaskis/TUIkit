//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameDiffWriter.swift
//
//  Converts FrameBuffers to terminal-ready output lines and writes
//  only the lines that changed since the previous frame.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Frame Diff Writer

/// Compares rendered frames and writes only changed lines to the terminal.
///
/// `FrameDiffWriter` is the core of TUIkit's render optimization. Instead
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
    /// (shifting everything after an emoji one cell right). Detected once from
    /// `TERM_PROGRAM`; injectable so tests exercise both paths
    /// deterministically regardless of which terminal runs them.
    private let isAppleTerminal: Bool

    /// Whether the host terminal is iTerm2, which (in its default width
    /// configuration) renders a Fitzpatrick skin-tone cluster as the base
    /// emoji PLUS a separate 2-cell colour swatch — 4 cells painted where
    /// the column accounting claims 2, shifting the rest of the row right.
    /// Its build path strips the modifiers (falling back to the
    /// generic-yellow base — `String.withSkinToneFallback()`), which
    /// restores the 2-cell claim exactly. Same detection/injection story as
    /// `isAppleTerminal`.
    private let isITerm2: Bool

    /// Whether the host terminal is Ghostty, which advances every composed
    /// emoji class exactly as claimed (alone among the measured terminals)
    /// but under-advances the VS-15 chrome glyphs ⬛︎ / ⬜︎ and Plane-16 PUA
    /// SF Symbols. Its build path injects CUF for just those two —
    /// `String.withGhosttyCursorCompensation()`; no skin-tone strip, which
    /// would needlessly discard the correct merged rendering. Same
    /// detection/injection story as `isAppleTerminal`.
    private let isGhostty: Bool

    /// Whether the host terminal is Warp, which draws Fitzpatrick skin-tone
    /// clusters as base + swatch exactly as iTerm2 does (so it takes the same
    /// `String.withSkinToneFallback()` strip) and under-advances a lone
    /// regional indicator as Terminal.app does (so it takes a CUF). Same
    /// detection/injection story as `isAppleTerminal`.
    private let isWarp: Bool

    /// Whether we are running inside tmux, which is a COMPOSITOR rather than a
    /// renderer: it parses our bytes into its own grid using its own width table
    /// and re-renders that grid to whichever client is attached. So tmux's model
    /// is the one our output has to satisfy, and it wins over any native host
    /// flag — checked first in the dispatch below. Its divergences (SF Symbols,
    /// bare pictographs and lone regional indicators all advance 1 against a
    /// 2-cell claim; BMP-base skin tones over-advance) take the same
    /// strip-then-CUF treatment as iTerm2's. DSR-measured with all four
    /// terminals attached AND with none — identical every time.
    private let isTmux: Bool

    /// Which skin-tone bases the tmux path strips: `.bmpOnly` when every
    /// attached client renders SMP-base tones (Ghostty alone, measured),
    /// `.all` otherwise — Apple Terminal and Warp advance tmux's verbatim
    /// re-emission of 👍🏽 by 4 against tmux's believed 2, shearing the row,
    /// and iTerm2 paints the tone as a broken separate swatch (the same
    /// appearance its native path strips for). Stripping at SOURCE is the one
    /// fix that survives the tmux hop: tmux's grid then holds and re-emits
    /// the toneless cluster.
    ///
    /// Per-frame config, set by `RenderLoop` from the push-refreshed client
    /// capabilities. Safe default (`.all`) so a writer nobody configures
    /// never emits tones a client can't place. Mutable, unlike the host
    /// flags — legitimate against the line-reuse cache only because every
    /// change arrives via the refresher's `onChange`, which fully invalidates
    /// this writer before the next frame is built.
    var tmuxSkinToneBasePlane: String.SkinToneBasePlane = .all

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

        /// What the last *build* produced for each row.
        ///
        /// Deliberately not the diff's `previousXxxLines`, which the reuse used
        /// to read: those are what is ON SCREEN, and an animation replay writes
        /// PATCHED lines there (a run's current frame spliced into the line it
        /// sits on). Reusing one of those as "what the builder would produce"
        /// hands the next render the pulse colour that happened to be showing —
        /// and since it then equals the diff baseline, that row is never written
        /// again. A focus indicator froze mid-breath the moment focus moved
        /// away, because the row it left behind renders the same raw line
        /// focused or not; only its animated run differed.
        var builtLines: [String] = []
    }

    private var contentReuse = LineReuseCache()
    private var statusBarReuse = LineReuseCache()
    private var appHeaderReuse = LineReuseCache()

    /// One region's previous frame taken apart into cells, so a row is
    /// decomposed ONCE: the row this frame diffs as "new" is the row the next
    /// frame diffs as "previous", and doing both sides every frame doubles the
    /// work for no new information.
    ///
    /// Every entry carries the exact string it was built from, so a stale one is
    /// not merely unlikely but impossible. `previousXxxLines = newLines` hands
    /// the same `String` instances back, which makes the check a pointer
    /// comparison in the case that matters; anything that changes what is on
    /// screen behind this cache's back — an animation replay patching a row, a
    /// rebuild, a resize — simply misses and decomposes again.
    private struct CellCache {
        var lines: [String] = []
        var cells: [ANSIRowCells?] = []

        /// Sizes the cache to a frame, dropping entries for rows that no longer
        /// exist and leaving the rest to be validated by string, not by index.
        mutating func fit(to count: Int) {
            if lines.count != count {
                lines = Array(repeating: "", count: count)
                cells = Array(repeating: nil, count: count)
            }
        }

        mutating func remember(_ row: ANSIRowCells, line: String, at index: Int) {
            guard index < cells.count else { return }
            cells[index] = row
            lines[index] = line
        }

        /// The decomposition for `line`, or `nil` when this cache does not hold
        /// one built from exactly that string.
        func cells(matching line: String, at index: Int) -> ANSIRowCells? {
            guard index < cells.count, lines[index] == line else { return nil }
            return cells[index]
        }
    }

    private var contentCells = CellCache()
    private var statusBarCells = CellCache()
    private var appHeaderCells = CellCache()

    /// Number of rows actually (re)built by the most recent
    /// `buildOutputLines(…reusingFor:)` call; the remainder were reused from the
    /// previous frame. Exposed for tests and profiling.
    private(set) var rowsBuiltInLastBuild = 0

    init(
        isAppleTerminal: Bool = TerminalHost.isAppleTerminal,
        isITerm2: Bool = TerminalHost.isITerm2,
        isGhostty: Bool = TerminalHost.isGhostty,
        isWarp: Bool = TerminalHost.isWarp,
        isTmux: Bool = TerminalHost.isTmux
    ) {
        // tmux wins over any native host, and here that is enforced ONCE, at the
        // source, rather than re-checked at each use. Under tmux OUR bytes land
        // in tmux's grid — its width table is what we must satisfy — so the outer
        // terminal's advance model must not drive cursor math even if its
        // variable survived into the pane. That is a live case, not a
        // hypothetical: a tmux older than 3.2 never overwrote `TERM_PROGRAM`, so
        // a pane started from Terminal.app carries `$TMUX` (→ isTmux) AND
        // `TERM_PROGRAM=Apple_Terminal` (→ isAppleTerminal) at once.
        //
        // Zeroing the native flags when isTmux means every reader of them — the
        // dispatch below, but ALSO the right-edge clip and `repaintRightEdge`,
        // which check `isAppleTerminal` directly and would otherwise apply
        // Terminal.app's model to tmux's grid — is tmux-correct without its own
        // guard. Nothing is lost: which client is attached matters only for the
        // emoji chrome, and that is resolved separately (RenderLoop asks tmux
        // itself), never from these flags.
        self.isTmux = isTmux
        self.isAppleTerminal = isAppleTerminal && !isTmux
        self.isITerm2 = isITerm2 && !isTmux
        self.isGhostty = isGhostty && !isTmux
        self.isWarp = isWarp && !isTmux
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
    /// isAppleTerminal, isITerm2, isGhostty, isWarp)` — the host flags are
    /// fixed for the writer's lifetime, so the reuse key need not carry them.
    /// When the rest match the previous frame the
    /// previously-built line IS exactly what the builder would produce: output
    /// is byte-identical to ``buildOutputLines(buffer:terminalWidth:terminalHeight:bgCode:reset:)``.
    /// The downstream `writeXxxDiff` still compares the built lines to decide
    /// what to write, so write behaviour is unchanged; this only skips the
    /// per-line clip / compensation / pad work for rows that did not change —
    /// the win for partial-update frames (a cursor blink, a spinner tick, or a
    /// one-row selection move re-renders the whole screen but changes one row).
    ///
    /// Reuse state is keyed by `region` (each region has its own previous built
    /// lines and background colour) and is self-contained: the cache holds the
    /// lines this builder produced, NOT the lines the diff last wrote. The two
    /// are the same after an ordinary frame and differ after an animation
    /// replay, which patches a run's current frame into what is on screen.
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

        let cache = reuseCache(for: region)
        let previousBuilt = cache.builtLines
        // A row is reusable only when every parameter feeding `buildLine` is
        // unchanged; otherwise the cached built line is stale.
        let canReuse = cache.params == params

        // Total for ANY height. Callers clamp the content area at zero, but this
        // must not *depend* on that: a negative height reached the row loop as
        // `0..<negative` and trapped. Belt and braces — the same negative value
        // used to crash `WindowGroup.centerBuffer`, and clamping only there just
        // moved the crash here.
        let terminalHeight = max(0, terminalHeight)

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
            LineReuseCache(
                rawLines: buffer.lines, rawHeight: buffer.height, params: params,
                builtLines: lines),
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
        // iTerm2 draws a Fitzpatrick skin-tone modifier as a SEPARATE swatch
        // beside the base — 4 painted cells against the 2 the layout
        // allocated — so its path strips the modifiers (generic-yellow
        // fallback) to restore the 2-cell claim; it then compensates its own
        // (small) set of under-advancers — keycaps and SF-Symbol PUA glyphs —
        // with CUF, exactly as the Apple path does for Terminal.app's larger
        // set. Both advance models are DSR-measured; see
        // Documentation/Terminal-compatibility.md.
        // Ghostty needs no skin-tone strip — it is the only measured terminal
        // that merges Fitzpatrick clusters into the 2 cells the layout claims
        // — but under-advances its VS-15 chrome glyphs and SF Symbols. Warp
        // draws skin tones as base + swatch exactly like iTerm2, so it takes
        // the same strip, then a CUF for its lone-regional-indicator
        // under-advance. All models are DSR-measured; see
        // Documentation/Terminal-compatibility.md.
        let compensated = compensatingCursorAdvance(clipped)
        // Native Swift `replacing(_:with:)` — NOT Foundation's
        // `replacingOccurrences`, which bridges to `NSString` and was ~8% of the
        // render loop in a Mode-B (live-app) profile.
        let mainWithBg = compensated.replacing(reset, with: reset + bgCode)
        let padding = max(0, terminalWidth - clippedWidth)
        let line = bgCode + eraseLine + mainWithBg + String(repeating: " ", count: padding) + reset
        // Last, after every compensation has had the bytes it expects to match
        // on. The line above is assembled from styled fragments, each ending in
        // a reset, each of which then has the row's background put back — so a
        // row of uniformly-styled cells restates its styling once per fragment.
        // Measured on one frame of a divider drag: 2,565 escapes for 4,800
        // cells, 19,974 of the frame's 32,394 bytes. See
        // ``String/collapsingAdjacentSGR()``.
        return line.collapsingAdjacentSGR()
    }

    /// `text` with this host's cursor-advance divergences compensated for.
    ///
    /// The one place the per-host model is chosen, because there is more than
    /// one caller and they have to agree: `buildLine` compensates a whole row
    /// on its way to the screen, and the animation replay compensates the frame
    /// it splices into a row already there. A frame that skipped this reached
    /// Terminal.app bare — the row painted correctly once and then shifted a
    /// cell left on every tick of its pulse, which is exactly what an
    /// uncompensated emission looks like.
    ///
    /// - Parameters:
    ///   - text: A whole row, or a fragment of one.
    ///   - followedByContent: Whether visible cells follow `text` on the same
    ///     row. Only Terminal.app's model asks: it keeps a skin-tone cluster's
    ///     modifier when nothing follows it (the over-advance then has nothing
    ///     to shove out of place) and strips it when something does — and a
    ///     fragment cannot see past its own end. `false`, the whole-row answer,
    ///     is the default.
    func compensatingCursorAdvance(_ text: String, followedByContent: Bool = false) -> String {
        if isTmux {
            // FIRST: tmux is a compositor, so ITS grid is what our output
            // lands in — the outer terminal's quirks apply to tmux's output,
            // not ours, and its model must win even if a native host's
            // variable somehow survived into the pane.
            //
            // `.bmpOnly`, NOT the blanket strip iTerm2/Warp take: tmux joins
            // an SMP-based skin-tone cluster (👍🏽 👩🏽‍🚀) into exactly the 2
            // cells we claim, and only over-advances on a BMP base (✊🏻 ☝🏽).
            // Stripping the ones it gets right would throw away skin tones
            // the user asked for and the attached client renders perfectly.
            return text.withSkinToneFallback(basePlane: tmuxSkinToneBasePlane)
                .withTmuxCursorCompensation()
        } else if isAppleTerminal {
            return text.withTerminalAppCursorCompensation(followedByContent: followedByContent)
        } else if isITerm2 {
            return text.withSkinToneFallback().withITerm2CursorCompensation()
        } else if isGhostty {
            return text.withGhosttyCursorCompensation()
        } else if isWarp {
            return text.withSkinToneFallback().withWarpCursorCompensation()
        } else {
            return text
        }
    }

    /// One row this writer has already built, with an animated run's current
    /// `frame` redrawn over the `width` cells starting at `column`.
    ///
    /// The animation tick, and the reason it lives here rather than at the call
    /// site: a run's frames are *rendered content*, and rendered content
    /// reaches a terminal only through this type, because this is where the
    /// host's cursor-advance model is. A frame spliced straight into a built
    /// row has never met that model — so on Terminal.app a row carrying `⚙️`
    /// painted correctly on the frame that rendered it and then shifted
    /// everything after the emoji one cell left on every tick of its pulse,
    /// which is precisely what an uncompensated emission measures as
    /// (`Tools/TerminalProbes/row_probe.py`; see
    /// `Documentation/Terminal-compatibility.md`).
    ///
    /// The compensation cannot move a cell — it erases, draws and steps, and
    /// writes no visible characters — so the splice arithmetic below is
    /// unaffected by it.
    ///
    /// - Parameters:
    ///   - line: A row as `buildOutputLines` produced it.
    ///   - frame: The run's picture for this tick, as the view rendered it.
    ///   - column: The run's first visible column.
    ///   - width: How many cells the run covers.
    ///   - terminalWidth: The row's full width, which is what says whether the
    ///     row continues past the run — see `compensatingCursorAdvance`.
    func patchingAnimatedRun(
        in line: String, with frame: String, atColumn column: Int, width: Int,
        terminalWidth: Int
    ) -> String {
        FrameBuffer.patchingAnimatedCells(
            in: line,
            with: compensatingCursorAdvance(
                frame, followedByContent: column + width < terminalWidth),
            atColumn: column, width: width)
    }

    private func reuseCache(for region: OutputRegion) -> LineReuseCache {
        switch region {
        case .content: return contentReuse
        case .statusBar: return statusBarReuse
        case .appHeader: return appHeaderReuse
        }
    }

    private func cellCache(for region: OutputRegion) -> CellCache {
        switch region {
        case .content: return contentCells
        case .statusBar: return statusBarCells
        case .appHeader: return appHeaderCells
        }
    }

    private func setCellCache(_ cache: CellCache, for region: OutputRegion) {
        switch region {
        case .content: contentCells = cache
        case .statusBar: statusBarCells = cache
        case .appHeader: appHeaderCells = cache
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
        let changedRows = writeDiff(
            newLines: newLines, previousLines: previousContentLines, terminal: terminal,
            startRow: startRow, terminalWidth: terminalWidth, region: .content)
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
        let changedRows = writeDiff(
            newLines: newLines, previousLines: previousStatusBarLines, terminal: terminal,
            startRow: startRow, terminalWidth: terminalWidth, region: .statusBar)
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
        let changedRows = writeDiff(
            newLines: newLines, previousLines: previousAppHeaderLines, terminal: terminal,
            startRow: startRow, terminalWidth: terminalWidth, region: .appHeader)
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
        contentCells = CellCache()
        statusBarCells = CellCache()
        appHeaderCells = CellCache()
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
    /// Writes only the lines that differ between two frames — and within each of
    /// those, only the cell runs that differ. See
    /// ``Swift/String/ansiCellDiff(replacing:width:mergingGapsUpTo:)`` for what
    /// makes a run, and when it declines to answer.
    ///
    /// - Returns: The row indices that were actually written (needed by
    ///   ``repaintRightEdge`` to scope its workaround to only changed rows).
    @discardableResult
    fileprivate func writeDiff(
        newLines: [String], previousLines: [String], terminal: any TerminalProtocol,
        startRow: Int, terminalWidth: Int, region: OutputRegion
    ) -> [Int] {
        let changedRows = Self.computeChangedRows(newLines: newLines, previousLines: previousLines)
        var cache = cellCache(for: region)
        cache.fit(to: newLines.count)
        defer { setCellCache(cache, for: region) }

        // The styling this pass has left the terminal in, carried from row to
        // row. Rows are written in ascending order with nothing between them but
        // cursor moves, and a cursor move is not styling — so a span opening the
        // next row can say only what changed, exactly as one opening the next
        // run within a row does. Measured over a divider drag, `ESC[0m` alone
        // appeared 1,898 times in one capture: a row's worth of styling stated
        // afresh, per row, to say what a handful of parameters would.
        //
        // `nil` means "not known", which is the honest state at the start: what
        // the caller left in force before this pass is not ours to assume.
        var emitted: SGRState?
        for row in changedRows {
            switch spanDiff(
                newLines: newLines, previousLines: previousLines, row: row,
                terminalWidth: terminalWidth, cache: &cache, emitted: &emitted)
            {
            case .identical:
                // The two spellings land the terminal in the same place, so
                // there is nothing to draw — but the row still counts as
                // written, because `repaintRightEdge` scopes itself to rows
                // whose CONTENT it has to reason about, not to rows that moved.
                continue
            case .spans(let spans):
                for span in spans {
                    terminal.moveCursor(toRow: startRow + row, column: span.column + 1)
                    terminal.write(span.content)
                }
            case .wholeLine:
                terminal.moveCursor(toRow: startRow + row, column: 1)
                // A built row opens by STATING ITS BACKGROUND, not by resetting,
                // so anything else this pass carried in — a bold, an underline,
                // a reverse — would still be in force, and the `ESC[2K` the row
                // opens with would erase under it. Close the chain first.
                if emitted?.isDefault == false { terminal.write("\u{1B}[0m") }
                terminal.write(newLines[row])
                emitted = SGRState()  // every built row ends with a reset
            }
        }
        // Hand the terminal back the way every row used to: unstyled. The erase
        // below depends on it — `ESC[2K` clears with the background in force,
        // and this pass's last row must not choose the colour of a row it is
        // not painting.
        if emitted?.isDefault == false { terminal.write("\u{1B}[0m") }

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

    /// How many unchanged columns may sit inside one written run.
    ///
    /// Closing a run and opening another costs a cursor move plus a restatement
    /// of styling — call it twenty bytes — so bridging a short gap of unchanged
    /// cells is cheaper than skipping it. Measured over a divider drag at
    /// 140×42, the total is flat from about 4 to about 16 and rises sharply
    /// outside that: 2,628 bytes a frame at a gap of 4, 2,577 at 8, 2,606 at 16,
    /// 2,971 at 0 (a cursor move for every isolated cell) and 4,232 at
    /// unbounded (one run per row, which is the prefix/suffix trim and little
    /// more). Eight sits in the middle of the flat stretch.
    private static let spanMergeGap = 8

    /// The per-row plan, or ``ANSICellDiff/wholeLine`` when there is no previous
    /// row to diff against or the row is one the cell walk declines.
    private func spanDiff(
        newLines: [String], previousLines: [String], row: Int, terminalWidth: Int,
        cache: inout CellCache, emitted: inout SGRState?
    ) -> ANSICellDiff {
        guard row < previousLines.count else { return .wholeLine }
        let previous =
            cache.cells(matching: previousLines[row], at: row)
            ?? ANSIRowCells(decomposing: previousLines[row], width: terminalWidth)
        guard let previous,
            let new = ANSIRowCells(decomposing: newLines[row], width: terminalWidth)
        else { return .wholeLine }
        cache.remember(new, line: newLines[row], at: row)
        return new.diff(
            replacing: previous, mergingGapsUpTo: Self.spanMergeGap, continuing: &emitted)
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
