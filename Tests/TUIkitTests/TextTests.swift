//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Text Terminal Width Tests")
struct TextTerminalWidthTests {

    private func testContext(width: Int = 80) -> RenderContext {
        RenderContext(
            availableWidth: width,
            availableHeight: 24,
            tuiContext: TUIContext()
        )
    }

    @Test("Text with CJK characters reports correct terminal width")
    func cjkTextWidth() {
        // Each CJK character occupies 2 terminal cells
        let text = Text("你好")  // 2 CJK chars = 4 terminal cells
        let context = testContext(width: 80)
        let size = text.sizeThatFits(proposal: ProposedSize(width: 80, height: nil), context: context)
        #expect(size.width == 4, "CJK text '你好' should report width 4 (2 cells per character), got \(size.width)")
    }

    @Test("Text with ASCII characters reports correct terminal width")
    func asciiTextWidth() {
        let text = Text("Hello")
        let context = testContext(width: 80)
        let size = text.sizeThatFits(proposal: ProposedSize(width: 80, height: nil), context: context)
        #expect(size.width == 5, "ASCII text 'Hello' should report width 5")
    }

    @Test("Text with mixed ASCII and CJK reports correct terminal width")
    func mixedTextWidth() {
        // "Hi你好" = 2 ASCII (2 cells) + 2 CJK (4 cells) = 6 terminal cells
        let text = Text("Hi你好")
        let context = testContext(width: 80)
        let size = text.sizeThatFits(proposal: ProposedSize(width: 80, height: nil), context: context)
        #expect(size.width == 6, "Mixed text 'Hi你好' should report width 6, got \(size.width)")
    }

    @Test("Text word-wraps CJK text at correct terminal width boundary")
    func cjkWordWrap() {
        // "你好 世界" = word1 "你好" (4 cells) + space + word2 "世界" (4 cells) = 9 cells
        // With maxWidth 6, should wrap to 2 lines
        let text = Text("你好 世界")
        let context = testContext(width: 6)
        let size = text.sizeThatFits(proposal: ProposedSize(width: 6, height: nil), context: context)
        #expect(size.height == 2, "CJK text should wrap to 2 lines at width 6, got \(size.height)")
        #expect(size.width == 4, "Each line should be 4 cells wide, got \(size.width)")
    }
}

// MARK: - Explicit Line Break Tests

@MainActor
@Suite("Text Explicit Line Break Tests")
struct TextLineBreakTests {

    private func context(width: Int, height: Int = 24) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    @Test("Embedded newlines split into separate buffer lines")
    func newlineSplitsLines() {
        // A raw "\n" left inside a buffer line would be interpreted by the
        // terminal as a real row break, corrupting the rows below it.
        let text = Text("Hi,\n\nBest,\nAlice")
        let buffer = renderToBuffer(text, context: context(width: 80))

        #expect(buffer.height == 4, "Expected 4 lines, got \(buffer.height)")
        #expect(buffer.lines.allSatisfy { !$0.contains("\n") }, "No buffer line may contain a raw newline")
        #expect(buffer.lines[0].stripped == "Hi,")
        #expect(buffer.lines[1].stripped == "")
        #expect(buffer.lines[2].stripped == "Best,")
        #expect(buffer.lines[3].stripped == "Alice")
    }

    @Test("Each paragraph wraps independently")
    func paragraphsWrapIndependently() {
        // First paragraph is long enough to wrap; second is short.
        let text = Text("one two three four five\n\ndone")
        let buffer = renderToBuffer(text, context: context(width: 10))

        #expect(buffer.lines.allSatisfy { !$0.contains("\n") })
        #expect(buffer.lines.last?.stripped == "done", "Final paragraph must not be merged into the wrap of the first")
    }

    @Test("sizeThatFits accounts for explicit newlines")
    func sizeAccountsForNewlines() {
        let text = Text("a\nb\nc")
        let size = text.sizeThatFits(proposal: .unspecified, context: context(width: 80))
        #expect(size.height == 3, "Three newline-separated lines should report height 3, got \(size.height)")
    }

    @Test("Carriage returns are treated as line breaks")
    func carriageReturnsSplit() {
        let text = Text("first\r\nsecond")
        let buffer = renderToBuffer(text, context: context(width: 80))
        #expect(buffer.height == 2, "CRLF should split into 2 lines, got \(buffer.height)")
        #expect(buffer.lines.allSatisfy { !$0.contains("\r") && !$0.contains("\n") })
    }
}

// MARK: - Text Truncation Tests

@MainActor
@Suite("Text Truncation Tests")
struct TextTruncationTests {

    private func context(width: Int, height: Int = 24) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    @Test("A word longer than the width truncates with a tail ellipsis")
    func longWordTailTruncates() {
        let buffer = renderToBuffer(Text("Supercalifragilistic"), context: context(width: 10))
        let line = buffer.lines[0].stripped
        #expect(line.strippedLength == 10, "Truncated line must fill exactly the width, got \(line.strippedLength)")
        #expect(line.hasSuffix("…"), "Tail truncation must end with an ellipsis, got \(line)")
        #expect(line == "Supercali…")
    }

    @Test("Head truncation keeps the end of the text")
    func headTruncation() {
        let text = Text("Supercalifragilistic").truncationMode(.head)
        let line = renderToBuffer(text, context: context(width: 10)).lines[0].stripped
        #expect(line.hasPrefix("…"), "Head truncation must start with an ellipsis, got \(line)")
        #expect(line.hasSuffix("c"), "Head truncation keeps the end of the text, got \(line)")
        #expect(line.strippedLength == 10)
    }

    @Test("Middle truncation keeps both ends")
    func middleTruncation() {
        let text = Text("Supercalifragilistic").truncationMode(.middle)
        let line = renderToBuffer(text, context: context(width: 11)).lines[0].stripped
        #expect(line.contains("…"))
        #expect(line.hasPrefix("Supe"), "Middle truncation keeps the start, got \(line)")
        #expect(line.hasSuffix("istic"), "Middle truncation keeps the end, got \(line)")
    }

    @Test("Text that fits is not truncated")
    func fittingTextUnchanged() {
        let line = renderToBuffer(Text("Hello"), context: context(width: 40)).lines[0].stripped
        #expect(line == "Hello")
        #expect(!line.contains("…"))
    }

    @Test("Height-constrained text fills and marks the final visible line")
    func heightTruncationFillsLastLine() {
        // Four explicit lines rendered into two rows of space: the first
        // row shows the first line, the last row absorbs the remaining
        // content rather than dropping it behind a bare ellipsis.
        let buffer = renderToBuffer(Text("a\nb\nc\nd"), context: context(width: 40, height: 2))
        #expect(buffer.height == 2, "Expected the text clipped to 2 rows, got \(buffer.height)")
        #expect(buffer.lines[0].stripped == "a")
        #expect(
            buffer.lines[1].stripped == "b c d…",
            "Final visible line must absorb the remaining content, got \(buffer.lines[1].stripped)"
        )
    }

    @Test("Default truncation cuts at any character position")
    func defaultTruncationCutsAnywhere() {
        let line = "Hello Wonderful Day".truncatedToWidth(13)
        #expect(line == "Hello Wonder…", "Default truncation fills the line, got \(line)")
    }

    @Test("Word-boundary truncation cuts back to a whole word")
    func wordBoundaryTruncation() {
        let line = "Hello Wonderful Day".truncatedToWidth(13, atWordBoundary: true)
        #expect(line == "Hello…", "Word-boundary truncation keeps whole words, got \(line)")
    }

    @Test("Word-boundary truncation falls back to mid-word for a single long word")
    func wordBoundarySingleLongWord() {
        let line = "Supercalifragilistic".truncatedToWidth(10, atWordBoundary: true)
        #expect(line == "Supercali…", "A single over-long word must still be cut, got \(line)")
    }

    @Test("Text honours the word-boundary truncation modifier")
    func textWordBoundaryModifier() {
        let anyPosition = renderToBuffer(
            Text("Hello Wonderful Day"),
            context: context(width: 13, height: 1)
        ).lines[0].stripped
        let wordBoundary = renderToBuffer(
            Text("Hello Wonderful Day").truncatesAtWordBoundary(),
            context: context(width: 13, height: 1)
        ).lines[0].stripped

        #expect(anyPosition == "Hello Wonder…", "Default should fill the line, got \(anyPosition)")
        #expect(wordBoundary == "Hello…", "Word-boundary mode should keep whole words, got \(wordBoundary)")
    }

    @Test("truncatedToWidth respects terminal cell width of wide characters")
    func truncateWideCharacters() {
        // Four CJK characters = 8 cells; truncate to 5 cells.
        let result = "你好世界".truncatedToWidth(5)
        #expect(result.strippedLength <= 5, "Must not exceed 5 cells, got \(result.strippedLength)")
        #expect(result.hasSuffix("…"))
        #expect(result == "你好…")
    }

    @Test("truncatedToWidth forceEllipsis appends to a fitting string")
    func truncateForceEllipsis() {
        #expect("Best,".truncatedToWidth(40, forceEllipsis: true) == "Best,…")
        #expect("Best,".truncatedToWidth(5, forceEllipsis: true) == "Best…")
    }

    @Test("truncatedToWidth degrades gracefully at tiny widths")
    func truncateTinyWidths() {
        #expect("Hello".truncatedToWidth(1) == "…")
        #expect("Hello".truncatedToWidth(0) == "")
        #expect("Hello".truncatedToWidth(-3) == "")
    }

    @Test("lineLimit caps the number of rendered lines")
    func lineLimitCapsLines() {
        let text = Text("one two three four five six seven eight").lineLimit(2)
        let buffer = renderToBuffer(text, context: context(width: 12, height: 24))
        #expect(buffer.height == 2, "lineLimit(2) must cap the text at 2 lines, got \(buffer.height)")
        #expect(
            buffer.lines.last?.stripped.contains("…") == true,
            "The final line must show a truncation ellipsis"
        )
    }

    @Test("lineLimit caps the measured height")
    func lineLimitCapsMeasuredHeight() {
        let text = Text("one two three four five six").lineLimit(1)
        let size = text.sizeThatFits(
            proposal: ProposedSize(width: 10, height: nil),
            context: context(width: 10)
        )
        #expect(size.height == 1, "lineLimit(1) must report height 1, got \(size.height)")
    }

    @Test("lineLimit(nil) imposes no limit")
    func lineLimitNilNoLimit() {
        let text = Text("one two three four five six").lineLimit(nil)
        let buffer = renderToBuffer(text, context: context(width: 10, height: 24))
        #expect(buffer.height > 2, "lineLimit(nil) should not cap the lines, got \(buffer.height)")
    }
}
