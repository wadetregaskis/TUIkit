//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollbarPulseSeparationTests.swift
//
//  A focused scrollbar's thumb stays readable against its track at EVERY point
//  of the breath, not only at the two ends of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("A pulsing scrollbar thumb never merges with its track")
struct ScrollbarPulseSeparationTests {

    /// Every palette the app ships, because this is a property of the pair of
    /// colours and only some palettes bring them close enough to collide.
    private var palettes: [any Palette] {
        [
            SystemPalette.green, SystemPalette.amber, SystemPalette.red,
            SystemPalette.violet, SystemPalette.blue, SystemPalette.white,
        ]
    }

    /// The reported case: the thumb disappears into its track once per breath,
    /// taking the scroll position with it.
    ///
    /// Flooring the recessive END was not enough. The points between the ends
    /// are interpolated in RGB and then quantised, and a quiet accent and a
    /// quiet grey collapse onto one 256-entry somewhere in the middle of a span
    /// whose ends are both clear of each other.
    @Test("Every frame of the cycle is legible against the track")
    func everyFrameIsSeparated() {
        var offenders: [String] = []
        for palette in palettes {
            let track = palette.foregroundQuaternary.resolve(with: palette)
            var environment = EnvironmentValues()
            environment.palette = palette
            let cycle = SelectionEmphasisClock(environment: environment).cycle(true)
            let frames = cycle.colors(
                dim: ScrollbarColors.pulseDim(palette), bright: palette.accent
            ).map { ScrollbarColors.separated($0, from: track) }
            #expect(!frames.isEmpty, "the cycle has frames to check")
            for (index, thumb) in frames.enumerated() {
                let ratio = thumb.downsampledToPalette256()
                    .contrastRatio(against: track.downsampledToPalette256())
                if ratio < ViewConstants.chromeSeparationFloor {
                    offenders.append(
                        "\(palette.name) frame \(index): \(String(format: "%.2f", ratio))")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
