//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositedFieldPerColumnTests.swift
//
//  A cell has a glyph and a field, and an overlay cell that states no field of
//  its own keeps the field it lands on: `ZStack { Color.red; Text("hi") }` draws
//  the letters ON the red. "The field it lands on" is the field under THAT cell.
//  Compositing used to read one field for a whole overlay row — the base's under
//  the overlay's first column — and paint it under every cell, so a label laid
//  over two colours drew all of itself on the first. SwiftUI draws each letter
//  over whatever is behind it.
//
//  Every expectation here is read off the base drawn ALONE, or spelled out, never
//  off another composite: a composite over the same base makes the same mistake.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A composited cell keeps the field under its own column")
struct CompositedFieldPerColumnTests {

    private static let red = Color.rgb(200, 0, 0)
    private static let blue = Color.rgb(0, 0, 200)
    private static let redField = "\u{1B}[48;2;200;0;0m"
    private static let blueField = "\u{1B}[48;2;0;0;200m"
    /// The default palette's page, as a written row spells it.
    private static let page = "\u{1B}[48;2;5;10;5m"

    /// Three cells on `left`, then three on `right`.
    private static func threeThenThree(_ left: String, _ right: String) -> [String] {
        Array(repeating: left, count: 3) + Array(repeating: right, count: 3)
    }

    /// Three red cells and three blue ones.
    private static var split: some View {
        HStack(spacing: 0) {
            red.frame(width: 3, height: 1)
            blue.frame(width: 3, height: 1)
        }
    }

    /// The first row's first six cells, as written on the default palette's page,
    /// as (glyph, field) pairs.
    private func drawn(_ view: some View) throws -> [(glyph: Character, field: String)] {
        let row = try #require(writtenRows(of: view, width: 8, height: 2).first)
        return row.prefix(6).map { ($0.glyph, $0.background) }
    }

    private func expect(
        _ cells: [(glyph: Character, field: String)], glyphs: String, fields: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(String(cells.map(\.glyph)) == glyphs, sourceLocation: sourceLocation)
        #expect(
            cells.map(\.field) == fields, "drawn on \(cells.map(\.field))", sourceLocation: sourceLocation)
    }

    // MARK: - The reported shape, and its relatives

    /// The report: `abc` is over the red and `def` over the blue.
    @Test("A label in a ZStack over two colours is drawn on each")
    func aLabelInAZStackOverTwoColours() throws {
        let cells = try drawn(ZStack(alignment: .leading) { Self.split; Text("abcdef") })
        expect(cells, glyphs: "abcdef", fields: Self.threeThenThree(Self.redField, Self.blueField))
    }

    /// `.overlay` composites the same way.
    @Test("An overlay on a view of two colours is drawn on each")
    func anOverlayOnTwoColours() throws {
        let base = HStack(spacing: 0) {
            Text("   ").background(Self.red)
            Text("   ").background(Self.blue)
        }
        let cells = try drawn(base.overlay(alignment: .leading) { Text("abcdef") })
        expect(cells, glyphs: "abcdef", fields: Self.threeThenThree(Self.redField, Self.blueField))
    }

    /// A ramp is a different field under every column: each letter is on the entry
    /// the ramp alone draws under it.
    @Test("A label in a ZStack over a ramp is drawn on the ramp's colour at each column")
    func aLabelOverARamp() throws {
        let ramp = LinearGradient(colors: [Self.red, Self.blue], startPoint: .leading, endPoint: .trailing)
            .frame(width: 6, height: 1)
        let alone = try drawn(ramp)
        let cells = try drawn(ZStack(alignment: .leading) { ramp; Text("abcdef") })
        // Not vacuous: the ramp has more than one entry across the label.
        #expect(Set(alone.map(\.field)).count > 1)
        expect(cells, glyphs: "abcdef", fields: alone.map(\.field))
    }

    /// Where the base's field ENDS under the overlay, the rest of the label is on
    /// no field — the page, as the row builder puts it back after a reset — and not
    /// on the terminal's own, which is what a stated `ESC[49m` would be.
    @Test("Past the end of the base's field, a label is on the page")
    func pastTheEndOfTheField() throws {
        let base = HStack(spacing: 0) { Text("   ").background(Self.red); Text("   ") }
        let cells = try drawn(base.overlay(alignment: .leading) { Text("abcdef") })
        expect(cells, glyphs: "abcdef", fields: Self.threeThenThree(Self.redField, Self.page))
    }

    /// And where it BEGINS under the overlay: the first cells are on the page, and
    /// the rest on the field.
    @Test("Before the start of the base's field, a label is on the page")
    func beforeTheStartOfTheField() throws {
        let base = HStack(spacing: 0) { Text("   "); Text("   ").background(Self.blue) }
        let cells = try drawn(base.overlay(alignment: .leading) { Text("abcdef") })
        expect(cells, glyphs: "abcdef", fields: Self.threeThenThree(Self.page, Self.blueField))
    }

    /// A label's own styling is kept across every change of field, the one back to
    /// no field included: going back to the page takes a reset, and the label's ink
    /// and weight are restated after it.
    @Test("A label keeps its own ink and weight across the fields it is drawn over")
    func aLabelKeepsItsStyling() throws {
        let base = HStack(spacing: 0) {
            Text("  ").background(Self.red)
            Text("  ")
            Text("  ").background(Self.blue)
        }
        let label = Text("abcdef").bold().foregroundStyle(Color.rgb(0, 200, 0))
        let row = try #require(
            writtenRows(of: base.overlay(alignment: .leading) { label }, width: 8, height: 2).first)
        let fields = [Self.redField, Self.redField, Self.page, Self.page, Self.blueField, Self.blueField]
        #expect(row.prefix(6).map(\.background) == fields)
        for cell in row.prefix(6) {
            #expect(cell.ink == .rgb(0, 200, 0), "\(cell.glyph) is inked \(String(describing: cell.ink))")
            #expect(cell.state.rendered.contains("1;"), "\(cell.glyph) is drawn in \(cell.state.rendered)")
        }
    }

    /// A wide glyph over a change of field is drawn on its FIRST column's: a cell has
    /// one field, and a glyph that cannot be half-drawn is one cell. `界` covers the
    /// last red column and the first blue one.
    @Test("A wide glyph over a change of field is drawn on its first column's")
    func aWideGlyphOverAChangeOfField() throws {
        let cells = try drawn(ZStack(alignment: .leading) { Self.split; Text("ab界cd") })
        expect(
            cells, glyphs: "ab界界cd",
            fields: [Self.redField, Self.redField, Self.redField, Self.redField, Self.blueField, Self.blueField])
    }

    // MARK: - A custom layout

    /// Every subview's leading edge at its own column of one row: a custom `Layout`,
    /// which composites its subviews one at a time IN PLACE
    /// (`FrameBuffer.composite(with:at:)`) rather than through the copying twin a
    /// `ZStack` uses.
    private struct AtColumns: Layout {
        let columns: [Int]

        func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
            ViewSize(width: 8, height: 1)
        }

        func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
            for index in subviews.indices {
                subviews[index].place(at: (x: bounds.x + columns[index], y: bounds.y), proposal: .unspecified)
            }
        }
    }

    /// `view` rendered to the screen, as the rows are written and with the runs it
    /// carries.
    private func drawnWithRuns(_ view: some View) throws -> (row: [PaintedCell], runs: [AnimatedCellRun]) {
        let context = makeRenderContext(width: 8, height: 2)
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }
        let row = try #require(
            ColorDepth.withCurrent(.truecolor) {
                writtenRows(buffer, palette: context.environment.palette, width: 8)
            }.first)
        return (row, buffer.animatedCells)
    }

    /// The field a run's one cell records in its ground, on no page.
    private func groundField(of run: AnimatedCellRun) -> String {
        run.groundFields(onPage: "").first.flatMap { $0 }.map { SGRState.backgroundEscape($0) } ?? ""
    }

    /// The in-place composite reads the base under each column too, and a run inside
    /// the overlay records the field under its own cell: the spinner, at column 4,
    /// is over the blue.
    @Test("A custom layout's label over two colours is drawn on each, its run on its own")
    func aCustomLayoutsLabelOverTwoColours() throws {
        let (row, runs) = try drawnWithRuns(
            AtColumns(columns: [0, 0]) {
                Self.split
                HStack(spacing: 0) { Text("abcd"); Spinner() }
            })
        #expect(String(row.prefix(4).map(\.glyph)) == "abcd")
        #expect(
            row.prefix(5).map(\.background)
                == [Self.redField, Self.redField, Self.redField, Self.blueField, Self.blueField],
            "drawn on \(row.prefix(5).map(\.background))")
        let run = try #require(runs.first, "the spinner left no run")
        #expect(run.offsetX == 4)
        #expect(groundField(of: run) == Self.blueField, "the spinner's ground is \(groundField(of: run).debugDescription)")
    }

    /// Placed two columns left of the canvas, the overlay is cut to what is on it and
    /// inserted at column 0 — and still over the field under each column, its run
    /// shifted onto the blue with it.
    @Test("An overlay placed left of the canvas is drawn on the field under each column, its run too")
    func anOverlayLeftOfTheCanvas() throws {
        let (row, runs) = try drawnWithRuns(
            AtColumns(columns: [0, -2]) {
                Self.split
                HStack(spacing: 0) { Text("xyabc"); Spinner() }
            })
        #expect(String(row.prefix(3).map(\.glyph)) == "abc")
        #expect(
            row.prefix(4).map(\.background) == [Self.redField, Self.redField, Self.redField, Self.blueField],
            "drawn on \(row.prefix(4).map(\.background))")
        let run = try #require(runs.first, "the spinner left no run")
        #expect(run.offsetX == 3)
        #expect(groundField(of: run) == Self.blueField, "the spinner's ground is \(groundField(of: run).debugDescription)")
    }

    // MARK: - A stated terminal field

    /// Compositing reads a stated `ESC[49m` as no field and fills it
    /// (`Terminal-compatibility.md`, the stated-49 note) — with the field under THAT
    /// cell, like any other it fills.
    @Test("A stated terminal field in an overlay is filled with the field under each cell")
    func aStatedTerminalFieldIsFilledPerColumn() throws {
        let cells = try drawn(
            ZStack(alignment: .leading) { Self.split; Text("abcdef").background(Color.default) })
        expect(cells, glyphs: "abcdef", fields: Self.threeThenThree(Self.redField, Self.blueField))
    }

    /// And where there is no field under it to fill it with, the 49 stands: the
    /// terminal's own, not the page.
    @Test("A stated terminal field over no field stays the terminal's own")
    func aStatedTerminalFieldOverNoField() throws {
        let base = HStack(spacing: 0) { Text("   ").background(Self.red); Text("   ") }
        let cells = try drawn(base.overlay(alignment: .leading) { Text("abcdef").background(Color.default) })
        expect(cells, glyphs: "abcdef", fields: Self.threeThenThree(Self.redField, ""))
    }

    // MARK: - Faded, and floating

    /// A fade blends the cells it covers against the base under each; the cells it
    /// does not cover are composited like any other. Here `def` is unfaded, over
    /// the blue.
    @Test("The unfaded part of a partly faded label is drawn on the field under it")
    func aPartlyFadedLabel() throws {
        let cells = try drawn(
            ZStack(alignment: .leading) {
                Self.split
                HStack(spacing: 0) { Text("abc").opacity(0.6); Text("def") }
            })
        #expect(String(cells.map(\.glyph)) == "abcdef")
        #expect(cells.prefix(3).allSatisfy { $0.field == Self.redField }, "abc on \(cells.prefix(3).map(\.field))")
        #expect(cells.suffix(3).allSatisfy { $0.field == Self.blueField }, "def on \(cells.suffix(3).map(\.field))")
    }

    /// The whole label faded: every cell is covered, and blended over its own
    /// column's field. (Right before, too: the blend reads the base per column.)
    @Test("A wholly faded label is drawn on the field under each cell")
    func aWhollyFadedLabel() throws {
        let cells = try drawn(ZStack(alignment: .leading) { Self.split; Text("abcdef").opacity(0.6) })
        expect(cells, glyphs: "abcdef", fields: Self.threeThenThree(Self.redField, Self.blueField))
    }

    /// A displaced view floats in a layer with no surface of its own, and is
    /// composited over the page at the root: one column right, over two red cells,
    /// three blue ones and the page past them.
    @Test("An offset label over two colours is drawn on each")
    func anOffsetLabel() throws {
        let context = makeRenderContext(width: 8, height: 2)
        let row = try #require(
            ColorDepth.withCurrent(.truecolor) {
                let screen = renderToScreen(
                    ZStack(alignment: .topLeading) { Self.split; Text("abcdef").offset(x: 1, y: 0) },
                    context: context
                ).compositingOverlays(maxWidth: 8, maxHeight: 2, palette: context.environment.palette)
                return writtenRows(screen, palette: context.environment.palette, width: 8)
            }.first)
        expect(
            row[1..<7].map { ($0.glyph, $0.background) }, glyphs: "abcdef",
            fields: [Self.redField, Self.redField, Self.blueField, Self.blueField, Self.blueField, Self.page])
    }
}
