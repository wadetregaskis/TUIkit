//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StringTerminalWidthTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Character.terminalWidth

@Suite("Character.terminalWidth")
struct CharacterTerminalWidthTests {

    @Test("ASCII letters are 1 cell wide")
    func asciiLetters() {
        #expect(Character("A").terminalWidth == 1)
        #expect(Character("z").terminalWidth == 1)
        #expect(Character("0").terminalWidth == 1)
        #expect(Character(" ").terminalWidth == 1)
    }

    @Test("Base emoji without modifier are 2 cells wide")
    func baseEmoji() {
        #expect(Character("🤙").terminalWidth == 2)
        #expect(Character("🎉").terminalWidth == 2)
        #expect(Character("💫").terminalWidth == 2)
    }

    @Test("Skin-tone emoji are 2 cells wide (modifier is zero-width)")
    func skinToneEmoji() {
        // The Fitzpatrick modifier is zero-width on its own, but when
        // combined with a base emoji the grapheme cluster is still 2 cells.
        let tones = ["🤙🏻", "🤙🏼", "🤙🏽", "🤙🏾", "🤙🏿"]
        for s in tones {
            let ch = Character(s)
            #expect(ch.terminalWidth == 2, "\(s) should be 2 cells wide")
        }
    }

    @Test("VS-16 emoji in pictographic block are 2 cells wide")
    func vs16PictographicEmoji() {
        // 🖥️ = U+1F5A5 + U+FE0F — renders 2 cells wide
        let ch = Character("🖥️")
        #expect(ch.terminalWidth == 2)
    }

    @Test("CJK characters are 2 cells wide")
    func cjkCharacters() {
        #expect(Character("中").terminalWidth == 2)
        #expect(Character("日").terminalWidth == 2)
        #expect(Character("한").terminalWidth == 2)
    }

    @Test("Fitzpatrick modifier alone is 0 cells wide")
    func fitzpatrickModifierAlone() {
        // U+1F3FD (medium skin tone) is zero-width on its own
        let scalar = Unicode.Scalar(0x1F3FD)!
        let ch = Character(scalar)
        #expect(ch.terminalWidth == 0)
    }

    @Test("Variation selector U+FE0F alone is 0 cells wide")
    func variationSelectorAlone() {
        let scalar = Unicode.Scalar(0xFE0F)!
        let ch = Character(scalar)
        #expect(ch.terminalWidth == 0)
    }
}

// MARK: - Character.terminalAppCursorAdvance

@Suite("Character.terminalAppCursorAdvance")
struct CharacterTerminalAppCursorAdvanceTests {

    @Test("ASCII characters: cursor advance equals terminal width")
    func asciiCursorAdvance() {
        #expect(Character("A").terminalAppCursorAdvance == 1)
        #expect(Character(" ").terminalAppCursorAdvance == 1)
    }

    @Test("Skin-tone emoji: cursor over-advances by 4 in Terminal.app")
    func skinToneEmojiCursorAdvance() {
        // 🤙🏽 paints 2 cells but advances Terminal.app's cursor by 4;
        // `withTerminalAppCursorCompensation` resynchronises by emitting a
        // dummy space (which commits the grapheme cluster) and a CUB that
        // rewinds the cursor.
        let ch = Character("🤙🏽")
        #expect(ch.terminalWidth == 2, "Renders 2 cells")
        #expect(ch.terminalAppCursorAdvance == 4, "But cursor advances by 4 in Terminal.app")
    }

    @Test("VS-16 pictographic emoji: cursor advance is 1 (Terminal.app under-advance bug)")
    func vs16EmojiCursorAdvance() {
        // 🖥️ = U+1F5A5 + U+FE0F — Terminal.app renders 2 cells but advances cursor by 1
        let ch = Character("🖥️")
        #expect(ch.terminalWidth == 2, "Renders 2 cells")
        #expect(ch.terminalAppCursorAdvance == 1, "But cursor only advances by 1 in Terminal.app")
    }

    @Test("Base emoji without VS-16: cursor advance equals terminal width")
    func baseEmojiNoCursorBug() {
        // 🎉 is a pure emoji with no VS-16 selector
        let ch = Character("🎉")
        #expect(ch.terminalAppCursorAdvance == ch.terminalWidth)
    }
}

// MARK: - String.withTerminalAppCursorCompensation

@Suite("String.withTerminalAppCursorCompensation")
struct WithTerminalAppCursorCompensationTests {

    @Test("Plain ASCII: no CUF injected")
    func plainASCIINoCUF() {
        let s = "Hello, World!"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result == s, "Plain ASCII should be unchanged")
        #expect(!result.contains("\u{1B}[1C"), "Should contain no CUF")
    }

    @Test("Skin-tone emoji followed by content: Fitzpatrick scalar stripped")
    func skinToneFollowedByContentStripsModifier() {
        // When the cluster is followed by inline content on the same
        // line, Terminal.app applies a row-wide LEFT shift that pushes
        // the rightmost 2 cells off the visible row.  No ANSI sequence
        // can recover both the modifier AND the layout — so the
        // Fitzpatrick scalar is stripped and the base emoji is rendered
        // alone.
        let s = "Call 🤙🏽 now"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result == "Call 🤙 now",
            "Modifier stripped when cluster has visible content after it")
        #expect(!result.stripped.contains("🤙🏽"), "Fitzpatrick scalar dropped")
        #expect(result.contains("🤙"), "Base emoji preserved")
    }

    @Test("Skin-tone emoji at end of input: modifier preserved")
    func skinToneAtEndPreservesModifier() {
        // No content after the cluster — the over-advance happens after
        // the row is otherwise written, so the row-wide shift bug has
        // nothing to push.  Keep the modifier.
        let s = "Call 🤙🏽"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result == s, "Modifier preserved when cluster is last visible content")
        #expect(result.stripped.contains("🤙🏽"), "Fitzpatrick scalar kept")
    }

    @Test("VS-16 pictographic emoji: CUF(1) injected after it")
    func vs16EmojiGetsCUF() {
        // 🖥️ = U+1F5A5 + U+FE0F: Terminal.app under-advances by 1
        let s = "🖥️ TUIkit"
        let result = s.withTerminalAppCursorCompensation()
        // CUF(1) = ESC[1C should appear immediately after the emoji
        #expect(result.contains("🖥️\u{1B}[1C"), "CUF should be injected right after the VS-16 emoji")
    }

    @Test("Multiple VS-16 emoji: each gets its own CUF")
    func multipleVS16EmojiEachGetCUF() {
        let s = "🖥️A🖥️B"
        let result = s.withTerminalAppCursorCompensation()
        // Two occurrences of 🖥️ESC[1C expected
        let cufs = result.components(separatedBy: "\u{1B}[1C")
        #expect(cufs.count == 3, "Should have 2 CUF insertions (splitting into 3 parts)")
    }

    @Test("ANSI sequences in input are preserved unchanged")
    func ansiSequencesPreserved() {
        let s = "\u{1B}[31m🖥️\u{1B}[0m Text"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result.contains("\u{1B}[31m"), "Color code should be preserved")
        #expect(result.contains("\u{1B}[0m"), "Reset should be preserved")
        #expect(result.contains("🖥️\u{1B}[1C"), "CUF after emoji should be present")
    }

    @Test("strippedLength is unchanged by CUF injection")
    func strippedLengthPreserved() {
        // CUF sequences are ANSI and stripped by strippedLength,
        // so the visible width should be the same before and after compensation.
        let s = "🖥️ ABC"
        let compensated = s.withTerminalAppCursorCompensation()
        #expect(compensated.strippedLength == s.strippedLength)
    }
}

// MARK: - String.ansiAwarePrefixForTerminalApp

@Suite("String.ansiAwarePrefixForTerminalApp")
struct AnsiAwarePrefixForTerminalAppTests {

    @Test("Plain ASCII: same as ansiAwarePrefix")
    func plainASCII() {
        let s = "Hello, World!"
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 5) == "Hello")
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 100) == s)
    }

    @Test("Skin-tone emoji at right edge: replaced with bg-spaces to prevent wrap")
    func skinToneAtEdgeReplaced() {
        // The cluster's visible width fits in the remaining cells, but
        // its 4-cell cursor advance would push Terminal.app's cursor
        // past the right edge — at which point Terminal.app wraps the
        // glyph to the next row.  Replace it with plain spaces to keep
        // the layout intact (skin tone is sacrificed in this case).
        let s = "12345678🤙🏽"
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 10) == "12345678  ")
    }

    @Test("Mid-line skin-tone emoji is preserved (over-advance fits)")
    func midLineSkinTonePreserved() {
        // With plenty of room (visibleCount=20), the cluster's 4-cell
        // advance stays well within the line — it's kept verbatim and
        // the modifier-stripping decision is left to the compensation
        // function downstream.
        let s = "Call 🤙🏽 now"
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 20) == "Call 🤙🏽 now")
    }

    @Test("Wide CJK character respects the visible boundary (not over-advancing)")
    func cjkBoundary() {
        let s = "Hi 所有"
        // 'Hi ' = 3 cells, '所' = 2 cells — fits in 5.
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 5) == "Hi 所")
        // visibleCount=4 cannot fit '所' (would need cells 4-5, only cell 4 left).
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 4) == "Hi ")
    }

    @Test("ANSI sequences are preserved through truncation")
    func ansiPreserved() {
        let s = "\u{1B}[31mAB\u{1B}[0mCDE"
        let result = s.ansiAwarePrefixForTerminalApp(visibleCount: 3)
        #expect(result == "\u{1B}[31mAB\u{1B}[0mC")
    }
}

// MARK: - String.ansiSGRContextAndCleanSuffix

/// Tests for the "clean" variant that strips non-SGR sequences from the suffix
/// so it is safe to write at an absolute cursor position.
@Suite("String.ansiSGRContextAndCleanSuffix")
struct AnsiSGRContextAndCleanSuffixTests {

    // MARK: Basic behaviour (mirrors ansiSGRContextAndSuffix for plain strings)

    @Test("Plain string: suffix starts at correct visible offset")
    func plainStringSuffix() {
        let s = "ABCDE"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)
        #expect(result == "DE")
    }

    @Test("Plain string: offset 0 returns entire string")
    func offsetZeroReturnsAll() {
        let s = "ABCDE"
        #expect(s.ansiSGRContextAndCleanSuffix(from: 0) == "ABCDE")
    }

    @Test("Plain string: offset equal to length returns empty string")
    func offsetEqualLength() {
        let s = "ABC"
        #expect(s.ansiSGRContextAndCleanSuffix(from: 3) == "")
    }

    @Test("Plain string: offset beyond length returns nil")
    func offsetBeyondLength() {
        #expect("ABC".ansiSGRContextAndCleanSuffix(from: 4) == nil)
    }

    @Test("Empty string: offset 0 returns empty")
    func emptyStringOffset0() {
        #expect("".ansiSGRContextAndCleanSuffix(from: 0) == "")
    }

    @Test("Empty string: any positive offset returns nil")
    func emptyStringPositiveOffset() {
        #expect("".ansiSGRContextAndCleanSuffix(from: 1) == nil)
    }

    // MARK: The critical difference: CUF in suffix is stripped

    @Test("CUF after split is stripped from suffix (not included verbatim)")
    func cufAfterSplitIsStripped() {
        // This is the inverse of ansiSGRContextAndSuffix's "verbatim" behavior.
        // CUF must NOT appear in the result so writing at a fixed column is safe.
        let cuf = "\u{1B}[1C"
        let s = "ABC\(cuf)DE"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(!result.contains(cuf), "CUF after split must be stripped")
        #expect(result.contains("DE"), "Visible content after CUF must still be included")
    }

    @Test("CUF before split is also not in context (same as ansiSGRContextAndSuffix)")
    func cufBeforeSplitNotInContext() {
        let cuf = "\u{1B}[1C"
        let s = "A\(cuf)BCDE"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(!result.hasPrefix(cuf), "CUF must not appear in context prefix")
    }

    @Test("ESC[2K erase sequence in suffix is stripped")
    func eraseInSuffixStripped() {
        let eraseLine = "\u{1B}[2K"
        let s = "ABC\(eraseLine)DE"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(!result.contains(eraseLine), "Erase sequence in suffix must be stripped")
        #expect(result.contains("DE"))
    }

    // MARK: SGR sequences are preserved

    @Test("SGR context from before split is prepended to result")
    func sgrContextPrepended() {
        let red = "\u{1B}[31m"
        let reset = "\u{1B}[0m"
        let s = "\(red)ABCDE\(reset)"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(result.hasPrefix(red), "SGR context should be prepended")
        #expect(result.contains("DE"))
    }

    @Test("SGR sequences in suffix are kept")
    func sgrInSuffixKept() {
        let red   = "\u{1B}[31m"
        let reset = "\u{1B}[0m"
        // Color mid-string, split before the color change
        let s = "ABC\(red)DE\(reset)"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(result.contains(red), "SGR in suffix must be preserved")
        #expect(result.contains(reset), "Reset in suffix must be preserved")
        #expect(result.contains("DE"))
    }

    @Test("Mixed CUF and SGR in suffix: SGR kept, CUF stripped")
    func mixedCUFAndSGRInSuffix() {
        let cuf   = "\u{1B}[1C"
        let red   = "\u{1B}[31m"
        let reset = "\u{1B}[0m"
        let s = "ABC\(cuf)\(red)DE\(reset)"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(!result.contains(cuf), "CUF must be stripped")
        #expect(result.contains(red), "SGR must be kept")
        #expect(result.contains(reset), "Reset must be kept")
        #expect(result.contains("DE"))
    }

    // MARK: Key regression: VS-16 line with CUF injected by cursor compensation

    @Test("VS-16 emoji line: CUF injected by cursor compensation is stripped")
    func vs16CUFStrippedFromSuffix() {
        // 🖥️ triggers CUF(1) injection from withTerminalAppCursorCompensation().
        // If the split falls after the emoji, the CUF appears in the raw suffix.
        // ansiSGRContextAndCleanSuffix must strip it.
        let cuf = "\u{1B}[1C"
        let raw = "🖥️ TUIkit"
        let compensated = raw.withTerminalAppCursorCompensation()
        #expect(compensated.contains(cuf), "Prerequisite: CUF was injected")

        // Split right at cell 2 (after the emoji): suffix should contain "TUIkit" but not CUF
        let result = compensated.ansiSGRContextAndCleanSuffix(from: 2)
        #expect(result != nil)
        #expect(!result!.contains(cuf), "CUF must be stripped from clean suffix")
        #expect(result!.contains(" TUIkit"), "Visible content must remain")
    }

    @Test("Result contains no ESC[ sequences that are not SGR (m-terminated)")
    func noNonSGRSequencesInResult() {
        // Build a string with multiple ANSI sequence types
        let cuf       = "\u{1B}[1C"
        let eraseLine = "\u{1B}[2K"
        let red       = "\u{1B}[31m"
        let reset     = "\u{1B}[0m"
        let s = "\(red)AB\(cuf)CD\(eraseLine)EF\(reset)"
        // offset 2: A=1, B=2 → split after B
        let result = s.ansiSGRContextAndCleanSuffix(from: 2)!

        // Walk result and check every ESC sequence ends in 'm' (SGR)
        var idx = result.startIndex
        while idx < result.endIndex {
            if result[idx] == "\u{1B}" {
                idx = result.index(after: idx)
                if idx < result.endIndex && result[idx] == "[" {
                    idx = result.index(after: idx)
                    while idx < result.endIndex && (result[idx].isNumber || result[idx] == ";") {
                        idx = result.index(after: idx)
                    }
                    if idx < result.endIndex {
                        #expect(result[idx] == "m", "All ANSI sequences in clean suffix must be SGR (m), found: \(result[idx])")
                        idx = result.index(after: idx)
                    }
                }
            } else {
                idx = result.index(after: idx)
            }
        }
    }
}

// MARK: - Right-edge repaint: cursor column verification

/// Tests that verify the terminal sequences emitted by `repaintRightEdge`
/// target exactly the last 2 cells and nothing more.
@Suite("FrameDiffWriter repaintRightEdge column targeting")
@MainActor
struct RepaintRightEdgeColumnTests {

    // Helper: build a padded output line for a given text and terminal width.
    func makePaddedLine(text: String, terminalWidth: Int, bgCode: String, reset: String) -> String {
        let eraseLine = "\u{1B}[2K"
        let lineWithBg = text.replacingOccurrences(of: reset, with: reset + bgCode)
        let padding = max(0, terminalWidth - text.strippedLength)
        return bgCode + eraseLine + lineWithBg + String(repeating: " ", count: padding) + reset
    }

    @Test("Bare emoji row (no modifier): no repaint")
    func bareEmojiRowNotRepainted() {
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // 🤙 with no Fitzpatrick modifier: claimed width and Terminal.app
        // cursor advance both equal 2 — no quirk, no repaint needed.
        let line = makePaddedLine(text: "Hello 🤙 World", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        #expect(!line.containsTerminalAppCursorAdvanceQuirk, "Base 🤙 has no advance quirk")

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        #expect(!output.contains(repaintCursorSeq),
            "Repaint should NOT fire on a row without a cursor-advance quirk")
        #expect(!output.contains("\u{1B}[K"),
            "ESC[K should NOT be emitted on a non-quirky row")
    }

    @Test("Skin-tone-stripped row: right-edge repaint targets baseRepaintCol")
    func skinToneStrippedRowRepainted() {
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // The pre-rendered line emitted by `buildOutputLines` has already
        // had the Fitzpatrick scalar stripped (since the cluster is
        // followed by content here).  The remaining base emoji is a
        // normal 2-cell glyph with no over-advance — the line therefore
        // has no quirk and the repaint is skipped.
        let line = makePaddedLine(text: "Hi 🤙 X         ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        #expect(!line.containsTerminalAppCursorAdvanceQuirk,
            "Stripped cluster has no quirk")

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: terminalWidth - 1)
        #expect(!output.contains(repaintCursorSeq),
            "Repaint should NOT fire after Fitzpatrick stripping")
        #expect(!output.contains("\u{1B}[K"),
            "ESC[K should NOT be emitted on a stripped-cluster row")
    }

    @Test("Row without cursor-advance quirk: right-edge repaint is skipped")
    func plainRowNotRepainted() {
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // Plain line: no cursor-advance quirk — Terminal.app's right-edge
        // phantom-cell bug isn't triggered, so the repaint is skipped to
        // preserve content (including wide chars) at the boundary.
        let line = makePaddedLine(text: "Hello World!", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        #expect(!line.containsTerminalAppCursorAdvanceQuirk, "Prerequisite: plain ASCII has no quirk")

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        #expect(!output.contains(repaintCursorSeq),
            "Cursor should NOT move to repaintCol for non-quirky rows")
        #expect(!output.contains("\u{1B}[K"),
            "ESC[K should NOT be emitted for non-quirky rows")
    }

    @Test("VS-16 emoji row: right-edge repaint IS applied")
    func vs16EmojiGetsRepainted() {
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // 🖥️ has VS-16 — its CUF compensation can trigger right-edge issues too
        let line = makePaddedLine(text: "🖥️ TUIkit App    ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        #expect(output.contains(repaintCursorSeq),
            "VS-16 emoji rows should receive the right-edge repaint")
        #expect(output.contains("\u{1B}[K"),
            "ESC[K should be emitted for VS-16 emoji rows")
    }

    @Test("VS-16 repaint suffix covers at most 2 visible cells")
    func repaintSuffixExactly2Cells() {
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // VS-16 emoji 🖥️ — still triggers the quirk after compensation.
        let line = makePaddedLine(text: "Hello 🖥️ World", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        let allOutput = terminal.allOutput

        let range1 = allOutput.range(of: repaintCursorSeq)
        let suffixAfterPass1 = range1.map { allOutput[allOutput.index($0.upperBound, offsetBy: 0)...] } ?? allOutput[...]
        let range2 = suffixAfterPass1.range(of: repaintCursorSeq)

        if let range2 {
            let writtenAfterPass2 = String(suffixAfterPass1[range2.upperBound...])
            let visibleWidth = writtenAfterPass2.strippedLength
            #expect(visibleWidth <= 2,
                "Pass-2 suffix should write at most 2 visible cells, wrote \(visibleWidth)")
        }
    }

    @Test("Pass-2 suffix contains no CUF sequences (regression: 4-cell overdraw)")
    func pass2SuffixNoCUF() {
        // Regression test for the bug where ansiSGRContextAndSuffix was used in
        // repaintRightEdge instead of ansiSGRContextAndCleanSuffix.  A CUF in the
        // suffix displaced the cursor past the terminal edge, wrapping characters
        // to the next row.  Uses a VS-16 emoji at the right edge so CUF is
        // injected by withTerminalAppCursorCompensation.
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let terminalWidth = 12
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        let line = makePaddedLine(text: "Hi 🖥️ ABC", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let cuf = "\u{1B}[1C"
        let allOutput = terminal.allOutput

        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        if let range1 = allOutput.range(of: repaintCursorSeq),
           let range2 = allOutput[range1.upperBound...].range(of: repaintCursorSeq) {
            let pass2Content = String(allOutput[range2.upperBound...])
            #expect(!pass2Content.contains(cuf),
                "Pass-2 suffix must not contain CUF")
        }
    }

    @Test("Repaint only applies to changed rows")
    func repaintOnlyForChangedRows() {
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        let vs16Line   = makePaddedLine(text: "Hello 🖥️ World", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        let plainLine  = makePaddedLine(text: "Hello World     ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)

        writer.writeContentDiff(
            newLines: [vs16Line, plainLine], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )
        terminal.reset()

        // Second frame: identical lines → diff finds 0 changed rows → no repaint
        writer.writeContentDiff(
            newLines: [vs16Line, plainLine], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )
        let eraseCount2 = terminal.allOutput.components(separatedBy: "\u{1B}[K").count - 1
        #expect(eraseCount2 == 0,
            "No repaint should occur when no rows changed (was \(eraseCount2) ESC[K)")
    }

    @Test("Multi-row frame: only quirky rows get repainted")
    func multiRowOnlyQuirkyRepainted() {
        let writer = FrameDiffWriter()
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        let row0 = makePaddedLine(text: "Normal line     ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        let row1 = makePaddedLine(text: "Has 🖥️ emoji  ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        let row2 = makePaddedLine(text: "Another normal  ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)

        writer.writeContentDiff(
            newLines: [row0, row1, row2], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let eraseToEOL = "\u{1B}[K"
        let eraseCount = output.components(separatedBy: eraseToEOL).count - 1

        // Only the VS-16 row (row 1, written at terminal row 2) triggers repaint.
        #expect(eraseCount == 1, "Only the quirky row should be repainted, got \(eraseCount)")

        let repaintAtRow1 = ANSIRenderer.moveCursor(toRow: 1, column: terminalWidth - 1)
        let repaintAtRow2 = ANSIRenderer.moveCursor(toRow: 2, column: terminalWidth - 1)
        let repaintAtRow3 = ANSIRenderer.moveCursor(toRow: 3, column: terminalWidth - 1)
        #expect(!output.contains(repaintAtRow1), "Row 1 (plain) should not be repainted")
        #expect(output.contains(repaintAtRow2), "Row 2 (VS-16) should be repainted")
        #expect(!output.contains(repaintAtRow3), "Row 3 (plain) should not be repainted")
    }
}
