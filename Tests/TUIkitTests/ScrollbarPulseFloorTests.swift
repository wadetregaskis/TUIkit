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

    /// The same invariant for BOTH ends of the breath, and against the
    /// separation that produces them rather than against one end's helper.
    ///
    /// The resting end used to fail this on **Man Page**, from a different
    /// cause than the reversed breath: a pale yellow page
    /// (`rgb(254, 244, 156)`) and a track close enough to the accent that
    /// ``Color/ensuringRenderedContrast(atLeast:against:)`` cleared the two by
    /// taking the NEARER direction, which was toward the page — 3.67:1 before,
    /// 2.21:1 after, against a track at 3.56:1. Contrast does not care which
    /// side of the groove the thumb is on; the eye does.
    /// ``ScrollbarColors/separated(_:from:over:)`` now takes the page as well
    /// and pushes away from it when the nearer answer would be quieter than the
    /// groove.
    @Test("Both ends of the breath stand at least as far off the page as the track")
    func bothEndsStandOffThePage() {
        for depth in [ColorDepth.truecolor, .palette256] {
            ColorDepth.withCurrent(depth) {
                for palette in PaletteRegistry.all {
                    let page = palette.background.resolve(with: palette)
                    let track = palette.foregroundQuaternary.resolve(with: palette)
                    let groove = track.downsampledToPalette256()
                        .contrastRatio(against: page.downsampledToPalette256())
                    let ends: [(String, Color)] = [
                        ("resting", palette.accent.resolve(with: palette)),
                        ("lifted", palette.hoveredForeground(palette.accent)),
                    ]
                    for (name, raw) in ends {
                        let thumb = ScrollbarColors.separated(raw, in: palette)
                        let stands = thumb.downsampledToPalette256()
                            .contrastRatio(against: page.downsampledToPalette256())
                        #expect(
                            stands >= groove,
                            """
                            \(palette.name) at \(depth): the \(name) end stands \
                            \(String(format: "%.2f", stands)):1 off the page where its own \
                            track stands \(String(format: "%.2f", groove)):1
                            """)
                    }
                }
            }
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
    /// The LIFTED end is what this asserts, that being the end the breath
    /// travels to; ``bothEndsStandOffThePage`` covers the resting end, which
    /// used to fail on one palette for a second reason — see there.
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
