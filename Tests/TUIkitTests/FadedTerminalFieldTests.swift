//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FadedTerminalFieldTests.swift
//
//  A row reaches the terminal opened on the PAGE, with the page put back after
//  every reset in it (`FrameDiffWriter`), so in a row a reset and `ESC[49m` are
//  two fields: the page, and the terminal's own — on a page with an RGB, two
//  colours. A fade rebuilds the rows it covers, and has to keep the two apart
//  wherever the unfaded row has either.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A fade keeps the terminal's own field where the unfaded row has it")
struct FadedTerminalFieldTests {

    /// The page of the palette every test here draws on when it does not name
    /// one — the content area's, as a row's opening escape spells it.
    private static let rgbPage = "\u{1B}[48;2;5;10;5m"

    /// `view`'s rows as the screen shows them, column by column: on the terminal's
    /// own page with `terminalPage`, and on the default palette's RGB page without.
    ///
    /// Written as the run loop writes them (``writtenRows(of:palette:width:height:)``),
    /// because that is the one thing that tells a stated 49 from a cell naming no
    /// field: the buffer spells both as no background, and only the written row
    /// puts the page under one of them.
    private func rows(_ view: some View, terminalPage: Bool = false) -> [[PaintedCell]] {
        writtenRows(of: view, palette: terminalPage ? terminalPagePalette : nil)
    }

    /// Whether `cell` shows the terminal's own field: it names no background, and
    /// no reversal puts its ink where the field would be.
    private static func showsTerminalField(_ cell: PaintedCell) -> Bool {
        cell.background.isEmpty && !cell.state.reversesVideo
    }

    /// A fade anywhere on a row rebuilds the whole row, and collapses its escapes.
    /// `b` follows a coloured `a` in the same ink, after a reset: the page. Netted
    /// as a terminal would net it — where a reset and 49 are one field — the reset
    /// became the shorter `ESC[49m`, and `b` took the terminal's own field.
    @Test("A cell after a coloured one keeps the page when a fade rebuilds its row")
    func aCellAfterAColouredOneKeepsThePage() throws {
        let row = { (alpha: Double) in
            HStack(spacing: 0) {
                Text("x")
                Text("a").background(Color.rgb(200, 40, 40))
                Text("b")
                Text("c").opacity(alpha)
            }
        }
        let opaque = try #require(rows(row(1)).first)
        let faded = try #require(rows(row(0.5)).first)
        // Not vacuous: unfaded, `b` is on the page.
        #expect(opaque[2].glyph == "b")
        #expect(opaque[2].background == Self.rgbPage)
        #expect(faded[2].glyph == "b")
        #expect(faded[2].background == Self.rgbPage, "the faded row draws b on \(faded[2].background.debugDescription)")
    }

    /// A row with a cell the fade does not cover between two it does.
    enum Gap: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// A translucent field either side of `b`, which claims those cells.
        case translucentFields
        /// A faded label either side of `b`, the whole row bold, so `b` and the
        /// cells beside it differ only in their field and ink.
        case fadedBoldLabels

        var testDescription: String { rawValue }

        /// The row, faded — or its unfaded twin, the same colours opaque.
        @MainActor @ViewBuilder
        func view(faded: Bool) -> some View {
            switch self {
            case .translucentFields:
                let field = faded ? Color.blue.opacity(0.5) : Color.blue
                HStack(spacing: 0) { Text("a").background(field); Text("b"); Text("c").background(field) }
            case .fadedBoldLabels:
                let alpha = faded ? 0.6 : 1
                HStack(spacing: 0) { Text("a").opacity(alpha); Text("b"); Text("c").opacity(alpha) }.bold()
            }
        }
    }

    /// The span a fade rebuilds runs from its leftmost covered column to its
    /// rightmost, and passes the cells between as the row had them. `b` names no
    /// field, after a reset: the page. The span re-emitted it as the shortest change
    /// from the covered cell before it, and where only the field and the ink moved
    /// that was `ESC[49m` — the terminal's own field, on a page with an RGB a colour
    /// of its own.
    @Test("A cell a fade passes over keeps the page after a covered one", arguments: Gap.allCases)
    func aCellAFadePassesOverKeepsThePage(gap: Gap) throws {
        let opaque = try #require(rows(gap.view(faded: false)).first)
        let faded = try #require(rows(gap.view(faded: true)).first)
        // Not vacuous: unfaded, `b` is on the page.
        #expect(opaque[1].glyph == "b" && faded[1].glyph == "b")
        #expect(opaque[1].background == Self.rgbPage)
        #expect(faded[1].background == Self.rgbPage, "the faded row draws b on \(faded[1].background.debugDescription)")
    }

    // MARK: - The splice

    /// The columns of `row` that show the terminal's own field.
    private static func terminalColumns(_ row: [PaintedCell]) -> [Int] {
        row.indices.filter { showsTerminalField(row[$0]) }
    }

    /// On a `Color.default` palette every cell a fade leaves on the page is spelled
    /// `ESC[49m`. `y` states no field and nothing paints one under it, so it is on
    /// the page — the terminal's own — at full strength; faded, the opacity splice
    /// used to paint the field under its span's first cell, `x`'s blue, under it.
    @Test("A label after a coloured one stays on the terminal's own field through a fade")
    func aLabelAfterAColouredOne() throws {
        let view = HStack { Text("x").background(Color.blue); Text("y") }
        let opaque = try #require(rows(view.opacity(1), terminalPage: true).first)
        let faded = try #require(rows(view.opacity(0.6), terminalPage: true).first)
        let y = try #require(opaque.firstIndex { $0.glyph == "y" })
        // Not vacuous: at full strength `y` is on the terminal's own field and `x`
        // is not.
        #expect(Self.showsTerminalField(opaque[y]))
        #expect(!Self.showsTerminalField(opaque[0]))
        #expect(faded[y].glyph == "y")
        #expect(
            Self.showsTerminalField(faded[y]),
            "the faded y is drawn on \(faded[y].background.debugDescription)")
        // And the blue stays blue: at 0.6 a colour outweighs a page with no RGB.
        #expect(!Self.showsTerminalField(faded[0]))
    }

    /// The same property inside every painter, with a probe that has all three
    /// kinds of cell: one on a colour of its own, one stating no field (on
    /// whatever the painter puts under it), and two stating the terminal's own
    /// (`ESC[49m`), which a painter that restates its field only after a reset
    /// lets through and a compositor fills. The fade is OUTSIDE the painter, so the
    /// painter's field fades with the probe: at 0.6 every colour outweighs a page
    /// with no RGB, and a cell is on the terminal's own field faded exactly where
    /// it is unfaded.
    @Test(
        "Inside every painter, a faded row is on the terminal's own field exactly where the unfaded one is",
        arguments: FieldPainter.allCases)
    func everyPainterKeepsTheTerminalField(painter: FieldPainter) {
        let probe = HStack(spacing: 0) {
            Text("x").background(Color.rgb(40, 40, 200))
            Text("y")
            Text("ab").background(Color.default)
        }
        let opaque = rows(painter.view(probe).opacity(1), terminalPage: true)
        let faded = rows(painter.view(probe).opacity(0.6), terminalPage: true)
        #expect(faded.count == opaque.count)
        for (row, (was, now)) in zip(opaque, faded).enumerated() {
            #expect(
                Self.terminalColumns(now) == Self.terminalColumns(was),
                "\(painter), row \(row): unfaded on the terminal's own field at \(Self.terminalColumns(was))")
        }
        // Not vacuous: except where a compositor fills every `ESC[49m`, the probe
        // puts cells on the terminal's own field.
        if painter != .zStackOverColour, painter != .overlayOnFill {
            #expect(opaque.contains { !Self.terminalColumns($0).isEmpty }, "\(painter) shows no terminal field")
        }
    }

    // MARK: - A stated 49

    /// `Text("ab").background(Color.default)` shows the terminal's own field
    /// wherever it is drawn, and on a page with an RGB that is a colour of its own.
    /// Faded, it is a colour with no RGB against one with: at 0.6 it is the heavier
    /// side and stays, and at 0.4 the page is. The blend read the stated 49 as no
    /// field at all, so it faded to the page at every alpha below 1.
    @Test("A stated terminal field on an RGB page is the heavier side above one half", arguments: [0.6, 0.4])
    func aStatedTerminalFieldOnAnRGBPage(alpha: Double) throws {
        let label = Text("ab").background(Color.default)
        let opaque = try #require(rows(label.opacity(1)).first)
        let faded = try #require(rows(label.opacity(alpha)).first)
        // Not vacuous: unfaded, the label is on the terminal's own field.
        #expect(opaque.prefix(2).allSatisfy(Self.showsTerminalField))
        #expect(faded.prefix(2).map(\.glyph) == ["a", "b"])
        let fields = faded.prefix(2).map(\.background)
        if alpha >= 0.5 {
            #expect(fields == ["", ""], "at \(alpha) the label is drawn on \(fields)")
        } else {
            #expect(fields == [Self.rgbPage, Self.rgbPage], "at \(alpha) the label is drawn on \(fields)")
        }
    }

    /// A stated 49 between two faded regions is passed over, not blended, and has to
    /// come out as it went in. Re-emitted as the shortest change it could be a reset,
    /// which puts the row's page back, so on a page with an RGB the unfaded cell
    /// drew on the page.
    @Test("A stated terminal field between two faded regions stays the terminal's own")
    func aStatedTerminalFieldBetweenTwoRegions() throws {
        let row = { (alpha: Double) in
            HStack(spacing: 0) {
                Text("a").opacity(alpha)
                Text("b").background(Color.default)
                Text("c").opacity(alpha)
            }
        }
        let opaque = try #require(rows(row(1)).first)
        let faded = try #require(rows(row(0.6)).first)
        #expect(opaque[1].glyph == "b" && faded[1].glyph == "b")
        // Not vacuous: unfaded, `b` is on the terminal's own field.
        #expect(Self.showsTerminalField(opaque[1]))
        #expect(Self.showsTerminalField(faded[1]), "b is drawn on \(faded[1].background.debugDescription)")
    }

    /// The cell after a stated 49 that a fade passes over names no field: the page,
    /// put back after a reset. The span keeps the 49 as a colour of the cell's own,
    /// and re-emitted as the shortest change from it, "no field" was `ESC[49m` — so
    /// `c` took the terminal's own field, faded, where unfaded it is on the page.
    @Test("The cell after a stated terminal field a fade passes over keeps the page", arguments: [1, 0.6])
    func theCellAfterAStatedTerminalField(alpha: Double) throws {
        let view = HStack(spacing: 0) {
            Text("a").opacity(alpha)
            Text("b").background(Color.default)
            Text("c")
            Text("d").opacity(alpha)
        }
        let row = try #require(rows(view).first)
        #expect(row.prefix(4).map(\.glyph) == ["a", "b", "c", "d"])
        // Not vacuous: `b` is on the terminal's own field, faded or not.
        #expect(Self.showsTerminalField(row[1]))
        #expect(row[2].background == Self.rgbPage, "at \(alpha) c is drawn on \(row[2].background.debugDescription)")
    }

    /// `.transition(.opacity)` fades by rewriting the colours a view drew
    /// (`OpacityFade`), and says it performs the fade `.opacity` performs: a stated
    /// 49 is the terminal's own field, the heavier side against an RGB page from ½.
    /// It read the 49 as the page, so a label on `Color.default` jumped to the page
    /// for the whole of a transition. On the terminal's own page the two readings
    /// are one field, and the case there is a guard.
    @Test(
        "A transition fades a stated terminal field as the opacity fade does",
        arguments: [false, true], [0.6, 0.4])
    func aTransitionFadesAStatedTerminalField(terminalPage: Bool, phase: Double) throws {
        let palette: any Palette = terminalPage ? terminalPagePalette : ThemeProbePalette(background: .rgb(5, 10, 5))
        let context = makeRenderContext(width: 8, height: 1) { environment, _ in environment.palette = palette }
        let label = Text("ab").background(Color.default)
        let (transition, opacity) = ColorDepth.withCurrent(.truecolor) {
            (
                AnyTransition.Effect.opacity.apply(
                    to: renderToBuffer(label, context: context), phase: phase, context: context
                ).buffer,
                renderToScreen(label.opacity(phase), context: context)
            )
        }
        let faded = writtenRows(transition, palette: palette, width: 8).first ?? []
        let reference = writtenRows(opacity, palette: palette, width: 8).first ?? []
        // Below one half on the terminal's own page the ink is that page too, and
        // both fades drop the glyphs (§76).
        #expect(faded.prefix(2).map(\.glyph) == reference.prefix(2).map(\.glyph))
        // Not vacuous: on the RGB page the opacity fade keeps the terminal's own
        // field above one half and the page below it.
        if !terminalPage {
            #expect(reference.prefix(2).map(\.glyph) == ["a", "b"])
            #expect(reference.prefix(2).allSatisfy(Self.showsTerminalField) == (phase >= 0.5))
        }
        #expect(
            faded.prefix(2).map(\.background) == reference.prefix(2).map(\.background),
            "at \(phase) the transition draws the label on \(faded.prefix(2).map(\.background))")
    }

    /// A fade at zero reveals what is behind it untouched, and a stated 49 there is
    /// the terminal's own field: re-emitted, it has to say 49, because a reset puts
    /// the row's page back in its place.
    @Test("A fade at zero reveals a stated terminal field as the terminal's own")
    func aRevealedStatedTerminalField() throws {
        let view = ZStack(alignment: .leading) {
            Text("ab").background(Color.default)
            Text("xy").opacity(0)
        }
        let row = try #require(rows(view).first)
        #expect(row.prefix(2).map(\.glyph) == ["a", "b"])
        #expect(row.prefix(2).allSatisfy(Self.showsTerminalField), "revealed on \(row.prefix(2).map(\.background))")
    }

    /// And a cell revealed beside one: `a` states 49, `b` names no field, and each is
    /// revealed on its own — the terminal's own, then the page.
    @Test("A fade at zero reveals a stated terminal field and the page beside it as each")
    func aRevealedStatedTerminalFieldBesideThePage() throws {
        let view = ZStack(alignment: .leading) {
            HStack(spacing: 0) { Text("a").background(Color.default); Text("b") }
            Text("xy").opacity(0)
        }
        let row = try #require(rows(view).first)
        #expect(row.prefix(2).map(\.glyph) == ["a", "b"])
        #expect(Self.showsTerminalField(row[0]), "a is revealed on \(row[0].background.debugDescription)")
        #expect(row[1].background == Self.rgbPage, "b is revealed on \(row[1].background.debugDescription)")
    }

    /// A veil in the terminal's own colour — spaces on `ESC[49m` — faded over text.
    /// Its cells state a field, and at 0.6 that field outweighs the text's page, so
    /// the text's ink goes with it: the terminal's page, unreported, on that page,
    /// is no glyph at all (§76). At 0.4 the text stays. Read as no field, the veil
    /// composited nothing and the text stood at every alpha.
    @Test(
        "A veil stating the terminal's own field covers the text under it above one half",
        arguments: [false, true], [0.6, 0.4])
    func aVeilInTheTerminalsOwnField(terminalPage: Bool, alpha: Double) throws {
        let view = ZStack(alignment: .leading) {
            Text("hello")
            Text("     ").background(Color.default).opacity(alpha)
        }
        let row = try #require(rows(view, terminalPage: terminalPage).first)
        let glyphs = String(row.prefix(5).map(\.glyph))
        if alpha >= 0.5 {
            #expect(glyphs == "     ", "the veil at \(alpha) left \(glyphs.debugDescription)")
            #expect(row.prefix(5).allSatisfy(Self.showsTerminalField))
        } else {
            #expect(glyphs == "hello", "the veil at \(alpha) left \(glyphs.debugDescription)")
        }
    }

    /// The colours a cell shows: its field and its ink, a reversal undone.
    private static func displayed(_ cell: PaintedCell) -> (field: SGRState.Colour?, ink: SGRState.Colour?) {
        cell.state.reversesVideo
            ? (cell.state.foregroundColour, cell.state.backgroundColour)
            : (cell.state.backgroundColour, cell.state.foregroundColour)
    }

    /// A reversed cell that states 49 has it in the background SLOT, which a
    /// reversal shows as its ink — a `.plain` block caret on a `Color.default`
    /// palette is `ESC[7;38;2;220;220;220;49m `, drawn in the terminal's own on a
    /// field of 220. Faded, a run's frame takes what the painters made of a stated
    /// 49 into that slot, the cell's ink, and its field is its foreground still; put
    /// in the field instead, the frame's caret was drawn on the terminal's own where
    /// the faded line has it on 220, and the replay drew the caret away.
    @Test("A reversed cell stating the terminal's own field keeps its field in a faded run's frame")
    func aReversedStatedTerminalFieldInAFadedFrame() throws {
        let context = makeRenderContext(width: 12, height: 3) { environment, _ in
            environment.palette = terminalPagePalette
        }
        let buffer = ColorDepth.withCurrent(.truecolor) {
            renderToScreen(
                ReversedCaretProbe().padding(1).background(Color.rgb(90, 20, 120)).opacity(0.6),
                context: context)
        }
        let run = try #require(buffer.animatedCells.first { $0.frames.count == 2 }, "the caret left no run")
        let line = try #require(paintedCells(buffer.lines[run.offsetY]).dropFirst(run.offsetX).first)
        let frame = try #require(paintedCells(run.frames[0]).first)
        // Not vacuous: the line — the drawn frame, faded — is on the caret's 220.
        #expect(Self.displayed(line).field == .rgb(220, 220, 220), "the faded caret is on \(Self.displayed(line))")
        #expect(
            Self.displayed(frame).field == Self.displayed(line).field,
            "the faded frame is on \(Self.displayed(frame)), the line on \(Self.displayed(line))")
    }

    /// A terminal that reports its page (OSC 11): the terminal's own field has an RGB.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    /// Under a `ZStack` over a colour, a stated 49 in the layer is filled by the
    /// composite with the colour under it, so unfaded the label is on the red; faded,
    /// it is the same cell. Read as the terminal's own, it was MIXED with the page the
    /// terminal reported: `ab` on about `48;2;104;42;47` at 0.6, and at 0.99 all but
    /// the terminal's page, beside the red at 1.
    @Test("A faded stated 49 in a ZStack over a colour lands on the colour on a reported page", arguments: [0.6, 0.4])
    func aFadedStatedTerminalFieldOverAColourOnAReportedPage(alpha: Double) throws {
        let view = { (alpha: Double) in
            ZStack(alignment: .leading) {
                Color.rgb(200, 40, 40).frame(width: 2, height: 1)
                Text("ab").background(Color.default).opacity(alpha)
            }
        }
        try TerminalColors.withCurrent(Self.reported) {
            let opaque = try #require(rows(view(1)).first)
            let faded = try #require(rows(view(alpha)).first)
            // Not vacuous: the composite fills the 49 with the red.
            #expect(opaque[0].background == "\u{1B}[48;2;200;40;40m")
            #expect(faded[0].background == opaque[0].background, "faded, a is on \(faded[0].background)")
            #expect(faded[1].background == opaque[1].background)
        }
    }

    /// A run's frame stating 49 in the same layer lands on the colour too, in every
    /// frame, so the replay draws each tick on the red the render draws.
    @Test("A faded run's stated 49 in a ZStack over a colour lands on the colour on a reported page")
    func aFadedRunsStatedTerminalFieldOverAColour() throws {
        try TerminalColors.withCurrent(Self.reported) {
            let context = makeRenderContext(width: 24, height: 1)
            let view = ZStack(alignment: .leading) {
                Color.rgb(200, 40, 40).frame(width: 2, height: 1)
                StatedTerminalFieldSpinner().opacity(0.6)
            }
            let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }
            let run = try #require(buffer.animatedCells.first, "the spinner left no run")
            let writer = FrameDiffWriter(
                isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
            for index in run.frames.indices {
                let replayed = FrameBuffer.patchingAnimatedCells(in: buffer.lines[0], replaying: run, atIndex: index)
                let written = ColorDepth.withCurrent(.truecolor) {
                    writer.buildOutputLines(
                        buffer: FrameBuffer(lines: [replayed]), terminalWidth: 24, terminalHeight: 1,
                        bgCode: RenderBackgroundCodes(palette: context.environment.palette).content,
                        reset: ANSIRenderer.reset)
                }
                let cell = try #require(written.first.map(paintedCells)?.first)
                #expect(cell.background == "\u{1B}[48;2;200;40;40m", "frame \(index) is on \(cell.background)")
            }
        }
    }

    /// A guard: over a base with no field of its own the composite has nothing to fill
    /// a stated 49 with, and the veil is the terminal's own field, faded over the text
    /// as it is on an unreported page — mixed, since the page has an RGB.
    @Test("A faded veil stating 49 over text is the terminal's own field on a reported page")
    func aVeilOverTextOnAReportedPage() throws {
        try TerminalColors.withCurrent(Self.reported) {
            let row = try #require(
                rows(
                    ZStack(alignment: .leading) {
                        Text("hello")
                        Text("     ").background(Color.default).opacity(0.6)
                    }
                ).first)
            let page = Color.rgb(5, 10, 5)
            let terminal = Color.rgb(40, 44, 52)
            let rgb = try #require(terminal.opacity(0.6, over: page).rgbComponents)
            #expect(row[0].background == "\u{1B}[48;2;\(rgb.red);\(rgb.green);\(rgb.blue)m", "h is on \(row[0].background)")
        }
    }
}

/// A block caret as a `.plain` field draws one on a `Color.default` palette:
/// reversed, in 220, over a stated 49; and hidden.
private struct ReversedCaretProbe: View, Renderable {
    var body: Never { fatalError("renders via Renderable") }

    static let frames = ["\u{1B}[7;38;2;220;220;220;49m \u{1B}[0m", " "]

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [Self.frames[0]])
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 1, frames: Self.frames, clock: .cursor)
        ]
        return buffer
    }
}

/// A spinner stating the terminal's own field under its glyph.
private struct StatedTerminalFieldSpinner: View, Renderable {
    var body: Never { fatalError("renders via Renderable") }

    static let frames = ["\u{1B}[49m⠋\u{1B}[0m", "\u{1B}[49m⠙\u{1B}[0m"]

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [Self.frames[0]])
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 1, frames: Self.frames, clock: .content)
        ]
        return buffer
    }
}
