//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarPulseFloorTests.swift
//
//  A focused scrollbar breathes its thumb between the accent and the accent
//  LIFTED away from the page. Both ends have to stay clear of the track's own
//  quiet tone, or the thumb vanishes into its track once per breath — and with
//  it the one thing on the bar that says where you are.
//
//  And neither end may sink BELOW the track, which is a separate claim: a
//  contrast floor is satisfied by a thumb darker than its groove, and a solid
//  block darker than the groove it sits in reads as a hole rather than as a
//  handle. That is what the breath running the other way looked like.
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
                    let lift = ScrollbarColors.pulseLift(palette)
                    let ratio = lift.downsampledToPalette256()
                        .contrastRatio(against: track.downsampledToPalette256())
                    #expect(
                        ratio >= ViewConstants.chromeSeparationFloor,
                        "\(palette.name) at \(depth): the lifted end of the breath is \(String(format: "%.2f", ratio)):1 from its own track")
                }
            }
        }
    }

    /// …and it is still a breath. A floor that lifted the dim end all the way
    /// to the bright one would satisfy the test above and remove the animation.
    @Test("Both ends of the breath are still different colours")
    func theBreathSurvives() {
        for palette in PaletteRegistry.all {
            let lift = ScrollbarColors.pulseLift(palette).downsampledToPalette256()
            let rest = palette.accent.resolve(with: palette).downsampledToPalette256()
            #expect(
                lift.rgbComponents! != rest.rgbComponents!,
                "\(palette.name): the pulse has collapsed to one colour")
        }
    }

    /// The reported fault, as an invariant rather than as one palette's numbers.
    ///
    /// The breath used to run from the accent DOWN toward the page, and on the
    /// green palette its recessive end came out `rgb(11, 27, 11)` — darker than
    /// the track's `rgb(22, 90, 22)` and all but the background's
    /// `rgb(5, 10, 5)`. It passed the separation floor above, because contrast
    /// does not care which side of the groove the thumb is on; the eye does.
    ///
    /// The LIFTED end is what this asserts, that being the end the breath now
    /// travels to. The resting end is the plain accent and always has been, and
    /// on one palette it does fail this: **Man Page** has a pale yellow page
    /// (`rgb(254, 244, 156)`) and a track so close to its accent that
    /// ``ScrollbarColors/separated(_:from:)`` clears the two by pushing the
    /// thumb TOWARD the page — 3.67:1 before, 2.21:1 after, against a track at
    /// 3.56:1. That is the same fault from a different cause (a separation that
    /// picks its direction by contrast alone, with no opinion about which side
    /// of the track it lands on) and it predates the breath being reversed, so
    /// it is left for its own change rather than folded in here.
    @Test("The lifted end of the breath is never quieter than its own track")
    func theLiftNeverSinksBelowItsGroove() {
        for depth in [ColorDepth.truecolor, .palette256] {
            ColorDepth.withCurrent(depth) {
                for palette in PaletteRegistry.all {
                    let page = palette.background.resolve(with: palette)
                        .downsampledToPalette256()
                    let track = palette.foregroundQuaternary.resolve(with: palette)
                    let groove = track.downsampledToPalette256().contrastRatio(against: page)
                    let thumb = ScrollbarColors.pulseLift(palette)
                        .downsampledToPalette256().contrastRatio(against: page)
                    #expect(
                        thumb >= groove,
                        """
                        \(palette.name) at \(depth): the lifted end of the breath stands \
                        \(String(format: "%.2f", thumb)):1 off the page where its own track \
                        stands \(String(format: "%.2f", groove)):1
                        """)
                }
            }
        }
    }
}
