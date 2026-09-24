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
}
