//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    @Test("computeChangedRows returns all rows when previous is empty")
    func allRowsChangedOnFirstFrame() {
        let changed = FrameDiffWriter.computeChangedRows(
            newLines: ["A", "B", "C"],
            previousLines: []
        )

        #expect(changed == [0, 1, 2])
    }

    @Test("computeChangedRows returns empty when frames are identical")
    func noChangesForIdenticalFrames() {
        let lines = ["A", "B", "C"]
        let changed = FrameDiffWriter.computeChangedRows(
            newLines: lines,
            previousLines: lines
        )

        #expect(changed.isEmpty)
    }

    @Test("computeChangedRows detects single changed line")
    func singleLineChanged() {
        let changed = FrameDiffWriter.computeChangedRows(
            newLines: ["A", "X", "C"],
            previousLines: ["A", "B", "C"]
        )

        #expect(changed == [1])
    }

    @Test("computeChangedRows detects multiple changed lines")
    func multipleLinesChanged() {
        let changed = FrameDiffWriter.computeChangedRows(
            newLines: ["A", "X", "C", "Y"],
            previousLines: ["A", "B", "C", "D"]
        )

        #expect(changed == [1, 3])
    }

    @Test("computeChangedRows handles new lines longer than previous")
    func newLinesLongerThanPrevious() {
        let changed = FrameDiffWriter.computeChangedRows(
            newLines: ["A", "B", "C", "D"],
            previousLines: ["A", "B"]
        )

        // C and D are new (indices 2, 3)
        #expect(changed == [2, 3])
    }

    @Test("computeChangedRows handles ANSI-coded strings correctly")
    func ansiStringComparison() {
        let styledA = "\u{1B}[31mRed\u{1B}[0m"
        let styledB = "\u{1B}[32mGreen\u{1B}[0m"

        let changed = FrameDiffWriter.computeChangedRows(
            newLines: [styledA, styledB],
            previousLines: [styledA, styledA]
        )

        // Only the second line changed (red → green)
        #expect(changed == [1])
    }
}

// MARK: - Integration Tests

@Suite("FrameDiffWriter Integration Tests")
@MainActor
struct DiffIntegrationTests {

    @Test("Content and status bar caches are independent")
    func independentCaches() {
        // Simulate writing content + status bar (using internal state check)
        let contentLines = ["Content1", "Content2"]
        let statusLines = ["Status1"]

        // After writeContentDiff, content cache is set
        // After writeStatusBarDiff, status cache is set
        // We verify via computeChangedRows that each cache tracks independently

        // First: content has all changed (empty previous)
        let contentChanged1 = FrameDiffWriter.computeChangedRows(
            newLines: contentLines,
            previousLines: []
        )
        #expect(contentChanged1 == [0, 1])

        // Status also has all changed (different previous)
        let statusChanged1 = FrameDiffWriter.computeChangedRows(
            newLines: statusLines,
            previousLines: []
        )
        #expect(statusChanged1 == [0])

        // Same content → no changes
        let contentChanged2 = FrameDiffWriter.computeChangedRows(
            newLines: contentLines,
            previousLines: contentLines
        )
        #expect(contentChanged2.isEmpty)

        // Status changed → only status
        let statusChanged2 = FrameDiffWriter.computeChangedRows(
            newLines: ["NEW Status"],
            previousLines: statusLines
        )
        #expect(statusChanged2 == [0])
    }

    @Test("invalidate clears both content and status bar caches")
    func invalidateClearsBothCaches() {
        let writer = FrameDiffWriter()

        // After invalidate, previous lines are empty → all rows changed
        writer.invalidate()

        let changed = FrameDiffWriter.computeChangedRows(
            newLines: ["A", "B"],
            previousLines: []
        )
        #expect(changed == [0, 1])
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

    @Test("detectAppleTerminal is false off Apple_Terminal")
    func detectionMatchesTermProgram() {
        // Whatever runs the suite, detection must equal the TERM_PROGRAM check
        // (and is compile-time false on non-macOS).
        #if os(macOS)
        let expected = ProcessInfo.processInfo.environment["TERM_PROGRAM"] == "Apple_Terminal"
        #else
        let expected = false
        #endif
        #expect(FrameDiffWriter.detectAppleTerminal() == expected)
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

        // Re-building content does NOT consult the status-bar cache: with no
        // previousContentLines committed, content cannot reuse and rebuilds all,
        // independent of the status-bar region's state.
        _ = writer.buildOutputLines(buffer: contentBuffer, terminalWidth: 20, terminalHeight: height,
                                    bgCode: bg, reset: reset, reusingFor: .content)
        #expect(writer.rowsBuiltInLastBuild == height)
    }
}
