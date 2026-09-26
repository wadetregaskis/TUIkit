//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedTerminalInkOverlayTests.swift
//
//  A reversal whose ink is the terminal's own foreground (`ESC[7;39…m`) shows
//  that foreground as its FIELD, and a field the background slot cannot spell:
//  only a 7 draws it. So an overlay cell laid over such a base, which keeps the
//  field it lands on, is drawn reversed itself — 39 in its foreground slot, its
//  own ink moved to the background slot — or, once the terminal has reported
//  its foreground (OSC 10), on that colour's RGB (`Opacity as composition.md`
//  §107). Read off the background slot instead, it took the reversal's ink, the
//  terminal's own background: a hole in the reversed text.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A two-cell run in the overlay whose frames draw a glyph in an ink of its own,
/// one in none, and one on the terminal's own field, stated; frame `drawn` is
/// drawn into its lines.
private struct OverlayProbe: View, Renderable {
    var drawn = 0
    var body: Never { fatalError("renders via Renderable") }

    static let frames = [
        "\u{1B}[38;2;230;120;40m⠋\u{1B}[0m ",
        "⠙ ",
        "\u{1B}[49m⠹\u{1B}[0m ",
    ]

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [Self.frames[drawn]])
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 2, frames: Self.frames, clock: .content)
        ]
        return buffer
    }
}

@MainActor
@Suite("An overlay over a reversal of the terminal's own ink is drawn on that ink")
struct ReversedTerminalInkOverlayTests {

    private static let red = Color.rgb(200, 40, 40)
    private static let blue = Color.rgb(0, 0, 200)

    /// The terminal reporting its foreground, and so its own ink as an RGB.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    /// Each subview's leading edge at its own cell of the grid — a custom `Layout`,
    /// composited in place.
    private struct AtCells: Layout {
        let cells: [(x: Int, y: Int)]

        func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
            ViewSize(width: 12, height: 1)
        }

        func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
            for index in subviews.indices {
                subviews[index].place(
                    at: (x: bounds.x + cells[index].x, y: bounds.y + cells[index].y), proposal: .unspecified)
            }
        }
    }

    /// `view`'s first row as written on the terminal's own pair, and its runs.
    private func written(_ view: some View) throws -> (row: [PaintedCell], rows: [String], buffer: FrameBuffer) {
        let palette = ReversedRowTerminalPairPalette()
        let context = makeRenderContext(width: 12, height: 2) { environment, _ in
            environment.palette = palette
        }
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        let rows = ColorDepth.withCurrent(.truecolor) {
            writer.buildOutputLines(
                buffer: buffer, terminalWidth: 12, terminalHeight: buffer.lines.count,
                bgCode: RenderBackgroundCodes(palette: palette).content, reset: ANSIRenderer.reset)
        }
        let row = try #require(rows.first.map(paintedCells))
        return (row, rows, buffer)
    }

    /// The label, red, over inverted text — in a `ZStack`, and in a custom `Layout`
    /// that composites it in place: on the field the text shows, the terminal's own
    /// foreground, in its red. Before, on the terminal's own background.
    @Test("A label over inverted text of the terminal's own ink is drawn on that ink", arguments: [false, true])
    func aLabelOverInvertedTerminalInk(inPlace: Bool) throws {
        try TerminalColors.withCurrent(.unknown) {
            let base = Text("abcdef").inverted()
            let label = Text("xy").foregroundStyle(Self.red)
            let alone = try written(base).row
            let over =
                inPlace
                ? try written(AtCells(cells: [(0, 0), (0, 0)]) { base; label }).row
                : try written(ZStack(alignment: .leading) { base; label }).row
            // Not vacuous: the text is reversed on the terminal's own ink.
            #expect(alone[0].state.reversesVideo && alone[0].shownField == .terminalForeground, "the text is \(alone[0].shown)")
            #expect(String(over.prefix(6).map(\.glyph)) == "xycdef")
            #expect(
                over.prefix(6).map(\.shownField) == alone.prefix(6).map(\.shownField),
                "the label is on \(over.prefix(2).map(\.shownField)), the text on \(alone.prefix(2).map(\.shownField))")
            #expect(over[0].shownInk == .colour(.rgb(200, 40, 40)), "x is in \(over[0].shownInk)")
        }
    }

    /// A label in the terminal's own ink over that ink is invisible: its glyphs go,
    /// as §85 drops one whose ink is its field's colour, and the cells are the field.
    @Test("A label in the terminal's own ink over that ink is the ink")
    func aLabelInTheSameInk() throws {
        try TerminalColors.withCurrent(.unknown) {
            let base = Text("abcdef").inverted()
            let over = try written(ZStack(alignment: .leading) { base; Text("xy") }).row
            #expect(over.prefix(2).map(\.shownField) == [.terminalForeground, .terminalForeground], "the label is \(over[0].shown)")
            #expect(over.prefix(2).allSatisfy { $0.glyph == " " || $0.shownInk == $0.shownField }, "the label is \(over[0].shown)")
        }
    }

    /// A WIDE glyph in the terminal's own ink over that ink goes as a narrow one does,
    /// and its columns stay: a blank for each, on the field. Dropped into ONE blank,
    /// the painted label was a column short, and everything the insert put after it —
    /// the rest of the inverted text — moved a column left.
    @Test("A wide label in the terminal's own ink over that ink keeps both its columns")
    func aWideLabelInTheSameInk() throws {
        try TerminalColors.withCurrent(.unknown) {
            let alone = try written(Text("abcdef").inverted()).row
            let over = try written(ZStack(alignment: .leading) { Text("abcdef").inverted(); Text("中x") }).row
            #expect(String(over[3..<6].map(\.glyph)) == "def", "the row is \(over.prefix(6).map(\.glyph))")
            #expect(over[3..<6].map(\.shownField) == alone[3..<6].map(\.shownField))
            #expect(
                over.prefix(3).map(\.shownField) == Array(repeating: .terminalForeground, count: 3),
                "the label is \(over.prefix(3).map(\.shown))")
        }
    }

    /// Per column: over the inverted text, the terminal's foreground; over the blue,
    /// the blue.
    @Test("A label over inverted terminal ink and a colour is drawn on each")
    func aLabelOverTheInkAndAColour() throws {
        try TerminalColors.withCurrent(.unknown) {
            let base = HStack(spacing: 0) { Text("abc").inverted(); Text("def").background(Self.blue) }
            let over = try written(ZStack(alignment: .leading) { base; Text("uvwxyz").foregroundStyle(Self.red) }).row
            #expect(String(over.prefix(6).map(\.glyph)) == "uvwxyz")
            #expect(
                over.prefix(6).map(\.shownField)
                    == [.terminalForeground, .terminalForeground, .terminalForeground]
                    + Array(repeating: .colour(.rgb(0, 0, 200)), count: 3),
                "the label is on \(over.prefix(6).map(\.shownField))")
            #expect(over.prefix(6).allSatisfy { $0.shownInk == .colour(.rgb(200, 40, 40)) })
        }
    }

    /// Once the terminal has reported its foreground, the field has an RGB, and the
    /// label is drawn on it unreversed.
    @Test("Over a reported foreground, the label is drawn on its RGB")
    func overAReportedForeground() throws {
        try TerminalColors.withCurrent(Self.reported) {
            let over = try written(ZStack(alignment: .leading) { Text("abcdef").inverted(); Text("xy").foregroundStyle(Self.red) }).row
            #expect(String(over.prefix(2).map(\.glyph)) == "xy")
            #expect(over.prefix(2).allSatisfy { !$0.state.reversesVideo && $0.shownField == .colour(.rgb(171, 178, 191)) }, "the label is \(over[0].shown)")
            #expect(over[0].shownInk == .colour(.rgb(200, 40, 40)))
        }
    }

    /// A run in the label over the inverted text: every frame replayed over the row
    /// drawn at every other is the row a render draws at it, as the cells look.
    @Test("A run in a label over inverted terminal ink replays as a render draws it")
    func aRunReplays() throws {
        try TerminalColors.withCurrent(.unknown) {
            let frames = OverlayProbe.frames.indices
            let renders = try frames.map { drawn in
                try written(ZStack(alignment: .leading) {
                    Text("abcdef").inverted()
                    HStack(spacing: 0) { Text("x").foregroundStyle(Self.red); OverlayProbe(drawn: drawn) }
                })
            }
            let page = ColorDepth.withCurrent(.truecolor) {
                RenderBackgroundCodes(palette: ReversedRowTerminalPairPalette()).content
            }
            for drawn in frames {
                let run = try #require(renders[drawn].buffer.animatedCells.first { $0.width == 2 }, "no run at \(drawn)")
                // Not vacuous: the probe is on the terminal's own ink in the render.
                #expect(renders[drawn].row[1].shownField == .terminalForeground, "frame \(drawn) is \(renders[drawn].row[1].shown)")
                for shown in frames {
                    let replayed = ColorDepth.withCurrent(.truecolor) {
                        paintedCells(
                            FrameBuffer.patchingAnimatedCells(
                                in: renders[drawn].rows[run.offsetY], with: run.frame(atIndex: shown),
                                atColumn: run.offsetX, width: run.width, fields: run.fields(onPage: page)))
                    }
                    let rendered = renders[shown].row
                    for column in run.offsetX..<(run.offsetX + run.width)
                    where !replayed[column].looksLike(rendered[column]) {
                        Issue.record(
                            "frame \(shown) over frame \(drawn), column \(column): replayed \(replayed[column].shown), rendered \(rendered[column].shown)")
                    }
                }
            }
        }
    }

    /// The same run inside a painter of its own, in the label over the inverted text:
    /// its cells are on the painter's blue in the lines, and so in every frame.
    @Test("A run in a painter in a label over inverted terminal ink replays as a render draws it")
    func aRunInAPainterReplays() throws {
        try TerminalColors.withCurrent(.unknown) {
            let frames = OverlayProbe.frames.indices
            let renders = try frames.map { drawn in
                try written(ZStack(alignment: .leading) {
                    Text("abcdef").inverted()
                    HStack(spacing: 0) {
                        Text("x").foregroundStyle(Self.red)
                        OverlayProbe(drawn: drawn).background(Self.blue)
                    }
                })
            }
            let page = ColorDepth.withCurrent(.truecolor) {
                RenderBackgroundCodes(palette: ReversedRowTerminalPairPalette()).content
            }
            for drawn in frames {
                let run = try #require(renders[drawn].buffer.animatedCells.first { $0.width == 2 }, "no run at \(drawn)")
                for shown in frames {
                    let replayed = ColorDepth.withCurrent(.truecolor) {
                        paintedCells(
                            FrameBuffer.patchingAnimatedCells(
                                in: renders[drawn].rows[run.offsetY], with: run.frame(atIndex: shown),
                                atColumn: run.offsetX, width: run.width, fields: run.fields(onPage: page)))
                    }
                    let rendered = renders[shown].row
                    for column in run.offsetX..<(run.offsetX + run.width)
                    where !replayed[column].looksLike(rendered[column]) {
                        Issue.record(
                            "frame \(shown) over frame \(drawn), column \(column): replayed \(replayed[column].shown), rendered \(rendered[column].shown)")
                    }
                }
            }
        }
    }
}
