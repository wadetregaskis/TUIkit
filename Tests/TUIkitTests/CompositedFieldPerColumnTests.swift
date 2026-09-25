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

    // MARK: - A stated terminal field in the base

    /// A stated `ESC[49m` in the BASE is a field too, the terminal's own: in a row
    /// still to be written a reset and a 49 are two fields, and the row builder
    /// puts the page under the first. An overlay cell over it keeps it, as it keeps
    /// a colour, and so do the cells after the overlay, which the insert restores
    /// the base's styling for after the overlay's closing reset — faded or not, the
    /// opacity splice being the same insert. Netted with a reset into "no field",
    /// both were drawn on the page. On the terminal's own page the two are one
    /// field, and the case is a guard.
    @Test(
        "An overlay over a stated terminal field keeps it, and so do the cells after it",
        arguments: [false, true], [false, true])
    func anOverlayOverAStatedTerminalField(terminalPage: Bool, faded: Bool) throws {
        let palette: (any Palette)? = terminalPage ? terminalPagePalette : nil
        let base = Text("abcdef").background(Color.default)
        let alone = try #require(writtenRows(of: base, palette: palette, width: 8, height: 2).first)
        let composed = ZStack(alignment: .leading) { base; Text("xy").opacity(faded ? 0.6 : 1) }
        let row = try #require(writtenRows(of: composed, palette: palette, width: 8, height: 2).first)
        // Not vacuous: alone, the base is on the terminal's own field.
        #expect(alone.prefix(6).allSatisfy { $0.background.isEmpty })
        #expect(String(row.prefix(6).map(\.glyph)) == "xycdef")
        #expect(
            row.prefix(6).map(\.background) == alone.prefix(6).map(\.background),
            "drawn on \(row.prefix(6).map(\.background))")
    }

    /// And per column: a stated 49 under the first half of a label, a colour under
    /// the rest.
    @Test("A label over a stated terminal field and a colour is drawn on each")
    func aLabelOverAStatedTerminalFieldAndAColour() throws {
        let base = HStack(spacing: 0) {
            Text("   ").background(Color.default)
            Text("   ").background(Self.blue)
        }
        let cells = try drawn(base.overlay(alignment: .leading) { Text("abcdef") })
        expect(cells, glyphs: "abcdef", fields: Self.threeThenThree("", Self.blueField))
    }

    /// A run inside an overlay over a stated 49 records the terminal's own under its
    /// cell — so a replay draws it there, as the render does, and not on the page.
    @Test("A run over a stated terminal field records the terminal's own")
    func aRunOverAStatedTerminalField() throws {
        let (row, runs) = try drawnWithRuns(
            ZStack(alignment: .leading) {
                Text("      ").background(Color.default)
                HStack(spacing: 0) { Text("ab"); Spinner() }
            })
        #expect(row[2].background.isEmpty, "the render draws the spinner on \(row[2].background.debugDescription)")
        let run = try #require(runs.first, "the spinner left no run")
        #expect(run.offsetX == 2)
        #expect(
            run.groundFields(onPage: Self.page) == [nil],
            "the spinner's ground, on the page, is \(run.groundFields(onPage: Self.page))")
    }

    // MARK: - A reversed base

    /// Each subview's leading edge at its own cell of the grid — a custom `Layout`,
    /// composited in place.
    private struct AtCells: Layout {
        let cells: [(x: Int, y: Int)]

        func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
            ViewSize(width: 24, height: 6)
        }

        func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
            for index in subviews.indices {
                subviews[index].place(
                    at: (x: bounds.x + cells[index].x, y: bounds.y + cells[index].y), proposal: .unspecified)
            }
        }
    }

    /// A focused list's cursor row reverses where its highlight has no RGB to
    /// breathe between (`ESC[7;<ink>;<field>m`): it SHOWS the palette's ink as its
    /// field. A label laid over the row keeps that field, as it keeps any other.
    /// Read off the background slot, it took the row's field SLOT — which the
    /// reversal shows as the row's ink, here the terminal's own — and the label was
    /// a hole in the bar.
    @Test("A label over a list's reversed cursor row is drawn on the row's field")
    func aLabelOverAReversedRow() throws {
        let list = List(selection: .constant(Int?.none)) {
            ForEach(0..<3, id: \.self) { row in Text("row \(row)") }
        }
        .frame(width: 20, height: 5)
        func screen(_ view: some View) -> FrameBuffer {
            let context = makeRenderContext(width: 24, height: 6) { environment, _ in
                environment.palette = terminalPagePalette
            }
            return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }
        }
        let base = paintedCells(screen(list).lines[1])
        // Not vacuous: the cursor row is reversed under the label, on an ink of its own.
        #expect(base[4].state.reversesVideo && base[5].state.reversesVideo, "the row is \(base[4].shown)")
        #expect(base[4].shownField != .terminalBackground)
        let row = paintedCells(screen(AtCells(cells: [(0, 0), (4, 1)]) { list; Text("xy") }).lines[1])
        #expect(row[4].glyph == "x" && row[5].glyph == "y")
        #expect(
            row[4...5].map(\.shownField) == base[4...5].map(\.shownField),
            "the label is on \(row[4...5].map(\.shownField)), the row on \(base[4...5].map(\.shownField))")
    }

    /// The plainest shape: a label over inverted text. The text shows its ink — the
    /// palette's foreground — as its field, and the label is drawn on that.
    @Test("A label over inverted text is drawn on the field the text shows")
    func aLabelOverInvertedText() throws {
        let base = Text("abcdef").inverted()
        let alone = try #require(writtenRows(of: base, width: 8, height: 2).first)
        let row = try #require(
            writtenRows(of: ZStack(alignment: .leading) { base; Text("xy") }, width: 8, height: 2).first)
        // Not vacuous: the text is reversed, on an ink of its own.
        #expect(alone[0].state.reversesVideo && alone[0].state.foregroundColour != nil, "the text is \(alone[0].shown)")
        #expect(String(row.prefix(6).map(\.glyph)) == "xycdef")
        #expect(
            row.prefix(6).map(\.shownField) == alone.prefix(6).map(\.shownField),
            "the label is on \(row.prefix(2).map(\.shownField)), the text on \(alone.prefix(2).map(\.shownField))")
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
