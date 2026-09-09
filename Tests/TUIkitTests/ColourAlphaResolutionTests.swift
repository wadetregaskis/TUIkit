//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColourAlphaResolutionTests.swift
//
//  A COLOUR's alpha, as distinct from a LAYER's. The two are different claims
//  wearing the same number: a layer at 0.3 is 30% present, so its glyph competes
//  with what is behind it and the ½ rule decides; ink at 0.3 is faint text that
//  is definitely drawn. These pin the difference.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("Colour alpha resolution")
struct ColourAlphaResolutionTests {

    private func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    private func codes(_ color: Color) -> String {
        color.foregroundCodes().joined(separator: ";")
    }

    private func backgroundCodes(_ color: Color) -> String {
        color.backgroundCodes().joined(separator: ";")
    }

    /// A region carrying ink or field alpha at full layer strength.
    private func tinted(
        _ line: String, ink: Double = 1, field: Double = 1, width: Int
    ) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [line])
        buffer.opacityRegions = [
            OpacityRegion(
                offsetX: 0, offsetY: 0, width: width, height: 1, opacity: 1,
                inkOpacity: ink, fieldOpacity: field)
        ]
        return buffer
    }

    /// **The twin of `belowTheThresholdTheDestinationKeepsItsCharacter`, and the
    /// test that proves the ½ rule was correctly scoped to the layer.**
    ///
    /// The same 0.2 that hands the glyph to the destination when it is a LAYER's
    /// must keep the source's glyph when it is an INK's — and blend its colour
    /// 20% of the way from the destination's ink.
    @Test("Translucent ink keeps its own glyph and fades its colour")
    func translucentInkDrawsFaintly() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .red, background: .blue)
        ])
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .green), ink: 0.2, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(
            resolved.lines[0].stripped == "hello",
            "the source's glyph stands — there is no contest: \(resolved.lines)")
        #expect(
            resolved.lines[0].contains(codes(Color.green.opacity(0.2, over: .red))),
            "…in 20% green over red: \(resolved.lines[0].debugDescription)")
        #expect(!resolved.lines[0].contains(codes(.green)), "not at full strength")
        #expect(
            resolved.lines[0].contains(backgroundCodes(.blue)),
            "and the field is untouched — the ink channel does not move it")
    }

    /// Field alpha moves the background and leaves the ink alone: the two
    /// channels are independent, which is the whole reason there are two.
    @Test("Translucent field fades the background and not the ink")
    func translucentFieldFadesOnlyTheField() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .red, background: .blue)
        ])
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .green, background: .white),
            field: 0.25, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "hello")
        // Compared against green's own RGB rather than `codes(.green)`: the blend
        // re-emits every colour it touched as truecolor, so the standard-16
        // spelling ("32") is not what a blended row says even when the colour is
        // unchanged. `opacity(1, over:)` is the identity, in the blend's spelling.
        #expect(
            resolved.lines[0].contains(codes(Color.green.opacity(1, over: .red))),
            "the ink is at full strength: \(resolved.lines[0].debugDescription)")
        #expect(
            resolved.lines[0].contains(backgroundCodes(Color.white.opacity(0.25, over: .blue))),
            "…and the field is a quarter of the way from blue: \(resolved.lines[0].debugDescription)")
    }

    /// Ink at zero paints no glyph at all — which is what `Color.clear` as a
    /// foreground has to mean — and must NOT erase what is behind it. Getting the
    /// zero exit wrong makes `.clear` text blank the row it sits on.
    @Test("Ink at zero reveals the destination's glyph rather than erasing it")
    func zeroInkDrawsNothing() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .red, background: .blue)
        ])
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .green), ink: 0, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())
        #expect(
            resolved.lines[0].stripped == "world",
            "what is behind shows: \(resolved.lines)")
        #expect(
            !resolved.lines[0].contains(codes(Color.green.opacity(1, over: .red))),
            "and no green was stated")
    }

    /// …and over NOTHING it is blank cells rather than a hole: they still occupy
    /// their space, which is what SwiftUI does too.
    @Test("Ink at zero over an empty destination draws blanks")
    func zeroInkOverNothing() {
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .green), ink: 0, width: 5)
        let resolved = source.resolvingOpacity(surface: .black, palette: palette())
        #expect(
            resolved.lines[0].stripped.trimmingCharacters(in: .whitespaces).isEmpty,
            "nothing drawn: \(resolved.lines[0].debugDescription)")
    }

    /// The channels multiply, which is what lets a translucent colour inside a
    /// fading pane be faint twice over without either number knowing about the
    /// other.
    @Test("A layer's alpha and an ink's compose by multiplication")
    func channelsCompose() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .red, background: .blue)
        ])
        var source = FrameBuffer(lines: [ANSIRenderer.colorize("hello", foreground: .green)])
        source.opacityRegions = [
            OpacityRegion(
                offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.5, inkOpacity: 0.5)
        ]
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())
        #expect(
            resolved.lines[0].contains(codes(Color.green.opacity(0.25, over: .red))),
            "0.5 × 0.5: \(resolved.lines[0].debugDescription)")
    }

    /// A region that is opaque in every channel is still the identity — the fast
    /// exit has to test all three, or a translucent ink at full layer strength is
    /// eaten whole by "the layer wins the cell outright".
    @Test("Opaque in every channel is still the identity")
    func fullyOpaqueIsStillTheIdentity() {
        let line = ANSIRenderer.colorize("hello", foreground: .green)
        let source = tinted(line, width: 5)
        let resolved = source.resolvingOpacity(surface: .black, palette: palette())
        #expect(resolved.lines[0] == line, "untouched: \(resolved.lines[0].debugDescription)")
        #expect(resolved.opacityRegions.isEmpty)
    }

    /// And the region is kept when it says anything at all, over an EMPTY
    /// destination as well: dropping it there is how translucent text works
    /// inside a `ZStack` and renders opaque on a plain page — which is the
    /// common case, so it is the worse bug.
    @Test("An ink-alpha region survives the drop filter over nothing")
    func inkAlphaSurvivesOverNothing() {
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .green), ink: 0.5, width: 5)
        #expect(source.opacityRegions[0].isTranslucent, "the filter's own test")
        let resolved = source.resolvingOpacity(surface: .black, palette: palette())
        #expect(
            resolved.lines[0].contains(codes(Color.green.opacity(0.5, over: .black))),
            "blended toward the surface: \(resolved.lines[0].debugDescription)")
    }
}
