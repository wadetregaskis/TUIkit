//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayOracleScheduleTests.swift
//
//  The replay oracle (`ReplayOracle`) is only as good as its model of the run
//  loop, and the loop does not only replay: it renders whenever a firing a frame
//  asked for falls due — a lattice, or a one-shot wake. A view can hand an
//  animation to a wake instead of leaving it in a run, and a focused `List`'s
//  cursor row does: it breathes, repaints its whole line on every tick, so it
//  drops its row's own runs and asks for a render at their next step. An oracle
//  that only replayed held the glyph that row was drawn with, and reported the
//  app wrong where the app is right.
//
//  And it is only as good as the rows it looks at. A row whose run was dropped —
//  a spinner under a fade that cannot fold it in — holds the glyph it was drawn
//  with while a render at the same instant moves it on, and nothing replays there:
//  the oracle compared only the rows a run sits on, and skipped a stop with no run
//  at all, so such a row froze unseen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A focused list with no selection, a spinner in every row: its cursor row
/// breathes, and drops that row's spinner run for as long as it does.
private struct BreathingListApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            List(selection: .constant(Int?.none)) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) { Text("row \(row) "); Spinner(style: .dots) }
                }
            }
            .frame(width: 20, height: 3)
        }
    }
}

/// A row that moves on with the clock and leaves nothing to move it: no run, no
/// wake — what a run the resolution dropped leaves behind. Its digit is the step
/// of the standard frame the render landed in.
private struct FrozenRow: View, Renderable {
    var body: Never { fatalError("FrozenRow renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let step = context.environment.frameNowNanos / AnimationClock.nanoseconds(
            AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks))
        return FrameBuffer(text: "step \(step % 10)")
    }
}

/// A row whose COLOUR moves on with the clock, its glyphs still, and nothing to move
/// it: a fade that froze over a row's fill.
private struct FrozenColourRow: View, Renderable {
    var body: Never { fatalError("FrozenColourRow renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let step = context.environment.frameNowNanos / AnimationClock.nanoseconds(
            AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks))
        return FrameBuffer(text: ANSIRenderer.colorize("step", background: .rgb(UInt8(step % 10) * 20, 0, 0)))
    }
}

/// The frozen row — its glyph moving, or only its colour — beside a spinner or alone.
private struct FrozenRowApp: App {
    let besideASpinner: Bool
    let colourOnly: Bool
    init() { (besideASpinner, colourOnly) = (true, false) }
    init(besideASpinner: Bool, colourOnly: Bool = false) { (self.besideASpinner, self.colourOnly) = (besideASpinner, colourOnly) }
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                if colourOnly { FrozenColourRow() } else { FrozenRow() }
                if besideASpinner { Spinner() }
            }
        }
    }
}

@MainActor
@Suite("The replay oracle renders where the run loop would")
struct ReplayOracleScheduleTests {

    /// Beside a row with a run, and on a screen with none: either way the row moved
    /// between two renders, and the oracle has to say so. Before, it compared only
    /// the spinner's row in the first case and skipped the stop in the second, and
    /// reported nothing.
    /// And a row whose colour alone moved: before, only rows whose glyphs moved were
    /// compared, and a fade frozen over a row's fill, moving no glyph, went unseen.
    @Test(
        "A row a render moves with no run on it is compared, and its freeze reported",
        arguments: [true, false], [false, true])
    func aRowThatFrozeIsSeen(besideASpinner: Bool, colourOnly: Bool) {
        let found = ReplayOracle.compare(
            { FrozenRowApp(besideASpinner: besideASpinner, colourOnly: colourOnly) }, ticks: 24, size: (20, 4),
            reportOncePerRow: true)
        #expect(
            found.mismatches.contains { $0.contains("row 0") },
            "the frozen row was never compared: \(found.mismatches)")
    }

    @Test("A wake a breathing List row asks for is rendered, so its spinner moves on")
    func aWakeFallingDueIsRendered() {
        let found = ReplayOracle.compare({ BreathingListApp() }, focusSteps: 0, ticks: 24, size: (40, 8))
        #expect(found.compared > 0, "nothing was replayed")
        // Not vacuous: the list asked for renders, and the walk made them.
        #expect(found.scheduledRenders > 0, "no wake the list asked for fell due in the walk")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }
}
