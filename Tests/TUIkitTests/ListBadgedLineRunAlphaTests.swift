//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListBadgedLineRunAlphaTests.swift
//
//  A List row carrying a `.badge(_:)` drops every child run on its first line,
//  because the badge re-lays that line's columns — and keeps the line. A run that
//  states its alpha per frame took the only statement about its cells with it, so a
//  several-alpha border drew an opaque top rule above its faded walls (§69.4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A badged List row's dropped first-line runs")
struct ListBadgedLineRunAlphaTests {

    private struct Row: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    private let rows = (0..<3).map { Row(id: $0, name: "row\($0)") }

    /// One colour at two alphas, drawn at the faded frame, for the reason
    /// `ListBreathingRowRunAlphaTests` gives: at the opaque one there is nothing to leave.
    private var border: AnimatedColor {
        AnimatedColor(frames: [Color.rgb(200, 40, 40), Color.rgb(200, 40, 40).opacity(0.5)], step: 1)
    }

    private func draw<V: View>(_ list: V, height: Int) -> FrameBuffer {
        renderToBuffer(
            list,
            context: RenderContext(availableWidth: 30, availableHeight: height, tuiContext: TUIContext())
                .isolatingRenderCache())
    }

    /// The column the badge's glyph landed on, on buffer line `line`.
    private func badgeColumn(in drawn: FrameBuffer, line: Int) throws -> Int {
        let text = drawn.lines.count > line ? drawn.lines[line].stripped : ""
        return try #require(Array(text).lastIndex(of: "3"), "no badge on line \(line): \(text)")
    }

    /// No focus manager and no selection, so no row breathes: this is the ordinary
    /// return, and the badge is the only reason anything is dropped. Each row is three
    /// lines inside the list's border, so their first lines — their top rules — are 1,
    /// 4 and 7, and the badge sits far enough right that nothing is truncated.
    @Test("A badged row's several-alpha top rule keeps its drawn alpha, short of the badge")
    func badgedLineLeavesItsAlpha() throws {
        let drawn = draw(
            List {
                ForEach(rows) { row in Text(row.name).border(border).badge(3) }
            },
            height: 14)
        let runs = drawn.animatedCells.map { "y=\($0.offsetY) w=\($0.width) alpha=\($0.alpha != nil)" }
        let firstLines: Set<Int> = [1, 4, 7]

        // The premise: the badge is drawn on row 0's first line, the walls and bottom
        // rules carry their payload on their runs, and no payload rides on a first line.
        let badge = try badgeColumn(in: drawn, line: 1)
        let carried = drawn.animatedCells.filter { $0.alpha != nil }
        let carriedOnAFirstLine = carried.contains { firstLines.contains($0.offsetY) }
        #expect(!carried.isEmpty, "the walls carry their alpha on their runs: \(runs)")
        #expect(!carriedOnAFirstLine, "a badged first line drops its runs: \(runs)")

        // What was missing: each dropped top rule's drawn frame, left behind on exactly
        // the first lines, and no region of it reaching the badge's column.
        let owed = drawn.opacityRegions.filter { $0.inkOpacity < 1 }
        let owedRows = Set(owed.map(\.offsetY))
        let clearOfTheBadge = owed.allSatisfy { $0.offsetX + $0.width <= badge }
        #expect(owedRows == firstLines, "the top rules claim nothing: \(owed)")
        #expect(clearOfTheBadge, "a region reaches the badge at column \(badge): \(owed)")
    }

    /// A row the badge actually TRUNCATES, which the row above never is. Its top rule
    /// is as wide as the row lets content be, so it fits the row's geometry and is
    /// dropped only for the badge — and its region, uncut, runs on over the fill and
    /// the badge. This is the case the cut exists for.
    @Test("A truncated badged row's top-rule regions stop where its kept content does")
    func truncatedBadgedLineStopsAtTheContent() throws {
        let drawn = draw(
            List {
                Text(String(repeating: "x", count: 40)).border(border).badge(3)
            },
            height: 10)
        let badge = try badgeColumn(in: drawn, line: 1)
        let owed = drawn.opacityRegions.filter { $0.inkOpacity < 1 && $0.offsetY == 1 }
        try #require(!owed.isEmpty, "the truncated top rule left nothing: \(drawn.opacityRegions)")
        let reach = owed.map { $0.offsetX + $0.width }.max() ?? 0
        #expect(reach < badge, "a region reaches column \(reach), at or past the badge at \(badge): \(owed)")
    }
}
