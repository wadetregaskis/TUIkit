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
}
