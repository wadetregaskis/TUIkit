//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SwitchTrackBreathTests.swift
//
//  The two ends a focused coloured-track switch breathes between, asked for
//  directly: both spend their alpha over the page, so every tick is opaque, and an
//  opaque palette's ends are the colours they always were.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A switch track's breath spends both ends")
struct SwitchTrackBreathTests {

    /// Every tick, not the two ends: a cycle interpolates alpha as a fourth channel
    /// between ends that disagree (§29.3). Every shipped palette under a half-faded
    /// tint and a wholly faded one, the track on and off, lifted by a hover or not.
    @Test("Every tick of a focused switch track's breath is opaque", arguments: [true, false])
    func everyTickIsOpaque(isOn: Bool) {
        let palettes: [any Palette] =
            PaletteRegistry.all.map { TintedPalette(base: $0, tint: $0.accent.opacity(0.5)) }
            + [FadedAll()]
        var environment = EnvironmentValues()
        environment.selectionIndicatorStyle = SelectionIndicatorStyle(animation: .pulse)
        let cycle = environment.selectionEmphasis.cycle(true)
        var offenders: [String] = []
        for palette in palettes {
            // The tracks `_ToggleCore` draws: the accent on, a fixed grey off.
            let base = isOn ? palette.accent : Color.brightBlack
            for track in [base, palette.hoveredForeground(base)] {
                let ends = SwitchTrackBreath.ends(track: track, isOn: isOn, palette: palette)
                let colors = cycle.colors(dim: ends.dim, bright: ends.bright)
                if !colors.allSatisfy(\.isOpaque) {
                    offenders.append("\(palette.name): \(colors.map(\.alpha))")
                }
            }
        }
        #expect(offenders.isEmpty, "the track's breath carries an alpha: \(offenders)")
    }

    /// An opaque palette's two ends are the colours they always were, spelled the same:
    /// spending an opaque colour returns it untouched.
    @Test("An opaque palette's switch track breathes between the colours it always did")
    func opaqueEndsKeepTheirSpelling() {
        for palette in PaletteRegistry.all {
            let on = SwitchTrackBreath.ends(track: palette.accent, isOn: true, palette: palette)
            #expect(on.bright == palette.accent, "\(palette.name): the on end was re-spelled")
            let off = SwitchTrackBreath.ends(track: .brightBlack, isOn: false, palette: palette)
            #expect(
                off.bright == Color.lerp(.brightBlack, palette.foreground, phase: 0.45),
                "\(palette.name): the off end was re-spelled")
        }
    }
}
