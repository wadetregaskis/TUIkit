//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RepeatingFadeRunWidthTests.swift
//
//  A repeating `.opacity` fade replays as runs over the columns its fades cover
//  (`OpacityResolution.cyclingRuns`), so what else animates on the same row
//  keeps animating: a spinner beside the fade, or a fade a painter has already
//  spent into a run of its own. One run over the whole row replaced every cell
//  on it at every tick, and put everything beside the fade back at the frame
//  it was drawn with. Every tick is replayed against a render at the same
//  instant (`ReplayOracle`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A spinner beside a label that breathes, on one row.
private struct SpinnerBesideAFade: View {
    @State private var dim = false

    var body: some View {
        HStack(spacing: 0) {
            Spinner()
            Text(" B ").opacity(dim ? 0.2 : 1)
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 0.4).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

private struct SpinnerBesideAFadeApp: App {
    init() {}
    var body: some Scene { WindowGroup { SpinnerBesideAFade().palette(SystemPalette(.green)) } }
}

/// A label breathing inside a `.listRowBackground` — which spends its content's
/// fades against its fill, so the breath reaches the root as a run of its own —
/// inside a breath of its own.
private struct FadeInsideARowFillInsideAFade: View {
    @State private var dim = false

    var body: some View {
        HStack(spacing: 0) {
            Text(" A ").opacity(dim ? 0.2 : 1).listRowBackground(Color.rgb(40, 40, 200))
                .frame(width: 5)
                .opacity(dim ? 0.3 : 1)
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 0.4).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

private struct FadeInsideARowFillInsideAFadeApp: App {
    init() {}
    var body: some Scene { WindowGroup { FadeInsideARowFillInsideAFade().palette(SystemPalette(.green)) } }
}

/// A label breathing inside a `.background`, which spends its content's fades
/// against its fill (§96) and so leaves a run of its own, beside another label
/// breathing at the root — or, nested, inside a breath of its own.
private struct TwoBreaths: View {
    let nested: Bool
    @State private var dim = false

    var body: some View {
        Group {
            if nested {
                HStack(spacing: 0) {
                    Text(" A ").opacity(dim ? 0.2 : 1).background(Color.rgb(40, 40, 200)).opacity(dim ? 0.2 : 1)
                    Spacer()
                }
            } else {
                HStack(spacing: 0) {
                    Text(" A ").opacity(dim ? 0.2 : 1).background(Color.rgb(40, 40, 200))
                    Text(" B ").opacity(dim ? 0.2 : 1)
                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.4).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

private struct TwoBreathsApp: App {
    let nested: Bool
    init() { nested = false }
    init(nested: Bool) { self.nested = nested }
    var body: some Scene { WindowGroup { TwoBreaths(nested: nested).palette(SystemPalette(.green)) } }
}

@MainActor
@Suite("A repeating fade's run is as wide as its fades")
struct RepeatingFadeRunWidthTests {

    /// Before, every tick drew the spinner's first cell at the glyph it was
    /// rendered with, where a render at the same instant draws the next.
    @Test("A spinner beside a repeating fade keeps turning between renders")
    func aSpinnerBesideAFadeTurns() throws {
        let found = ReplayOracle.compare({ SpinnerBesideAFadeApp() }, ticks: 24, size: (30, 4))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        #expect(found.movedGlyphs > 0, "no replay moved the spinner")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// A breath spent at a `.background`, beside one resolved at the root and inside
    /// one. Whole-row, the root's run put the `.background`'s back at the phase it
    /// was drawn at on every tick; and nested, the inner run was dropped under the
    /// outer fade. Before, both held `A` still between renders.
    @Test("A breath a background spent keeps breathing beside and inside another", arguments: [false, true])
    func aBreathABackgroundSpentBreathes(nested: Bool) throws {
        let found = ReplayOracle.compare({ TwoBreathsApp(nested: nested) }, ticks: 24, size: (30, 4))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// The row fill's run is under the list's own repeating fade: folded into the
    /// list's run, both breaths go on. Before, the row fill's run was dropped under
    /// the outer fade and the label held the phase of its own breath it was drawn
    /// at, while a render moved it.
    @Test("A fade a row fill spent into a run keeps breathing inside another repeating fade")
    func aFadeInsideARowFillInsideAFadeBreathes() throws {
        let found = ReplayOracle.compare({ FadeInsideARowFillInsideAFadeApp() }, ticks: 24, size: (30, 4))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    private func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    /// A run that steps with the fade — on its clock, at the standard frame a cycle
    /// steps at — IS representable with it: one run, in the space both divide into,
    /// with the run's frame spliced in before each phase is blended. That is what a
    /// fade a painter has already spent into a run of its own is, under an outer
    /// repeating fade; dropped, as every run under a repeating fade was, it froze
    /// at the phase it was drawn at while the outer fade went on moving.
    @Test("A run that steps with a repeating fade over it is folded into the fade's run")
    func aRunSteppingWithTheFadeIsFoldedIn() throws {
        var buffer = FrameBuffer(lines: ["aaaaa"])
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 5, frames: ["aaaaa", "bbbbb"], clock: .cursor)
        ]
        var region = OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.9)
        region.cycle = OpacityCycle(phases: [0.9, 0.9, 0.1], clock: .cursor)
        buffer.opacityRegions = [region]
        // Over a destination that paints its own glyphs, so each step is legible in
        // `stripped`: the source's character at or above one half, the destination's
        // below it.
        let resolved = buffer.resolvingOpacity(
            over: FrameBuffer(lines: ["xxxxx"]), at: (x: 0, y: 0), surface: .black, palette: palette())
        #expect(resolved.animatedCells.count == 1, "one run, holding both")
        let run = try #require(resolved.animatedCells.first)
        // Two frames and three phases share six steps.
        #expect(
            run.frames.map(\.stripped) == ["aaaaa", "bbbbb", "xxxxx", "bbbbb", "aaaaa", "xxxxx"],
            "\(run.frames.map(\.stripped))")
    }

    /// A folded run's frames go into the row BEFORE the writer builds it, over the
    /// fields its painters left under each cell as such a row reads them: a
    /// `.background(Color.default)`'s stated 49 is the terminal's own there. Read on a
    /// page, as the tick reads a row already on screen, a stated 49 and a reset were
    /// one field, and the frame's bare cells went back to none — the page, once the row
    /// is built — so the fade's frame at the step the render drew was not the row it
    /// drew, and every tick replayed it.
    @Test("A folded run is spliced into its row over the fields its painters left there")
    func aFoldedRunKeepsItsPaintersFields() throws {
        func painted(_ cells: String) -> String { "\u{1B}[49m" + cells + "\u{1B}[0m" }
        try TerminalColors.withCurrent(.unknown) {
            try ColorDepth.withCurrent(.truecolor) {
                var buffer = FrameBuffer(lines: [painted("⠋ ")])
                buffer.animatedCells = [
                    AnimatedCellRun(offsetX: 0, offsetY: 0, width: 2, frames: ["⠋ ", "⠙ "], clock: .content)
                        .paintingGround { painted($0) }
                ]
                var breath = OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 0.9)
                breath.cycle = OpacityCycle(phases: [0.9, 0.7], clock: .content)
                buffer.opacityRegions = [breath]
                let resolved = buffer.resolvingOpacity(surface: .rgb(5, 10, 5), palette: palette())
                let run = try #require(resolved.animatedCells.first, "the fade left no run")
                #expect(run.frames.count == 2, "the spinner was not folded in: \(run.frames.count) frames")
                let replayed = FrameBuffer.patchingAnimatedCells(in: resolved.lines[0], replaying: run, atIndex: 0)
                #expect(
                    paintedCells(replayed).map(\.state) == paintedCells(resolved.lines[0]).map(\.state),
                    "replayed \(replayed.debugDescription), drawn \(resolved.lines[0].debugDescription)")
            }
        }
    }

    /// Two cycling fades BESIDE each other on one row are a run each, over its own
    /// columns: each animates on its own, and a run beside either on the row —
    /// the other fade's, a spinner's — is left to animate too. One run over the
    /// whole row replaced every cell on it at every tick, and a run beside the
    /// fades froze at the frame it was drawn with (`Opacity as composition.md`
    /// §6b.1).
    @Test("Two cycling fades beside each other on one row are a run each, over its own columns")
    func twoCyclingFadesBesideEachOther() throws {
        var buffer = FrameBuffer(lines: ["AB-"])
        var left = OpacityRegion(offsetX: 0, offsetY: 0, width: 1, height: 1, opacity: 0.9)
        left.cycle = OpacityCycle(phases: [0.9, 0.1], clock: .content)
        var right = OpacityRegion(offsetX: 1, offsetY: 0, width: 1, height: 1, opacity: 0.9)
        right.cycle = OpacityCycle(phases: [0.9, 0.9, 0.1], clock: .content)
        buffer.opacityRegions = [left, right]
        buffer.animatedCells = [AnimatedCellRun(offsetX: 2, offsetY: 0, width: 1, frames: ["-", "+"], frameTicks: 7, clock: .content)]

        let resolved = buffer.resolvingOpacity(
            over: FrameBuffer(lines: ["xyz"]), at: (x: 0, y: 0), surface: .black,
            palette: palette())

        let fades = resolved.animatedCells.filter { $0.frameTicks == AnimationClock.standardFrameTicks }
        #expect(fades.map { $0.offsetX..<($0.offsetX + $0.width) } == [0..<1, 1..<2], "\(fades)")
        #expect(fades.map { $0.frames.map(\.stripped) } == [["A", "x"], ["B", "B", "y"]])
        #expect(resolved.animatedCells.contains { $0.offsetX == 2 && $0.frames.count == 2 }, "the run beside them went")
        // And each frame for the tick the render drew shows what the line drew.
        for run in fades {
            let replayed = FrameBuffer.patchingAnimatedCells(in: resolved.lines[0], replaying: run, atIndex: 0)
            #expect(paintedCells(replayed).map(\.state) == paintedCells(resolved.lines[0]).map(\.state))
            #expect(replayed.stripped == resolved.lines[0].stripped)
        }
    }
}
