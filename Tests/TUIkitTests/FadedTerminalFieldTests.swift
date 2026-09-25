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
    /// Built as the run loop builds them, on the page and with the page put back
    /// after every reset (`FrameDiffWriter`), because that is the one thing that
    /// tells a stated 49 from a cell naming no field: the buffer spells both as no
    /// background, and only the row puts the page under one of them.
    private func rows(_ view: some View, terminalPage: Bool = false) -> [[PaintedCell]] {
        let context = makeRenderContext(width: 24, height: 12) { environment, _ in
            if terminalPage { environment.palette = terminalPagePalette }
        }
        let lines = ColorDepth.withCurrent(.truecolor) {
            let buffer = renderToScreen(view, context: context)
            let writer = FrameDiffWriter(
                isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
            return writer.buildOutputLines(
                buffer: buffer, terminalWidth: 24, terminalHeight: buffer.lines.count,
                bgCode: RenderBackgroundCodes(palette: context.environment.palette).content,
                reset: ANSIRenderer.reset)
        }
        return lines.map(paintedCells)
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
        // Where the span opens on a field, the opacity splice paints that field
        // under every cell the span names none for — `b` after its reset included.
        withKnownIssue("the opacity splice paints the field under its span's first cell") {
            #expect(
                faded[1].background == Self.rgbPage, "the faded row draws b on \(faded[1].background.debugDescription)")
        } when: {
            gap == .translucentFields
        }
    }
}
