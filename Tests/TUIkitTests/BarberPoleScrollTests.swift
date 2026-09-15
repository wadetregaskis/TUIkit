//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BarberPoleScrollTests.swift
//
//  The indeterminate bar's barberPole motion: a stripe pattern that scrolls one
//  cell a step, whichever path draws it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@Suite("barberPole scrolls its stripes")
struct BarberPoleScrollTests {

    private let filled = Color.rgb(150, 150, 150)
    private let accent = Color.rgb(0, 200, 255)

    /// `style`'s cycle across `width` cells, in truecolor.
    private func cycle(
        _ style: IndeterminateStyle, width: Int, speed: IndicatorAnimationSpeed = .standard
    ) -> (frames: [String], frameTicks: Int) {
        ColorDepth.withCurrent(.truecolor) {
            IndeterminateRenderer.cycle(
                width: width, style: style, fillColor: filled,
                backgroundColor: .rgb(80, 80, 80), accentColor: accent,
                palette: SystemPalette.green, speed: speed)
        }
    }

    /// The frame `cycle` shows `tick` 1/60 s ticks into its pass.
    private func shown(_ cycle: (frames: [String], frameTicks: Int), atTick tick: Int) -> String {
        cycle.frames[(tick / cycle.frameTicks) % cycle.frames.count]
    }

    /// One drawn cell: its glyph, and every escape it is drawn under since the last
    /// reset, so two cells compare equal only when they look alike.
    private struct Cell: Equatable {
        let glyph: Character
        let escapes: String
    }

    /// `row`'s cells, left to right.
    private func cells(_ row: String) -> [Cell] {
        var result: [Cell] = []
        var escapes = ""
        var escape: String?
        for character in row {
            if var partial = escape {
                partial.append(character)
                guard character.isLetter else {
                    escape = partial
                    continue
                }
                escapes = partial == "\u{1B}[0m" ? "" : escapes + partial
                escape = nil
            } else if character == "\u{1B}" {
                escape = "\u{1B}"
            } else {
                result.append(Cell(glyph: character, escapes: escapes))
            }
        }
        return result
    }

    /// The escapes a cell in `colour` is drawn under, spelled as the renderer spells it.
    private func escapes(of colour: Color) -> String {
        ColorDepth.withCurrent(.truecolor) {
            cells(ANSIRenderer.colorize("x", foreground: colour)).first?.escapes ?? ""
        }
    }

    /// A pass of the preset is four steps of 9 ticks, 0.6 s, each the last moved one
    /// cell left, colours and all. Its stripes are one `◢◤` wide, so the pattern
    /// repeats every four cells and a one-cell shift has a direction. The colours
    /// used to go one per glyph, a pattern that repeats every two cells: a one-cell
    /// shift of it only swaps which colour is where, so the pass was two frames of 18
    /// ticks, alternating.
    @Test("The preset's pass is four one-cell shifts to the left, 9 ticks each", arguments: [20, 36, 200])
    func presetShiftsOneCellLeftEachStep(width: Int) throws {
        let cycle = cycle(.barberPole, width: width)
        #expect(cycle.frames.count * cycle.frameTicks == 36, "the 0.6 s pass")
        let held = (0..<4).map { step in Set((9 * step..<9 * step + 9).map { shown(cycle, atTick: $0) }).count }
        #expect(held == [1, 1, 1, 1], "pictures shown in each 9-tick step: \(held)")
        #expect(Set((0..<4).map { shown(cycle, atTick: 9 * $0) }).count == 4, "four different pictures")
        for step in 0..<4 {
            let before = cells(shown(cycle, atTick: 9 * step))
            let after = cells(shown(cycle, atTick: 9 * (step + 1)))
            try #require(before.count == width && after.count == width)
            let moved = (0..<(width - 1)).allSatisfy { after[$0] == before[$0 + 1] }
            #expect(moved, "\(width) cells: step \(step) to \(step + 1) is not a one-cell shift left")
        }
    }

    /// A stripe is one repetition of the fill: the preset's first frame is `◢◤` in the
    /// accent, then `◢◤` in the filled colour. It was `◢` in the accent and `◤` in the
    /// filled colour.
    @Test("The preset's first frame paints cells 0-1 in the accent and cells 2-3 in the filled colour")
    func presetStripesAreOnePatternWide() throws {
        let row = cells(shown(cycle(.barberPole, width: 36), atTick: 0))
        try #require(row.count == 36)
        #expect(String(row.prefix(4).map(\.glyph)) == "◢◤◢◤")
        let accent = escapes(of: accent)
        let filled = escapes(of: filled)
        #expect(accent != filled)
        #expect(row.prefix(4).map(\.escapes) == [accent, accent, filled, filled])
    }

    /// Every stripe colour a configuration names is painted, a stripe of each in turn.
    /// Colours used to go one per glyph of the fill, so a two-character fill painted
    /// the first two of three and never the third.
    @Test("A barberPole of three stripe colours paints each over one repetition of its fill")
    func everyStripeColourIsPainted() throws {
        let red = Color.rgb(255, 0, 0)
        let green = Color.rgb(0, 255, 0)
        let blue = Color.rgb(0, 0, 255)
        let style = IndeterminateStyle.custom(
            IndeterminateConfiguration(
                motion: .barberPole, fill: "◢◤", gradient: Gradient(colors: [red, green, blue]), period: 0.6))
        let cycle = cycle(style, width: 20)
        #expect(cycle.frames.count == 6, "two characters times three colours")
        #expect(cycle.frameTicks == 6)
        let row = cells(shown(cycle, atTick: 0))
        try #require(row.count == 20)
        let (r, g, b) = (escapes(of: red), escapes(of: green), escapes(of: blue))
        #expect(row.prefix(6).map(\.escapes) == [r, r, g, g, b, b])
    }

    /// A barberPole whose stripe colours repeat is its first row again once its stripes
    /// have moved one repeat: red, blue, red, blue under "◢◤" is eight states, and the
    /// fifth draws what the first does. Its cycle is those four.
    @Test("A barberPole whose stripe colours repeat holds one repeat of its pass")
    func repeatingStripesHoldOneRepeat() {
        let red = Color.rgb(255, 0, 0)
        let blue = Color.rgb(0, 0, 255)
        let style = IndeterminateStyle.custom(
            IndeterminateConfiguration(
                motion: .barberPole, fill: "◢◤", gradient: Gradient(colors: [red, blue, red, blue]), period: 0.6))
        let cycle = cycle(style, width: 20)
        #expect(cycle.frames.count == 4)
        #expect(Set(cycle.frames).count == 4)
    }

    /// A bar no run can carry draws one frame per render at an elapsed time, and must
    /// draw what the run would show then. Read mid-tick, so a time that lands on a
    /// step's first instant cannot read the step before.
    @Test("A barberPole drawn at a time shows what its cycle shows at that tick", arguments: [20, 36, 200])
    func elapsedPathAgreesWithTheCycle(width: Int) {
        let cycle = cycle(.barberPole, width: width)
        let differing = (0..<72).filter { tick in
            let drawn = ColorDepth.withCurrent(.truecolor) {
                IndeterminateRenderer.render(
                    width: width, style: .barberPole, fillColor: filled,
                    backgroundColor: .rgb(80, 80, 80), accentColor: accent,
                    elapsed: (Double(tick) + 0.5) / 60, palette: SystemPalette.green
                ).text
            }
            return drawn != shown(cycle, atTick: tick)
        }
        #expect(differing.isEmpty, "\(width) cells: ticks \(differing)")
    }

    /// A barberPole's pass is a sequence, one frame per state, each held the same whole
    /// number of ticks. A fill of four characters in the control's two colours over a
    /// 0.5 s pass is eight states of 3.75 ticks, which rounds to 4: eight frames of 4
    /// ticks, a 0.5333 s pass. Laid out like a ramp it would be 15 frames of 2 ticks,
    /// and ⌊i·8/15⌋ holds its last state for one frame of them where the rest have two.
    @Test("A barberPole of four characters over 0.5 s is eight frames of 4 ticks, one per state")
    func customPassIsASequenceOfEqualFrames() {
        let style = IndeterminateStyle.custom(
            IndeterminateConfiguration(motion: .barberPole, fill: "abcd", period: 0.5))
        let cycle = cycle(style, width: 20)
        #expect(cycle.frames.count == 8)
        #expect(cycle.frameTicks == 4)
        var holds: [Int] = []
        var previous: String?
        for tick in 0..<(cycle.frames.count * cycle.frameTicks) {
            let frame = shown(cycle, atTick: tick)
            if frame == previous { holds[holds.count - 1] += 1 } else { holds.append(1) }
            previous = frame
        }
        #expect(holds == Array(repeating: 4, count: 8), "each state was held for \(holds) ticks")
    }

    /// The preset is four frames of 9 ticks: 150 ms a cell, 6.7 cells a second.
    @Test("The preset barberPole is four frames of 9 ticks")
    func presetIsFourFramesOf9Ticks() {
        let cycle = cycle(.barberPole, width: 36)
        #expect(cycle.frames.count == 4)
        #expect(cycle.frameTicks == 9)
    }
}
