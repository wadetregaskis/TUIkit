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
/// over the page, and a brighter tone in the state's own hue — the accent when on, a
/// grey lifted toward the foreground when off — so the breathing never reads as a
/// change of state.
///
/// Both SPEND their alpha over the page, so every frame is opaque and the track's
/// claims hold for all of them (§58). The bright end used to carry the accent's alpha
/// when on; off, it lerped `.brightBlack` toward a translucent foreground, and a lerp
/// interpolates alpha — 198 of 128, neither kept nor spent. An opaque palette's bytes
/// do not change: spending an opaque colour returns it untouched.
enum SwitchTrackBreath {
    static func ends(track: Color, isOn: Bool, palette: any Palette) -> (dim: Color, bright: Color) {
        let ground = palette.background
        // On, exactly `accentPulse`'s bright end: the accent spent over the page. Off,
        // the lerp toward the foreground AS IT SHOWS — the grey it starts from is a
        // fixed, opaque `.brightBlack` by design.
        let bright =
            isOn
            ? palette.accentPulse().bright
            : Color.lerp(.brightBlack, palette.foreground.spendingAlpha(over: ground), phase: 0.45)
        return (track.opacity(ViewConstants.focusPulseMin, over: ground), bright)
    }
}
