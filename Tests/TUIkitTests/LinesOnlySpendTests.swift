//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinesOnlySpendTests.swift
//
//  A breathing row spends its content's fades against every colour of its
//  breath, and keeps only the LINES of all but the colour it draws: a breath's
//  frames are whole lines the row replays in place of its own. So those spends
//  build no runs — no frame of a covered run faded, no repeating fade's runs
//  rebuilt — and the lines they answer are exactly the lines a whole spend
//  gives, the drawn frame's own alpha included.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A breath's colours are spent for their lines alone")
struct LinesOnlySpendTests {

    /// A row's content with every kind of thing a spend builds runs for: a spinner
    /// under a static fade, a label under a repeating fade, and a run whose frames
    /// say their own alpha — whose drawn frame's claim the LINES take either way.
    private func content() -> FrameBuffer {
        var buffer = FrameBuffer(lines: ["ab cd ef"])
        var breathing = OpacityRegion(offsetX: 3, offsetY: 0, width: 2, height: 1, opacity: 0.8)
        breathing.cycle = OpacityCycle(phases: [0.8, 0.4, 0.2], clock: .content)
        buffer.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 0.5), breathing]
        var caret = AnimatedCellRun(offsetX: 6, offsetY: 0, width: 1, frames: ["e", "E"], clock: .cursor)
        caret.alpha = AnimatedRunAlpha(perFrame: [[.init(start: 0, cells: 1, ink: 1, field: 0.3)], []], drawnIndex: 0)
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 1, frames: ["a", "A"], clock: .content), caret,
        ]
        return buffer
    }

    @Test("A spend for the lines alone builds no run and answers the whole spend's lines")
    func aLinesOnlySpendMatchesTheWholeOne() throws {
        let palette = makeRenderContext(width: 12, height: 2).environment.palette
        let buffer = content()
        let fill = Color.rgb(40, 40, 200)
        ColorDepth.withCurrent(.truecolor) {
            let whole = buffer.resolvingOpacity(onOpaqueFill: { nil }, surface: fill, palette: palette)
            let lines = buffer.resolvingOpacity(
                onOpaqueFill: { nil }, surface: fill, palette: palette, buildingRuns: false)
            // Not vacuous: the whole spend built runs — the spinner faded, the breath's own.
            #expect(whole.animatedCells.count >= 3, "the whole spend built \(whole.animatedCells.count) runs")
            #expect(lines.animatedCells.isEmpty, "the lines-only spend built \(lines.animatedCells.count) runs")
            #expect(lines.lines == whole.lines)
            #expect(lines.opacityRegions.isEmpty)
        }
    }

    /// Through a breathing row: every colour of the breath but the drawn one is spent
    /// for its lines, which are the lines a whole spend against that colour gives.
    @Test("A breathing row's other colours are its content's lines, spent")
    func aBreathingRowsOtherColours() throws {
        let palette = makeRenderContext(width: 12, height: 2).environment.palette
        let cycle = SelectionEmphasisCycle(
            frames: (0..<8).map { tick in
                SelectionEmphasis(isFocused: true, animation: .pulse, phase: Double(tick) / 8, blinkOn: true)
            },
            step: 0)
        let (dim, bright) = (Color.rgb(20, 24, 30), Color.rgb(90, 200, 250))
        try ColorDepth.withCurrent(.truecolor) {
            let row = ListRowContent(content(), background: .pulsing(cycle, dim: dim, bright: bright), palette: palette)
            let colours = cycle.colors(dim: dim, bright: bright)
            let drawn = cycle.colorNow(dim: dim, bright: bright)
            let other = try #require(colours.first { $0 != drawn }, "the breath has one colour")
            let painted = content().replacingLines(
                content().lines.map { $0.withPersistentBackground(other) + ANSIRenderer.reset })
            let whole = painted.resolvingOpacity(onOpaqueFill: { nil }, surface: other, palette: palette)
            #expect(row.lines(over: other) == whole.lines)
            #expect(row.lines(over: drawn) == row.drawn.lines)
            // Not vacuous: the drawn colour's spend kept its runs.
            #expect(!row.drawn.animatedCells.isEmpty)
        }
    }
}
