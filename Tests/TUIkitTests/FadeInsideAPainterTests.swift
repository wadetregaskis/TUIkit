//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FadeInsideAPainterTests.swift
//
//  A painter that puts an opaque field under content — a `.background`, a ramp,
//  a list row's fill, a tab's surface, a compositor's base — is what is behind
//  every fade inside that content. So a fade INSIDE a painter fades toward the
//  painter's field and leaves the field alone: a cell the faded view states no
//  field for is on the painter's field, faded or not, and a field the view does
//  state is mixed toward it. Carried up to the root instead, the fade met the
//  painter's field as the faded view's own and faded it too — toward the page,
//  or, on a page that is the terminal's own, all the way to it below one half.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A fade inside a painter fades toward the painter's field")
struct FadeInsideAPainterTests {

    /// `rgb` spelled as a written cell reports it.
    private static func spelled(_ rgb: (red: UInt8, green: UInt8, blue: UInt8)) -> String {
        "\u{1B}[48;2;\(rgb.red);\(rgb.green);\(rgb.blue)m"
    }

    /// The colour a written cell's field is, for a blend: its RGB, or the
    /// terminal's own field where it names none.
    private static func colour(ofField field: String) -> Color {
        let parameters = field.dropFirst(2).dropLast().split(separator: ";").compactMap { UInt8($0) }
        guard parameters.count == 5, parameters[0] == 48, parameters[1] == 2 else { return .terminalBackground }
        return .rgb(parameters[2], parameters[3], parameters[4])
    }

    /// The reported shape: the fade is inside the `.background`, so the blue is
    /// behind it and stays blue, and the label fades toward the blue. On the
    /// terminal's own page, carried to the root, the blue faded toward a page with
    /// no RGB — the heavier side winning — and was that page at 0.3; on a page
    /// with an RGB it came out 30% of the way to the page.
    @Test("A label faded inside a background stays on the background", arguments: [false, true])
    func aLabelFadedInsideABackground(terminalPage: Bool) throws {
        let palette: (any Palette)? = terminalPage ? terminalPagePalette : nil
        let blue = try #require(Color.blue.rgbComponents)
        let unfaded = try #require(writtenRows(of: Text("x").background(Color.blue), palette: palette).first)
        let row = try #require(
            writtenRows(of: Text("x").opacity(0.3).background(Color.blue), palette: palette).first)
        #expect(row[0].glyph == "x", "the label is gone: \(row[0])")
        #expect(row[0].background == Self.spelled(blue), "x is drawn on \(row[0].background.debugDescription)")
        // And the ink is the label's, 30% of the way from the blue.
        guard case .rgb(let red, let green, let blue) = unfaded[0].ink else {
            Issue.record("the unfaded label's ink is \(String(describing: unfaded[0].ink))")
            return
        }
        let ink = try #require(
            Color.rgb(UInt8(red), UInt8(green), UInt8(blue)).opacity(0.3, over: .blue).rgbComponents)
        #expect(row[0].ink == .rgb(Int(ink.red), Int(ink.green), Int(ink.blue)))
    }

    /// A painter inside the painter: a focused list's cursor row reverses the
    /// palette's pair where its highlight has no RGB to breathe between, and spends
    /// the fades inside it against that reversal (§86.1). A `.background` around the
    /// list is behind the row, not behind the label, and has nothing left to spend.
    /// Spent by the `.background` instead, the label's cells were mixed toward its
    /// fill — at 0.6, a patch of `rgb(132, 132, 180)` under `ab` in a bar of 220.
    @Test("A fade inside a reversed row inside a background is the row's to spend", arguments: [0.3, 0.6])
    func aFadeInsideAReversedRowInsideABackground(alpha: Double) throws {
        let context = makeRenderContext(width: 24, height: 6) { environment, _ in
            environment.palette = terminalPagePalette
        }
        let list = List(selection: .constant(Int?.none)) {
            ForEach(0..<3, id: \.self) { _ in HStack(spacing: 0) { Text("ab").opacity(alpha); Text("cd") } }
        }
        .frame(width: 20, height: 5)
        .background(Color.rgb(0, 0, 120))
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToScreen(list, context: context) }
        let row = try #require(
            writtenRows(buffer, palette: terminalPagePalette, width: 24).first { $0.count > 4 && $0[4].glyph == "c" && $0[4].state.reversesVideo },
            "no reversed row holds the label")
        #expect(
            row[2].shownField == row[4].shownField && row[2].glyph == "a",
            "at \(alpha) the label is \(row[2].shown), beside \(row[4].shown)")
    }

    /// A probe with all three kinds of cell — one on a colour of its own, one
    /// stating no field, and two stating the terminal's own — faded below one half
    /// INSIDE each painter. Every column keeps the painter's field except the
    /// coloured one, which is its colour 30% of the way from the painter's field
    /// (or that field, where it has no RGB): the bare cell names no field and
    /// composites none, and a stated 49 — a colour with no RGB — is the lighter
    /// side below one half. Columns outside the probe are the unfaded row's.
    @Test(
        "Inside every painter, a fade below one half leaves the painter's field where it was",
        arguments: FieldPainter.allCases, [false, true])
    func aFadeBelowOneHalfInsideEveryPainter(painter: FieldPainter, terminalPage: Bool) throws {
        let palette: (any Palette)? = terminalPage ? terminalPagePalette : nil
        let own = Color.rgb(40, 40, 200)
        let probe = HStack(spacing: 0) {
            Text("x").background(own)
            Text("y")
            Text("ab").background(Color.default)
        }
        let unfaded = writtenRows(of: painter.view(probe), palette: palette)
        let faded = writtenRows(of: painter.view(probe.opacity(0.3)), palette: palette)
        // What the painter puts under each column, the probe drawing no field.
        let bare = writtenRows(of: painter.view(Text("xyab")), palette: palette)
        try #require(faded.count == unfaded.count && bare.count == unfaded.count)
        if painter == .listRowFill {
            withKnownIssue("a List row's fill is not yet the backdrop of the fades inside it") {
                expectPaintersFieldsKept(painter, unfaded: unfaded, faded: faded, bare: bare, own: own)
            }
        } else if terminalPage, painter == .none || painter == .tabSurface {
            // Where the backdrop is the terminal's own page, every cell the fade
            // leaves on it is spelled `ESC[49m`, and the opacity splice paints the
            // field under its span's first cell — the probe's own colour — under
            // every one of them.
            withKnownIssue("the opacity splice fills a faded span's stated 49 with the field it lands on") {
                expectPaintersFieldsKept(painter, unfaded: unfaded, faded: faded, bare: bare, own: own)
            }
        } else {
            expectPaintersFieldsKept(painter, unfaded: unfaded, faded: faded, bare: bare, own: own)
        }
    }

    /// Every probe `unfaded` has, in `faded` on exactly the fields
    /// ``aFadeBelowOneHalfInsideEveryPainter(painter:terminalPage:)`` describes.
    private func expectPaintersFieldsKept(
        _ painter: FieldPainter, unfaded: [[PaintedCell]], faded: [[PaintedCell]], bare: [[PaintedCell]],
        own: Color
    ) {
        var probed = 0
        for (row, cells) in unfaded.enumerated() {
            // Every probe on the row, found in the unfaded one: faded on the
            // terminal's own page, a glyph can blend away.
            let starts = cells.indices.filter { start in
                start + 3 < cells.count && cells[start..<(start + 4)].map(\.glyph) == ["x", "y", "a", "b"]
            }
            probed += starts.count
            // The four columns under each probe are what it states, over the painter.
            var expected = cells.map(\.background)
            for start in starts {
                let under = (start..<(start + 4)).map { bare[row][$0].background }
                let mixed = own.opacity(0.3, over: Self.colour(ofField: under[0]))
                expected.replaceSubrange(
                    start..<(start + 4), with: [mixed.rgbComponents.map(Self.spelled) ?? under[0]] + under.dropFirst())
            }
            // And every other column is the unfaded row's: nothing outside the
            // probe moves.
            #expect(
                faded[row].map(\.background) == expected,
                "\(painter), row \(row): probes at \(starts) over \(bare[row].map(\.background))")
        }
        #expect(probed > 0, "\(painter) drew no probe")
    }

    /// A `withAnimation` fade from 0.2 to 0.8 inside a `.background`, on the
    /// terminal's own page, rendered every 100 ms across the second it takes. The
    /// cell that states no field is on the blue at every frame; a stated 49 — no
    /// RGB, so the heavier side wins — is on the blue below one half and on the
    /// terminal's own at or above it, and changes once. Resolved at the root, the
    /// blue itself was the faded side: it vanished to the page under every cell
    /// for every frame below one half and came back at it.
    @Test("A fade crossing one half inside a background leaves the background where it was")
    func aFadeCrossingOneHalfInsideABackground() throws {
        var context = makeRenderContext(width: 24, height: 3) { environment, _ in
            environment.palette = terminalPagePalette
        }
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))
        let blue = Self.spelled(try #require(Color.blue.rgbComponents))
        func row(_ alpha: Double, atMillis millis: Int) -> [PaintedCell] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let view = HStack(spacing: 0) {
                Text("x").background(Color.rgb(40, 40, 200))
                Text("y")
                Text("ab").background(Color.default)
            }
            .opacity(alpha).background(Color.blue)
            return ColorDepth.withCurrent(.truecolor) {
                writtenRows(
                    renderToScreen(view, context: context), palette: context.environment.palette, width: 24)
            }.first ?? []
        }
        _ = row(0.2, atMillis: 0)
        var stated: [String] = []
        for millis in stride(from: 0, through: 1_000, by: 100) {
            let cells = row(0.8, atMillis: millis)
            try #require(cells.count > 3)
            #expect(cells[1].glyph == "y")
            #expect(cells[1].background == blue, "at \(millis) ms y is on \(cells[1].background.debugDescription)")
            stated.append(cells[2].background)
        }
        // The stated 49 goes from the blue to the terminal's own, once, and was on
        // each side at some frame: the fade did cross one half. Above one half the
        // span states it as `ESC[49m`, and the opacity splice paints the field under
        // the span's first cell — `x`'s own colour — under it.
        let changes = zip(stated, stated.dropFirst()).filter { $0 != $1 }.count
        withKnownIssue("the opacity splice fills a faded span's stated 49 with the field it lands on") {
            #expect(stated.first == blue && stated.last?.isEmpty == true && changes == 1, "the stated 49 was on \(stated)")
        }
    }
}
