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

    @Test("Only the rows intersecting the window carry content; the rest are blank")
    func windowsToViewport() {
        let lines = windowed(offset: 5, viewportHeight: 4)  // rows 5..8 visible
        #expect(lines.count == 20, "the buffer stays full-height so the ScrollView clip is correct")
        #expect(lines[5] == "Row 5")
        #expect(lines[8] == "Row 8")
        #expect(lines[0].isEmpty, "row 0 (above the window) is blank")
        #expect(lines[4].isEmpty, "row 4 (just above) is blank")
        #expect(lines[9].isEmpty, "row 9 (just below) is blank")
        #expect(lines[19].isEmpty, "row 19 (below the window) is blank")
    }

    @Test("The window slides with the offset")
    func windowSlides() {
        let top = windowed(offset: 0, viewportHeight: 3)
        #expect(top[0] == "Row 0" && top[2] == "Row 2")
        #expect(top[10].isEmpty)

        let mid = windowed(offset: 10, viewportHeight: 3)
        #expect(mid[10] == "Row 10" && mid[12] == "Row 12")
        #expect(mid[0].isEmpty)
        #expect(mid[2].isEmpty)
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
