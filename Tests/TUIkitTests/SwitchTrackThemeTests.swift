//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SwitchTrackThemeTests.swift
//
//  A switch's off and disabled track are drawn from the palette: its tertiary
//  tone, separated from the page and the accent the way a scroll track is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A switch's off track follows the palette")
struct SwitchTrackThemeTests {

    /// Unfocused, so the track is drawn at rest rather than at some point of its
    /// breath, under `palette`, in truecolor so a role's RGB is spelled out.
    private func render<V: View>(_ view: V, palette: any Palette) -> FrameBuffer {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = palette
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 3, environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
        return ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }
    }

    @Test("An off switch draws its track in the palette's tertiary tone")
    func offTrackIsTertiary() {
        let drawn = render(
            Toggle("Wifi", isOn: .constant(false)).toggleStyle(.switch),
            palette: ThemeProbePalette()
        ).lines.joined()
        #expect(drawn.contains("48;2;90;90;90"), "\(drawn.debugDescription)")
        #expect(
            !drawn.contains("100m") && !drawn.contains(";100"),
            "the fixed bright-black track: \(drawn.debugDescription)")
    }

    /// The off track faded halfway toward the page: rgb(90, 90, 90) at 0.5 over
    /// rgb(10, 10, 10).
    @Test("A disabled switch draws the off track faded over the page")
    func disabledTrackIsFadedTertiary() {
        let drawn = render(
            Toggle("Wifi", isOn: .constant(false)).toggleStyle(.switch).disabled(true),
            palette: ThemeProbePalette()
        ).lines.joined()
        #expect(drawn.contains("48;2;50;50;50"), "\(drawn.debugDescription)")
    }

    /// The knob is drawn in the page's colour on the track, and the accent is what
    /// the same track turns when on. Measured as drawn, through the 256-colour cube,
    /// against the same floors a scroll track keeps.
    /// Every palette that STATES its own colours: a palette that leaves its page and its
    /// accent to the terminal paints no ratio for a track to stand off until the
    /// terminal reports them.
    @Test("Every stated palette's off track stands off its page and its accent")
    func offTrackStandsOff() {
        var offenders: [String] = []
        for palette in PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles {
            let track = SwitchTrackBreath.offTrack(in: palette).resolve(with: palette)
            let page = palette.background.resolve(with: palette)
            let accent = palette.accent.resolve(with: palette)
            let groove = ChromeTrack.renderedRatio(track, page)
            let separation = ChromeTrack.renderedRatio(track, accent)
            if groove < ViewConstants.chromeGrooveFloor || separation < ViewConstants.chromeSeparationFloor {
                offenders.append(
                    "\(palette.name): page \(String(format: "%.2f", groove)), "
                        + "accent \(String(format: "%.2f", separation))")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// A translucent tertiary makes the resting off track a translucent FIELD, and
    /// the switch claims it at that alpha.
    @Test("A faded tertiary's off track is claimed at the tertiary's alpha")
    func fadedOffTrackIsClaimed() {
        let palette = FadedNavigation()
        let drawn = render(Toggle("Wifi", isOn: .constant(false)).toggleStyle(.switch), palette: palette)
        let expected = Double(palette.foregroundTertiary.alpha) / 255
        #expect(
            drawn.opacityRegions.contains { $0.fieldOpacity == expected },
            "\(drawn.opacityRegions)")
    }
}
