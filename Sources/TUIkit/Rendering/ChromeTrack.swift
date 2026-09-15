//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeTrack.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The colour of a TRACK that chrome draws the accent on: a palette rung,
/// moved along its own line until it is tellable from both the accent drawn on
/// it and the page it sits on.
///
/// Fixed here rather than in the derivation, deliberately. The requirement
/// belongs to the chrome that draws the accent ON a quiet rung, and
/// constraining the rung itself would move a colour that spinners, pickers and
/// menu chrome also draw in — measured on Grass, it took the quaternary from a
/// muted green to a pale yellow to get clear of the amber accent, which is a
/// large change to a theme for one control's benefit.
///
/// Toward the page first at each step, because a groove wants to be the
/// quieter of the two; toward the ink when that direction runs out (Grass's
/// page is a teal its track already sits near, so quieting it further erases
/// it). Failing both, the palette's own rung stands: a groove too close to its
/// thumb is a worse bar than one too close to its page, and an INVISIBLE groove
/// is worse than either.
enum ChromeTrack {
    /// `base`, resolved against `palette` and separated from the palette's
    /// accent and page, answered once per distinct set of inputs and kept.
    @MainActor
    static func track(from base: Color, in palette: any Palette) -> Color {
        let base = base.resolve(with: palette)
        let accent = palette.accent.resolve(with: palette)
        let page = palette.background.resolve(with: palette)
        let ink = palette.foreground.resolve(with: palette)
        // Every input of `resolvedTrack` is in the key. The ink was not, so two
        // palettes alike but for their foreground shared one answer — and the
        // answer can be the FALLBACK, cached from a palette whose ink offered
        // no acceptable rung and served to one whose ink would have.
        let key = TrackKey(base: base, accent: accent, page: page, ink: ink)
        if let cached = trackCache[key] { return cached }
        let answer = resolvedTrack(base: base, accent: accent, page: page, ink: ink)
        // Sixteen palettes and one entry each; the cap is a backstop against an
        // app generating palettes per frame, not a working set.
        if trackCache.count > 64 { trackCache.removeAll(keepingCapacity: true) }
        trackCache[key] = answer
        return answer
    }

    private struct TrackKey: Hashable {
        let base: Color
        let accent: Color
        let page: Color
        let ink: Color
    }

    /// Up to 24 quantisations per palette, so it is answered once and kept —
    /// this is asked per scrollbar per frame.
    @MainActor private static var trackCache: [TrackKey: Color] = [:]

    /// Internal, not private, so the memo test can ask for a cold answer.
    static func resolvedTrack(base: Color, accent: Color, page: Color, ink: Color) -> Color {
        func acceptable(_ candidate: Color) -> Bool {
            renderedRatio(candidate, accent) >= ViewConstants.chromeSeparationFloor
                && renderedRatio(candidate, page) >= ViewConstants.chromeGrooveFloor
        }
        guard !acceptable(base) else { return base }
        // Each candidate is the RUNG moved, not a mix of two paints: the page and
        // the ink are only directions here. `lerp` would otherwise walk the alpha
        // toward theirs as a fourth channel — a faded rung coming back part-way
        // opaque, an opaque one part-way faded, by however far it had to move
        // (§45). The floors are measured on the channels alone, so carrying the
        // alpha changes which colour comes back, never which step is chosen.
        for step in 1...12 {
            let phase = Double(step) / 12
            for candidate in [
                Color.lerp(base, page, phase: phase), Color.lerp(base, ink, phase: phase),
            ].map({ $0.carryingAlpha(of: base) }) where acceptable(candidate) {
                return candidate
            }
        }
        return base
    }

    /// Two colours' contrast AS DRAWN — through the 256-colour cube, which is
    /// where chrome this quiet collapses. See
    /// ``ScrollbarColors/separated(_:in:standingOffThePage:)``.
    static func renderedRatio(_ lhs: Color, _ rhs: Color) -> Double {
        lhs.downsampledToPalette256().contrastRatio(against: rhs.downsampledToPalette256())
    }
}
