//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CellSpanDiffTests.swift
//
//  The cell-span diff decides what a row does NOT need rewritten, which makes
//  its failure mode visible corruption rather than a slow frame. So it is graded
//  the way the design note asked for — against a reference terminal, not against
//  the bytes it happens to emit: paint the previous row, apply the plan, and the
//  screen must be indistinguishable from painting the new row outright.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("Cell span diff")
struct CellSpanDiffTests {

    // MARK: - A reference terminal

    /// A deliberately literal terminal: a grid of cells, a cursor, and the two
    /// escapes this path emits. Independent of the code under test, so the two
    /// can disagree — which is why it parses SGR itself rather than borrowing
    /// ``SGRState``, whose netting is one of the things being graded.
    private struct Screen: Equatable {
        var cells: [[Cell]]
        var cursor = (row: 0, column: 0)
        var style = ReferenceStyle()

        /// One cell, compared by what a viewer can SEE in it — which is less
        /// than what its styling says. See ``ReferenceStyle/appearance(of:)``.
        struct Cell: Equatable {
            var character: Character = " "
            var style = ReferenceStyle()

            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.style.appearance(of: lhs.character) == rhs.style.appearance(of: rhs.character)
            }
        }

        init(rows: Int, columns: Int) {
            cells = Array(repeating: Array(repeating: Cell(), count: columns), count: rows)
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.cells == rhs.cells }

        mutating func move(row: Int, column: Int) { cursor = (row, column) }

        mutating func feed(_ bytes: String) {
            var index = bytes.startIndex
            while index < bytes.endIndex {
                if bytes[index] == "\u{1B}", let end = escapeEnd(in: bytes, from: index) {
                    let sequence = String(bytes[index..<end])
                    if sequence.hasSuffix("m") {
                        style.apply(sequence)
                    } else if sequence.hasSuffix("K") {
                        // ESC[2K — erase the whole row with the background in
                        // force, which is what a built row opens with.
                        for column in cells[cursor.row].indices {
                            cells[cursor.row][column] = Cell(character: " ", style: style)
                        }
                    } else if sequence.hasSuffix("C") {
                        // ESC[nC — cursor forward, which is what the per-host
                        // emoji compensation injects. Modelled so the whole-line
                        // fallback for such a row can be checked at all.
                        let count = Int(sequence.dropFirst(2).dropLast()) ?? 1
                        cursor.column += max(1, count)
                    } else {
                        Issue.record("reference terminal met an escape it does not model: \(sequence.debugDescription)")
                    }
                    index = end
                    continue
                }
                if cursor.column < cells[cursor.row].count {
                    cells[cursor.row][cursor.column] = Cell(character: bytes[index], style: style)
                }
                cursor.column += 1
                index = bytes.index(after: index)
            }
        }

        private func escapeEnd(in bytes: String, from start: String.Index) -> String.Index? {
            var index = bytes.index(after: start)
            guard index < bytes.endIndex, bytes[index] == "[" else { return nil }
            index = bytes.index(after: index)
            while index < bytes.endIndex {
                let character = bytes[index]
                index = bytes.index(after: index)
                if character.isLetter { return index }
            }
            return nil
        }
    }

    // MARK: - The contract

    /// Paints `previous`, applies whatever the diff plans, and requires the
    /// result to equal painting `new` outright.
    @discardableResult
    private func check(
        _ previous: String, _ new: String, width: Int, _ label: String,
        expecting expected: ExpectedPlan? = nil
    ) -> ANSICellDiff {
        let plan = new.ansiCellDiff(replacing: previous, width: width, mergingGapsUpTo: 8)

        var incremental = Screen(rows: 1, columns: width)
        incremental.move(row: 0, column: 0)
        incremental.feed(previous)
        switch plan {
        case .identical:
            break
        case .spans(let spans):
            for span in spans {
                incremental.move(row: 0, column: span.column)
                incremental.feed(span.content)
            }
        case .wholeLine:
            incremental.move(row: 0, column: 0)
            incremental.feed(new)
        }

        var reference = Screen(rows: 1, columns: width)
        reference.move(row: 0, column: 0)
        reference.feed(new)

        #expect(incremental == reference, "\(label): the plan did not reproduce the row")
        if let expected { #expect(expected.matches(plan), "\(label): unexpected plan \(plan)") }
        return plan
    }

    /// What a case asserts about the SHAPE of the plan, over and above it being
    /// correct — so a change that quietly stopped optimising anything would fail
    /// rather than pass by falling back to whole-line writes everywhere.
    private enum ExpectedPlan {
        case identical
        case wholeLine
        case spanCount(Int)
        case atMostColumns(Int)

        func matches(_ plan: ANSICellDiff) -> Bool {
            switch (self, plan) {
            case (.identical, .identical), (.wholeLine, .wholeLine):
                return true
            case (.spanCount(let n), .spans(let spans)):
                return spans.count == n
            case (.atMostColumns(let limit), .spans(let spans)):
                return spans.reduce(0) { $0 + $1.content.filter { !$0.isASCII || $0 != "\u{1B}" }.count } <= limit
            default:
                return false
            }
        }
    }

    /// A row built the way `FrameDiffWriter.buildLine` builds one: background,
    /// erase, content, padding, trailing reset, then collapsed.
    private func built(_ content: String, width: Int, background: String = "\u{1B}[48;5;16m")
        -> String
    {
        let visible = content.strippedLength
        let line =
            background + "\u{1B}[2K" + content
            + String(repeating: " ", count: max(0, width - visible)) + "\u{1B}[0m"
        return line.collapsingAdjacentSGR()
    }

    // MARK: - Cases

    @Test("A row that paints the same cells needs nothing written")
    func identicalRows() {
        let row = built("hello", width: 20)
        check(row, row, width: 20, "byte-identical", expecting: .identical)
    }

    @Test("Two spellings of the same row are recognised as the same row")
    func equivalentSpellings() {
        // The same cells, reached by different escapes: one states the colour
        // twice, the other once. A byte diff calls these different.
        let width = 12
        let terse = built("\u{1B}[31mred\u{1B}[0m", width: width)
        let verbose = built("\u{1B}[31mr\u{1B}[31me\u{1B}[31md\u{1B}[0m", width: width)
        check(terse, verbose, width: width, "same cells, different escapes", expecting: .identical)
    }

    @Test("A style-only change is found, though no character moves")
    func styleOnlyChange() {
        // A text cursor: one cell goes reverse-video and back. Nothing in the
        // visible text differs, which is what a text diff would miss entirely.
        let width = 40
        let plain = built("value: abcdef", width: width)
        let cursored = built("value: abc\u{1B}[7md\u{1B}[0mef", width: width)
        check(plain, cursored, width: width, "cursor on", expecting: .spanCount(1))
        check(cursored, plain, width: width, "cursor off", expecting: .spanCount(1))
    }

    @Test("A change at the very start, and at the very end")
    func edges() {
        let width = 30
        check(built("abcdef", width: width), built("Xbcdef", width: width), width: width, "first cell")
        let long = String(repeating: "x", count: 30)
        check(built(long, width: width), built(String(long.dropLast()) + "Y", width: width),
              width: width, "last cell")
    }

    @Test("Two changes far apart become two spans, near ones become one")
    func spanMerging() {
        let width = 60
        let base = String(repeating: ".", count: 60)
        var far = Array(base)
        far[2] = "A"
        far[40] = "B"
        check(built(base, width: width), built(String(far), width: width), width: width,
              "40 columns apart", expecting: .spanCount(2))
        var near = Array(base)
        near[2] = "A"
        near[7] = "B"
        // Five unchanged columns between them is cheaper to write than to skip.
        check(built(base, width: width), built(String(near), width: width), width: width,
              "5 columns apart", expecting: .spanCount(1))
    }

    @Test("A whole-row shift is still correct, span or not")
    func everyCellChanges() {
        let width = 40
        check(built("the quick brown fox jumps", width: width),
              built(" the quick brown fox jump", width: width),
              width: width, "shifted one column right")
    }

    @Test("A row that loses its tail has the tail erased, not left standing")
    func contentShrinks() {
        let width = 40
        check(built("a much longer line of text", width: width), built("short", width: width),
              width: width, "long to short")
        check(built("short", width: width), built("a much longer line of text", width: width),
              width: width, "short to long")
    }

    @Test("A row carrying a wide character is written whole")
    func wideCharacterDeclines() {
        // Every advance divergence in Terminal-compatibility.md is a 2-cell
        // claim meeting a 1-cell advance, so a span — which trusts our column
        // count to place the cursor — must not be planned for such a row.
        let width = 30
        check(built("ab 🖥️ cd", width: width), built("ab 🖥️ ce", width: width),
              width: width, "wide in both", expecting: .wholeLine)
        check(built("abcdefg", width: width), built("ab 🖥️ ce", width: width),
              width: width, "wide arriving", expecting: .wholeLine)
        check(built("ab 🖥️ ce", width: width), built("abcdefg", width: width),
              width: width, "wide leaving", expecting: .wholeLine)
    }

    @Test("A row carrying a cursor move is written whole")
    func cursorMoveDeclines() {
        // What the per-host emoji compensation injects. A CUF means a column's
        // identity no longer follows from counting characters.
        let width = 20
        let compensated = "\u{1B}[48;5;16m\u{1B}[2Kab\u{1B}[1Ccd" + String(repeating: " ", count: 14)
        check(compensated, built("abcde", width: width), width: width, "CUF in previous",
              expecting: .wholeLine)
        check(built("abcde", width: width), compensated, width: width, "CUF in new",
              expecting: .wholeLine)
    }

    @Test("An attribute going off is stated from a reset")
    func attributeOff() {
        let width = 24
        check(built("\u{1B}[1mbold\u{1B}[0m plain", width: width),
              built("bold plain", width: width), width: width, "bold leaves")
        check(built("bold plain", width: width),
              built("\u{1B}[1mbold\u{1B}[0m plain", width: width), width: width, "bold arrives")
    }

    @Test("A row against an empty one is written whole")
    func emptyRow() {
        let width = 20
        let empty = "\u{1B}[48;5;16m\u{1B}[2K\u{1B}[0m"
        check(empty, built("hello", width: width), width: width, "empty to content",
              expecting: .wholeLine)
        check(built("hello", width: width), empty, width: width, "content to empty",
              expecting: .wholeLine)
    }

    @Test("Randomised rows stay faithful")
    func randomisedSweep() {
        let width = 48
        let palette = [
            "", "\u{1B}[31m", "\u{1B}[38;5;208m", "\u{1B}[1m", "\u{1B}[7m",
            "\u{1B}[48;5;22m", "\u{1B}[2;38;5;46m", "\u{1B}[0m",
        ]
        let alphabet = Array("abcdef ─│▓·")
        var seed: UInt64 = 0xC0FF_EE00
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        func row() -> String {
            var content = ""
            for _ in 0..<(4 + next(30)) {
                if next(4) == 0 { content += palette[next(palette.count)] }
                content.append(alphabet[next(alphabet.count)])
            }
            return built(content + "\u{1B}[0m", width: width)
        }
        for sample in 0..<300 {
            check(row(), row(), width: width, "random #\(sample)")
        }
    }

    // MARK: - Carrying styling from row to row

    /// Paints `previous` on a multi-row screen, plans every row with the state
    /// carried between them exactly as `FrameDiffWriter` does, applies the
    /// plans, and requires the screen to equal painting `new` outright.
    @discardableResult
    private func checkRows(_ previous: [String], _ new: [String], width: Int, _ label: String)
        -> Int
    {
        var incremental = Screen(rows: previous.count, columns: width)
        for (row, line) in previous.enumerated() {
            incremental.move(row: row, column: 0)
            incremental.feed(line)
        }

        var emitted: SGRState?
        var written = 0
        for row in previous.indices {
            guard let old = ANSIRowCells(decomposing: previous[row], width: width),
                let fresh = ANSIRowCells(decomposing: new[row], width: width)
            else {
                // What the writer does for a row it cannot account for: close
                // the chain, then rewrite the row whole.
                if emitted?.isDefault == false {
                    incremental.move(row: row, column: 0)
                    incremental.feed("\u{1B}[0m")
                }
                incremental.move(row: row, column: 0)
                incremental.feed(new[row])
                emitted = SGRState()
                continue
            }
            switch fresh.diff(replacing: old, mergingGapsUpTo: 8, continuing: &emitted) {
            case .identical, .wholeLine:
                continue
            case .spans(let spans):
                for span in spans {
                    incremental.move(row: row, column: span.column)
                    incremental.feed(span.content)
                    written += span.content.utf8.count
                }
            }
        }

        var reference = Screen(rows: previous.count, columns: width)
        for (row, line) in new.enumerated() {
            reference.move(row: row, column: 0)
            reference.feed(line)
        }
        #expect(incremental == reference, "\(label): the plans did not reproduce the rows")
        return written
    }

    @Test("Styling carries from one row to the next, and costs less for it")
    func stateCarriesAcrossRows() {
        // Rows are written in ascending order with nothing between them but
        // cursor moves, and a cursor move is not styling — so the second row's
        // span need not restate what the first already established.
        let width = 30
        let previous = (0..<6).map { _ in built("\u{1B}[38;5;22mabcdef\u{1B}[0m", width: width) }
        let new = (0..<6).map { _ in built("\u{1B}[38;5;22mabcXef\u{1B}[0m", width: width) }
        let carried = checkRows(previous, new, width: width, "six rows, same styling")

        // The same rows planned one at a time, each stating itself from a reset
        // and closing with one — which is what this used to cost.
        var alone = 0
        for row in previous.indices {
            if case .spans(let spans) = new[row].ansiCellDiff(
                replacing: previous[row], width: width, mergingGapsUpTo: 8)
            {
                alone += spans.reduce(0) { $0 + $1.content.utf8.count }
            }
        }
        #expect(carried < alone, "carrying state cost \(carried) against \(alone) alone")
    }

    @Test("A row the walk declines closes the chain before it is written whole")
    func wholeLineRowClosesTheChain() {
        // A built row opens by stating its BACKGROUND, not by resetting, so a
        // bold or a reverse carried into it would still be in force — and the
        // `ESC[2K` it opens with would erase under it.
        let width = 24
        let previous = [
            built("\u{1B}[1;7mab\u{1B}[0m", width: width),
            built("plain", width: width),
        ]
        let new = [
            built("\u{1B}[1;7mXb\u{1B}[0m", width: width),
            // A wide character: the walk declines this row, so it is written
            // whole, immediately after a row whose span left bold+reverse on.
            built("wide \u{1F5A5}\u{FE0F} here", width: width),
        ]
        checkRows(previous, new, width: width, "span row then whole-line row")
    }

    @Test("Randomised multi-row frames stay faithful")
    func randomisedRowCarry() {
        let width = 40
        var seed: UInt64 = 0xBEEF_0042
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let palette = [
            "", "\u{1B}[31m", "\u{1B}[38;5;208m", "\u{1B}[1m", "\u{1B}[7m", "\u{1B}[4m",
            "\u{1B}[48;5;22m", "\u{1B}[0m",
        ]
        let alphabet = Array("abc   ─│ ")
        func frame() -> [String] {
            (0..<8).map { _ in
                var content = ""
                for _ in 0..<(6 + next(28)) {
                    if next(4) == 0 { content += palette[next(palette.count)] }
                    content.append(alphabet[next(alphabet.count)])
                }
                return built(content + "\u{1B}[0m", width: width)
            }
        }
        for sample in 0..<120 {
            checkRows(frame(), frame(), width: width, "random frame #\(sample)")
        }
    }

    @Test("Randomised small edits stay faithful")
    func randomisedEdits() {
        // The shape that matters most in practice: a row that mostly stays put
        // while a few cells move — a drag, a cursor, a hover tint.
        let width = 64
        var seed: UInt64 = 0xFACE_D00D
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let alphabet = Array("abcdefghij ─│")
        for sample in 0..<300 {
            var content = (0..<(20 + next(40))).map { _ in alphabet[next(alphabet.count)] }
            let before = built(String(content) + "\u{1B}[0m", width: width)
            for _ in 0..<(1 + next(4)) {
                content[next(content.count)] = alphabet[next(alphabet.count)]
            }
            var styled = String(content)
            if next(2) == 0 {
                let at = styled.index(styled.startIndex, offsetBy: next(styled.count))
                styled.insert(contentsOf: "\u{1B}[7m", at: at)
            }
            check(before, built(styled + "\u{1B}[0m", width: width), width: width,
                  "random edit #\(sample)")
        }
    }
}

/// `AnimatedCellRun.fits(columns:rows:)` — the geometry guard every replay
/// surface applies before agreeing to patch a run into itself.
@Suite("Animated run geometry")
struct AnimatedRunFitsTests {

    private func run(x: Int, y: Int, width: Int) -> AnimatedCellRun {
        AnimatedCellRun(offsetX: x, offsetY: y, width: width, frames: ["a", "b"], clock: .cursor)
    }

    @Test("Wholly inside fits; touching the edge fits; past it does not")
    func edges() {
        #expect(run(x: 0, y: 0, width: 10).fits(columns: 10, rows: 1))
        #expect(run(x: 7, y: 0, width: 3).fits(columns: 10, rows: 1))
        #expect(!run(x: 8, y: 0, width: 3).fits(columns: 10, rows: 1))
        #expect(!run(x: -1, y: 0, width: 3).fits(columns: 10, rows: 1))
        #expect(!run(x: 0, y: 1, width: 3).fits(columns: 10, rows: 1))
        #expect(!run(x: 0, y: -1, width: 3).fits(columns: 10, rows: 1))
    }
}
