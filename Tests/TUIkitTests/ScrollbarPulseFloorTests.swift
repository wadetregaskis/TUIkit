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
    ///
    /// Measured on the colours actually DRAWN — both ends through
    /// ``ScrollbarColors/separated(_:in:standingOffThePage:)`` and through the
    /// 256-colour cube — rather than on the raw pair. The raw pair differed on
    /// every palette while three of them drew a bar that did not move, which is
    /// the same lesson the Man Page contrast case taught: a colour the renderer
    /// is going to change is not the colour to assert about.
    ///
    /// **Two palettes have no room, and cannot be given any here.** Ocean and
    /// Grass derive an accent that lands on the same cube entry as their own
    /// scrollbar track, so clearing the track pins the thumb against an extreme
    /// — and the walk that clears it is hue-preserving, so the only colours far
    /// enough from the track on the OTHER side are past the track itself, which
    /// the breath may not cross (that is "the scroller goes momentarily
    /// invisible"). Their bars are still, and the fix would be to the palette
    /// derivation rather than to the bar.
    @Test("Both ends of the breath are still different colours")
    func theBreathSurvives() {
        let noRoom: Set<String> = ["Ocean", "Grass"]
        ColorDepth.withCurrent(.palette256) {
            for palette in PaletteRegistry.all {
                let resting = ScrollbarColors.separated(
                    palette.accent.resolve(with: palette), in: palette)
                let lift = ScrollbarColors.separated(
                    ScrollbarColors.pulseLift(palette), in: palette, standingOffThePage: false)
                let ratio = lift.downsampledToPalette256()
                    .contrastRatio(against: resting.downsampledToPalette256())
                if noRoom.contains(palette.name) { continue }
                #expect(
                    ratio >= ViewConstants.chromePulseFloor,
                    """
                    \(palette.name): the two ends of the breath stand \
                    \(String(format: "%.2f", ratio)):1 apart, which is not a breath
                    """)
            }
        }
    }

    /// The RESTING thumb is never quieter against the page than its own track.
    ///
    /// The resting end is the one this is about: a thumb that sits quieter than
    /// the groove it is in reads as a hole in the bar, which is what the
    /// breath's direction was reversed to fix and what Man Page's own track
    /// separation reintroduced from the other side (a pale yellow page, a track
    /// 3.56:1 off it, an accent 1.03:1 off the track — the thumb came back at
    /// 2.21:1).
    ///
    /// The FAR end of the breath is deliberately exempt, and
    /// ``ScrollbarColors/separated(_:in:standingOffThePage:)`` says so: on the
    /// palettes with no room to lift, the only way to have a breath at all is a
    /// small dip, and the smallest visible step cannot read as a hole. What it
    /// may never do is merge with the track, and `everyFrameIsSeparated` next
    /// door asserts that for every frame of the cycle.
    @Test("The resting thumb is never quieter than its own groove")
    func theRestingThumbStandsOffThePage() {
        for depth in [ColorDepth.truecolor, .palette256] {
            ColorDepth.withCurrent(depth) {
                for palette in PaletteRegistry.all {
                    let page = palette.background.resolve(with: palette)
                    let track = palette.foregroundQuaternary.resolve(with: palette)
                    let groove = track.downsampledToPalette256()
                        .contrastRatio(against: page.downsampledToPalette256())
                    let thumb = ScrollbarColors.separated(
                        palette.accent.resolve(with: palette), in: palette)
                    let stands = thumb.downsampledToPalette256()
                        .contrastRatio(against: page.downsampledToPalette256())
                    #expect(
                        stands >= groove,
                        """
                        \(palette.name) at \(depth): the resting thumb stands \
                        \(String(format: "%.2f", stands)):1 off the page where its own track \
                        stands \(String(format: "%.2f", groove)):1
                        """)
                }
            }
        }
    }
}
