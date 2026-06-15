//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextRenderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Buffer-level render audit for `Text`. Complements the wrapping /
//  truncation focused tests in `TextTests.swift` by asserting on the
//  rendered FrameBuffer for the default, empty, multi-line, wide, narrow,
//  and styled configurations: exact stripped content, line counts (no
//  stray blank lines), width clamping, and that styling / inherited colour
//  is actually emitted as ANSI.

import Testing

@testable import TUIkit

@MainActor
@Suite("Text rendering")
struct TextRenderTests {

    private func context(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    // MARK: - Default

    @Test("Default short text renders one line with exact content")
    func defaultSingleLine() {
        let buffer = renderToBuffer(Text("Hello, World!"), context: context())
        #expect(buffer.lines.count == 1, "Single short text must be exactly one line, got \(buffer.lines.count)")
        #expect(buffer.lines[0].stripped == "Hello, World!")
        // It must not be padded out to the available width.
        #expect(buffer.lines[0].stripped.strippedLength == 13)
    }

    @Test("Text reports its own width, not the available width")
    func widthIsContentWidth() {
        let buffer = renderToBuffer(Text("Hi"), context: context(width: 30))
        #expect(buffer.width == 2, "Buffer width should match the content (2), got \(buffer.width)")
    }

    // MARK: - Empty / whitespace

    @Test("Empty text renders a single empty line (no extra rows)")
    func emptyText() {
        let buffer = renderToBuffer(Text(""), context: context())
        // A primitive Text("") legitimately occupies one (empty) line; it
        // must NOT expand to fill the available height with blank rows.
        #expect(buffer.lines.count == 1, "Empty text must be a single line, got \(buffer.lines.count)")
        #expect(buffer.lines[0].stripped.isEmpty, "Empty text line must be visibly empty, got >>\(buffer.lines[0].stripped)<<")
    }

    @Test("verbatim initializer renders the string unchanged")
    func verbatim() {
        let buffer = renderToBuffer(Text(verbatim: "raw {value}"), context: context())
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "raw {value}")
    }

    // MARK: - Multi-line (explicit newlines)

    @Test("Explicit newlines produce one buffer line each with no raw control chars")
    func explicitNewlines() {
        let buffer = renderToBuffer(Text("Top\nMiddle\nBottom"), context: context())
        #expect(buffer.lines.count == 3, "Three newline-separated lines expected, got \(buffer.lines.count)")
        #expect(buffer.lines.map { $0.stripped } == ["Top", "Middle", "Bottom"])
        #expect(buffer.lines.allSatisfy { !$0.contains("\n") && !$0.contains("\r") },
                "No buffer line may carry a raw newline/carriage-return")
    }

    @Test("A blank line between paragraphs is preserved, not collapsed")
    func blankLinePreserved() {
        let buffer = renderToBuffer(Text("A\n\nB"), context: context())
        #expect(buffer.lines.count == 3, "Blank middle line must be preserved, got \(buffer.lines.count)")
        #expect(buffer.lines[0].stripped == "A")
        #expect(buffer.lines[1].stripped.isEmpty, "Middle line should be blank, got >>\(buffer.lines[1].stripped)<<")
        #expect(buffer.lines[2].stripped == "B")
    }

    // MARK: - Wrapping (wide content)

    @Test("Long text word-wraps at word boundaries within the width")
    func wordWrap() {
        let buffer = renderToBuffer(Text("one two three four"), context: context(width: 8))
        #expect(buffer.lines.map { $0.stripped } == ["one two", "three", "four"],
                "Unexpected wrap: \(buffer.lines.map { $0.stripped })")
        // No wrapped line may exceed the available width.
        #expect(buffer.lines.allSatisfy { $0.stripped.strippedLength <= 8 })
    }

    @Test("Wide width leaves short content on one line")
    func wideWidthSingleLine() {
        let buffer = renderToBuffer(Text("Short"), context: context(width: 120))
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "Short")
    }

    // MARK: - Narrow width / truncation

    @Test("A word longer than the width is truncated with a tail ellipsis")
    func longWordTruncates() {
        let buffer = renderToBuffer(Text("Supercalifragilistic"), context: context(width: 10))
        let line = buffer.lines[0].stripped
        #expect(line.strippedLength == 10, "Truncated line must exactly fill the width, got \(line.strippedLength)")
        #expect(line.hasSuffix("…"), "Tail truncation must end with an ellipsis, got >>\(line)<<")
        #expect(line == "Supercali…")
    }

    @Test("Head truncation keeps the tail of the content")
    func headTruncation() {
        let buffer = renderToBuffer(Text("Supercalifragilistic").truncationMode(.head), context: context(width: 10))
        let line = buffer.lines[0].stripped
        #expect(line.hasPrefix("…"), "Head truncation must start with an ellipsis, got >>\(line)<<")
        #expect(line.strippedLength == 10)
    }

    // MARK: - CJK / wide characters

    @Test("CJK text is measured at two cells per glyph")
    func cjkWidth() {
        let buffer = renderToBuffer(Text("你好"), context: context(width: 30))
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "你好")
        #expect(buffer.width == 4, "Two CJK glyphs occupy 4 cells, got \(buffer.width)")
    }

    // MARK: - Styling emits ANSI

    @Test("foregroundStyle on the Text emits the colour as ANSI")
    func explicitForegroundColor() {
        let buffer = renderToBuffer(Text("Red").foregroundStyle(.red), context: context())
        #expect(buffer.lines[0].stripped == "Red", "Visible content must be unchanged by colour")
        #expect(buffer.lines[0].contains("\u{1B}[31m"), "Red foreground ANSI code must be present")
    }

    @Test("bold emits the SGR bold attribute")
    func boldEmitsAnsi() {
        let buffer = renderToBuffer(Text("Bold").bold(), context: context())
        #expect(buffer.lines[0].stripped == "Bold")
        // The renderer joins all SGR parameters into one CSI sequence
        // (e.g. "\u{1B}[1;38;2;...m"), so bold appears as the leading `1`
        // parameter immediately after the CSI.
        #expect(buffer.lines[0].contains("\u{1B}[1;") || buffer.lines[0].contains("\u{1B}[1m"),
                "Bold should emit SGR attribute 1, got >>\(buffer.lines[0])<<")
    }

    @Test("Inherited foregroundStyle from the environment colours the text")
    func inheritsEnvironmentColor() {
        // foregroundStyle applied to a parent must flow down to a plain Text.
        let view = VStack { Text("Inherited") }.foregroundStyle(.blue)
        let buffer = renderToBuffer(view, context: context())
        #expect(buffer.lines[0].stripped == "Inherited")
        #expect(buffer.lines[0].contains("\u{1B}[34m"), "Inherited blue foreground must be emitted")
    }

    // MARK: - lineLimit

    @Test("lineLimit caps the rendered rows and ellipsizes the last")
    func lineLimitCaps() {
        let view = Text("one two three four five six seven").lineLimit(2)
        let buffer = renderToBuffer(view, context: context(width: 10, height: 8))
        #expect(buffer.lines.count == 2, "lineLimit(2) must cap at 2 rows, got \(buffer.lines.count)")
        #expect(buffer.lines.last?.stripped.contains("…") == true,
                "The final capped line must carry a truncation ellipsis")
        #expect(buffer.lines.allSatisfy { $0.stripped.strippedLength <= 10 })
    }
}
