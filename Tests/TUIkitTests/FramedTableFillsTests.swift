//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FramedTableFillsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A `Table` given a height fills it, like every other row view.
///
/// It did not. `RenderContext.withAvailableHeight(_:)` documents
/// `hasExplicitHeight` as the flag by which "child views (like List) know to
/// expand to fill the available height", and `.frame(height:)` — which is
/// precisely a container giving a height — set only the WIDTH half of that pair.
/// So `Table(threeRows).frame(height: 12)` drew a six-line bordered box with six
/// blank lines under it, and a filter that narrowed a browse table's rows
/// collapsed the box on every keystroke.
///
/// An UNFRAMED table still hugs its rows, which is what a table in a `VStack`
/// wants — and is the behaviour the fill must not take away.
@MainActor
@Suite("A framed Table fills its frame")
struct FramedTableFillsTests {

    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    /// How many lines of the buffer belong to the table's own bordered box.
    private func boxHeight(_ buffer: FrameBuffer) -> Int {
        buffer.lines.filter { line in
            let text = line.stripped
            return text.contains("│") || text.contains("╭") || text.contains("╰")
        }.count
    }

    private func table(rows: Int, lineLimit: Int) -> some View {
        Table((0..<rows).map { Row(id: $0) }, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Row.name).width(.flexible).lineLimit(lineLimit)
        }
    }

    /// Both paths: `lineLimit: 1` is the single-line composer, above 1 the
    /// multi-line one, and they had to be fixed in one place to agree.
    @Test("A framed table with room to spare fills the frame", arguments: [1, 3])
    func framedTableFills(lineLimit: Int) {
        let buffer = renderToBuffer(
            table(rows: 3, lineLimit: lineLimit).frame(height: 12),
            context: makeRenderContext(width: 30, height: 20))
        #expect(buffer.height == 12, "the frame is 12 lines: \(buffer.height)")
        #expect(
            boxHeight(buffer) == 12,
            "…and so is the table's box, not just the frame around it: \(boxHeight(buffer))")
    }

    /// The behaviour the fill must not take away.
    @Test("An unframed table still hugs its rows", arguments: [1, 3])
    func unframedTableHugs(lineLimit: Int) {
        let buffer = renderToBuffer(
            table(rows: 3, lineLimit: lineLimit),
            context: makeRenderContext(width: 30, height: 20))
        #expect(
            buffer.height < 12,
            "three rows in a 20-line context hug: \(buffer.height)")
    }

    /// A table with MORE rows than the frame was always right; this is the
    /// control that says the fill did not change it.
    @Test("A framed table that overflows still fills the frame exactly")
    func overflowingTableFills() {
        let buffer = renderToBuffer(
            table(rows: 40, lineLimit: 1).frame(height: 12),
            context: makeRenderContext(width: 30, height: 20))
        #expect(buffer.height == 12)
        #expect(boxHeight(buffer) == 12)
    }
}
