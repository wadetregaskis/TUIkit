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
        makeBareRenderContext(width: width, height: 24)
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

    /// The trap the test above couldn't see: its sample has an ASCII SPACE.
    /// Chinese and Japanese put no spaces between words, and spaces were the
    /// only break the wrapper knew — a space-less paragraph was one giant
    /// "word", placed on ONE line, and the fit pass then truncated it: all
    /// content past the first visual line silently dropped, in every zh/ja
    /// string the example app ships. Breaks are permitted between ideographs
    /// (UAX #14), so the paragraph must wrap like prose.
    @Test("Space-less CJK paragraphs wrap instead of truncating to one line")
    func spacelessCJKWraps() {
        let paragraph = "这是一段没有空格的中文说明文字会被完整地保留"  // 22 chars, 44 cells
        let wrapped = TextWrapping.wrapMeasured(paragraph, width: 10)
        #expect(wrapped.lines.count == 5, "44 cells at width 10: \(wrapped.lines)")
        #expect(wrapped.widths.allSatisfy { $0 <= 10 }, "every line fits: \(wrapped.widths)")
        #expect(
            wrapped.lines.joined() == paragraph,
            "wrapping loses NOTHING — the old path truncated all but line 1")

        // And the fit pass keeps its line budget instead of eating the rest.
        let fitted = TextWrapping.fit(paragraph, width: 10, maxLines: 3)
        #expect(fitted.count == 3)
        #expect(fitted.last?.hasSuffix("…") == true, "the fold is shown, not silent")
    }

    @Test("Mixed-script text keeps Latin words whole between ideographs")
    func mixedScriptWrap() {
        // The Latin word is an unbreakable unit; the ideographs around it
        // each carry their own break opportunities.
        let wrapped = TextWrapping.wrapMeasured("端末TUIkit框架", width: 8)
        #expect(
            wrapped.lines.joined() == "端末TUIkit框架",
            "nothing lost: \(wrapped.lines)")
        #expect(wrapped.widths.allSatisfy { $0 <= 8 }, "every line fits: \(wrapped.widths)")
        #expect(
            wrapped.lines.contains { $0.contains("TUIkit") },
            "the Latin word survives whole on one line: \(wrapped.lines)")
    }

    @Test("A space-less CJK Text renders every line, not just the first")
    func spacelessCJKTextRenders() {
        let text = Text("这是一段没有空格的中文说明文字")  // 15 chars, 30 cells
        let context = testContext(width: 10)
        let size = text.sizeThatFits(
            proposal: ProposedSize(width: 10, height: nil), context: context)
        #expect(size.height == 3, "30 cells at width 10 is 3 lines, got \(size.height)")
    }
}

// MARK: - Explicit Line Break Tests

@MainActor
@Suite("Text Explicit Line Break Tests")
struct TextLineBreakTests {

    private func context(width: Int, height: Int = 24) -> RenderContext {
        makeBareRenderContext(width: width, height: height)
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
        #expect(buffer.lines[1].stripped.isEmpty)
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

// MARK: - Whitespace

/// Spaces the author wrote are content. The word walk in
/// `TextWrapping.wrapParagraph` used to lose the LEADING run — splitting
/// `" Cut"` yields `["", "Cut"]`, and an empty first token was
/// indistinguishable from "nothing on this line yet" — so `Text("  Item")`
/// drew `"Item"` and indentation was impossible.
@MainActor
@Suite("Text whitespace")
struct TextWhitespaceTests {

    private func context(width: Int, height: Int = 24) -> RenderContext {
        makeBareRenderContext(width: width, height: height)
    }

    private func render(_ text: String, width: Int) -> [String] {
        renderToBuffer(Text(text), context: context(width: width)).lines.map(\.stripped)
    }

    @Test("A leading space is drawn, not swallowed")
    func leadingSpaceSurvives() {
        #expect(render(" Cut", width: 40) == [" Cut"])
        #expect(render("   deeply indented", width: 40) == ["   deeply indented"])
    }

    @Test("Trailing and interior spaces are preserved as written")
    func otherSpacesSurvive() {
        #expect(render("Cut ", width: 40) == ["Cut "])
        #expect(render("a  b", width: 40) == ["a  b"])
        #expect(render("  ", width: 40) == ["  "], "an all-space line is space, not empty")
    }

    /// The measure and the render must agree, or a parent reserves the wrong
    /// number of cells and the text is clipped (or floats in dead space).
    @Test("The measured width matches the rendered width")
    func measureMatchesRender() {
        for text in [" Cut", "   x", "Cut ", "a  b", "  ", "", "plain"] {
            let size = Text(text).sizeThatFits(
                proposal: .unspecified, context: context(width: 40))
            let drawn = render(text, width: 40).map(\.strippedLength).max() ?? 0
            #expect(
                size.width == drawn,
                "\(text.debugDescription): measured \(size.width), drew \(drawn)")
        }
    }

    /// The indent belongs to the first line only — a soft-wrapped continuation
    /// starts at the margin, as it does in every other text system.
    @Test("A wrapped continuation line is not re-indented")
    func continuationIsNotIndented() {
        let lines = render("  one two three four", width: 10)
        #expect(lines.first == "  one two", "the indent eats into the first line's room: \(lines)")
        #expect(
            lines.dropFirst().allSatisfy { !$0.hasPrefix(" ") },
            "continuations start at the margin: \(lines)")
        // …so they must be WRAPPED at the full width too. Wrapping them against
        // width − indent made every continuation up to `indent.count` cells
        // narrower than the room it renders into: "three four" is exactly 10
        // cells and fits, but used to break into two lines.
        #expect(lines == ["  one two", "three four"])
    }

    /// The cost of the too-narrow continuation was not only an extra line: under
    /// a line limit the fold truncated content that fits.
    @Test("An indented paragraph does not lose content to a line limit")
    func indentedParagraphKeepsContentUnderLineLimit() {
        #expect(
            TextWrapping.fit("  one two three four", width: 10, maxLines: 2)
                == ["  one two", "three four"])
    }

    /// The wide-character walk is a second, independent implementation of the
    /// same rule, so it needs its own case — a fix to the space walk alone
    /// leaves this one wrapping short.
    @Test("An indented CJK paragraph wraps continuations at the full width")
    func indentedCJKContinuationUsesFullWidth() {
        let wrapped = TextWrapping.wrapMeasured("  一二三四五六七八九", width: 10)
        #expect(wrapped.lines == ["  一二三四", "五六七八九"])
        #expect(wrapped.widths == [10, 10])
    }

    @Test("Explicit line breaks each get their own indent")
    func perParagraphIndent() {
        #expect(render("  a\n    b", width: 40) == ["  a", "    b"])
    }

    /// `.textCase` is applied when the text is DRAWN, so it must be applied
    /// when the text is MEASURED too: the German ß uppercases to two
    /// characters, so a measure of the untransformed string reserves one cell
    /// too few and the render is clipped.
    @Test("A width-changing text case is measured as it will be drawn")
    func textCaseIsMeasured() {
        let view = Text("straße").textCase(.uppercase)
        let context = context(width: 40)
        let size = measureChild(
            view, proposal: ProposedSize(width: 40, height: nil), context: context)
        let drawn = renderToBuffer(view, context: context).lines.map(\.stripped)

        #expect(drawn == ["STRASSE"], "sanity: the render uppercases, got \(drawn)")
        #expect(
            size.width == drawn[0].strippedLength,
            "measured \(size.width), drew \(drawn[0].strippedLength) cells")
    }

    /// A width budget of zero means the render draws nothing (every line goes
    /// through `truncatedToWidth(0)`), so the measure must not claim cells the
    /// parent would then reserve for text that never appears.
    @Test("A zero width budget measures as zero, matching what is drawn")
    func zeroWidthMeasuresZero() {
        let view = Text("Hello")
        let context = context(width: 0)
        let size = view.sizeThatFits(proposal: .unspecified, context: context)
        let drawn = renderToBuffer(view, context: context).lines.map(\.stripped)

        #expect(drawn.allSatisfy { $0.isEmpty }, "sanity: nothing is drawn, got \(drawn)")
        #expect(size.width == 0, "measured \(size.width) cells for text that draws none")
    }

    /// An indent wider than the width is emitted and left to the caller to
    /// truncate — the same contract a single over-long word has.
    @Test("An indent wider than the width does not produce a blank line")
    func indentWiderThanWidth() {
        let lines = TextWrapping.wrap("    x", width: 3)
        #expect(lines.count == 1, "no phantom blank first line: \(lines)")
        #expect(lines[0] == "    x")
    }
}

// MARK: - Text Truncation Tests

@MainActor
@Suite("Text Truncation Tests")
struct TextTruncationTests {

    private func context(width: Int, height: Int = 24) -> RenderContext {
        makeBareRenderContext(width: width, height: height)
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
        #expect("Hello".truncatedToWidth(0).isEmpty)
        #expect("Hello".truncatedToWidth(-3).isEmpty)
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
