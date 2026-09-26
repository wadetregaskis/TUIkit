//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositorOverNothingTests.swift
//
//  A compositor inside the tree — a `ZStack`, an `.overlay`, a custom `Layout` —
//  resolves a layer's fades against its base where the base shows something under
//  them, and carries them up where it shows nothing, to the painter or the page
//  that is behind the compositor. Resolved against the base's nothing, a faded
//  cell was blended over the page and stated it: a page-coloured hole under a
//  faded label inside a `.background`, its ink mixed toward the page. And a
//  custom `Layout` resolved nothing at all, so a faded child laid over another
//  child's field had that field faded as its own (`Opacity as composition.md`
//  §108).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A `Layout` that lays every subview at the same origin, the last on top.
private struct Overlap: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: 4, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for index in subviews.indices {
            subviews[index].place(at: (x: bounds.x, y: bounds.y), proposal: .unspecified)
        }
    }
}

/// A `Layout` that lays its one subview two columns in.
private struct Indented: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: 6, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for index in subviews.indices {
            subviews[index].place(at: (x: bounds.x + 2, y: bounds.y), proposal: .unspecified)
        }
    }
}

/// A `Layout` that lays every subview at the same origin, the last on top, six cells wide.
private struct WideOverlap: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: 6, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for index in subviews.indices {
            subviews[index].place(at: (x: bounds.x, y: bounds.y), proposal: .unspecified)
        }
    }
}

/// A `Layout` that lays its first subview at the origin, 80 × 24, and every other one
/// cell of its own after it: five to a row, sixteen columns apart, top to bottom.
private struct Scattered: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(width: 80, height: 24)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for index in subviews.indices {
            let cell = max(0, index - 1)
            let at = index == 0 ? (x: 0, y: 0) : (x: (cell % 5) * 16, y: cell / 5)
            subviews[index].place(at: (x: bounds.x + at.x, y: bounds.y + at.y), proposal: .unspecified)
        }
    }
}

/// Two cells of red whose run says their field's alpha, 0.3, frame by frame.
private struct SpokenFieldProbe: View, Renderable {
    var body: Never { fatalError("renders via Renderable") }

    static let frames = ["\u{1B}[48;2;200;0;0m⠋ \u{1B}[0m", "\u{1B}[48;2;200;0;0m⠙ \u{1B}[0m"]

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [Self.frames[0]])
        guard !context.isMeasuring else { return buffer }
        var run = AnimatedCellRun(offsetX: 0, offsetY: 0, width: 2, frames: Self.frames, clock: .content)
        run.alpha = AnimatedRunAlpha(
            perFrame: Self.frames.map { _ in [.init(start: 0, cells: 2, field: 0.3)] }, drawnIndex: 0)
        buffer.animatedCells = [run]
        return buffer
    }
}

/// One cell a block caret draws visible: red in the drawn frame, bare in the other.
private struct RedBlink: View, Renderable {
    var body: Never { fatalError("renders via Renderable") }

    static let frames = ["\u{1B}[48;2;200;0;0mx\u{1B}[0m", "x"]

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [Self.frames[0]])
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells = [AnimatedCellRun(offsetX: 0, offsetY: 0, width: 1, frames: Self.frames, clock: .cursor)]
        return buffer
    }
}

@MainActor
@Suite("A compositor carries up the fades over nothing")
struct CompositorOverNothingTests {

    private static let blue = Color.rgb(0, 0, 200)
    private static let red = Color.rgb(200, 0, 0)
    private static let green = Color.rgb(0, 200, 0)

    /// `colour` as a written cell's field reports it.
    private static func field(_ colour: Color) throws -> String {
        let rgb = try #require(colour.rgbComponents)
        return "\u{1B}[48;2;\(rgb.red);\(rgb.green);\(rgb.blue)m"
    }

    /// The label's ink faded to `alpha` over `colour`, as a cell reports it.
    private func ink(fadedTo alpha: Double, over colour: Color, from row: [PaintedCell], at column: Int) throws
        -> SGRState.Colour?
    {
        guard case .rgb(let red, let green, let blue) = row[column].ink else {
            Issue.record("the unfaded ink is \(String(describing: row[column].ink))")
            return nil
        }
        let faded = try #require(
            Color.rgb(UInt8(red), UInt8(green), UInt8(blue)).opacity(alpha, over: colour).rgbComponents)
        return .rgb(Int(faded.red), Int(faded.green), Int(faded.blue))
    }

    /// The reported shape: the `ZStack` composites the label over its blank canvas,
    /// which shows nothing, so the blue around the `ZStack` is behind the fade. Before,
    /// `a` and `b` were on the page's `48;2;5;10;5` in the middle of the blue, their
    /// ink mixed toward the page.
    @Test("A label faded in a ZStack inside a background is on the background")
    func aFadeInAZStackInsideABackground() throws {
        let unfaded = try #require(
            writtenRows(of: ZStack { Text("ab") }.padding(.horizontal, 1).background(Self.blue)).first)
        let row = try #require(
            writtenRows(of: ZStack { Text("ab").opacity(0.5) }.padding(.horizontal, 1).background(Self.blue)).first)
        #expect(row[1].glyph == "a" && row[2].glyph == "b")
        for column in 1...2 {
            #expect(row[column].background == (try Self.field(Self.blue)), "column \(column) is \(row[column].shown)")
            #expect(row[column].ink == (try ink(fadedTo: 0.5, over: Self.blue, from: unfaded, at: column)))
        }
    }

    /// An `.overlay` over text: its base shows the letter under the dot, so the glyph
    /// contest is the overlay's to decide — and the field under both is nothing, which
    /// the painter outside fills. Before, the dot was on the page, stated, where the blue
    /// is behind it.
    @Test("A dot faded in an overlay over text inside a background is on the background")
    func aFadeInAnOverlayOverTextInsideABackground() throws {
        let row = try #require(
            writtenRows(
                of: Text("xy").overlay { Text("•").opacity(0.5) }.padding(.horizontal, 1).background(Self.blue)
            ).first)
        #expect(row[1].glyph == "•", "the dot lost its contest: \(row[1].shown)")
        #expect(row[1].background == (try Self.field(Self.blue)), "the dot is \(row[1].shown)")
        #expect(row[1].background == row[2].background)
    }

    /// Where the base DOES show something, the compositor still decides it: below one
    /// half the base's glyph wins the cell.
    @Test("A label faded below one half over text still yields to it")
    func aFadeOverTextStillYields() throws {
        let row = try #require(writtenRows(of: ZStack { Text("xy"); Text("ab").opacity(0.3) }).first)
        #expect(row.prefix(2).map(\.glyph) == ["x", "y"])
    }

    /// A custom `Layout` lays a faded label over another child's red. It composited
    /// the label in place and lifted its fade unresolved, so the root met the red
    /// as the label's own field and faded it: `ab` on `48;2;103;5;3` beside the red.
    /// Resolved where it lands on the red, as a `ZStack` resolves it.
    @Test("A label a custom Layout lays over a colour is faded over the colour, as a ZStack's is")
    func aFadeALayoutLaysOverAColour() throws {
        let laid = try #require(
            writtenRows(of: Overlap { Self.red.frame(width: 4, height: 1); Text("ab").opacity(0.5) }).first)
        let stacked = try #require(
            writtenRows(
                of: ZStack(alignment: .topLeading) { Self.red.frame(width: 4, height: 1); Text("ab").opacity(0.5) }
            ).first)
        #expect(laid[0].glyph == "a")
        #expect(laid[0].background == (try Self.field(Self.red)), "a is \(laid[0].shown)")
        #expect(laid[0].background == laid[2].background)
        #expect(laid.prefix(4).map(\.shown) == stacked.prefix(4).map(\.shown))
    }

    /// A child a `Layout` lays over nothing still carries its fade up, to the painter.
    @Test("A label a custom Layout lays over nothing is faded over the painter around it")
    func aFadeALayoutLaysOverNothing() throws {
        let row = try #require(
            writtenRows(of: Indented { Text("ab").opacity(0.5) }.background(Self.blue)).first)
        #expect(row[2].glyph == "a")
        #expect(row[2].background == (try Self.field(Self.blue)), "a is \(row[2].shown)")
        #expect(row[2].background == row[0].background)
    }

    /// With nothing around the compositor, the page is behind it, and the carried fade
    /// is resolved there as it was at the compositor.
    @Test("With no painter around it, a faded label in a ZStack is on the page as before")
    func aFadeInAZStackWithNothingAround() throws {
        let row = try #require(writtenRows(of: ZStack { Text("ab").opacity(0.5) }).first)
        let page = try #require(writtenRows(of: Text("ab").opacity(0.5)).first)
        #expect(row.prefix(2).map(\.shown) == page.prefix(2).map(\.shown))
    }

    /// The split itself: claims over cells whose base shows nothing go up, the rest
    /// stay; a run that states its own alpha wholly over nothing goes up whole.
    @Test("A layer's claims are cut by what its base shows under them")
    func claimsAreCutByTheBase() {
        var layer = FrameBuffer(lines: ["abcd"])
        layer.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 4, height: 1, opacity: 0.5)]
        var caret = AnimatedCellRun(offsetX: 3, offsetY: 0, width: 1, frames: ["d", "D"], clock: .cursor)
        caret.alpha = AnimatedRunAlpha(perFrame: [[.init(start: 0, cells: 1, field: 0.3)], []], drawnIndex: 0)
        layer.animatedCells = [caret]
        // A base of two painted cells, then two blank ones.
        let base = FrameBuffer(lines: [ANSIRenderer.colorize("  ", background: Self.red) + "  "])
        let split = layer.splittingClaims(overNothingIn: base, at: (x: 0, y: 0))
        #expect(split.here.opacityRegions.map { $0.offsetX..<($0.offsetX + $0.width) } == [0..<2])
        #expect(split.carried.map { $0.offsetX..<($0.offsetX + $0.width) } == [2..<4])
        #expect(split.setAside.map(\.offsetX) == [3])
        #expect(split.here.animatedCells.isEmpty)
    }

    /// `view` as the page shows it, its fades spent over the page — what a layer laid
    /// on it is laid on, where nothing further out is behind it.
    private static func spent(_ view: some View, width: Int = 6) -> FrameBuffer {
        let context = makeRenderContext(width: width, height: 1)
        return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }
    }

    /// The reported shape. The translucent colour lands on the `ZStack`'s blank canvas
    /// and carries its claim up; the label laid over it keeps the field it lands on,
    /// which is the colour's opaque spelling there, and the composite punched the
    /// claim under it: `a` and `b` on `48;2;0;0;200` in a row of `48;2;2;5;103`.
    @Test("A label over a translucent colour in a ZStack is on the colour as it shows beside the label")
    func aLabelOverATranslucentColourInAZStack() throws {
        let row = try #require(
            writtenRows(
                of: ZStack(alignment: .leading) {
                    Self.blue.opacity(0.5).frame(width: 6, height: 1)
                    Text("ab")
                }
            ).first)
        #expect(row[0].glyph == "a")
        // Not vacuous: beside the label the fill is half way to the page.
        #expect(row[4].background == "\u{1B}[48;2;2;5;103m")
        #expect(row[0].background == row[4].background, "a is on \(row[0].background), the fill beside it on \(row[4].background)")
        #expect(row[1].background == row[4].background)
    }

    /// Inside a painter the colour is over the painter's field, under the label and
    /// beside it alike: the claim the label leaves the field to is kept, about that
    /// field alone, and spent where the painter is known.
    @Test("A label over a translucent colour in a ZStack inside a background is on the colour over the background")
    func aLabelOverATranslucentColourInAZStackInsideABackground() throws {
        let row = try #require(
            writtenRows(
                of: ZStack(alignment: .leading) {
                    Self.blue.opacity(0.5).frame(width: 6, height: 1)
                    Text("ab")
                }.background(Self.red)
            ).first)
        #expect(row[0].glyph == "a")
        #expect(row[4].background == (try Self.field(Self.blue.opacity(0.5, over: Self.red))))
        #expect(row[0].background == row[4].background, "a is on \(row[0].background), the fill beside it on \(row[4].background)")
        // And the label's ink is its own, at full strength.
        let alone = try #require(writtenRows(of: Text("ab").background(Self.red)).first)
        #expect(row[0].ink == alone[0].ink)
    }

    /// A label stating the terminal's own field over the translucent colour, in a
    /// `ZStack`, a custom `Layout`, and an `.overlay` on a translucent fill: the
    /// composite fills a stated 49 as it fills a cell that says nothing, so the label
    /// shows the colour's field and keeps its claim. Read as the label's own field, as a
    /// painter reads a 49, the claim was punched: `a` on `48;2;0;0;200` in a row of
    /// `48;2;2;5;103`.
    @Test("A label stating 49 over a translucent colour is on the colour as it shows beside the label", arguments: StatedLabel.allCases)
    func aStated49LabelOverATranslucentColour(in shape: StatedLabel) throws {
        let row = try #require(writtenRows(of: shape.view(over: Self.blue.opacity(0.5))).first)
        #expect(row[0].glyph == shape.glyph)
        #expect(row[4].background == "\u{1B}[48;2;2;5;103m", "the colour beside the label is \(row[4].shown)")
        #expect(row[0].background == row[4].background, "\(shape.glyph) is on \(row[0].background)")
    }

    /// The shapes a label stating 49 lands on a translucent colour in.
    enum StatedLabel: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case zStack
        case layout
        case overlay

        var testDescription: String { rawValue }
        var glyph: Character { self == .overlay ? "x" : "a" }

        @MainActor @ViewBuilder
        func view(over colour: Color) -> some View {
            switch self {
            case .zStack:
                ZStack(alignment: .leading) {
                    colour.frame(width: 6, height: 1)
                    Text("ab").background(Color.default)
                }
            case .layout:
                WideOverlap {
                    colour.frame(width: 6, height: 1)
                    Text("ab").background(Color.default)
                }
            case .overlay:
                Text("hello ").background(colour).overlay(alignment: .leading) { Text("x").background(Color.default) }
            }
        }
    }

    /// A label reversed over the translucent colour: the composite fills its background
    /// slot, which the reversal shows as its INK, with the colour's field — which a
    /// claim on a field cannot reach, so the colour is spent there first. Punched, the
    /// glyphs were drawn in the colour at full strength.
    @Test("An inverted label over a translucent colour is drawn in the colour as it lands")
    func anInvertedLabelOverATranslucentColour() throws {
        let row = try #require(
            writtenRows(
                of: ZStack(alignment: .leading) {
                    Self.blue.opacity(0.5).frame(width: 6, height: 1)
                    Text("ab").inverted()
                }
            ).first)
        #expect(row[0].glyph == "a")
        #expect(row[0].shownInk == .colour(.rgb(2, 5, 103)), "a is \(row[0].shown)")
    }

    /// A label whose only alpha is its INK's, over the translucent colour inside a
    /// painter: an ink's alpha fades nothing on what is behind it, so the colour's claim
    /// under the label is kept, and the label's goes up with it, to be mixed over the
    /// field the cell ends up with. Taken for a fade, the colour was spent over the page
    /// under the label and carried to the painter beside it: `a` on `48;2;2;5;103`
    /// beside `48;2;100;0;100`.
    @Test("A label in a translucent ink over a translucent colour inside a background is on the colour over it")
    func aTranslucentInkLabelOverATranslucentColourInsideABackground() throws {
        let row = try #require(
            writtenRows(
                of: ZStack(alignment: .leading) {
                    Self.blue.opacity(0.5).frame(width: 6, height: 1)
                    Text("ab").foregroundStyle(Self.green.opacity(0.4))
                }.background(Self.red)
            ).first)
        let landed = Self.blue.opacity(0.5, over: Self.red)
        #expect(row[4].background == (try Self.field(landed)))
        #expect(row[0].background == row[4].background, "a is on \(row[0].background)")
        let ink = try #require(Self.green.opacity(0.4, over: landed).rgbComponents)
        #expect(row[0].ink == .rgb(Int(ink.red), Int(ink.green), Int(ink.blue)), "a is \(row[0].shown)")
    }

    /// The same at the root, where the page is behind the colour: the label's ink is
    /// mixed toward the colour as it lands on the page, as it was before its claim went up.
    @Test("A label in a translucent ink over a translucent colour at the root is mixed toward the colour as it lands")
    func aTranslucentInkLabelOverATranslucentColourAtTheRoot() throws {
        let row = try #require(
            writtenRows(
                of: ZStack(alignment: .leading) {
                    Self.blue.opacity(0.5).frame(width: 6, height: 1)
                    Text("ab").foregroundStyle(Self.green.opacity(0.4))
                }
            ).first)
        #expect(row[4].background == "\u{1B}[48;2;2;5;103m")
        #expect(row[0].background == row[4].background, "a is on \(row[0].background)")
        let ink = try #require(Self.green.opacity(0.4, over: Color.rgb(2, 5, 103)).rgbComponents)
        #expect(row[0].ink == .rgb(Int(ink.red), Int(ink.green), Int(ink.blue)), "a is \(row[0].shown)")
    }

    /// Faded inverted text under a label inside a painter: a reversal of an ink with an
    /// RGB shows that ink as a field the composite spells, so the text's claim is kept
    /// under the label and resolved over the painter there, as beside the label. Spent
    /// first, it was mixed over the page under the label.
    @Test("Faded inverted text under a label inside a background is mixed over the background under it")
    func fadedInvertedTextUnderALabelInsideABackground() throws {
        let row = try #require(
            writtenRows(
                of: ZStack(alignment: .leading) { Text("abcdef").inverted().opacity(0.5); Text("xy") }
                    .background(Self.red)
            ).first)
        #expect(row[0].glyph == "x" && row[3].glyph == "d")
        #expect(row[0].shownField == row[3].shownField, "x is \(row[0].shown), d \(row[3].shown)")
    }

    /// A translucent fill under an `.overlay`: the overlay's label leaves the field to
    /// the fill, which is kept under it, as a `ZStack`'s colour is. Punched, the label
    /// was on the fill's opaque spelling in a row of the fill at one half.
    @Test("A label overlaid on a translucent fill is on the fill as it shows beside the label")
    func aLabelOverlaidOnATranslucentFill() throws {
        let row = try #require(
            writtenRows(of: Text("hello").background(Self.blue.opacity(0.5)).overlay(alignment: .leading) { Text("x") })
                .first)
        #expect(row[0].glyph == "x")
        #expect(row[3].background == "\u{1B}[48;2;2;5;103m")
        #expect(row[0].background == row[3].background, "x is on \(row[0].background), the fill beside it on \(row[3].background)")
    }

    /// A run whose drawn frame states a field of its own over a translucent
    /// `Color.default`: the colour's claim is kept beneath the frame's field, in the
    /// base's colour — the terminal's own, a stated `ESC[49m` in the canvas. Spelled as
    /// no escape at all, the claim read as the field the cell SHOWS, and the caret's
    /// own red was mixed at 0.4 over the page: `x` on `48;2;82;6;4`.
    @Test("A run's drawn field over a translucent Color.default is its own")
    func aRunsDrawnFieldOverATranslucentTerminalField() throws {
        let row = try #require(
            writtenRows(
                of: ZStack(alignment: .leading) {
                    Color.default.opacity(0.4).frame(width: 4, height: 1)
                    RedBlink()
                }
            ).first)
        #expect(row[0].glyph == "x")
        #expect(row[0].background == "\u{1B}[48;2;200;0;0m", "x is on \(row[0].shown)")
    }

    /// A hundred one-cell labels a custom `Layout` lays over a translucent backdrop filling
    /// its canvas: the backdrop's claim is carried in the canvas, and each label settles it
    /// under its one cell. Cut over the whole claim, each settle asked about every cell of
    /// the backdrop's piece the label landed in — 27,780 cells for 100 of footprint. Only
    /// the cells the label covers are asked about now, 100, and each label is on the
    /// backdrop as it shows beside it.
    @Test("A layer settles only the base's cells it covers")
    func aSettleAsksOnlyTheCellsTheLayerCovers() throws {
        let work = FrameBuffer.SettleWork()
        let rows = FrameBuffer.$settleWork.withValue(work) {
            writtenRows(
                of: Scattered {
                    Self.blue.opacity(0.5).frame(width: 80, height: 24)
                    ForEach(0..<100, id: \.self) { _ in Text("x") }
                },
                width: 80, height: 24)
        }
        #expect(work.cellsAsked > 0, "no settle asked about a cell")
        #expect(work.cellsAsked <= 4 * 100, "\(work.cellsAsked) cells asked about for 100 of footprint")
        let top = try #require(rows.first)
        #expect(top[0].glyph == "x" && top[16].glyph == "x")
        #expect(top[1].background == "\u{1B}[48;2;2;5;103m")
        #expect(top[0].background == top[1].background, "x is on \(top[0].shown)")
    }

    /// Where the later layer FADES, it is blended over the earlier one as the page
    /// shows it: that layer's claims are spent first. Blended over the earlier layer
    /// unfaded, the `x` that wins the contest below one half was drawn at nearly full
    /// strength where it is faint, and a label faded over a translucent colour was
    /// blended over the colour's opaque spelling.
    @Test("A faded layer over a faded one is blended over it as it shows", arguments: [false, true])
    func aFadedLayerOverAFadedOne(overAColour: Bool) throws {
        let lower: AnyView =
            overAColour ? AnyView(Self.blue.opacity(0.5).frame(width: 2, height: 1)) : AnyView(Text("xy").opacity(0.3))
        let upperAlpha = overAColour ? 0.5 : 0.4
        let stacked = try #require(
            writtenRows(of: ZStack(alignment: .leading) { lower; Text("ab").opacity(upperAlpha) }).first)
        // The two in turn, by hand: the lower layer as the page shows it, and the upper
        // one resolved over that.
        let palette = makeRenderContext(width: 6, height: 1).environment.palette
        let upper = ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(Text("ab").opacity(upperAlpha), context: makeRenderContext(width: 6, height: 1))
        }
        let byHand = ColorDepth.withCurrent(.truecolor) {
            Self.spent(lower).compositedResolvingOpacity(with: upper, at: (x: 0, y: 0), palette: palette)
        }
        let expected = try #require(writtenRows(byHand, palette: palette, width: 24).first)
        #expect(stacked.prefix(2).map(\.shown) == expected.prefix(2).map(\.shown))
        // Not vacuous: over the faint text the text wins, faint; over the colour the
        // label is on the colour as it shows.
        if overAColour {
            #expect(stacked[0].background == "\u{1B}[48;2;2;5;103m", "a is on \(stacked[0].background)")
        } else {
            let unfaded = try #require(writtenRows(of: Text("xy")).first)
            #expect(stacked[0].glyph == "x")
            #expect(stacked[0].ink != unfaded[0].ink, "x is at full strength")
        }
    }

    /// A run that says its field's alpha frame by frame, across the edge of what a
    /// `ZStack`'s base shows: its cell over nothing goes up, and is resolved over the
    /// painter around the `ZStack`, as a run wholly over nothing is. Resolved with the
    /// rest where it landed, its field was mixed over the page.
    @Test("A run stating its alpha partly over nothing is resolved over the painter beyond it")
    func aSpokenRunPartlyOverNothing() throws {
        let row = try #require(
            writtenRows(
                of: ZStack(alignment: .leading) {
                    Self.blue.frame(width: 1, height: 1)
                    SpokenFieldProbe()
                }.background(Self.green)
            ).first)
        #expect(row[1].glyph == " ")
        #expect(row[1].background == (try Self.field(Self.red.opacity(0.3, over: Self.green))), "the cell over nothing is \(row[1].shown)")
        // Not vacuous: over the blue it is mixed over the blue.
        #expect(row[0].background == (try Self.field(Self.red.opacity(0.3, over: Self.blue))), "the cell over the blue is \(row[0].shown)")
    }

    /// A repeating fade cut by the split, over a run that steps with it: the run is cut
    /// at the same column, so each side's fade folds its own piece. Whole, the run was
    /// inside neither side's columns, and the side resolved here dropped it.
    @Test("A run under a repeating fade the split cuts is cut with it")
    func aRunUnderACutFadeIsCutWithIt() {
        var layer = FrameBuffer(lines: ["abc"])
        var breath = OpacityRegion(offsetX: 0, offsetY: 0, width: 3, height: 1, opacity: 0.9)
        breath.cycle = OpacityCycle(phases: [0.9, 0.7], clock: .content)
        layer.opacityRegions = [breath]
        layer.animatedCells = [AnimatedCellRun(offsetX: 0, offsetY: 0, width: 3, frames: ["abc", "ABC"], clock: .content)]
        let split = layer.splittingClaims(overNothingIn: FrameBuffer(lines: ["xy "]), at: (x: 0, y: 0))
        #expect(split.here.opacityRegions.map { $0.offsetX..<($0.offsetX + $0.width) } == [0..<2])
        #expect(split.carried.map { $0.offsetX..<($0.offsetX + $0.width) } == [2..<3])
        #expect(split.here.animatedCells.map { $0.offsetX..<($0.offsetX + $0.width) } == [0..<2, 2..<3])
        #expect(split.here.animatedCells.map(\.frames) == [["ab", "AB"], ["c", "C"]])
    }
}
