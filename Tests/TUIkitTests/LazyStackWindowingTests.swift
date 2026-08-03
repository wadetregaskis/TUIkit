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

    /// A row TALLER than the viewport must render ALL its lines into its
    /// slot: the render used to be clamped to the viewport height, so lines
    /// viewportHeight..natural of a tall row existed only as blank padding —
    /// scrolling into the row's tail showed empty rows that the content
    /// height and scrollbar fully accounted for, and those lines could never
    /// be displayed at any offset.
    @Test("A row taller than the viewport keeps its tail")
    func tallRowKeepsItsTail() {
        let paragraph = (0..<12).map { "line \($0)" }.joined(separator: "\n")
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            Text("head")
            Text(paragraph)  // 12 lines in a 5-line viewport
            Text("tail")
        }
        var context = makeBareRenderContext(width: 20, height: 200)
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: 6, viewportHeight: 5)
        let lines = renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
        // Canvas: head at 0, the paragraph at 1...12, tail at 13. The window
        // covers canvas lines 6..10 — the paragraph's lines 5..9.
        for canvasLine in 6...10 {
            #expect(
                lines[canvasLine] == "line \(canvasLine - 1)",
                "canvas line \(canvasLine) lost the tall row's tail: '\(lines[canvasLine])'")
        }
        #expect(lines[13] == "tail", "the next row stays below the full slot")
    }

    /// The uniform fast path (engaged on large uniform row sets) has the same
    /// contract: a uniform extent taller than the viewport renders whole.
    @Test("Uniform rows taller than the viewport keep their tails")
    func uniformTallRowsKeepTails() {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<300, id: \.self) { index in
                Text((0..<3).map { "r\(index)l\($0)" }.joined(separator: "\n"))
            }
        }
        var context = makeBareRenderContext(width: 20, height: 2000)
        // Viewport of 2 lines over 3-line rows: the window lands mid-row.
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: 452, viewportHeight: 2)
        let lines = renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
        // Canvas line 452 is row 150's THIRD line (rows span 450..452) — the
        // line the viewport-clamped render used to blank.
        #expect(lines[452] == "r150l2", "the uniform row's last line: '\(lines[452])'")
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
