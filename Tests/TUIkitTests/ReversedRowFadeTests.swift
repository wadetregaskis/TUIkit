//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedRowFadeTests.swift
//
//  A fade INSIDE a row that reverses — a focused list's cursor row, a menu's
//  focused row, where the highlight has no RGB to breathe between (Opacity as
//  composition §86, §88) — fades toward the row and leaves the row alone: the
//  row is behind it (§86.1). Carried up past the reversal to the root, below one
//  half it met the reversal's field as the faded label's own and lost it to the
//  page: a hole in the bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// A two-cell run in the shapes a spinner's frames come in — a glyph in an ink of
/// its own, one in none (the row's), one on the terminal's own field, stated —
/// each followed by a blank the frame leaves bare. Frame `drawn` is drawn into
/// its lines.
private struct ReversedRowProbe: View, Renderable {
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
@Suite("A fade inside a reversed row is spent against the row")
struct ReversedRowFadeTests {

    /// The row that reverses.
    enum Row: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// A focused list's cursor row (`RowBackground.reversed`).
        case list
        /// A focused menu row's bar (`_MenuItemRowBar`).
        case menu

        var testDescription: String { rawValue }

        /// The row: a label faded to `alpha`, one that is not, and the probe faded
        /// with the label.
        @MainActor @ViewBuilder
        func view(alpha: Double, drawn: Int) -> some View {
            let label = HStack(spacing: 0) {
                Text("ab").opacity(alpha)
                Text("cd")
                ReversedRowProbe(drawn: drawn).opacity(alpha)
            }
            switch self {
            case .list:
                List(selection: .constant(Optional(0))) {
                    ForEach(0..<2, id: \.self) { _ in label }
                }
                .frame(width: 16, height: 2)
            case .menu:
                Button(action: {}, label: { label }).buttonStyle(_MenuItemButtonStyle())
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

    private static let width = 20

    /// `row` with its label faded to `alpha` drawing the probe's frame `drawn`, as the
    /// run loop writes it — rendered twice, so the row has taken the keyboard — and the
    /// probe's run.
    private func built(_ row: Row, alpha: Double, drawn: Int, pair: Pair) -> (
        rows: [String], run: AnimatedCellRun?, page: String
    ) {
        let palette = pair.palette
        let context = makeRenderContext(width: Self.width, height: 6) { environment, _ in
            environment.palette = palette
        }
        let view = row.view(alpha: alpha, drawn: drawn)
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
        let run = buffer.animatedCells.first { $0.width == 2 && $0.frames.count == ReversedRowProbe.frames.count }
        return (rows, run, page)
    }

    /// The label faded below and above one half: its cells on the row's field, as
    /// the unfaded label's neighbour is, and its glyphs kept wherever their ink has a
    /// spelling; above one half, where the reversal's colours have no RGB to mix, as
    /// the unfaded label looks. Before, below one half the label was two blanks on the
    /// terminal's own field in the middle of the bar.
    @Test("A label faded inside a reversed row stays on the row", arguments: Row.allCases, [0.3, 0.6])
    func aFadedLabelStaysOnTheRow(row: Row, alpha: Double) throws {
        for pair in Pair.allCases {
            try TerminalColors.withCurrent(.unknown) {
                let faded = built(row, alpha: alpha, drawn: 1, pair: pair)
                let unfaded = built(row, alpha: 1, drawn: 1, pair: pair)
                let line = try #require(
                    faded.rows.firstIndex { paintedCells($0).map(\.glyph).contains("c") },
                    "\(row), \(pair): no row holds the label")
                let cells = paintedCells(faded.rows[line])
                let plain = paintedCells(unfaded.rows[line])
                let neighbour = try #require(cells.firstIndex { $0.glyph == "c" })
                let label = neighbour - 2
                // Not vacuous: the row is reversed around the label.
                #expect(plain[neighbour].state.reversesVideo, "\(row), \(pair): the row is \(plain[neighbour].shown)")
                for column in label..<neighbour {
                    #expect(
                        cells[column].shownField == cells[neighbour].shownField,
                        "\(row), \(pair) at \(alpha): column \(column) is \(cells[column].shown), beside \(cells[neighbour].shown)")
                    // The glyph stays, but where its ink fades all the way into the
                    // field and neither has a spelling in the other's slot: the terminal's
                    // own pair below one half, its page as ink on its foreground as field —
                    // invisible, and dropped as §85 drops one.
                    #expect(
                        cells[column].glyph == plain[column].glyph || (pair == .terminalPair && alpha < 0.5),
                        "\(row), \(pair) at \(alpha): column \(column) lost its glyph: \(cells[column].shown)")
                }
            }
        }
    }

    /// The probe faded with the label: every frame replayed over the row drawn at every
    /// other is the row a render draws at it, as the cells look — the tick restating
    /// nothing over a frame the row has spent.
    @Test("A run faded inside a reversed row replays as a render draws it", arguments: Row.allCases, [0.3, 0.6])
    func aFadedRunReplays(row: Row, alpha: Double) throws {
        for pair in Pair.allCases {
            try TerminalColors.withCurrent(.unknown) {
                let frames = ReversedRowProbe.frames.indices
                let renders = frames.map { built(row, alpha: alpha, drawn: $0, pair: pair) }
                for drawn in frames {
                    let (rows, run, page) = renders[drawn]
                    let probe = try #require(run, "\(row), \(pair) at \(alpha): no run carried up")
                    for shown in frames {
                        let replayed = ColorDepth.withCurrent(.truecolor) {
                            paintedCells(
                                FrameBuffer.patchingAnimatedCells(
                                    in: rows[probe.offsetY], with: probe.frame(atIndex: shown),
                                    atColumn: probe.offsetX, width: probe.width, fields: probe.fields(onPage: page)))
                        }
                        let rendered = paintedCells(renders[shown].rows[probe.offsetY])
                        for column in probe.offsetX..<(probe.offsetX + probe.width)
                        where !replayed[column].looksLike(rendered[column]) {
                            Issue.record(
                                """
                                \(row), \(pair) at \(alpha): frame \(shown) over frame \(drawn), column \(column): \
                                replayed \(replayed[column].shown), rendered \(rendered[column].shown)
                                """)
                        }
                    }
                }
            }
        }
    }
}
