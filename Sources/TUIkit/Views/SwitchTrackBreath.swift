//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SwitchTrackBreath.swift
//
//  The two ends a focused coloured-track switch breathes between. Lifted out of
//  the generic toggle core so they can be asked for directly, the way
//  `SwitchIndicatorGlyphs` is.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The two ends a focused coloured-track switch breathes between: its track, dimmed
/// over the page, and a brighter tone in the state's own hue — the accent when on, the
/// off track lifted toward the foreground when off — so the breathing never reads as a
/// change of state.
///
/// Both SPEND their alpha over the page, so every frame is opaque and the track's
/// claims hold for all of them (§58). The bright end used to carry the accent's alpha
/// when on; off, it lerped the track toward a translucent foreground, and a lerp
/// interpolates alpha — 198 of 128, neither kept nor spent. An opaque palette's bytes
/// do not change: spending an opaque colour returns it untouched.
enum SwitchTrackBreath {
    /// The track an OFF switch is drawn on: the palette's tertiary tone, moved by
    /// ``ChromeTrack/track(from:in:)`` until it stands off both the page, which the
    /// knob is drawn in, and the accent, which the same track turns when on.
    ///
    /// A palette rung rather than a fixed grey, so the switch follows the theme; the
    /// tertiary, because it is what the unlit part of a slider, a progress bar and a
    /// gauge is drawn in. Separated, because on four of the shipped palettes the raw
    /// rung sits within the chrome-separation floor of the accent (Ocean's at 1.05:1),
    /// an off switch that reads as a dimmer "on"; the fixed `.brightBlack` it replaces
    /// missed the floors of the page or the accent on seven.
    ///
    /// It carries the rung's alpha. Under a palette whose tertiary is translucent the
    /// resting track is a translucent field, which the switch claims at that alpha;
    /// both ends of the breath still spend it.
    @MainActor
    static func offTrack(in palette: any Palette) -> Color {
        ChromeTrack.track(from: palette.foregroundTertiary, in: palette)
    }

    @MainActor
    static func ends(track: Color, isOn: Bool, palette: any Palette) -> (dim: Color, bright: Color) {
        let ground = palette.background
        // On, exactly `accentPulse`'s bright end: the accent spent over the page. Off,
        // the off track lerped toward the foreground, both AS THEY SHOW, since either
        // can be translucent.
        let bright =
            isOn
            ? palette.accentPulse().bright
            : Color.lerp(
                offTrack(in: palette).spendingAlpha(over: ground),
                palette.foreground.spendingAlpha(over: ground), phase: 0.45)
        // Held at the bright end where either end has no RGB: the dim end is a composite
        // over the page, which then snaps to the page or the track (§75), and the breath
        // would blink between the two.
        return Color.breathEnds(dim: track.opacity(ViewConstants.focusPulseMin, over: ground), bright: bright)
    }
}
