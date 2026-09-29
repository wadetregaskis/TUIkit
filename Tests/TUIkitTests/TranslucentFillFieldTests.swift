//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TranslucentFillFieldTests.swift
//
//  A painter whose field is TRANSLUCENT — a `.background` of a translucent colour
//  or ramp, a translucent `.listRowBackground` — is not a backdrop yet (§22), so
//  its field and its content's fades both travel to where what is behind the
//  painter is known, and meet there in one cell, one above the other. Each is
//  composited in its place: the painter's field over what is behind, as it lands,
//  and the content over that, at its own alphas. So a fade inside the fill fades
//  toward the fill and leaves the fill alone, a field the content states itself
//  stands over the fill, and a glyph behind the painter contests the content's
//  glyph through the fill (`Opacity as composition.md` §105).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A two-cell run whose frames are the shapes a field comes in: a field of its
/// own, none — the painter's — and the terminal's own, stated; each followed by a
/// blank the frame leaves bare. Frame `drawn` is drawn into its lines.
private struct FieldProbe: View, Renderable {
    var drawn = 0
    var body: Never { fatalError("renders via Renderable") }

    static let frames = [
        "\u{1B}[38;2;230;120;40;48;2;200;40;40m⠋\u{1B}[0m ",
        "\u{1B}[38;2;230;120;40m⠙\u{1B}[0m ",
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
@Suite("A translucent fill is composited under its content, and the content's fades over it")
struct TranslucentFillFieldTests {

    private static let fill = Color.rgb(0, 0, 200).opacity(0.5)
    private static let red = Color.rgb(200, 40, 40)

    /// The default palette's page and ink, measured.
    private static var page: Color {
        makeRenderContext(width: 24, height: 4).environment.palette.background
    }
    private static var labelInk: Color {
        makeRenderContext(width: 24, height: 4).environment.palette.foreground
    }

    /// `colour` at `translucent`'s own alpha — a byte — over `backdrop`.
    private static func landed(_ translucent: Color, over backdrop: Color) -> Color {
        translucent.opaqueSpelling.opacity(OpacityRegion.opacity(of: translucent.alpha), over: backdrop)
    }

    /// `colour` as a written cell spells its field.
    private static func field(_ colour: Color) -> String {
        guard let rgb = colour.resolve(with: makeRenderContext(width: 4, height: 1).environment.palette).rgbComponents
        else { return "" }
        return "\u{1B}[48;2;\(rgb.red);\(rgb.green);\(rgb.blue)m"
    }

    /// `colour` as a written cell spells its ink.
    private static func ink(_ colour: Color) -> SGRState.Colour? {
        guard let rgb = colour.resolve(with: makeRenderContext(width: 4, height: 1).environment.palette).rgbComponents
        else { return nil }
        return .rgb(Int(rgb.red), Int(rgb.green), Int(rgb.blue))
    }

    // MARK: - The reported shape

    /// A label faded inside the fill: every cell of the row is on the fill as it
    /// lands — the label's letters and its space as well as its neighbours — and the
    /// letters' ink is the label's, faded toward that. Before, the fill under the label
    /// took the label's fade too: `rgb(4, 9, 34)` beside `rgb(2, 5, 103)` at 0.3.
    @Test("A label faded inside a translucent fill leaves the fill under it as it is beside it", arguments: [0.3, 0.6])
    func aFadeInsideATranslucentFill(alpha: Double) throws {
        let view = HStack(spacing: 0) { Text("a b").opacity(alpha); Text("cd") }
            .padding(.horizontal, 1)
            .background(Self.fill)
        let row = try #require(writtenRows(of: view).first)
        #expect(row.prefix(7).map(\.glyph) == [" ", "a", " ", "b", "c", "d", " "])
        let landed = Self.landed(Self.fill, over: Self.page)
        for column in 0..<7 {
            #expect(
                row[column].background == Self.field(landed),
                "column \(column), '\(row[column].glyph)', is on \(row[column].background.debugDescription)")
        }
        #expect(row[1].ink == Self.ink(Self.labelInk.opacity(alpha, over: landed)), "a is in \(String(describing: row[1].ink))")
    }

    // MARK: - Fields the content states itself

    /// Inside the fill, a field the content states is its own, over the fill: an
    /// opaque colour stands whole, the terminal's own stays the terminal's own, and a
    /// faded or translucent one is mixed over the fill as it lands — a second
    /// translucent fill inside the first included. Before, the fill's alpha scaled
    /// every one of them (the red half red at `48;2;103;21;22`), the terminal's own
    /// became the page below one half, and the faded and inner fills were mixed over
    /// the page with no fill under them.
    @Test("A field the content states inside a translucent fill is over the fill")
    func aFieldOfTheContentsOwnIsOverTheFill() throws {
        let fill = Color.rgb(0, 0, 200).opacity(0.4)
        let view = HStack(spacing: 0) {
            Text("r").background(Self.red)
            Text("d").background(Color.default)
            Text("f").background(Self.red).opacity(0.5)
            Text("n").background(Self.red.opacity(0.5))
            Text("c")
        }
        .padding(.horizontal, 1)
        .background(fill)
        let row = try #require(writtenRows(of: view).first)
        #expect(row.prefix(7).map(\.glyph) == [" ", "r", "d", "f", "n", "c", " "])
        let landed = Self.landed(fill, over: Self.page)
        #expect(row[1].background == Self.field(Self.red), "r is on \(row[1].background.debugDescription)")
        #expect(row[2].background.isEmpty, "d is on \(row[2].background.debugDescription), not the terminal's own")
        #expect(
            row[3].background == Self.field(Self.red.opacity(0.5, over: landed)),
            "f is on \(row[3].background.debugDescription)")
        #expect(
            row[4].background == Self.field(Self.landed(Self.red.opacity(0.5), over: landed)),
            "n is on \(row[4].background.debugDescription)")
        #expect(row[5].background == Self.field(landed), "c is on \(row[5].background.debugDescription)")
    }

    /// A translucent `.listRowBackground` composites its content over its fill, and a
    /// compositor fills a stated 49 as it fills a cell that says nothing: the cell shows
    /// the fill, and the fill's claim is on it, as on the cells beside it. Read as the
    /// content's own field, the claim was beneath it: `d` on the fill's opaque spelling,
    /// `48;2;0;0;200`, in a row of `48;2;2;5;103`.
    @Test("A stated 49 inside a translucent row fill is on the fill as it lands")
    func aStated49InsideATranslucentRowFill() throws {
        let row = try #require(
            writtenRows(
                of: HStack(spacing: 0) { Text("d").background(Color.default); Text("cd") }.listRowBackground(Self.fill)
            ).first)
        let landed = Self.landed(Self.fill, over: Self.page)
        #expect(row[1].background == Self.field(landed), "c is on \(row[1].background.debugDescription)")
        #expect(row[0].background == row[1].background, "d is on \(row[0].background.debugDescription)")
    }

    // MARK: - Other translucent painters

    /// A translucent ramp: a label faded inside it leaves every entry of the ramp as
    /// the unfaded row has it.
    @Test("A label faded inside a translucent ramp leaves the ramp as it is unfaded")
    func aFadeInsideATranslucentRamp() throws {
        func view(_ alpha: Double) -> some View {
            HStack(spacing: 0) { Text("ab").opacity(alpha); Text("cd") }
                .padding(.horizontal, 1)
                .background(
                    LinearGradient(
                        colors: [Self.red.opacity(0.5), Color.rgb(40, 40, 200).opacity(0.5)],
                        startPoint: .leading, endPoint: .trailing))
        }
        let faded = try #require(writtenRows(of: view(0.3)).first)
        let unfaded = try #require(writtenRows(of: view(1)).first)
        for column in 0..<6 {
            #expect(
                faded[column].background == unfaded[column].background,
                "column \(column): \(faded[column].background.debugDescription), unfaded \(unfaded[column].background.debugDescription)")
        }
    }

    /// A translucent `.listRowBackground`: the fade inside the row leaves the row's
    /// fill as the unfaded row has it.
    @Test("A label faded inside a translucent list row fill leaves the fill as it is unfaded")
    func aFadeInsideATranslucentRowFill() throws {
        func list(_ alpha: Double) -> some View {
            List(selection: .constant(Int?.none)) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 0) { Text("ab").opacity(alpha); Text("cd") }
                        .listRowBackground(Self.fill)
                }
            }
            .frame(width: 12, height: 2)
        }
        // The first row under the list's top border.
        let faded = try #require(writtenRows(of: list(0.3)).dropFirst().first)
        let unfaded = try #require(writtenRows(of: list(1)).dropFirst().first)
        #expect(faded.map(\.glyph) == unfaded.map(\.glyph))
        #expect(faded.map(\.glyph).contains("a"), "the row is \(String(faded.map(\.glyph)))")
        for column in 0..<12 {
            #expect(
                faded[column].background == unfaded[column].background,
                "column \(column): \(faded[column].background.debugDescription), unfaded \(unfaded[column].background.debugDescription)")
        }
    }

    /// Outside the painter, a fade takes the fill with it; the label's ink is faded
    /// toward the fill as that fade leaves it, not toward the page under it. Before,
    /// the ink stepped toward the page.
    @Test("A fade around a translucent fill fades the label toward the fill under it")
    func aFadeAroundATranslucentFill() throws {
        let view = HStack(spacing: 0) { Text("ab"); Text("cd") }.background(Self.fill).opacity(0.6)
        let row = try #require(writtenRows(of: view).first)
        let landed = Self.fill.opaqueSpelling.opacity(0.6 * OpacityRegion.opacity(of: Self.fill.alpha), over: Self.page)
        #expect(row[0].background == Self.field(landed), "a is on \(row[0].background.debugDescription)")
        #expect(row[0].ink == Self.ink(Self.labelInk.opacity(0.6, over: landed)), "a is in \(String(describing: row[0].ink))")
    }

    // MARK: - What is behind the painter

    /// The painter over text, in a `ZStack`: the fill is a veil over the text, and
    /// the faded label contests the text's glyph THROUGH it — below one half the
    /// text's glyph stands, above it the label's; either way the ink is the label's
    /// faded over the text's as the fill leaves it, on the fill as it lands.
    @Test("A label faded inside a translucent fill contests the glyph behind it through the fill", arguments: [0.3, 0.6])
    func aGlyphContestThroughATranslucentFill(alpha: Double) throws {
        let view = ZStack(alignment: .leading) {
            Text("######")
            HStack(spacing: 0) { Text("ab").opacity(alpha); Text("cd") }.padding(.horizontal, 1).background(Self.fill)
        }
        let row = try #require(writtenRows(of: view).first)
        let fieldAlpha = OpacityRegion.opacity(of: Self.fill.alpha)
        let landed = Self.fill.opaqueSpelling.opacity(fieldAlpha, over: Self.page)
        let veiled = Self.fill.opaqueSpelling.opacity(fieldAlpha, over: Self.labelInk)
        #expect(row[1].glyph == (alpha < 0.5 ? "#" : "a"), "column 1 is '\(row[1].glyph)'")
        #expect(row[1].background == Self.field(landed), "column 1 is on \(row[1].background.debugDescription)")
        #expect(
            row[1].ink == Self.ink(Self.labelInk.opacity(alpha, over: veiled)),
            "column 1 is in \(String(describing: row[1].ink))")
        #expect(row[4].glyph == "d" && row[4].background == Self.field(landed))
    }

    // MARK: - The replay

    /// The two painters of a translucent field: one that restates its colour after
    /// every reset in its content, and lets a stated 49 through; and one that
    /// composites its content over its fill, and fills a stated 49 as none.
    enum Painter: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case background
        case listRowBackground

        var testDescription: String { rawValue }

        @MainActor @ViewBuilder
        func painting(_ content: some View, with fill: Color) -> some View {
            switch self {
            case .background: content.background(fill)
            case .listRowBackground: content.listRowBackground(fill)
            }
        }
    }

    /// A run inside the fill, faded inside it or not, whose frames state a field of
    /// their own, none, and the terminal's own: every frame replayed over the row
    /// drawn at every other is the row a render draws at it, cell by cell as the
    /// cells look. The drawn frame is not the one the painter's claims were cut to at
    /// every frame, and each frame says which place of the fill is its own.
    @Test("A run inside a translucent fill replays as a render draws it", arguments: [1, 0.6, 0.3], Painter.allCases)
    func aRunInsideATranslucentFillReplays(alpha: Double, painter: Painter) throws {
        let frames = FieldProbe.frames.indices
        let width = 16
        func built(_ drawn: Int) -> (rows: [String], run: AnimatedCellRun?, page: String) {
            let context = makeRenderContext(width: width, height: 4)
            let view = painter.painting(
                HStack(spacing: 0) { Text("x"); FieldProbe(drawn: drawn).opacity(alpha); Text("y") }
                    .padding(.horizontal, 1),
                with: Self.fill)
            let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }
            let page = ColorDepth.withCurrent(.truecolor) {
                ANSIRenderer.backgroundCode(for: context.environment.palette.background)
            }
            let writer = FrameDiffWriter(
                isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
            let rows = writer.buildOutputLines(
                buffer: buffer, terminalWidth: width, terminalHeight: buffer.lines.count,
                bgCode: page, reset: ANSIRenderer.reset)
            return (rows, buffer.animatedCells.first { $0.width == 2 }, page)
        }
        let renders = frames.map(built)
        for drawn in frames {
            let (rows, run, page) = renders[drawn]
            let probe = try #require(run, "no run carried up at \(alpha), frame \(drawn)")
            for shown in frames {
                let replayed = ColorDepth.withCurrent(.truecolor) {
                    paintedCells(
                        FrameBuffer.patchingAnimatedCells(
                            in: rows[probe.offsetY], with: probe.frame(atIndex: shown), atColumn: probe.offsetX,
                            width: probe.width, fields: probe.fields(onPage: page)))
                }
                let rendered = paintedCells(renders[shown].rows[probe.offsetY])
                for column in probe.offsetX..<(probe.offsetX + probe.width)
                where !replayed[column].looksLike(rendered[column]) {
                    Issue.record(
                        """
                        at \(alpha): frame \(shown) over frame \(drawn), column \(column): \
                        replayed \(replayed[column].shown), rendered \(rendered[column].shown)
                        """)
                }
            }
        }
        // Not vacuous: the frame with a field of its own is on it, and the bare one on the fill.
        let own = try #require(renders[0].rows.first.map(paintedCells))
        let bare = try #require(renders[1].rows.first.map(paintedCells))
        let landed = Self.landed(Self.fill, over: Self.page)
        #expect(bare[3].background == Self.field(landed), "the bare frame is on \(bare[3].background.debugDescription)")
        #expect(
            own[2].background == Self.field(Self.red.opacity(alpha, over: landed)),
            "the frame's own field is \(own[2].background.debugDescription)")
    }

    /// What lays the translucent fill under the row: a painter, or a `ZStack` over the
    /// colour, whose composite fills a stated 49 the way a compositing painter does.
    enum Outer: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case background
        case listRowBackground
        case zStack

        var testDescription: String { rawValue }

        @MainActor @ViewBuilder
        func laying(_ fill: Color, under content: some View) -> some View {
            switch self {
            case .background: content.background(fill)
            case .listRowBackground: content.listRowBackground(fill)
            case .zStack:
                ZStack(alignment: .leading) {
                    fill.frame(width: 6, height: 1)
                    content
                }
            }
        }
    }

    /// A run inside an OPAQUE painter inside the translucent fill: its bare cells are on
    /// the opaque painter's colour, in the line and in every frame, and the translucent
    /// fill's claim is beneath that colour. Every frame replayed over the row drawn at
    /// every other is the row a render draws at it. Taking the ground for the translucent
    /// painter's field wherever a frame's cell took it, the bare cells replayed on the
    /// inner green mixed at the fill's alpha, `rgb(23, 85, 23)`, where a render drew the
    /// green, `rgb(40, 160, 40)`.
    ///
    /// Where the fill COMPOSITES — a translucent `.listRowBackground`, a `ZStack` — it
    /// fills the stated 49 the opaque `.background` lets through with the translucent
    /// colour, and the frame stating 49 shows the fill at its alpha, while a bare frame
    /// shows the green. Taking the translucent painter's field only where a frame's cell
    /// took the GROUND, the frame stating 49 replayed on the fill's opaque spelling,
    /// `rgb(0, 0, 200)`, where a render drew `rgb(2, 5, 103)`, at every drawn frame.
    @Test(
        "A run inside an opaque painter inside a translucent fill replays as a render draws it",
        arguments: Painter.allCases, Outer.allCases)
    func aRunInsideAnOpaquePainterInsideATranslucentFill(inner: Painter, outer: Outer) throws {
        let frames = FieldProbe.frames.indices
        let width = 16
        func built(_ drawn: Int) -> (rows: [String], run: AnimatedCellRun?, page: String) {
            let context = makeRenderContext(width: width, height: 4)
            let view = outer.laying(
                Self.fill,
                under: HStack(spacing: 0) {
                    Text("x"); inner.painting(FieldProbe(drawn: drawn), with: Color.rgb(40, 160, 40)); Text("y")
                }
                .padding(.horizontal, 1))
            let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }
            let page = ColorDepth.withCurrent(.truecolor) {
                ANSIRenderer.backgroundCode(for: context.environment.palette.background)
            }
            let writer = FrameDiffWriter(
                isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
            let rows = writer.buildOutputLines(
                buffer: buffer, terminalWidth: width, terminalHeight: buffer.lines.count,
                bgCode: page, reset: ANSIRenderer.reset)
            return (rows, buffer.animatedCells.first { $0.width == 2 }, page)
        }
        let renders = frames.map(built)
        for drawn in frames {
            let (rows, run, page) = renders[drawn]
            let probe = try #require(run, "no run carried up, frame \(drawn)")
            for shown in frames {
                let replayed = ColorDepth.withCurrent(.truecolor) {
                    paintedCells(
                        FrameBuffer.patchingAnimatedCells(
                            in: rows[probe.offsetY], with: probe.frame(atIndex: shown), atColumn: probe.offsetX,
                            width: probe.width, fields: probe.fields(onPage: page)))
                }
                let rendered = paintedCells(renders[shown].rows[probe.offsetY])
                for column in probe.offsetX..<(probe.offsetX + probe.width)
                where !replayed[column].looksLike(rendered[column]) {
                    Issue.record(
                        """
                        \(outer): frame \(shown) over frame \(drawn), column \(column): \
                        replayed \(replayed[column].shown), rendered \(rendered[column].shown)
                        """)
                }
            }
        }
        // Not vacuous: the bare frame's blank is on the green in the render.
        let bare = try #require(renders[1].rows.first.map(paintedCells))
        #expect(bare[3].background == "\u{1B}[48;2;40;160;40m", "the bare frame is on \(bare[3].background.debugDescription)")
    }
}
