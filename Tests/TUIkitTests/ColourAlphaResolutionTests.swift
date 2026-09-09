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

// MARK: - A translucent colour used as a view

/// `Color.blue.opacity(0.4)` in a `ZStack` — the first real translucent pane, and
/// the case the whole design exists for: resolved against what is ACTUALLY behind
/// the cell, not against the palette's background and not toward black.
@MainActor
@Suite("A translucent colour as a view")
struct TranslucentColourViewTests {

    private func rendered<V: View>(_ view: V, width: Int = 12, height: Int = 2) -> [String] {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context).lines
    }

    /// A blue at `value` opacity, plus the fraction the byte ACTUALLY holds.
    ///
    /// Not `value`: alpha is a byte, so 0.5 stores as 128 and reads back as
    /// 0.50196…, and the blend uses the stored number. A test comparing against
    /// the number it asked for is off by one in the last channel — which is a
    /// property of the storage the tests should state, not paper over.
    private func alpha(_ value: Double) -> (colour: Color, exact: Double) {
        var colour = Color.blue
        colour.alpha = UInt8((value * 255).rounded())
        return (colour, Double(colour.alpha) / 255)
    }

    private func codes(_ color: Color) -> String {
        color.backgroundCodes().joined(separator: ";")
    }

    /// Over a red pane, a 40% blue veil must land 40% of the way from RED — not
    /// from black, and not from the palette's background.
    @Test("A veil blends toward the sibling actually behind it")
    func veilBlendsTowardTheSibling() {
        let veil = alpha(0.4)
        let lines = rendered(
            ZStack {
                Color.red
                veil.colour
            })
        let expected = codes(Color.blue.opacity(veil.exact, over: .red))
        #expect(
            lines[0].contains(expected),
            "40% blue over red (\(expected)): \(lines[0].debugDescription)")
        // And emphatically not the two wrong answers.
        #expect(
            !lines[0].contains(codes(Color.blue.opacity(veil.exact, over: .black))),
            "not toward black")
        #expect(!lines[0].contains(codes(.blue)), "not at full strength")
    }

    /// The same veil over a DIFFERENT sibling gives a different answer, which is
    /// the property that distinguishes composite-time resolution from every
    /// approximation of it. One assertion; the whole point.
    @Test("The same veil over a different sibling resolves differently")
    func veilDependsOnWhatIsBehind() {
        let veil = alpha(0.5)
        let overRed = rendered(ZStack { Color.red; veil.colour })[0]
        let overGreen = rendered(ZStack { Color.green; veil.colour })[0]
        #expect(
            overRed != overGreen,
            "the veil is not a fixed colour: \(overRed.debugDescription)")
        #expect(overRed.contains(codes(Color.blue.opacity(veil.exact, over: .red))))
        #expect(overGreen.contains(codes(Color.blue.opacity(veil.exact, over: .green))))
    }

    /// A veil over TEXT tints the field under the letters and leaves the letters
    /// legible — the pane rule the ½ threshold encodes, now reached by a colour's
    /// own alpha rather than by `View.opacity`.
    @Test("A veil over text keeps the text")
    func veilOverTextKeepsTheGlyphs() {
        let lines = rendered(
            ZStack {
                Text("hello")
                alpha(0.5).colour
            })
        #expect(lines[0].stripped.contains("hello"), "the letters survive: \(lines[0].stripped)")
    }

    /// **Alpha 0 needs its region, and this is the test that says why.**
    ///
    /// Bare spaces are not transparent to the compositor: it inherits an unstated
    /// FIELD but a space is still a character, so it overwrites the glyph
    /// underneath. Skipping the region as an optimisation rendered
    /// `ZStack { Text("hello"); Color.clear }` as twelve spaces.
    @Test("A fully transparent colour reveals what is behind it")
    func transparentRevealsWhatIsBehind() {
        let context = RenderContext(
            availableWidth: 6, availableHeight: 1, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(alpha(0).colour, context: context)
        #expect(
            buffer.opacityRegions.count == 1 && buffer.opacityRegions[0].fieldOpacity == 0,
            "the region is what routes these cells through the blend")

        let stacked = rendered(ZStack { Text("hello"); alpha(0).colour })
        #expect(stacked[0].stripped.contains("hello"), "the letters survive: \(stacked[0].stripped)")
    }

    /// An opaque colour is byte-identical to what it drew before this feature
    /// existed — no region, no blend, nothing changed.
    @Test("An opaque colour emits no region")
    func opaqueEmitsNoRegion() {
        let context = RenderContext(
            availableWidth: 6, availableHeight: 1, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(Color.blue, context: context)
        #expect(buffer.opacityRegions.isEmpty)
        #expect(buffer.lines[0].contains(codes(.blue)))
    }
}

// MARK: - The two places a colour is written

/// `.background(_:)` and `Text`'s own foreground — the other two sites that know
/// the rectangle they painted, and so can send an alpha up as a region.
@MainActor
@Suite("A translucent background and a translucent ink")
struct TranslucentPaintTests {

    private func screen<V: View>(_ view: V, width: Int = 14, height: Int = 3) -> [String] {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context).lines
    }

    private func faded(_ base: Color, _ alpha: UInt8) -> (colour: Color, exact: Double) {
        var colour = base
        colour.alpha = alpha
        return (colour, Double(alpha) / 255)
    }

    private func bgCodes(_ color: Color) -> String {
        color.backgroundCodes().joined(separator: ";")
    }

    private func fgCodes(_ color: Color) -> String {
        color.foregroundCodes().joined(separator: ";")
    }

    /// A translucent BACKGROUND fades the field and leaves the letters alone —
    /// which is exactly what the two channels are for.
    @Test("A translucent background fades the field and not the text")
    func translucentBackground() {
        let veil = faded(.blue, 128)
        // One row, so the ZStack cannot centre the text onto a line the pane
        // occupies alone — the first version of this test read row 0 and found
        // only the red fill.
        let lines = screen(
            ZStack {
                Color.red
                Text("hi").background(veil.colour)
            }, height: 1)
        #expect(lines[0].stripped.contains("hi"), "the letters survive: \(lines[0].stripped)")
        #expect(
            lines[0].contains(bgCodes(Color.blue.opacity(veil.exact, over: .red))),
            "the field is half blue over red: \(lines[0].debugDescription)")
    }

    /// `.background(<transparent>)` paints nothing, and stamps nothing — there is
    /// no claim to make about cells the modifier did not touch.
    @Test("A fully transparent background is a no-op")
    func transparentBackgroundIsANoOp() {
        let context = RenderContext(
            availableWidth: 8, availableHeight: 1, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let plain = renderToBuffer(Text("hi"), context: context)
        let backed = renderToBuffer(
            Text("hi").background(faded(.blue, 0).colour), context: context)
        #expect(backed.opacityRegions.isEmpty, "nothing claimed")
        #expect(
            backed.lines[0].stripped == plain.lines[0].stripped,
            "and nothing painted: \(backed.lines[0].debugDescription)")
    }

    /// **Translucent INK.** The glyph draws — it is not in a contest with
    /// anything — and its colour blends toward what is behind the cell.
    @Test("Translucent ink draws its glyph faintly over what is behind it")
    func translucentInk() {
        let ink = faded(.green, 51)  // 20%
        let lines = screen(
            ZStack {
                Text("world").foregroundStyle(.red)
                Text("hello").foregroundStyle(ink.colour)
            })
        #expect(
            lines[0].stripped.contains("hello"),
            "the faint glyph still draws: \(lines[0].stripped)")
        #expect(
            lines[0].contains(fgCodes(Color.green.opacity(ink.exact, over: .red))),
            "…in 20% green over red: \(lines[0].debugDescription)")
    }

    /// A wrapped text stamps one region PER LINE, sized to that line — not one
    /// rectangle over the block. A rectangle would claim the blank cells past the
    /// end of every short line and fade whatever a sibling drew there.
    @Test("A ragged text claims each line's own width")
    func raggedTextClaimsPerLine() {
        let context = RenderContext(
            availableWidth: 7, availableHeight: 3, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(
            Text("hi there").foregroundStyle(faded(.green, 128).colour), context: context)
        #expect(buffer.lines.count == 2, "it wrapped: \(buffer.lines.map { $0.stripped })")
        #expect(buffer.opacityRegions.count == 2, "one region per line")
        let widths = buffer.opacityRegions.map(\.width)
        #expect(
            Set(widths).count == 2,
            "and each is its own line's width, not the block's: \(widths)")
    }

    /// An opaque colour changes nothing anywhere: no region, and the same bytes as
    /// before this feature existed.
    @Test("Opaque paint stamps no region")
    func opaquePaintStampsNothing() {
        let context = RenderContext(
            availableWidth: 8, availableHeight: 1, tuiContext: TUIContext()
        ).isolatingRenderCache()
        #expect(
            renderToBuffer(Text("hi").background(Color.blue), context: context)
                .opacityRegions.isEmpty)
        #expect(
            renderToBuffer(Text("hi").foregroundStyle(Color.green), context: context)
                .opacityRegions.isEmpty)
    }
}
