//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameDiffWriterTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// MARK: - buildOutputLines Tests

@Suite("FrameDiffWriter buildOutputLines Tests")
@MainActor
struct BuildOutputLinesTests {

    @Test("Produces exactly terminalHeight output lines")
    func outputLineCount() {
        let writer = FrameDiffWriter()
        var buffer = FrameBuffer()
        buffer.appendVertically(FrameBuffer(text: "Hello"))
        buffer.appendVertically(FrameBuffer(text: "World"))

        let lines = writer.buildOutputLines(
            buffer: buffer,
            terminalWidth: 20,
            terminalHeight: 5,
            bgCode: "",
            reset: ""
        )

        #expect(lines.count == 5)
    }

    /// A built row states its BACKGROUND, not a reset. After `invalidate()`
    /// the writer's belief about the terminal's styling is `nil`, and the
    /// whole-line arm's guard was spelled `== false`, which `nil` fails — so
    /// the first row after a resize inherited the previous pass's underline.
    @Test("A whole-line write after an invalidation closes the styling chain first")
    func wholeLineAfterInvalidationResets() {
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let bg = "\u{1B}[48;5;236m"
        let reset = "\u{1B}[0m"
        func row(_ text: String) -> String { bg + "\u{1B}[2K" + text + reset + bg + String(repeating: " ", count: 20 - text.strippedLength) + reset }
        let frameA = [row("hello"), row("world")]
        writer.writeContentDiff(newLines: frameA, terminal: terminal, startRow: 1, terminalWidth: 20, bgCode: bg, reset: reset)
        // Frame B differs in the middle of row 1 only, and the differing run
        // is styled — so the span pass ends with that style in force.
        let frameB = [row("hello"), row("wo" + "\u{1B}[4;31m" + "RL" + reset + "d")]
        writer.writeContentDiff(newLines: frameB, terminal: terminal, startRow: 1, terminalWidth: 20, bgCode: bg, reset: reset)
        terminal.reset()
        writer.invalidate()
        writer.writeContentDiff(newLines: frameB, terminal: terminal, startRow: 1, terminalWidth: 20, bgCode: bg, reset: reset)
        let output = terminal.allOutput
        let firstErase = output.range(of: "\u{1B}[2K")
        let head = firstErase.map { String(output[..<$0.lowerBound]) } ?? output
        #expect(head.contains(reset), "the first whole row was written under the previous pass's SGR: \(head.debugDescription)")
    }

    @Test("Content lines include background and padding")
    func contentLinesHaveBgAndPadding() {
        let writer = FrameDiffWriter()
        let buffer = FrameBuffer(text: "Hi")

        let lines = writer.buildOutputLines(
            buffer: buffer,
            terminalWidth: 10,
            terminalHeight: 1,
            bgCode: "[BG]",
            reset: "[R]"
        )

        let line = lines[0]
        #expect(line.hasPrefix("[BG]"))
        #expect(line.hasSuffix("[R]"))
        #expect(line.contains("Hi"))
    }

    /// A reset that arrives already fused with its styling still has to give the
    /// row's background back.
    ///
    /// `collapsingAdjacentSGR()` renders a line's first absolute run as
    /// `ESC[0;<params>m`, and the opacity resolution collapses at the seam where
    /// it splices a faded span — so a faded row reaches the writer in that
    /// spelling. The restoration matched the literal `ESC[0m` alone, so those
    /// cells cleared the background and showed the terminal's own: reported as
    /// the Animation page's fading text having a white background in Apple
    /// Terminal, whose default profile is light.
    ///
    /// Measured on the real app (Opacity page, "Text through text", the faded
    /// front line) — before: `ESC[0;38;5;77m` and the page background absent
    /// until the unfaded tail; after: `ESC[38;5;77;48;5;16m` from the first cell.
    @Test("A collapsed reset gets the row background back too")
    func collapsedResetRestoresBackground() {
        let writer = FrameDiffWriter()
        // What a faded span looks like once collapsed: reset and foreground in
        // one sequence, with no background of its own.
        let buffer = FrameBuffer(lines: ["\u{1B}[0;38;5;77mfaded\u{1B}[0m"])

        let line = writer.buildOutputLines(
            buffer: buffer,
            terminalWidth: 12,
            terminalHeight: 1,
            bgCode: "\u{1B}[48;5;16m",
            reset: "\u{1B}[0m"
        )[0]

        // The cells carrying "faded" must name the row's background. Whatever
        // spelling the final collapse settles on, no `faded` may be reached
        // through a reset that has not had the background restated after it.
        let beforeText = String(line[line.startIndex..<(line.range(of: "faded")?.lowerBound ?? line.endIndex)])
        guard let lastReset = beforeText.range(of: "\u{1B}[0", options: .backwards) else {
            // No reset before the text at all: the row's leading background
            // stands, which is also correct.
            #expect(beforeText.contains("48;5;16"), "no background before the text: \(escaped(line))")
            return
        }
        let afterLastReset = String(beforeText[lastReset.lowerBound...])
        #expect(
            afterLastReset.contains("48;5;16"),
            "the last reset before the text does not restate the background: \(escaped(line))")
    }

    /// `\u{1B}` rendered visibly, for a failure message worth reading.
    private func escaped(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{1B}", with: "<ESC>")
    }

    @Test("Empty rows are filled with background-colored spaces")
    func emptyRowsFilled() {
        let writer = FrameDiffWriter()
        let buffer = FrameBuffer()

        let lines = writer.buildOutputLines(
            buffer: buffer,
            terminalWidth: 5,
            terminalHeight: 2,
            bgCode: "[BG]",
            reset: "[R]"
        )

        // Empty lines use bgCode + ESC[2K (erase entire line with bg color) + reset
        let eraseLine = "\u{1B}[2K"
        let expected = "[BG]" + eraseLine + "[R]"
        #expect(lines[0] == expected)
        #expect(lines[1] == expected)
    }

    @Test("ANSI reset codes in content are replaced with reset+bg")
    func resetCodesReplaced() {
        let writer = FrameDiffWriter()
        let reset = ANSIRenderer.reset
        let buffer = FrameBuffer(text: "A\(reset)B")

        let lines = writer.buildOutputLines(
            buffer: buffer,
            terminalWidth: 20,
            terminalHeight: 1,
            bgCode: "[BG]",
            reset: reset
        )

        #expect(lines[0].contains("\(reset)[BG]"))
    }

    @Test("A buffer line with control characters is sanitised before output")
    func controlCharactersSanitised() {
        let writer = FrameDiffWriter()
        // A cell value with an embedded newline / tab / carriage return — the bug
        // that drew outside the row. The emitted line must contain none of them
        // (each would move the cursor); they are replaced with spaces in place.
        let buffer = FrameBuffer(lines: ["A\nB\tC\rD"])
        let lines = writer.buildOutputLines(
            buffer: buffer, terminalWidth: 20, terminalHeight: 1, bgCode: "[BG]", reset: "[R]")
        #expect(!lines[0].contains("\n"))
        #expect(!lines[0].contains("\r"))
        #expect(!lines[0].contains("\t"))
        #expect(lines[0].contains("A B C D"), "control chars become spaces: \(lines[0])")
    }

    @Test("Multiple content lines are all processed")
    func multipleContentLines() {
        let writer = FrameDiffWriter()
        var buffer = FrameBuffer()
        buffer.appendVertically(FrameBuffer(text: "Line1"))
        buffer.appendVertically(FrameBuffer(text: "Line2"))
        buffer.appendVertically(FrameBuffer(text: "Line3"))

        let lines = writer.buildOutputLines(
            buffer: buffer,
            terminalWidth: 10,
            terminalHeight: 3,
            bgCode: "",
            reset: ""
        )

        #expect(lines[0].contains("Line1"))
        #expect(lines[1].contains("Line2"))
        #expect(lines[2].contains("Line3"))
    }
}

// MARK: - Line Diff Logic Tests

@Suite("FrameDiffWriter Diff Logic Tests")
@MainActor
struct DiffLogicTests {

    @Test(
        "computeChangedRows returns exactly the changed row indices",
        arguments: [
            // (new, previous, expected changed rows)
            (["A", "B", "C"], [String](), [0, 1, 2]),  // first frame: everything
            (["A", "B", "C"], ["A", "B", "C"], []),  // identical: nothing
            (["A", "X", "C"], ["A", "B", "C"], [1]),  // single change
            (["A", "X", "C", "Y"], ["A", "B", "C", "D"], [1, 3]),  // multiple changes
            (["A", "B", "C", "D"], ["A", "B"], [2, 3]),  // grown: new tail rows
            // ANSI-coded strings: only CONTENT-differing lines count as changed.
            (
                ["\u{1B}[31mRed\u{1B}[0m", "\u{1B}[32mGreen\u{1B}[0m"],
                ["\u{1B}[31mRed\u{1B}[0m", "\u{1B}[31mRed\u{1B}[0m"],
                [1]
            ),
            // Content vs status-bar shapes (from the retired integration suite —
            // both cache paths compare through this same pure function).
            (["Content1", "Content2"], [String](), [0, 1]),
            (["Status1"], [String](), [0]),
            (["Content1", "Content2"], ["Content1", "Content2"], []),
            (["NEW Status"], ["Status1"], [0]),
        ])
    func changedRows(new: [String], previous: [String], expected: [Int]) {
        let changed = FrameDiffWriter.computeChangedRows(
            newLines: new, previousLines: previous)
        #expect(changed == expected)
    }
}

// MARK: - Terminal.app Workaround Gating

/// The emoji cursor-advance / right-edge workarounds in `buildOutputLines`
/// (and `repaintRightEdge`) compensate for bugs that ONLY macOS Terminal.app
/// has. Applied to any other terminal they corrupt output — injecting spurious
/// `CUF` cursor moves and stripping skin-tone modifiers — so they must be gated
/// on `isAppleTerminal`.
@Suite("FrameDiffWriter Terminal.app gating")
@MainActor
struct FrameDiffWriterTerminalGatingTests {
    /// A lone regional-indicator scalar is a *range-based* under-advancer
    /// (Terminal.app advances the cursor by 1 but the glyph is 2 cells wide),
    /// so it deterministically triggers the CUF compensation on every platform,
    /// independent of the host's Unicode property tables.
    private let underAdvancer = "\u{1F1E6}"  // 🇦

    private func firstLine(isAppleTerminal: Bool) -> String {
        FrameDiffWriter(isAppleTerminal: isAppleTerminal).buildOutputLines(
            buffer: FrameBuffer(text: underAdvancer + "x"),
            terminalWidth: 20, terminalHeight: 1, bgCode: "", reset: ""
        )[0]
    }

    @Test("Apple_Terminal still gets cursor compensation (a CUF after the emoji)")
    func appleTerminalCompensates() {
        #expect(firstLine(isAppleTerminal: true).contains("\u{1B}[1C"))
    }

    @Test("Other terminals get NO compensation — it would corrupt them")
    func otherTerminalsUntouched() {
        let line = firstLine(isAppleTerminal: false)
        #expect(!line.contains("\u{1B}[1C"))    // no spurious CUF injected
        #expect(line.contains(underAdvancer))    // the emoji passes through verbatim
    }

    /// Every signal spelled out in the argument, none read from the ambient
    /// shell — `detectAppleTerminal(environment:)` is pure over the dictionary
    /// precisely so both answers are reachable from any terminal, on any
    /// platform.
    @Test("Apple Terminal detection reads the documented signals, in the documented order")
    func detectionFollowsDocumentedPrecedence() {
        // `TERM_PROGRAM`, the local answer.
        #expect(TerminalHost.detectAppleTerminal(environment: ["TERM_PROGRAM": "Apple_Terminal"]))
        #expect(!TerminalHost.detectAppleTerminal(environment: ["TERM_PROGRAM": "iTerm.app"]))
        #expect(!TerminalHost.detectAppleTerminal(environment: [:]))

        // `TUIKIT_TERM_PROGRAM` outranks it, in BOTH directions. This is the
        // case the variable exists for (Terminal-compatibility.md): Terminal.app
        // sets no forwarded signal and answers no XTVERSION, so across an ssh
        // hop the explicit override is the only thing that names it.
        #expect(
            TerminalHost.detectAppleTerminal(
                environment: [
                    "TERM_PROGRAM": "iTerm.app", "TUIKIT_TERM_PROGRAM": "Apple_Terminal",
                ]))
        #expect(
            !TerminalHost.detectAppleTerminal(
                environment: [
                    "TERM_PROGRAM": "Apple_Terminal", "TUIKIT_TERM_PROGRAM": "iTerm.app",
                ]))

        // The two weaker signals name other terminals only, so they answer a
        // definite false rather than falling through to a guess.
        #expect(!TerminalHost.detectAppleTerminal(environment: ["LC_TERMINAL": "iTerm2"]))
        #expect(!TerminalHost.detectAppleTerminal(environment: ["TERM": "xterm-ghostty"]))
    }

    /// What is left to pin about the cached `static let`, and all that can be:
    /// that it IS the detector's answer over the process environment.
    ///
    /// Not re-derived from `TERM_PROGRAM` — the earlier version of this test
    /// did that, and so failed on a defect-free build for anyone who had
    /// followed the documentation's own `export TUIKIT_TERM_PROGRAM=…`
    /// instruction, since the override wins in `hostProgram` and the
    /// expectation never saw it. And deliberately not under `#if os(macOS)`:
    /// `isAppleTerminal` is not platform-gated, because over ssh a Mac running
    /// Terminal.app routinely hosts the process on Linux (`TerminalHost`
    /// records the compile-time-false model as the bug it was).
    @Test("The cached answer is the detector's answer, on every platform")
    func cachedDetectionMatchesTheDetector() {
        #expect(
            TerminalHost.isAppleTerminal
                == TerminalHost.detectAppleTerminal(
                    environment: ProcessInfo.processInfo.environment))
    }
}

@Suite("Cursor-advance models (DSR-measured)")
@MainActor
struct CursorAdvanceModelTests {
    // All values below were measured by DSR cursor-position queries in the
    // real terminals (Terminal.app 455.1, iTerm2 3.6.11, macOS 15.7) — see
    // Documentation/Terminal-compatibility.md.

    @Test("Terminal.app: a flag PAIR conserves internally, and the walk trims its store")
    func appleFlagPairInternalAndStore() {
        // The INTERNAL column (this property — it governs wrapping) moves the
        // full 2 for a pair; the row STORES one column more than it paints,
        // which pushes everything later on the row a cell left — measured on
        // the treatment cards, where the old CUB(1)+CUF(1) nudge left both
        // sequential and absolutely-placed followers misaligned. The walk
        // deletes the surplus stored column: CUB(1), DCH(1), CUF(1).
        let pair = Character("\u{1F1FA}\u{1F1F8}")  // 🇺🇸
        #expect(pair.terminalAppCursorAdvance == 2)
        #expect(pair.terminalWidth == 2)
        // A LONE regional indicator still under-advances.
        let lone = Character("\u{1F1E6}")
        #expect(lone.terminalAppCursorAdvance == 1)
        #expect(lone.terminalWidth == 2)
        // So a compensated line trims the pair and steps past the lone one.
        let line = "\u{1F1FA}\u{1F1F8}x".withTerminalAppCursorCompensation()
        #expect(line.contains("\u{1B}[1D\u{1B}[1P\u{1B}[1C"), "|\(line)|")
    }

    @Test("iTerm2 (alternate screen): keycaps, PUA, and VS-16 emoji under-advance")
    func iTerm2AdvanceModel() {
        // All measured on the ALTERNATE screen — the buffer apps run in.
        // iTerm2's PRIMARY screen advances VS-16 clusters by 2; a model
        // built from primary-screen probes declared iTerm2 quirk-free and
        // the demo's Bug A row painted its brackets into the glyphs.
        #expect(Character("1\u{FE0F}\u{20E3}").iTerm2CursorAdvance == 1)  // 1️⃣
        #expect(Character("#\u{FE0F}\u{20E3}").iTerm2CursorAdvance == 1)
        #expect(Character("1\u{20E3}").iTerm2CursorAdvance == 1)          // bare keycap
        #expect(Character("\u{100038}").iTerm2CursorAdvance == 1)         // SF symbol
        #expect(Character("\u{2764}\u{FE0F}").iTerm2CursorAdvance == 1)  // ❤️
        #expect(Character("\u{270F}\u{FE0F}").iTerm2CursorAdvance == 1)  // ✏️
        #expect(Character("\u{1F5A5}\u{FE0F}").iTerm2CursorAdvance == 1)  // 🖥️
        // The EAW bases advance their full width — same exception as
        // Terminal.app; a CUF here left an unpainted hole after every 〰️.
        #expect(Character("\u{3030}\u{FE0F}").iTerm2CursorAdvance == 2)  // 〰️
        #expect(Character("\u{303D}\u{FE0F}").iTerm2CursorAdvance == 2)  // 〽️
        // Correct advancers stay uncompensated.
        #expect(Character("\u{1F1FA}\u{1F1F8}").iTerm2CursorAdvance == 2)  // 🇺🇸
        #expect(Character("\u{1F1E6}").iTerm2CursorAdvance == 2)          // lone RI
        #expect(Character("\u{1F44D}").iTerm2CursorAdvance == 2)          // 👍
        #expect(Character("\u{2B1B}\u{FE0E}").iTerm2CursorAdvance == 2)  // ⬛︎ (VS-15)
    }

    @Test("iTerm2 compensation erases under keycaps, PUA, and VS-16 clusters")
    func iTerm2CompensationWalk() {
        // ECH + glyph + CUF, the Terminal.app shape: iTerm2 too paints only
        // the single cell its cursor advance covers, so without the erase the
        // second cell keeps the default background (measured 2026-08-28).
        let keycap = "a1\u{FE0F}\u{20E3}b".withITerm2CursorCompensation()
        #expect(keycap == "a\u{1B}[2X1\u{FE0F}\u{20E3}\u{1B}[1Cb", "|\(keycap)|")
        let pua = "[\u{100038}]".withITerm2CursorCompensation()
        #expect(pua == "[\u{1B}[2X\u{100038}\u{1B}[1C]", "|\(pua)|")
        // The demo's Bug A shape: the CUF pushes the closing bracket clear
        // of the glyph's second cell (alternate-screen under-advance).
        let heart = "[\u{2764}\u{FE0F}]".withITerm2CursorCompensation()
        #expect(heart == "[\u{1B}[2X\u{2764}\u{FE0F}\u{1B}[1C]", "|\(heart)|")
        let wavy = "[\u{3030}\u{FE0F}]".withITerm2CursorCompensation()
        #expect(wavy == "[\u{3030}\u{FE0F}]", "EAW exception, no rewrite: |\(wavy)|")
        // ANSI escapes pass through; pure ASCII is the identity fast path.
        let styled = "\u{1B}[31m\u{100038}\u{1B}[0m".withITerm2CursorCompensation()
        #expect(styled == "\u{1B}[31m\u{1B}[2X\u{100038}\u{1B}[1C\u{1B}[0m", "|\(styled)|")
        #expect("plain".withITerm2CursorCompensation() == "plain")
    }

    @Test("The writer's iTerm2 path applies strip THEN compensation")
    func writerITerm2PathComposes() {
        let line = FrameDiffWriter(isAppleTerminal: false, isITerm2: true).buildOutputLines(
            buffer: FrameBuffer(text: "\u{1F44D}\u{1F3FD} \u{100038} x"),
            terminalWidth: 30, terminalHeight: 1, bgCode: "", reset: ""
        )[0]
        #expect(!line.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) })
        #expect(line.contains("\u{1B}[2X\u{100038}\u{1B}[1C"), "PUA compensated: |\(line)|")
    }
}

@Suite("FrameDiffWriter iTerm2 skin-tone fallback")
@MainActor
struct FrameDiffWriterITerm2GatingTests {
    private func firstLine(text: String, isITerm2: Bool) -> String {
        FrameDiffWriter(isAppleTerminal: false, isITerm2: isITerm2).buildOutputLines(
            buffer: FrameBuffer(text: text),
            terminalWidth: 30, terminalHeight: 1, bgCode: "", reset: ""
        )[0]
    }

    /// A Fitzpatrick scalar anywhere in the built line.
    private func containsSkinTone(_ line: String) -> Bool {
        line.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
    }

    @Test("iTerm2 with no published traits strips skin-tone modifiers")
    func iTerm2StripsModifiers() {
        // The NO-TRAITS fallback: with the old 2-cell claim in force, iTerm2
        // (default width configuration) would draw the modifier as a SEPARATE
        // 2-cell swatch beside the base — 4 painted cells where the column
        // accounting claims 2 — shifting the rest of the row right, so the
        // strip restores the claim. The shipped pipeline publishes
        // `.detachedOnBMPBases` at startup and keeps the modifier (next test).
        let line = firstLine(text: "a\u{1F44D}\u{1F3FD}b", isITerm2: true)  // a👍🏽b
        #expect(!containsSkinTone(line), "modifier stripped: |\(line)|")
        #expect(line.contains("\u{1F44D}"), "the base emoji survives: |\(line)|")
        #expect(line.contains("b"), "trailing content survives: |\(line)|")
        #expect(!line.contains("\u{1B}[1C"), "no cursor compensation on iTerm2")
    }

    @Test("iTerm2 under its published traits keeps the modifier — the claim covers it")
    func iTerm2KeepsModifiersUnderPublishedTraits() {
        // The SHIPPED pipeline: `.detachedOnBMPBases` claims the cells the
        // rendering occupies (👍🏽 merges at 2; ✊🏻 detaches and claims 4), so
        // the strip is inert and the user's scalars reach the screen. Every
        // writer test used to run only the fallback above, leaving the real
        // configuration's writer pipeline unpinned.
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .iTerm2)) {
            for cluster in ["\u{1F44D}\u{1F3FD}", "\u{270A}\u{1F3FB}"] {
                let line = firstLine(text: "a\(cluster)b", isITerm2: true)
                #expect(containsSkinTone(line), "modifier survives: |\(line)|")
            }
        }
    }

    @Test("A text-presentation base keeps its 2-cell claim via VS-16")
    func textPresentationBaseGainsVS16() {
        // ☝ renders 1 cell bare; the original cluster claimed 2 — the
        // fallback appends U+FE0F so the emoji rendering (2 cells) is kept.
        let line = firstLine(text: "\u{261D}\u{1F3FD}x", isITerm2: true)  // ☝🏽x
        #expect(!containsSkinTone(line))
        #expect(line.contains("\u{261D}\u{FE0F}"), "VS-16 restores the 2-cell claim: |\(line)|")
    }

    @Test("A standalone modifier is intentional content and passes through")
    func standaloneModifierUntouched() {
        // The emoji-corpus list deliberately shows bare U+1F3FB…U+1F3FF rows
        // as 2-cell swatches — correctly claimed, so never stripped.
        let line = firstLine(text: "[\u{1F3FD}]", isITerm2: true)
        #expect(containsSkinTone(line), "standalone swatch kept: |\(line)|")
    }

    @Test("Non-iTerm2 terminals pass skin-tone clusters through verbatim")
    func otherTerminalsUntouched() {
        let line = firstLine(text: "a\u{1F44D}\u{1F3FD}b", isITerm2: false)
        #expect(containsSkinTone(line), "no stripping off the allowlisted host: |\(line)|")
    }

    @Test("The fallback preserves each cluster's claimed width and ANSI runs")
    func fallbackPreservesClaimedWidthAndEscapes() {
        // The stripped cluster must claim exactly what the original claimed
        // (2 cells), or the layout that positioned the rest of the row would
        // be wrong — for both an emoji-presentation base and a
        // text-presentation base, styled with surrounding escapes.
        for cluster in ["\u{1F44D}\u{1F3FD}", "\u{261D}\u{1F3FB}", "\u{270A}\u{1F3FF}"] {
            let original = "\u{1B}[31m\(cluster)\u{1B}[0m"
            let stripped = original.withSkinToneFallback()
            #expect(stripped.strippedLength == original.strippedLength,
                    "claimed width unchanged for \(cluster): |\(stripped)|")
            #expect(stripped.hasPrefix("\u{1B}[31m") && stripped.hasSuffix("\u{1B}[0m"),
                    "escape runs preserved: |\(stripped)|")
        }
        // Already-selectored cluster (base + VS16 + modifier): no double VS16.
        let doubled = "\u{261D}\u{FE0F}\u{1F3FD}".withSkinToneFallback()
        #expect(doubled == "\u{261D}\u{FE0F}", "|\(doubled)|")
        // Pure-ASCII fast path is the identity.
        #expect("plain text".withSkinToneFallback() == "plain text")
    }
}

// MARK: - Incremental Build Reuse

/// `buildOutputLines(…reusingFor:)` reuses the previous frame's built line for
/// any row whose raw content + render params are unchanged. These tests pin
/// the two guarantees: output stays byte-identical to the pure builder, and
/// unchanged rows are genuinely skipped.
@Suite("FrameDiffWriter incremental build reuse")
@MainActor
struct FrameDiffWriterIncrementalReuseTests {
    private let bg = "[BG]"
    private let reset = "[R]"

    private func makeBuffer(_ rows: [String]) -> FrameBuffer {
        var buffer = FrameBuffer(text: rows[0])
        for row in rows.dropFirst() {
            buffer.appendVertically(FrameBuffer(text: row))
        }
        return buffer
    }

    /// Build the content region via the reusing path, then run the matching
    /// diff so `previousContentLines` is updated — mirroring RenderLoop's
    /// build→writeContentDiff pairing (the reuse reads what the diff stores).
    @discardableResult
    private func buildAndCommit(
        _ writer: FrameDiffWriter, _ rows: [String],
        width: Int, height: Int, terminal: MockTerminal
    ) -> [String] {
        let lines = writer.buildOutputLines(
            buffer: makeBuffer(rows), terminalWidth: width, terminalHeight: height,
            bgCode: bg, reset: reset, reusingFor: .content
        )
        writer.writeContentDiff(
            newLines: lines, terminal: terminal, startRow: 1,
            terminalWidth: width, bgCode: bg, reset: reset
        )
        return lines
    }

    @Test("Reusing build is byte-identical to the pure build, frame over frame")
    func reuseMatchesPureBuild() {
        let writer = FrameDiffWriter(isAppleTerminal: false)
        let oracle = FrameDiffWriter(isAppleTerminal: false)   // stateless reference
        let terminal = MockTerminal()
        let width = 20, height = 6

        // Content changes, no-ops, growth within `height`, and a shrink — every
        // case the reuse logic distinguishes.
        let frames: [[String]] = [
            ["alpha", "beta", "gamma"],
            ["alpha", "BETA!", "gamma"],            // one row changed
            ["alpha", "BETA!", "gamma"],            // unchanged
            ["alpha", "BETA!", "gamma", "delta"],   // a content row appears
            ["x"],                                  // shrink to a single content row
            ["alpha", "beta", "gamma"]              // grow again
        ]
        for rows in frames {
            let got = buildAndCommit(writer, rows, width: width, height: height, terminal: terminal)
            let want = oracle.buildOutputLines(
                buffer: makeBuffer(rows), terminalWidth: width, terminalHeight: height,
                bgCode: bg, reset: reset
            )
            #expect(got == want, "reusing build diverged from the pure build for \(rows)")
        }
    }

    @Test("Unchanged rows are reused, not rebuilt")
    func unchangedRowsAreReused() {
        let writer = FrameDiffWriter(isAppleTerminal: false)
        let terminal = MockTerminal()
        let width = 20, height = 6

        // Frame 1: nothing cached → all `height` rows built (3 content + 3 empty).
        buildAndCommit(writer, ["a", "b", "c"], width: width, height: height, terminal: terminal)
        #expect(writer.rowsBuiltInLastBuild == height)

        // Frame 2: identical buffer → every row reused.
        buildAndCommit(writer, ["a", "b", "c"], width: width, height: height, terminal: terminal)
        #expect(writer.rowsBuiltInLastBuild == 0)

        // Frame 3: one content row changes → exactly one row rebuilt (the
        // partial-update case this optimization targets).
        buildAndCommit(writer, ["a", "B", "c"], width: width, height: height, terminal: terminal)
        #expect(writer.rowsBuiltInLastBuild == 1)
    }

    @Test("An animation replay must not poison the reuse cache")
    func replayPatchDoesNotPoisonReuse() {
        // The freeze this pins: a focus indicator stuck mid-breath the instant
        // focus moved away, on every control whose RAW line is the same focused
        // or not (only its `AnimatedCellRun` differed).
        //
        // The replay patches a run's current frame into the line on screen and
        // commits that through `writeContentDiff`, so the diff baseline holds
        // the PATCHED line. The reuse read its "previously built" lines from
        // that same store, so the next render handed the patched line back as
        // "what the builder would produce" — which then equalled the baseline,
        // so the row was never written again and the pulse colour stayed put.
        let writer = FrameDiffWriter(isAppleTerminal: false)
        let terminal = MockTerminal()
        let width = 20, height = 4
        let rows = ["alpha", "beta"]

        let built = buildAndCommit(writer, rows, width: width, height: height, terminal: terminal)

        // A tick: the run's current frame spliced into row 0, committed the way
        // `RenderLoop.replayAnimations` commits it.
        var patched = built
        patched[0] = built[0] + "[PULSE]"
        writer.writeContentDiff(
            newLines: patched, terminal: terminal, startRow: 1,
            terminalWidth: width, bgCode: bg, reset: reset
        )

        // The next frame renders the same raw content (the row looks the same
        // unfocused as focused) …
        let again = writer.buildOutputLines(
            buffer: makeBuffer(rows), terminalWidth: width, terminalHeight: height,
            bgCode: bg, reset: reset, reusingFor: .content
        )
        #expect(again == built, "the build handed back the patch: \(again[0].debugDescription)")

        // … and because it differs from what is on screen, it is written, which
        // is what puts the row back to its resting appearance.
        terminal.reset()
        writer.writeContentDiff(
            newLines: again, terminal: terminal, startRow: 1,
            terminalWidth: width, bgCode: bg, reset: reset
        )
        #expect(
            terminal.writtenOutput.contains { $0.contains("alpha") },
            "the patched row was never repainted: \(terminal.writtenOutput)")
    }

    @Test("A parameter change invalidates all reuse")
    func parameterChangeRebuildsEveryRow() {
        let writer = FrameDiffWriter(isAppleTerminal: false)
        let terminal = MockTerminal()
        let rows = ["a", "b", "c"]
        let height = 4

        buildAndCommit(writer, rows, width: 20, height: height, terminal: terminal)
        // Same content, wider terminal → no row can be reused (padding differs).
        let lines = writer.buildOutputLines(
            buffer: makeBuffer(rows), terminalWidth: 30, terminalHeight: height,
            bgCode: bg, reset: reset, reusingFor: .content
        )
        #expect(writer.rowsBuiltInLastBuild == height)
        // And it still matches the pure build at the new width.
        let want = FrameDiffWriter(isAppleTerminal: false).buildOutputLines(
            buffer: makeBuffer(rows), terminalWidth: 30, terminalHeight: height,
            bgCode: bg, reset: reset
        )
        #expect(lines == want)
    }

    @Test("invalidate() forces a full rebuild on the next frame")
    func invalidateForcesRebuild() {
        let writer = FrameDiffWriter(isAppleTerminal: false)
        let terminal = MockTerminal()
        let width = 20, height = 5

        buildAndCommit(writer, ["a", "b"], width: width, height: height, terminal: terminal)
        buildAndCommit(writer, ["a", "b"], width: width, height: height, terminal: terminal)
        #expect(writer.rowsBuiltInLastBuild == 0)   // reused

        writer.invalidate()
        buildAndCommit(writer, ["a", "b"], width: width, height: height, terminal: terminal)
        #expect(writer.rowsBuiltInLastBuild == height)   // cache cleared → all rebuilt
    }

    @Test("Regions reuse independently")
    func regionsAreIndependent() {
        let writer = FrameDiffWriter(isAppleTerminal: false)
        let height = 3
        let contentBuffer = makeBuffer(["content"])
        let statusBuffer = makeBuffer(["status"])

        // Prime both regions.
        _ = writer.buildOutputLines(buffer: contentBuffer, terminalWidth: 20, terminalHeight: height,
                                    bgCode: bg, reset: reset, reusingFor: .content)
        _ = writer.buildOutputLines(buffer: statusBuffer, terminalWidth: 20, terminalHeight: height,
                                    bgCode: bg, reset: reset, reusingFor: .statusBar)

        // Content changing rebuilds content …
        _ = writer.buildOutputLines(buffer: makeBuffer(["CHANGED"]), terminalWidth: 20,
                                    terminalHeight: height,
                                    bgCode: bg, reset: reset, reusingFor: .content)
        #expect(writer.rowsBuiltInLastBuild == 1)

        // … and leaves the status bar's own cache untouched: it still reuses
        // every row, which it could not do if the two shared one cache.
        _ = writer.buildOutputLines(buffer: statusBuffer, terminalWidth: 20, terminalHeight: height,
                                    bgCode: bg, reset: reset, reusingFor: .statusBar)
        #expect(writer.rowsBuiltInLastBuild == 0)
    }
}
