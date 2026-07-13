//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DividerRenderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Buffer-level render audit for `Divider`. A divider draws a single
//  horizontal rule that fills the available width. These tests assert the
//  rendered line is exactly one row, exactly the available width, made of a
//  continuous run of the divider character (no gaps), for the default
//  character, custom characters, narrow / wide widths, and inside a VStack.

import Testing

@testable import TUIkit

@MainActor
@Suite("Divider rendering")
struct DividerRenderTests {

    private func context(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    // MARK: - Default

    @Test("Default divider fills the width with a continuous box-drawing rule")
    func defaultFillsWidth() {
        let buffer = renderToBuffer(Divider(), context: context(width: 10))
        #expect(buffer.lines.count == 1, "Divider must be exactly one row, got \(buffer.lines.count)")
        let line = buffer.lines[0].stripped
        #expect(line == String(repeating: "─", count: 10), "Expected a 10-wide rule, got >>\(line)<<")
        #expect(line.strippedLength == 10, "Rule must fill exactly the available width")
        // Continuous: every visible character is the same divider glyph (no gaps).
        #expect(line.allSatisfy { $0 == "─" }, "Divider must be a continuous run with no gaps")
    }

    @Test("Divider width matches the available width exactly")
    func widthMatchesAvailable() {
        let buffer = renderToBuffer(Divider(), context: context(width: 25))
        #expect(buffer.width == 25, "Divider buffer width should equal available width 25, got \(buffer.width)")
        #expect(buffer.lines[0].stripped.strippedLength == 25)
    }

    // MARK: - Custom character

    @Test("Custom ASCII character fills the width")
    func customAsciiCharacter() {
        let buffer = renderToBuffer(Divider(character: "="), context: context(width: 6))
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "======")
        #expect(buffer.lines[0].stripped.allSatisfy { $0 == "=" })
    }

    @Test("Custom box-drawing character fills the width continuously")
    func customBoxDrawingCharacter() {
        let buffer = renderToBuffer(Divider(character: "═"), context: context(width: 7))
        let line = buffer.lines[0].stripped
        #expect(line == "═══════")
        #expect(line.strippedLength == 7, "Single-cell box glyph must fill exactly the width")
        #expect(line.allSatisfy { $0 == "═" })
    }

    // MARK: - Narrow / wide

    @Test("Narrow width still produces a single continuous row")
    func narrowWidth() {
        let buffer = renderToBuffer(Divider(), context: context(width: 1))
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "─")
    }

    @Test("Wide width fills the whole span with no gaps and no overflow")
    func wideWidth() {
        let buffer = renderToBuffer(Divider(), context: context(width: 120))
        let line = buffer.lines[0].stripped
        #expect(buffer.lines.count == 1)
        #expect(line.strippedLength == 120, "Wide divider must fill exactly 120 cells, got \(line.strippedLength)")
        #expect(line.allSatisfy { $0 == "─" }, "No gaps across the wide rule")
    }

    // MARK: - In a stack

    @Test("Divider between two texts is exactly one full-width row")
    func dividerInVStack() {
        let view = VStack(spacing: 0) {
            Text("Section 1")
            Divider()
            Text("Section 2")
        }
        let buffer = renderToBuffer(view, context: context(width: 13))
        #expect(buffer.lines.count == 3, "Two texts + one divider = 3 rows, got \(buffer.lines.count)")
        #expect(buffer.lines[0].stripped.contains("Section 1"))
        let rule = buffer.lines[1].stripped
        #expect(rule.contains("─"), "Middle row must be the divider rule, got >>\(rule)<<")
        #expect(rule.trimmingCharacters(in: ["─", " "]).isEmpty, "Divider row must contain only rule/padding, got >>\(rule)<<")
        #expect(buffer.lines[2].stripped.contains("Section 2"))
    }

    // MARK: - Colour

    @Test("Divider defaults to the palette's border colour")
    func defaultBorderColour() {
        let ctx = context(width: 8)
        let raw = renderToBuffer(Divider(), context: ctx).lines[0]
        let border = ctx.environment.palette.border.resolve(with: ctx.environment.palette)
        if let c = border.rgbComponents {
            #expect(
                raw.contains("38;2;\(c.red);\(c.green);\(c.blue)"),
                "separator chrome draws muted, not in the body-text colour: >>\(raw)<<")
        } else {
            #expect(raw != raw.stripped, "the rule carries a colour, not bare text")
        }
    }

    @Test("An explicit foregroundStyle overrides the border default")
    func foregroundStyleOverrides() {
        let raw = renderToBuffer(
            Divider().foregroundStyle(.rgb(10, 20, 30)), context: context(width: 8)
        ).lines[0]
        #expect(raw.contains("38;2;10;20;30"), ">>\(raw)<<")
    }

    // MARK: - sizeThatFits contract

    @Test("Divider advertises flexible width and a single row of height")
    func sizeContract() {
        let size = Divider().sizeThatFits(proposal: .unspecified, context: context())
        #expect(size.height == 1, "Divider height must be 1, got \(size.height)")
        #expect(size.isWidthFlexible, "Divider must be width-flexible so it stretches to fill")
        #expect(!size.isHeightFlexible, "Divider must not be height-flexible")
    }
}
