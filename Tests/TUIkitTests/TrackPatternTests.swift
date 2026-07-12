//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TrackPatternTests.swift
//
//  Cyclic multi-character fill/unfilled patterns for the configured track
//  renderer (Slider + ProgressView custom styles): patterns repeat with
//  truncation; multi-cell characters (emoji/CJK) coarsen the resolution to
//  their cell width and permanently shrink the track to a neat multiple so
//  its width never varies with the fill ratio; and head-style tracks (dot /
//  knob) keep their head visible at EVERY value including 0%.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Track fill patterns")
struct TrackPatternTests {

    private func render(
        _ fraction: Double, width: Int, config: TrackConfiguration
    ) -> String {
        TrackRenderer.render(
            fraction: fraction, width: width, style: .custom(config),
            filledColor: .white, emptyColor: .brightBlack, accentColor: .cyan
        ).stripped
    }

    @Test("A multi-character fill repeats cyclically with truncation")
    func cyclicFill() {
        let config = TrackConfiguration(fill: "abc", emptyStyle: .glyph("-"))
        #expect(render(0.0, width: 5, config: config) == "-----")
        #expect(render(0.2, width: 5, config: config) == "a----")
        #expect(render(0.4, width: 5, config: config) == "ab---")
        #expect(render(0.6, width: 5, config: config) == "abc--")
        #expect(render(0.8, width: 5, config: config) == "abca-")
        #expect(render(1.0, width: 5, config: config) == "abcab")
    }

    @Test("A multi-character unfilled pattern is anchored to the track")
    func anchoredUnfill() {
        let config = TrackConfiguration(fill: "█", emptyStyle: .pattern(".oO"))
        // Cell j always shows the same pattern character regardless of the
        // fill, so the texture stays put while the fill sweeps over it.
        #expect(render(0.0, width: 6, config: config) == ".oO.oO")
        #expect(render(0.5, width: 6, config: config) == "███.oO")
        #expect(render(1.0 / 6.0, width: 6, config: config) == "█oO.oO")
    }

    @Test("A two-cell emoji fill coarsens the resolution and shrinks the track")
    func emojiFillCoarsens() {
        let config = TrackConfiguration(fill: "😀", emptyStyle: .glyph("-"))
        // Width 5 permanently becomes 4 (two 2-cell steps) at EVERY value —
        // the track must not change width with its fill ratio.
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            #expect(
                render(fraction, width: 5, config: config).strippedLength == 4,
                "constant width at \(fraction)")
        }
        #expect(render(0.0, width: 5, config: config) == "----")
        #expect(render(0.5, width: 5, config: config) == "😀--")
        #expect(render(1.0, width: 5, config: config) == "😀😀")
    }

    @Test("A CJK fill with a solid-background unfill shrinks the same way")
    func cjkFillWithBackground() {
        let config = TrackConfiguration(fill: "漢", emptyStyle: .background)
        let empty = render(0.0, width: 7, config: config)
        let full = render(1.0, width: 7, config: config)
        #expect(empty.strippedLength == 6, "7 shrinks to the 2-cell multiple 6")
        #expect(full == "漢漢漢")
        #expect(empty == "      ", "background unfill renders as spaces")
    }

    @Test("The sub-cell ramp still applies to single-cell patterns")
    func rampSurvivesPatterns() {
        let config = TrackConfiguration(
            fill: "ab", partialRamp: ["▌"], emptyStyle: .glyph("-"))
        // 2 steps per cell over 4 cells: fraction 0.625 = 5 steps = 2 full
        // pattern cells + a half boundary cell.
        #expect(render(0.625, width: 4, config: config) == "ab▌-")
    }

    @Test("Head styles (knob/dot) keep the head visible at every value")
    func headAlwaysVisible() {
        func knob(_ fraction: Double) -> String {
            TrackRenderer.render(
                fraction: fraction, width: 10, style: .knob,
                filledColor: .white, emptyColor: .brightBlack, accentColor: .cyan
            ).stripped
        }
        #expect(knob(0.0) == "●─────────", "the knob shows at 0%")
        #expect(knob(0.5) == "━━━━━●────")
        #expect(knob(1.0) == "━━━━━━━━━●")
        for fraction in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(knob(fraction).contains("●"), "knob missing at \(fraction)")
        }
    }
}
