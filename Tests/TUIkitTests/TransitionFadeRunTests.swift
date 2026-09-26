//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionFadeRunTests.swift
//
//  `.transition(.opacity)` fades the runs of the view it moves exactly as it
//  fades the lines: every frame's ink and field, and what the containers inside
//  it painted beneath the runs' cells (`AnimatedCellRun.ground`).
//
//  A transition renders on the view-animation lattice, every 2 ticks of 1/60 s,
//  and a replay serves any tick no render is due at: a `.dots` spinner steps every
//  7 ticks, so four of its eight steps in a one-second transition land between
//  renders and are replayed onto the frame the last render left. The fade used to
//  rewrite only the lines, so each of those ticks drew the spinner at full
//  strength, on its unfaded field, in the middle of a view half faded out.
//
//  Pinned twice: at the effect, where the drawn frame replayed over its ground has
//  to be the faded row; and through the run loop (`ReplayOracle`), where the loop
//  renders on the transition's lattice and replays the spinner's steps between.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A spinner on a colour of its own, arriving under a one-second `.opacity`
/// transition as the app first appears.
private struct ArrivingSpinner: View {
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Arriving")
            if shown {
                HStack(spacing: 0) { Text("Busy "); Spinner(style: .dots) }
                    .background(Color.rgb(40, 40, 200))
                    .transition(.opacity)
            }
        }
        .onAppear { withAnimation(.linear(duration: 1)) { shown = true } }
    }
}

private struct ArrivingSpinnerApp: App {
    init() {}
    var body: some Scene { WindowGroup { ArrivingSpinner() } }
}

/// A two-cell run in the shapes a spinner's frames come in — a glyph in an ink of
/// its own, one in none (the row's), one on the terminal's own field, stated — each
/// followed by a blank the frame leaves bare. Frame `drawn` is drawn into its lines.
private struct TransitionRowProbe: View, Renderable {
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
@Suite("A transition's fade fades the runs it covers")
struct TransitionFadeRunTests {

    /// Every replayed tick of the arrival against a render — its glyph at the
    /// replayed instant, its colours at the instant the loop last rendered, which
    /// is what the screen shows between two of the transition's renders
    /// (`ReplayOracle.ColourTruth.lastRendered`).
    @Test("Through the run loop, a spinner arriving under a fade replays faded as its render drew it")
    func arrivalReplaysFaded() {
        let found = ReplayOracle.compare({ ArrivingSpinnerApp() }, ticks: 24, colours: .lastRendered)
        // Not vacuous: the loop rendered on the transition's lattice, and between
        // those renders a replay moved the spinner on.
        #expect(found.scheduledRenders > 0, "the loop never rendered on the transition's lattice")
        #expect(found.movedGlyphs > 0, "no replay moved the spinner between two renders")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    @Test("The drawn frame, replayed over its ground, is the faded row", arguments: [0.25, 0.5, 0.75])
    func replayIsTheFadedRow(phase: Double) throws {
        let context = makeRenderContext(width: 8, height: 1)
        let spinner = Spinner().foregroundStyle(Color.rgb(40, 200, 40)).background(Color.rgb(40, 40, 200))
        let buffer = ColorDepth.withCurrent(.truecolor) {
            let drawn = renderToBuffer(spinner, context: context)
            return AnyTransition.Effect.opacity.apply(to: drawn, phase: phase, context: context).buffer
        }
        let run = try #require(buffer.animatedCells.first, "the fade dropped the spinner's run")
        let cells = paintedCells(buffer.lines[run.offsetY])
        let shown = (run.offsetX..<(run.offsetX + run.width)).map { cells[$0] }
        // Not vacuous: the fade moved the field away from the spinner's own.
        #expect(shown.allSatisfy { $0.background != "\u{1B}[48;2;40;40;200m" }, "at \(phase) the field is unfaded")
        #expect(run.groundFields(onPage: "").map(spelled) == shown.map(\.background), "at \(phase): the ground")
        expectReplayIsIdentity(buffer, "at \(phase): the replay does not draw what the fade drew")
    }

    /// The probe in a row that REVERSES — a focused list's cursor row, a menu's
    /// focused row, on a palette whose highlight has no RGB to breathe between — under
    /// the transition's fade. Over the terminal's unreported page the fade drops a
    /// glyph whose ink and field, as the cell displays them, are both that page, and
    /// clears the reversal with it: so below one half the row fades to the page. Its
    /// frames were restyled alone, judged unreversed on the terminal's own colours,
    /// which the fade never touches, and every frame but the one with an ink of its
    /// own replayed its glyph where the render has a blank of the page.
    @Test(
        "A run in a reversed row fades under a transition as the row does",
        arguments: [false, true], [0.25, 0.4, 0.6, 0.75])
    func aRunInAReversedRowFadesWithTheRow(list: Bool, phase: Double) throws {
        let palettes: [(String, any Palette)] = [
            ("terminalPage", terminalPagePalette), ("terminalPair", ReversedRowTerminalPairPalette()),
        ]
        for (name, palette) in palettes {
            try TerminalColors.withCurrent(.unknown) {
                let renders = TransitionRowProbe.frames.indices.map {
                    faded(inRow: list, drawn: $0, phase: phase, palette: palette)
                }
                let page = ColorDepth.withCurrent(.truecolor) { ANSIRenderer.backgroundCode(for: palette.background) }
                for drawn in TransitionRowProbe.frames.indices {
                    let (rows, run) = renders[drawn]
                    let probe = try #require(run, "\(name), list \(list), at \(phase): no run")
                    for shown in TransitionRowProbe.frames.indices {
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
                                \(name), list \(list), at \(phase): frame \(shown) over \(drawn), column \(column): \
                                replayed \(replayed[column].shown), rendered \(rendered[column].shown)
                                """)
                        }
                    }
                }
            }
        }
    }

    /// The probe drawing frame `drawn` in a reversed row, the transition's fade applied
    /// at `phase`, as the run loop writes it — and the probe's run.
    private func faded(
        inRow list: Bool, drawn: Int, phase: Double, palette: any Palette
    ) -> (rows: [String], run: AnimatedCellRun?) {
        let context = makeRenderContext(width: 20, height: 6) { environment, _ in
            environment.palette = palette
        }
        let label = HStack(spacing: 0) { Text("ab"); TransitionRowProbe(drawn: drawn) }
        let view: AnyView =
            list
            ? AnyView(
                List(selection: .constant(Optional(0))) { ForEach(0..<2, id: \.self) { _ in label } }
                    .frame(width: 16, height: 2))
            : AnyView(Button(action: {}, label: { label }).buttonStyle(_MenuItemButtonStyle()))
        let buffer = ColorDepth.withCurrent(.truecolor) { () -> FrameBuffer in
            // Twice, so the row has taken the keyboard.
            _ = renderToScreen(view, context: context)
            return AnyTransition.Effect.opacity.apply(
                to: renderToBuffer(view, context: context), phase: phase, context: context
            ).buffer
        }
        let page = ColorDepth.withCurrent(.truecolor) { ANSIRenderer.backgroundCode(for: palette.background) }
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        let rows = writer.buildOutputLines(
            buffer: buffer, terminalWidth: 20, terminalHeight: buffer.lines.count, bgCode: page,
            reset: ANSIRenderer.reset)
        return (rows, buffer.animatedCells.first { $0.width == 2 && $0.frames.count == TransitionRowProbe.frames.count })
    }
}
