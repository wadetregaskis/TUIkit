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
                    let track = ScrollbarColors.track(in: palette)
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

    /// Two palettes alike in groove, accent and page but not in ink must not
    /// share a memoised groove: the ink is the second direction the search
    /// walks, and the answer for a palette whose ink offers no acceptable rung
    /// is the FALLBACK — served, before the key named the ink, to a palette
    /// whose ink would have found one.
    @Test("The track memo keys on the ink as well")
    func trackMemoKeysOnInk() {
        struct InkPalette: Palette {
            let id = "ink"
            let name = "Ink"
            // A groove that fails the accent floor, with a page too close to
            // walk toward: only the ink-ward search can answer, so the ink is
            // the whole difference between these two palettes.
            let background = Color.rgb(55, 55, 55)
            let foregroundQuaternary = Color.rgb(70, 70, 70)
            let accent = Color.rgb(90, 90, 90)
            let foreground: Color
            let success = Color.green
            let warning = Color.yellow
            let error = Color.red
            let info = Color.blue
            let border = Color.gray
        }
        func cold(_ palette: InkPalette) -> Color {
            ChromeTrack.resolvedTrack(
                base: palette.foregroundQuaternary.resolve(with: palette),
                accent: palette.accent.resolve(with: palette),
                page: palette.background.resolve(with: palette),
                ink: palette.foreground.resolve(with: palette))
        }
        let pale = InkPalette(foreground: .rgb(250, 250, 250))
        let dim = InkPalette(foreground: .rgb(100, 100, 100))
        #expect(cold(pale) != cold(dim), "fixture: the ink must decide the answer")
        _ = ScrollbarColors.track(in: pale)
        #expect(ScrollbarColors.track(in: dim) == cold(dim), "the dim palette got the pale one's memo")
        #expect(ScrollbarColors.track(in: pale) == cold(pale))
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
    /// **One palette has no room.** Grass's page is a teal, its foreground a
    /// pale yellow and its accent an amber sitting between them: the groove has
    /// to travel almost to the foreground to clear the accent (4.36:1 off the
    /// page, where most sit near 2), and the thumb must then stand at least
    /// that far off the page as well, which leaves it pinned with nothing
    /// either side. Ocean was the reported one and is fixed — its groove used
    /// to land on the same cube entry as its own thumb.
    @Test("Both ends of the breath are still different colours")
    func theBreathSurvives() {
        let noRoom: Set<String> = ["Grass"]
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
    ///
    /// **Grass is exempt, and the exemption is the proxy misfiring.** Its
    /// groove has to travel almost to the foreground to clear its amber accent
    /// — 4.36:1 off the teal page, where most sit near 2 — and no thumb can
    /// then beat it. What the rule is really asking is "does the thumb read as
    /// a hole", and an amber thumb in a pale-yellow groove does not: the two
    /// stand 1.77:1 apart and the thumb is the more saturated of them. A
    /// recessive thumb on a quiet groove is the shape this catches, and that is
    /// not this.
    @Test("The resting thumb is never quieter than its own groove")
    func theRestingThumbStandsOffThePage() {
        for depth in [ColorDepth.truecolor, .palette256] {
            ColorDepth.withCurrent(depth) {
                for palette in PaletteRegistry.all where palette.name != "Grass" {
                    let page = palette.background.resolve(with: palette)
                    let track = ScrollbarColors.track(in: palette)
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

// MARK: - The groove

@MainActor
@Suite("A scroll track is not the colour of its own thumb")
struct ScrollbarTrackTests {

    /// Six of the sixteen shipped profiles derive `foregroundQuaternary` within
    /// the chrome-separation floor of their own accent, and Ocean's lands on the
    /// SAME 256-colour entry. A groove the colour of its thumb forces the thumb
    /// to an extreme to clear it, and an extreme has no room to breathe.
    @Test("Every palette's track is tellable from its own accent")
    func theTrackClearsTheAccent() {
        ColorDepth.withCurrent(.palette256) {
            for palette in PaletteRegistry.all {
                let track = ScrollbarColors.track(in: palette).downsampledToPalette256()
                let accent = palette.accent.resolve(with: palette).downsampledToPalette256()
                let ratio = track.contrastRatio(against: accent)
                #expect(
                    ratio >= ViewConstants.chromeSeparationFloor,
                    """
                    \(palette.name): the track stands \(String(format: "%.2f", ratio)):1 from the \
                    accent drawn on it
                    """)
            }
        }
    }

    /// …and moving it to get there may not erase it. Pushing toward the page is
    /// the natural direction and is not always available: Grass's page is a teal
    /// its rung already sits near, and quieting it further measured 1.00:1
    /// against the page — an invisible groove, which is worse than a loud one.
    @Test("…and is still visible against the page it sits on")
    func theTrackClearsThePage() {
        ColorDepth.withCurrent(.palette256) {
            for palette in PaletteRegistry.all {
                let track = ScrollbarColors.track(in: palette).downsampledToPalette256()
                let page = palette.background.resolve(with: palette).downsampledToPalette256()
                let ratio = track.contrastRatio(against: page)
                #expect(
                    ratio >= ViewConstants.chromeGrooveFloor,
                    """
                    \(palette.name): the track stands \(String(format: "%.2f", ratio)):1 from the \
                    page, which is not a groove
                    """)
            }
        }
    }

    /// The palette's own rung is left alone where it already works — 10 of the
    /// 16 need no adjustment at all, and a track that moved when it did not have
    /// to would be changing a theme for nothing.
    @Test("A palette whose rung already works keeps it")
    func anAcceptableRungIsUntouched() {
        ColorDepth.withCurrent(.palette256) {
            var untouched = 0
            for palette in PaletteRegistry.all
            where ScrollbarColors.track(in: palette)
                == palette.foregroundQuaternary.resolve(with: palette)
            {
                untouched += 1
            }
            #expect(untouched >= 10, "only \(untouched) palettes kept their own rung")
        }
    }
}
