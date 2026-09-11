//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarTrackAlphaTests.swift
//
//  A scroll track is the palette's quietest rung, moved until it can be told
//  from its thumb and its page — a re-spelling of that rung, which carries the
//  rung's alpha wherever the move took it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("A scroll track keeps its rung's alpha")
struct ScrollbarTrackAlphaTests {

    /// A rung one shade off the accent fails the separation floor, so
    /// `resolvedTrack` walks it toward the page or the ink — through `lerp`, which
    /// would otherwise interpolate the alpha toward theirs as a fourth channel.
    ///
    /// Three pages: an opaque one (the faded rung drifted OPAQUE, step by step), a
    /// faded one with a faded ink (the one case the old answer happened to get
    /// right, since everything agreed), and a light one, so the walk runs the other
    /// way. Each asserts the rung really moved, or the alpha check proves nothing.
    @Test("A faded rung, moved off itself, is still faded")
    func movedRungCarries() {
        let accent = Color.rgb(0, 180, 200)
        let rung = Color.rgb(0, 170, 190).opacity(0.5)
        for (page, ink) in [
            (Color.rgb(10, 10, 20), Color.rgb(230, 230, 240)),
            (Color.rgb(10, 10, 20).opacity(0.5), Color.rgb(230, 230, 240).opacity(0.5)),
            (Color.rgb(240, 240, 230), Color.rgb(20, 20, 30)),
        ] {
            let track = ScrollbarColors.resolvedTrack(base: rung, accent: accent, page: page, ink: ink)
            #expect(
                track.opaqueSpelling != rung.opaqueSpelling,
                "the rung was not moved on page \(page), so this asserts nothing")
            #expect(track.alpha == rung.alpha, "on page \(page) the track came back at \(track.alpha)")
        }
    }

    /// The other direction of the same drift: an opaque rung walked toward a FADED
    /// page used to come back part-way translucent — a colour the palette never
    /// asked to fade.
    @Test("An opaque rung, moved toward a faded page, is still opaque")
    func opaqueRungStaysOpaque() {
        let rung = Color.rgb(0, 170, 190)
        let track = ScrollbarColors.resolvedTrack(
            base: rung, accent: Color.rgb(0, 180, 200),
            page: Color.rgb(10, 10, 20).opacity(0.5), ink: Color.rgb(230, 230, 240))
        #expect(track.opaqueSpelling != rung.opaqueSpelling, "the rung was not moved")
        #expect(track.alpha == .max, "the track came back at \(track.alpha)")
    }
}
