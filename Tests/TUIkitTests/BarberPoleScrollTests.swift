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

    /// `style`'s cycle across `width` cells, in truecolor.
    private func cycle(
        _ style: IndeterminateStyle, width: Int, speed: IndicatorAnimationSpeed = .standard
    ) -> (frames: [String], frameTicks: Int) {
        ColorDepth.withCurrent(.truecolor) {
            IndeterminateRenderer.cycle(
                width: width, style: style, fillColor: .rgb(150, 150, 150),
                backgroundColor: .rgb(80, 80, 80), accentColor: .rgb(0, 200, 255),
                palette: SystemPalette.green, speed: speed)
        }
    }

    /// The frame `cycle` shows `tick` 1/60 s ticks into its pass.
    private func shown(_ cycle: (frames: [String], frameTicks: Int), atTick tick: Int) -> String {
        cycle.frames[(tick / cycle.frameTicks) % cycle.frames.count]
    }

    /// A pass of the preset is `◢◤` shifted by each of its two characters: 0.6 s, 36
    /// ticks, the first 18 showing one picture and the next 18 that picture moved one
    /// cell. The pattern used to be shifted twice the bar's width a pass, sampled at
    /// 18 frames and taken modulo 2, which aliased with the width: at 36 cells every
    /// frame but the twelfth was the same picture, so the bar stood still and
    /// glitched once a pass, and at 20 and 200 cells it held for five frames and
    /// then four.
    @Test("The preset's pass is its pattern, then that pattern one cell along, for 18 ticks each", arguments: [20, 36, 200])
    func presetShiftsOneCellEachHalfPass(width: Int) throws {
        let cycle = cycle(.barberPole, width: width)
        #expect(cycle.frames.count * cycle.frameTicks == 36, "the 0.6 s pass")
        let first = Set((0..<18).map { shown(cycle, atTick: $0) })
        let second = Set((18..<36).map { shown(cycle, atTick: $0) })
        #expect(first.count == 1, "ticks 0-17 showed \(first.count) pictures")
        #expect(second.count == 1, "ticks 18-35 showed \(second.count) pictures")
        let before = Array(shown(cycle, atTick: 0).stripped)
        let after = Array(shown(cycle, atTick: 18).stripped)
        try #require(before.count == width && after.count == width)
        let moved = (0..<(width - 1)).allSatisfy { after[$0] == before[$0 + 1] }
        #expect(moved, "not a one-cell shift: \(String(before)) then \(String(after))")
        #expect(shown(cycle, atTick: 0) != shown(cycle, atTick: 18))
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
                    width: width, style: .barberPole, fillColor: .rgb(150, 150, 150),
                    backgroundColor: .rgb(80, 80, 80), accentColor: .rgb(0, 200, 255),
                    elapsed: (Double(tick) + 0.5) / 60, palette: SystemPalette.green
                ).text
            }
            return drawn != shown(cycle, atTick: tick)
        }
        #expect(differing.isEmpty, "\(width) cells: ticks \(differing)")
    }
}
