//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowStyleReplayTests.swift
//
//  A run inside a row that restates more than a field after every reset in its
//  line — a menu's focused row and a list's cursor row that REVERSE, where the
//  palette's highlight has no RGB to breathe between (Opacity as composition
//  §86, §88) — replayed at every frame of its cycle over the row a render drew at
//  another, and compared with the row a render draws at that frame: cell by
//  cell, as the cells LOOK, the reversal included.
//
//  The row reverses by restating `ESC[7;<ink>;<field>m` after every reset in the
//  line, so a run's frame, drawn inside it, is reversed with it: its glyph is
//  drawn in the row's field on a block of the glyph's own colour. The run records
//  that restatement in its ground (`AnimatedCellRun.ground`), and everything that
//  draws a frame over its ground away from the row — the fade that blends it, the
//  tick that splices it — has to draw it reversed too.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// A two-cell run in the shapes a spinner's frames come in, drawing frame `drawn`
/// into its lines: a glyph in an ink of its own, a glyph in none — the row's —
/// and a glyph on the terminal's own field, stated; each followed by a blank the
/// frame leaves bare.
private struct SpinnerProbe: View, Renderable {
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
@Suite("A run in a row that restates a style replays in it")
struct RowStyleReplayTests {

    /// The row that reverses around the probe.
    enum Row: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// A focused menu row's bar (`_MenuItemRowBar`).
        case menu
        /// A focused list's cursor row (`RowBackground`).
        case list

        var testDescription: String { rawValue }

        @MainActor @ViewBuilder
        func view(drawn: Int) -> some View {
            switch self {
            case .menu:
                Button(action: {}, label: { HStack(spacing: 0) { Text("Busy "); SpinnerProbe(drawn: drawn) } })
                    .buttonStyle(_MenuItemButtonStyle())
            case .list:
                List(selection: .constant(Optional(0))) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 0) { Text("row \(row) "); SpinnerProbe(drawn: drawn) }
                    }
                }
                .frame(width: 16, height: 2)
            }
        }
    }

    /// Whose colours the reversal exchanges.
    enum Pair: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// The terminal's own page, and an RGB ink.
        case terminalPage
        /// An RGB page and ink, with an accent the terminal decides.
        case slotAccent
        /// The terminal's own page and ink.
        case terminalPair

        var testDescription: String { rawValue }

        @MainActor var palette: any Palette {
            switch self {
            case .terminalPage: terminalPagePalette
            case .slotAccent: ReversedRowSlotAccentPalette()
            case .terminalPair: ReversedRowTerminalPairPalette()
            }
        }
    }

    /// Where a fade meets the row.
    enum Fade: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// Around the row and a colour behind it, at 0.6: resolved at the root.
        case around
        /// Inside a colour, at 0.4: spent at the colour's painter (§96).
        case inside

        var testDescription: String { rawValue }

        @MainActor @ViewBuilder
        func view(_ row: some View) -> some View {
            switch self {
            case .around: row.padding(1).background(Color.rgb(90, 20, 120)).opacity(0.6)
            case .inside: row.opacity(0.4).padding(1).background(Color.rgb(90, 20, 120))
            }
        }
    }

    private static let width = 24

    /// `row` drawing the probe's frame `drawn`, faded by `fade`, as the run loop
    /// builds its rows — twice, so the row has taken the keyboard — with the probe's
    /// runs on them.
    private func built(_ row: Row, drawn: Int, pair: Pair, fade: Fade) -> (
        rows: [String], runs: [AnimatedCellRun], page: String
    ) {
        let palette = pair.palette
        let context = makeRenderContext(width: Self.width, height: 8) { environment, _ in
            environment.palette = palette
        }
        let view = fade.view(row.view(drawn: drawn))
        let buffer = ColorDepth.withCurrent(.truecolor) {
            _ = renderToScreen(view, context: context)
            return renderToScreen(view, context: context)
        }
        let page = ColorDepth.withCurrent(.truecolor) { ANSIRenderer.backgroundCode(for: palette.background) }
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        let rows = writer.buildOutputLines(
            buffer: buffer, terminalWidth: Self.width, terminalHeight: buffer.lines.count,
            bgCode: page, reset: ANSIRenderer.reset)
        // The probe's runs, by their shape: the fade rewrote their bytes.
        let runs = buffer.animatedCells.filter { $0.width == 2 && $0.frames.count == SpinnerProbe.frames.count }
        return (rows, runs, page)
    }

    /// Every frame of the probe replayed over the row a render drew at another, and
    /// compared with the row a render draws at that frame — for each pair a
    /// reversal can exchange.
    @Test(
        "A faded run in a reversed row replays as a render draws it",
        arguments: Row.allCases, Fade.allCases)
    func aFadedRunReplaysAsDrawn(row: Row, fade: Fade) throws {
        for pair in Pair.allCases { try replays(row, pair: pair, fade: fade) }
    }

    /// The probe in `row`, faded by `fade`, under `pair`: every frame replayed over
    /// the row drawn at every frame, against the row drawn at the replayed one.
    private func replays(_ row: Row, pair: Pair, fade: Fade) throws {
        try TerminalColors.withCurrent(.unknown) {
            let frames = SpinnerProbe.frames.indices
            let renders = frames.map { built(row, drawn: $0, pair: pair, fade: fade) }
            // Not vacuous: unfaded, the row the probe sits in is drawn reversed. (Faded,
            // a reversal whose colours have RGB is spelled without its 7.)
            let unfaded = ColorDepth.withCurrent(.truecolor) { () -> FrameBuffer in
                let context = makeRenderContext(width: Self.width, height: 8) { environment, _ in
                    environment.palette = pair.palette
                }
                _ = renderToScreen(row.view(drawn: 0), context: context)
                return renderToScreen(row.view(drawn: 0), context: context)
            }
            let line = try #require(unfaded.animatedCells.first.map { unfaded.lines[$0.offsetY] })
            try #require(
                paintedCells(line).contains { $0.state.reversesVideo },
                "\(row), \(pair): the row is not reversed: \(line.debugDescription)")
            for drawn in frames {
                let (rows, runs, page) = renders[drawn]
                let run = try #require(runs.first, "\(row), \(pair), \(fade): no run carried up")
                for shown in frames {
                    let replayed = ColorDepth.withCurrent(.truecolor) {
                        paintedCells(
                            FrameBuffer.patchingAnimatedCells(
                                in: rows[run.offsetY], with: run.frame(atIndex: shown), atColumn: run.offsetX,
                                width: run.width, fields: run.fields(onPage: page)))
                    }
                    let rendered = paintedCells(renders[shown].rows[run.offsetY])
                    for column in run.offsetX..<(run.offsetX + run.width)
                    where !replayed[column].looksLike(rendered[column]) {
                        Issue.record(
                            """
                            \(row), \(pair), \(fade): frame \(shown) over frame \(drawn), column \(column): \
                            replayed \(replayed[column].shown), rendered \(rendered[column].shown)
                            """)
                    }
                }
            }
        }
    }
}
