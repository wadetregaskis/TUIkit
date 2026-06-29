//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewRenderTests.swift
//
//  Buffer-level render audit for ScrollView. A ScrollView is greedy on
//  both axes (fills its viewport) and windows into a taller content
//  buffer, overwriting the top / bottom rows with "N more above / below"
//  indicators when content extends past the viewport.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("ScrollView rendering")
struct ScrollViewRenderTests {

    private func ctx(width: Int, height: Int) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    // MARK: - Fills its viewport

    @Test("Short content fills the full viewport height with blank rows")
    func shortContentFillsViewport() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) {
                    Text("L0")
                    Text("L1")
                }
            },
            context: ctx(width: 20, height: 6)
        )
        #expect(buffer.lines.count == 6, "ScrollView fills the whole viewport")
        #expect(buffer.width == 20, "Every row padded to the full viewport width")
        #expect(buffer.lines[0].stripped == "L0".padding(toLength: 20, withPad: " ", startingAt: 0))
        #expect(buffer.lines[1].stripped == "L1".padding(toLength: 20, withPad: " ", startingAt: 0))
        // Remaining rows are blank fill.
        for index in 2..<6 {
            #expect(buffer.lines[index].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test("Short content shows no scroll indicators")
    func shortContentNoIndicators() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) { Text("only line") }
            },
            context: ctx(width: 20, height: 6)
        )
        let joined = buffer.lines.map { $0.stripped }.joined()
        #expect(!joined.contains("more above"))
        #expect(!joined.contains("more below"))
    }

    // MARK: - Trailing Spacer (flexible filler)

    @Test("A trailing Spacer is not mistaken for overflowing content")
    func trailingSpacerFits() {
        // A Spacer expands to fill the tall measure canvas; its blank lines must
        // not be counted as content, or a fitting page shows a bogus overflow.
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) {
                    Text("A")
                    Text("B")
                    Text("C")
                    Spacer()
                }
            },
            context: ctx(width: 20, height: 8)
        )
        let joined = buffer.lines.map { $0.stripped }.joined()
        #expect(!joined.contains("more below"), "3 lines + Spacer fit in 8 rows: \(buffer.lines.map { $0.stripped })")
    }

    @Test("A trailing Spacer doesn't inflate the overflow count to the canvas height")
    func trailingSpacerSaneOverflow() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(0..<20, id: \.self) { Text("Line \($0)") }
                    Spacer()
                }
            },
            context: ctx(width: 20, height: 8)
        )
        let lines = buffer.lines.map { $0.stripped }
        let indicator = lines.first { $0.contains("more below") } ?? ""
        let count = indicator.split { !$0.isNumber }.compactMap { Int($0) }.first ?? -1
        #expect(count > 0 && count < 20, "overflow count is the real remainder, not the measure canvas: \(indicator)")
    }

    @Test("A middle Spacer spreads content to the viewport edges without forcing scroll")
    func middleSpacerSpreads() {
        // `VStack { Text; Spacer; Text }` shorter than the viewport: the Spacer
        // fills only to the viewport, putting the two texts at the top and bottom
        // with no overflow — rather than collapsing (SwiftUI) or pushing the second
        // text thousands of lines down (the pre-fix bug).
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) {
                    Text("top")
                    Spacer()
                    Text("bottom")
                }
            },
            context: ctx(width: 20, height: 8)
        )
        let lines = buffer.lines.map { $0.stripped }
        #expect(lines.count == 8, "fills the viewport: \(lines)")
        #expect(lines.first?.contains("top") == true, "first line is 'top': \(lines)")
        #expect(lines.last?.contains("bottom") == true, "last line is 'bottom': \(lines)")
        #expect(!lines.joined().contains("more below"), "fits — no overflow: \(lines)")
    }

    // MARK: - Overflowing content (bottom indicator)

    @Test("Tall content shows a 'N more below' indicator at the bottom edge")
    func tallContentBottomIndicator() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(0..<20) { Text("Line \($0)") }
                }
            },
            context: ctx(width: 20, height: 6)
        )
        #expect(buffer.lines.count == 6)
        // At rest (offset 0) the top shows real content, the bottom row is
        // the "more below" indicator.
        #expect(buffer.lines[0].stripped.hasPrefix("Line 0"))
        let lastLine = buffer.lines[5].stripped
        #expect(lastLine.contains("more below"), "Bottom row should be the down indicator, got '\(lastLine)'")
        // No top indicator while we are at the very top.
        #expect(!buffer.lines[0].stripped.contains("more above"))
    }

    @Test("showsIndicators:false suppresses the indicator and shows raw content")
    func indicatorsSuppressed() {
        let buffer = renderToBuffer(
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading) {
                    ForEach(0..<20) { Text("Line \($0)") }
                }
            },
            context: ctx(width: 20, height: 6)
        )
        #expect(buffer.lines.count == 6)
        let joined = buffer.lines.map { $0.stripped }.joined()
        #expect(!joined.contains("more below"), "No indicator when suppressed")
        // The bottom row shows real content (Line 5) rather than chrome.
        #expect(buffer.lines[5].stripped.hasPrefix("Line 5"))
    }

    // MARK: - Disabled

    @Test("A disabled ScrollView still renders its content")
    func disabledStillRenders() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) { Text("A"); Text("B") }
            }
            .disabled(),
            context: ctx(width: 20, height: 5)
        )
        #expect(buffer.lines.count == 5)
        #expect(buffer.lines[0].stripped.hasPrefix("A"))
        #expect(buffer.lines[1].stripped.hasPrefix("B"))
    }

    // MARK: - Greedy sizing

    @Test("ScrollView fills the available width even for narrow content")
    func fillsWidth() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) { Text("x") }
            },
            context: ctx(width: 25, height: 4)
        )
        #expect(buffer.width == 25, "Greedy on width — fills the viewport")
        for line in buffer.lines {
            #expect(line.strippedLength == 25)
        }
    }

    // MARK: - Zero-height viewport

    @Test("A zero-height viewport renders no rows")
    func zeroHeightViewport() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack { Text("hidden") }
            },
            context: ctx(width: 20, height: 0)
        )
        #expect(buffer.lines.isEmpty)
    }

    // MARK: - Scrollbar

    @Test("A visible scrollbar adds a trailing block-glyph column with end arrows")
    func visibleScrollbarColumn() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<20, id: \.self) { Text("line \($0)") }
                }
            }
            .scrollbarVisibility(.visible),
            context: ctx(width: 20, height: 6)
        )
        #expect(buffer.width == 20, "the scrollbar sits inside the viewport width")
        let lastColumn = buffer.lines.map { $0.stripped.last ?? " " }
        #expect(lastColumn.first == "▲", "single-arrow top: \(lastColumn)")
        #expect(lastColumn.last == "▼", "single-arrow bottom: \(lastColumn)")
        // The track cells between the arrows are block glyphs or spaces, with at
        // least one filled (the thumb).
        let track = lastColumn.dropFirst().dropLast()
        let blockOrSpace: Set<Character> = ["█", "▁", "▂", "▃", "▄", "▅", "▆", "▇", " "]
        #expect(track.allSatisfy { blockOrSpace.contains($0) }, "track is block glyphs: \(lastColumn)")
        #expect(track.contains { $0 != " " }, "the thumb is visible: \(lastColumn)")
    }

    @Test("Scrollbars are hidden by default — the viewport is unchanged")
    func hiddenScrollbarByDefault() {
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<20, id: \.self) { Text("line \($0)") }
                }
            },
            context: ctx(width: 20, height: 6)
        )
        let lastColumn = buffer.lines.map { $0.stripped.last ?? " " }
        #expect(
            !lastColumn.contains("▲") && !lastColumn.contains("▼"),
            "no scrollbar by default: \(lastColumn)")
        // The text "N more below" indicator is still shown.
        #expect(buffer.lines.map { $0.stripped }.joined().contains("more below"))
    }

    // MARK: - Single-pass convergence (no one-frame lag, no oscillation)

    @Test("An automatic scrollbar is reserved on the FIRST render when content overflows")
    func automaticScrollbarAppearsFirstRender() {
        // The bar is decided from THIS frame's measured content, so overflowing
        // content shows it immediately — it used to take a second render for the
        // handler's persisted height to catch up (a visible one-frame lag).
        let buffer = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<20, id: \.self) { Text("line \($0)") }
                }
            }
            .scrollbarVisibility(.automatic),
            context: ctx(width: 20, height: 6)
        )
        let lastColumn = buffer.lines.map { $0.stripped.last ?? " " }
        #expect(
            lastColumn.first == "▲" && lastColumn.last == "▼",
            "vertical scrollbar present on the first render: \(lastColumn)")
        // The bar supersedes the text indicator — they never show together (the
        // old lag flashed "more below" for a frame before the bar caught up).
        #expect(
            !buffer.lines.map { $0.stripped }.joined().contains("more below"),
            "no 'more below' text once the bar is shown")
    }

    @Test("Consecutive automatic renders are identical (the scrollbar does not oscillate)")
    func automaticScrollbarConvergesInOnePass() {
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { Text("line \($0)") }
            }
        }
        .scrollbarVisibility(.automatic)
        let context = ctx(width: 20, height: 6)
        let first = renderToBuffer(view, context: context).lines.map { $0.stripped }
        let second = renderToBuffer(view, context: context).lines.map { $0.stripped }
        #expect(first == second, "two consecutive renders settle to the same output")
    }
}
