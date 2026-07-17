//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LazyStackWindowingTests.swift
//
//  A LazyVStack that is the direct content of a vertical ScrollView windows to
//  the visible viewport: it renders ONLY the rows intersecting the published
//  scroll slice (into a full-height buffer) instead of every row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("LazyVStack viewport windowing")
struct LazyStackWindowingTests {
    /// Trailing width-padding is expected (rows fill the content width), so
    /// compare on the trimmed cell content.
    private func windowed(offset: Int, viewportHeight: Int, rows: Int = 20) -> [String] {
        let labels = (0..<rows).map { "Row \($0)" }
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(labels, id: \.self) { Text($0) }
        }
        var context = makeBareRenderContext(width: 20, height: 200)
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: viewportHeight)
        return renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    @Test("Only the rows intersecting the window (plus the one-row enumeration margin) carry content")
    func windowsToViewport() {
        let lines = windowed(offset: 5, viewportHeight: 4)  // rows 5..8 visible
        #expect(lines.count == 20, "the buffer stays full-height so the ScrollView clip is correct")
        #expect(lines[5] == "Row 5")
        #expect(lines[8] == "Row 8")
        // One margin row past each edge renders (and so registers its
        // focusables — the §5d enumeration margin); the ScrollView's clip
        // hides it on screen.
        #expect(lines[4] == "Row 4", "row 4 (just above) is the top margin row")
        #expect(lines[9] == "Row 9", "row 9 (just below) is the bottom margin row")
        #expect(lines[0].isEmpty, "row 0 (above the window + margin) is blank")
        #expect(lines[3].isEmpty, "row 3 (above the window + margin) is blank")
        #expect(lines[10].isEmpty, "row 10 (below the window + margin) is blank")
        #expect(lines[19].isEmpty, "row 19 (below the window + margin) is blank")
    }

    @Test("The window slides with the offset")
    func windowSlides() {
        let top = windowed(offset: 0, viewportHeight: 3)
        #expect(top[0] == "Row 0" && top[2] == "Row 2")
        #expect(top[3] == "Row 3", "bottom margin row")
        #expect(top[10].isEmpty)

        let mid = windowed(offset: 10, viewportHeight: 3)
        #expect(mid[10] == "Row 10" && mid[12] == "Row 12")
        #expect(mid[0].isEmpty)
        #expect(mid[2].isEmpty)
        #expect(mid[9] == "Row 9" && mid[13] == "Row 13", "margin rows at both edges")
    }

    @Test("A wrapping row's slot is its wrapped height, not its unwrapped one")
    func wrappedRowKeepsItsHeight() {
        // The slot walk measures at the render width. Width-blind slots
        // (measured .unspecified) gave this row a 1-line slot and the render
        // clipped its second line away.
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            Text("short")
            Text("a very long line that must wrap")  // 31 cols in a 20-col window
            Text("tail")
        }
        var context = makeBareRenderContext(width: 20, height: 200)
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: 0, viewportHeight: 6)
        let lines = renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
        #expect(lines[0] == "short")
        #expect(lines[1] == "a very long line", "first wrapped line")
        #expect(lines[2] == "that must wrap", "second wrapped line survives in its slot")
        #expect(lines[3] == "tail", "the next row sits below the FULL wrapped height")
    }

    @Test("Without a scroll window, a LazyVStack renders every row (no windowing)")
    func noWindowRendersAll() {
        let labels = (0..<12).map { "Row \($0)" }
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(labels, id: \.self) { Text($0) }
        }
        // A generous height so the .window fold doesn't trim anything.
        let lines = renderToBuffer(view, context: makeBareRenderContext(width: 20, height: 200))
            .lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect(lines.first == "Row 0")
        #expect(lines.contains("Row 11"), "all rows render when there's no enclosing scroll window")
    }
}
