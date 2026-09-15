//  🖥️ TUIkit — Terminal UI Kit for Swift
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
            fillColor: .ansi(.white), backgroundColor: .ansi(.brightBlack), accentColor: .ansi(.cyan),
        palette: SystemPalette.green
        ).text.stripped
    }

    @Test("A multi-character fill repeats cyclically with truncation")
    func cyclicFill() {
        let config = TrackConfiguration(fill: "abc", background: .glyph("-"))
        #expect(render(0.0, width: 5, config: config) == "-----")
        #expect(render(0.2, width: 5, config: config) == "a----")
        #expect(render(0.4, width: 5, config: config) == "ab---")
        #expect(render(0.6, width: 5, config: config) == "abc--")
        #expect(render(0.8, width: 5, config: config) == "abca-")
        #expect(render(1.0, width: 5, config: config) == "abcab")
    }

    @Test("A multi-character background pattern is anchored to the track")
    func anchoredBackground() {
        let config = TrackConfiguration(fill: "█", background: .pattern(".oO"))
        // Cell j always shows the same pattern character regardless of the
        // fill, so the texture stays put while the fill sweeps over it.
        #expect(render(0.0, width: 6, config: config) == ".oO.oO")
        #expect(render(0.5, width: 6, config: config) == "███.oO")
        #expect(render(1.0 / 6.0, width: 6, config: config) == "█oO.oO")
    }

    /// The ramp is drawn INTO the boundary cell, so a two-cell ramp glyph
    /// over a one-cell fill used to make the track one cell longer whenever a
    /// boundary cell was drawn — a bar whose length followed its value. A wide
    /// ramp glyph now coarsens the quantum exactly as a wide fill does.
    @Test("A two-cell ramp glyph over a one-cell fill does not lengthen the track")
    func emojiRampDoesNotLengthen() {
        let config = TrackConfiguration(fill: "█", leadingEdge: ["😀"], background: .glyph("-"))
        let widths = Set(stride(from: 0.0, through: 1.0, by: 0.05).map { fraction in
            render(fraction, width: 10, config: config).strippedLength
        })
        #expect(widths == [10], "the track's width followed its value: \(widths.sorted())")
        // And the ramp still draws: a value between two-cell steps shows it.
        #expect(render(0.25, width: 10, config: config).contains("😀"))
    }

    @Test("A two-cell emoji fill coarsens the resolution and shrinks the track")
    func emojiFillCoarsens() {
        let config = TrackConfiguration(fill: "😀", background: .glyph("-"))
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

    @Test("A CJK fill with a solid background shrinks the same way")
    func cjkFillWithBackground() {
        let config = TrackConfiguration(fill: "漢", background: .solid)
        let empty = render(0.0, width: 7, config: config)
        let full = render(1.0, width: 7, config: config)
        #expect(empty.strippedLength == 6, "7 shrinks to the 2-cell multiple 6")
        #expect(full == "漢漢漢")
        #expect(empty == "      ", "background unfill renders as spaces")
    }

    @Test("The leading edge still applies to single-cell patterns")
    func rampSurvivesPatterns() {
        let config = TrackConfiguration(
            fill: "ab", leadingEdge: ["▌"], background: .glyph("-"))
        // 2 steps per cell over 4 cells: fraction 0.625 = 5 steps = 2 full
        // pattern cells + a half boundary cell.
        #expect(render(0.625, width: 4, config: config) == "ab▌-")
    }

    @Test("The leading edge works with a coarse emoji fill, one block at a time")
    func rampSurvivesCoarseFill() {
        // A 2-cell fill coarsens the track to 2-cell blocks; the ramp then
        // subdivides the BLOCK: the partially-filled block renders as its ramp
        // glyph (by sub-block fraction) repeated across the block. This used
        // to be skipped outright — an emoji fill silently behaved as ramp=None.
        let config = TrackConfiguration(
            fill: "😀", leadingEdge: ["░", "▒", "▓"], background: .glyph("-"))

        // 4 blocks × 4 sub-steps = 16 steps across the 8-cell track.
        #expect(render(0.0, width: 8, config: config) == "--------")
        #expect(render(1.0 / 16.0, width: 8, config: config) == "░░------", "¼ of the first block")
        #expect(render(5.0 / 16.0, width: 8, config: config) == "😀░░----", "1 block + ¼")
        #expect(render(0.5, width: 8, config: config) == "😀😀----", "exactly 2 blocks — no ramp cell")
        #expect(render(15.0 / 16.0, width: 8, config: config) == "😀😀😀▓▓", "3 blocks + ¾")
        #expect(render(1.0, width: 8, config: config) == "😀😀😀😀")

        // The width stays constant at every value, ramp included.
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(
                render(fraction, width: 8, config: config).strippedLength == 8,
                "constant width at \(fraction)")
        }
    }

    @Test("The coarse leading-edge block sits on the background colour under a solid background")
    func coarseLeadingEdgePaintsBackground() {
        // A `.solid` background: the partial block is genuinely part-empty, so
        // it must carry the BACKGROUND colour (like the fine path's boundary
        // cell), not the fill colour.
        let config = TrackConfiguration(
            fill: "😀", leadingEdge: ["▒"], background: .solid)
        let track = TrackRenderer.render(
            fraction: 5.0 / 8.0, width: 8, style: .custom(config),
            fillColor: .ansi(.white), backgroundColor: .ansi(.brightBlack), accentColor: .ansi(.cyan),
            palette: SystemPalette.green).text
        #expect(track.stripped == "😀😀▒▒  ", "2 blocks + ½ block of ramp + empty")
    }

    @Test("Head styles (knob/dot) keep the head visible at every value")
    func headAlwaysVisible() {
        func knob(_ fraction: Double) -> String {
            TrackRenderer.render(
                fraction: fraction, width: 10, style: .knob,
                fillColor: .ansi(.white), backgroundColor: .ansi(.brightBlack), accentColor: .ansi(.cyan),
            palette: SystemPalette.green
            ).text.stripped
        }
        #expect(knob(0.0) == "●─────────", "the knob shows at 0%")
        #expect(knob(0.5) == "━━━━━●────")
        #expect(knob(1.0) == "━━━━━━━━━●")
        for fraction in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(knob(fraction).contains("●"), "knob missing at \(fraction)")
        }
    }
}
