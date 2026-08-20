//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarPulseFloorTests.swift
//
//  A focused scrollbar breathes its thumb between a dim accent and a bright
//  one. The dim end used to fade far enough to meet the track's own quiet tone,
//  so the thumb vanished into its track once per breath — and with it the one
//  thing on the bar that says where you are.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitStyling

@testable import TUIkit

@MainActor
@Suite("Scrollbar pulse floor")
struct ScrollbarPulseFloorTests {

    /// Every shipped palette, at both ends of the breath, on both the terminals
    /// that matter — a sweep, because this is a per-palette collapse and one
    /// example proves nothing about the others.
    @Test("The thumb is tellable from its track at every phase, on every palette")
    func dimEndStaysVisible() {
        for depth in [ColorDepth.truecolor, .palette256] {
            ColorDepth.withCurrent(depth) {
                for palette in PaletteRegistry.all {
                    let track = palette.foregroundQuaternary.resolve(with: palette)
                    let dim = ScrollbarColors.pulseDim(palette)
                    let ratio = dim.downsampledToPalette256()
                        .contrastRatio(against: track.downsampledToPalette256())
                    #expect(
                        ratio >= ViewConstants.chromeSeparationFloor,
                        "\(palette.name) at \(depth): the dim end of the breath is \(String(format: "%.2f", ratio)):1 from its own track")
                }
            }
        }
    }

    /// …and it is still a breath. A floor that lifted the dim end all the way
    /// to the bright one would satisfy the test above and remove the animation.
    @Test("Both ends of the breath are still different colours")
    func theBreathSurvives() {
        for palette in PaletteRegistry.all {
            let dim = ScrollbarColors.pulseDim(palette).downsampledToPalette256()
            let bright = palette.accent.resolve(with: palette).downsampledToPalette256()
            #expect(
                dim.rgbComponents! != bright.rgbComponents!,
                "\(palette.name): the pulse has collapsed to one colour")
        }
    }
}
