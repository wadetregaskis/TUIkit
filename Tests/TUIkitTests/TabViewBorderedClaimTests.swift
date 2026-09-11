//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewBorderedClaimTests.swift
//
//  A bordered TabView draws its folder tabs and the box around its panel with raw
//  paints, so under a palette whose border, page or surface is translucent it
//  trapped in a debug build and drew opaque in a release one. Every one of those
//  cells claims what it painted now: the walls and rules their border ink, the
//  labels their ink and field, the mouth under the active tab its surface, and the
//  panel its surface exactly once.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A bordered TabView owes what it painted")
struct TabViewBorderedClaimTests {

    /// A one-cell tab selected under a wider, taller one: its line is padded either
    /// side, and the rows the taller one needs are filled beneath it.
    private func view() -> some View {
        TabView(selection: .constant(0)) {
            Tab("one", value: 0) { Text("a") }
            Tab("two", value: 1) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("a much wider body")
                    Text("x")
                    Text("y")
                }
            }
        }
        .tabViewStyle(.bordered)
    }

    @Test("A still bordered TabView's chrome, labels, mouth and panel owe what they painted")
    func stillBoxClaims() throws {
        let palette = FadedAll()
        let surface = palette.liftedBackground.resolve(with: palette)
        let context = makeRenderContext(width: 40, height: 14) { environment, _ in
            environment.palette = palette
        }
        // A sentinel registered first holds the focus, so the strip rests.
        context.environment.focusManager?.register(FocusSentinel())
        let drawn = renderToBuffer(view(), context: context)
        let screen = drawn.lines.map(\.stripped)
        var wrong: [String] = []
        func expect(_ column: Int, _ row: Int, ink: Double, field: Double, _ what: String) {
            let owes = owed(atColumn: column, row: row, in: drawn)
            if owes.ink != ink || owes.field != field { wrong.append("\(what) (\(column), \(row)): \(owes)") }
        }

        // Every box-drawing cell is border ink on nothing.
        for glyph: Character in ["╭", "╮", "╯", "╰", "│", "─", "┬", "┴"] {
            for cell in cells(of: glyph, in: drawn) {
                expect(cell.column, cell.row, ink: owed(palette.border), field: 1, "\(glyph)")
            }
        }
        // The mouth under the active tab: the panel's surface, and no ink.
        let mouth = try #require(
            screen.firstIndex { line in
                guard let left = line.firstIndex(of: "╯"), let right = line.firstIndex(of: "╰") else { return false }
                return left < right
            }, "no mouth: \(screen)")
        let line = Array(screen[mouth])
        let left = try #require(line.firstIndex(of: "╯"))
        let right = try #require(line.firstIndex(of: "╰"))
        for column in (left + 1)..<right { expect(column, mouth, ink: 1, field: owed(surface), "mouth") }
        // The panel: every interior cell between the mouth and the bottom rule owes the
        // surface's field exactly once — the content's block, its pads, the fillers.
        for row in (mouth + 1)..<(screen.count - 1) {
            for column in 1..<(screen[row].count - 1) {
                let field = owed(atColumn: column, row: row, in: drawn).field
                if field != owed(surface) { wrong.append("panel (\(column), \(row)): field \(field)") }
            }
        }
        // The labels: the resting active one in black or white on the surface, the
        // inactive one in the secondary rung on the page.
        let active = try #require(cells(of: "n", in: drawn).first, "no \"one\": \(screen)")
        for column in (active.column - 1)...(active.column + 1) {
            expect(column, active.row, ink: 1, field: owed(surface), "active label")
        }
        let inactive = try #require(cells(of: "w", in: drawn).first, "no \"two\": \(screen)")
        for column in (inactive.column - 1)...(inactive.column + 1) {
            expect(
                column, inactive.row, ink: owed(palette.foregroundSecondary), field: owed(palette.background),
                "inactive label")
        }
        #expect(
            wrong.isEmpty,
            """
            cells owing the wrong alpha, \(wrong.count) of them: \(wrong.prefix(10))
            \(screen.joined(separator: "\n"))
            """)
    }

    /// Focused, the active label breathes through a run; its ends are spent (§55), so
    /// its cells owe the chip's surface as field and no ink, in every frame.
    @Test("A focused bordered TabView's breathing chip owes its surface and no ink")
    func breathingChipClaims() throws {
        let palette = FadedAll()
        let surface = palette.liftedBackground.resolve(with: palette)
        let context = makeRenderContext(width: 40, height: 14) { environment, _ in
            environment.palette = palette
        }
        // Rendered twice, so the frame asserted on is not the one the strip
        // registered its focus in.
        _ = renderToBuffer(view(), context: context)
        let drawn = renderToBuffer(view(), context: context)
        let label = try #require(cells(of: "n", in: drawn).first, "\(drawn.lines.map(\.stripped))")
        #expect(
            drawn.animatedCells.contains { $0.offsetY == label.row }, "the active chip does not breathe")
        for column in (label.column - 1)...(label.column + 1) {
            let owes = owed(atColumn: column, row: label.row, in: drawn)
            #expect(owes.ink == 1 && owes.field == owed(surface), "(\(column), \(label.row)) owes \(owes)")
        }
    }
}
