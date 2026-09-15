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
    /// 20% of the way from **the field behind the cell**, which here is the
    /// destination's blue background.
    ///
    /// Not from the destination's INK, which is what this test used to assert.
    /// The source's glyph won the cell, so the red "world" it replaced is not
    /// behind it — nothing is, except the field. Blending toward a displaced
    /// glyph's colour is visibly wrong at the bottom of the range, where an
    /// invisible glyph comes out painted in the colour of the letters it hid.
    @Test("Translucent ink keeps its own glyph and fades its colour")
    func translucentInkDrawsFaintly() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .ansi(.red), background: .ansi(.blue))
        ])
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .ansi(.green)), ink: 0.2, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .ansi(.black), palette: palette())

        #expect(
            resolved.lines[0].stripped == "hello",
            "the source's glyph stands — there is no contest: \(resolved.lines)")
        #expect(
            resolved.lines[0].contains(codes(Color.ansi(.green).opacity(0.2, over: .ansi(.blue)))),
            "…in 20% green over the blue field: \(resolved.lines[0].debugDescription)")
        #expect(!resolved.lines[0].contains(codes(.ansi(.green))), "not at full strength")
        #expect(
            resolved.lines[0].contains(backgroundCodes(.ansi(.blue))),
            "and the field is untouched — the ink channel does not move it")
    }

    /// Field alpha moves the background and leaves the ink alone: the two
    /// channels are independent, which is the whole reason there are two.
    @Test("Translucent field fades the background and not the ink")
    func translucentFieldFadesOnlyTheField() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .ansi(.red), background: .ansi(.blue))
        ])
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .ansi(.green), background: .ansi(.white)),
            field: 0.25, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .ansi(.black), palette: palette())

        #expect(resolved.lines[0].stripped == "hello")
        // Compared against green's own RGB rather than `codes(.green)`: the blend
        // re-emits every colour it touched as truecolor, so the standard-16
        // spelling ("32") is not what a blended row says even when the colour is
        // unchanged. `opacity(1, over:)` is the identity, in the blend's spelling.
        #expect(
            resolved.lines[0].contains(codes(Color.ansi(.green).opacity(1, over: .ansi(.red)))),
            "the ink is at full strength: \(resolved.lines[0].debugDescription)")
        #expect(
            resolved.lines[0].contains(backgroundCodes(Color.ansi(.white).opacity(0.25, over: .ansi(.blue)))),
            "…and the field is a quarter of the way from blue: \(resolved.lines[0].debugDescription)")
    }

    /// **Ink at zero keeps its glyph and paints it in the field's own colour.**
    ///
    /// The reasoning is the project owner's and it turns on what a cell is. A
    /// cell's character is the SELECTABLE text: drop the glyph and the cell holds
    /// whatever a sibling drew, so a transparent label is copied out of the
    /// terminal as the text underneath it. Emitting it keeps copy and paste
    /// honest, and removing something from the picture is what `.hidden()`,
    /// `.opacity(0)` and not drawing it are for.
    ///
    /// It is also the only answer continuous with the rest of the range —
    /// `inkFadesTowardItsOwnField`'s blend lands exactly on the field at zero —
    /// and it makes `.clear` ink behave as `.foregroundColor(<the field>)`, which
    /// is the equivalence `clearInkIsTheFieldsColour` pins.
    ///
    /// This test previously asserted the opposite: that the destination's "world"
    /// showed through. That reading treats a transparent colour as an absent view,
    /// and nobody expects `.foregroundColor(.black)` on a black field to reveal
    /// text behind it.
    @Test("Ink at zero keeps its own glyph, invisibly")
    func zeroInkKeepsItsGlyph() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .ansi(.red), background: .ansi(.blue))
        ])
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .ansi(.green)), ink: 0, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .ansi(.black), palette: palette())
        #expect(
            resolved.lines[0].stripped == "hello",
            "the source's own text is what is in the cells: \(resolved.lines)")
        // Invisible: the ink lands on the field it is drawn on, which the source
        // does not state and therefore inherits — the destination's blue.
        #expect(
            resolved.lines[0].contains(codes(Color.ansi(.green).opacity(0, over: .ansi(.blue)))),
            "painted in the field's colour: \(resolved.lines[0].debugDescription)")
        #expect(
            !resolved.lines[0].contains(codes(Color.ansi(.green).opacity(1, over: .ansi(.red)))),
            "and no green was stated")
    }

    /// **The equivalence that justifies the rule.** A transparent ink is not a
    /// missing view, it is a colour — and in a cell grid it is the same colour as
    /// the field, so at zero the ink NAMED must stop mattering entirely.
    ///
    /// Two very different inks, both fully transparent on a blue field, have to
    /// come out as the same bytes, and those bytes have to be blue. If they ever
    /// diverge one of them is wrong, and being invisible is what would keep
    /// anyone from noticing which.
    ///
    /// The source line states each ink in its OPAQUE spelling, as every real
    /// paint site does — `Color+ANSICodes.swift`'s assertion fires on a
    /// translucent colour reaching an emitter, and a test harness is not exempt.
    /// The alpha lives on the region, which is the whole design.
    @Test("At ink zero the colour named stops mattering — the field shows")
    func clearInkIsTheFieldsColour() {
        func foreground(of ink: Color, alpha: Double) -> String {
            let source = tinted(
                ANSIRenderer.colorize(
                    "hello", foreground: ink.opaqueSpelling, background: .ansi(.blue)),
                ink: alpha, width: 5)
            return source.resolvingOpacity(surface: .ansi(.black), palette: palette()).lines[0]
        }
        let fieldCodes = codes(Color.ansi(.blue).opacity(1, over: .ansi(.blue)))
        for ink in [Color.ansi(.green), .ansi(.red), .clear, .ansi(.white)] {
            let line = foreground(of: ink, alpha: 0)
            #expect(
                line.contains(fieldCodes),
                "\(ink) at ink 0 paints the blue field: \(line.debugDescription)")
        }
    }

    /// …and over NOTHING the glyphs stand too, in the surface's colour, so a
    /// transparent label still occupies and still copies.
    @Test("Ink at zero over an empty destination keeps its glyphs")
    func zeroInkOverNothing() {
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .ansi(.green)), ink: 0, width: 5)
        let resolved = source.resolvingOpacity(surface: .ansi(.black), palette: palette())
        #expect(
            resolved.lines[0].stripped == "hello",
            "still selectable: \(resolved.lines[0].debugDescription)")
        #expect(
            resolved.lines[0].contains(codes(Color.ansi(.green).opacity(0, over: .ansi(.black)))),
            "and invisible against the surface: \(resolved.lines[0].debugDescription)")
    }

    /// A translucent colour inside a fading pane is faint twice over, and neither
    /// number knows about the other — but they compose by SEQUENCE, not by
    /// multiplication, because they resolve against different backdrops.
    ///
    /// The ink's alpha resolves within its own layer, against the field the glyph
    /// sits on (here the inherited blue). The layer's alpha then composites that
    /// result over the backdrop, against the destination's ink (red). Multiplying
    /// the two into one blend — which this test used to assert — is only
    /// equivalent when both backdrops are the same colour, which is exactly the
    /// case the FIELD channel enjoys and the ink channel does not.
    @Test("A layer's alpha and an ink's compose in sequence, not by multiplication")
    func channelsCompose() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .ansi(.red), background: .ansi(.blue))
        ])
        var source = FrameBuffer(lines: [ANSIRenderer.colorize("hello", foreground: .ansi(.green))])
        source.opacityRegions = [
            OpacityRegion(
                offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.5, inkOpacity: 0.5)
        ]
        let resolved = source.resolvingOpacity(
            over: destination, surface: .ansi(.black), palette: palette())
        // Within the layer first, then across it.
        let expected = Color.ansi(.green).opacity(0.5, over: .ansi(.blue)).opacity(0.5, over: .ansi(.red))
        #expect(
            resolved.lines[0].contains(codes(expected)),
            "ink over its own field, then the layer: \(resolved.lines[0].debugDescription)")
        #expect(
            !resolved.lines[0].contains(codes(Color.ansi(.green).opacity(0.25, over: .ansi(.red)))),
            "and NOT the single multiplied blend")
    }

    /// **The bug the sequence fixes, in the shape it was reachable in.**
    ///
    /// A layer that paints its OWN background — a `Table` row, a `.background()`,
    /// any filled panel — is the field its glyphs sit on. Translucent ink there
    /// has to fade toward that field, not toward whatever the page behind the
    /// panel happens to be, or the fade reveals a colour that is nowhere near
    /// the cell.
    ///
    /// Here the source paints a green field with red ink at 25%; the page behind
    /// is blue. The letters must land 25% of the way from GREEN, and the blue
    /// must not appear in the row at all.
    @Test("Translucent ink fades toward its own layer's background")
    func inkFadesTowardItsOwnField() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .ansi(.white), background: .ansi(.blue))
        ])
        let source = tinted(
            ANSIRenderer.colorize("hello", foreground: .ansi(.red), background: .ansi(.green)),
            ink: 0.25, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .ansi(.black), palette: palette())

        #expect(
            resolved.lines[0].contains(codes(Color.ansi(.red).opacity(0.25, over: .ansi(.green)))),
            "25% red over its own green field: \(resolved.lines[0].debugDescription)")
        // Spelled as a blend at alpha 1 rather than as `backgroundCodes(.green)`:
        // the resolver re-emits every colour it touched as truecolor, so the
        // standard-palette spelling `42` would be comparing notations, not
        // colours.
        #expect(
            resolved.lines[0].contains(backgroundCodes(Color.ansi(.green).opacity(1, over: .ansi(.blue)))),
            "the field itself is opaque and unmoved: \(resolved.lines[0].debugDescription)")
        #expect(
            !resolved.lines[0].contains(codes(Color.ansi(.red).opacity(0.25, over: .ansi(.blue)))),
            "and nothing blended toward the page behind the panel")
    }

    /// A region that is opaque in every channel is still the identity — the fast
    /// exit has to test all three, or a translucent ink at full layer strength is
    /// eaten whole by "the layer wins the cell outright".
    @Test("Opaque in every channel is still the identity")
    func fullyOpaqueIsStillTheIdentity() {
        let line = ANSIRenderer.colorize("hello", foreground: .ansi(.green))
        let source = tinted(line, width: 5)
        let resolved = source.resolvingOpacity(surface: .ansi(.black), palette: palette())
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
            ANSIRenderer.colorize("hello", foreground: .ansi(.green)), ink: 0.5, width: 5)
        #expect(source.opacityRegions[0].isTranslucent, "the filter's own test")
        let resolved = source.resolvingOpacity(surface: .ansi(.black), palette: palette())
        #expect(
            resolved.lines[0].contains(codes(Color.ansi(.green).opacity(0.5, over: .ansi(.black)))),
            "blended toward the surface: \(resolved.lines[0].debugDescription)")
    }

    /// **The run-path twin of the ink-and-field fold.**
    ///
    /// Two independent claims on one cell — an ink one and a field one, which is
    /// what `.foregroundStyle(…opacity).background(…opacity)` stamps — must
    /// multiply, and the run's frames took `covering.first` where the line
    /// multiplied. That is not a small difference: the drawn line came out faded
    /// on both channels and the very next replay tick painted the background back
    /// at full strength, so the bug appeared only once the animation moved.
    @Test("A run's frames fold both claims, exactly as the line does")
    func runFramesFoldEveryClaim() {
        let ink = Color.rgb(40, 220, 40)
        let field = Color.rgb(220, 40, 40)
        let frame = { (glyph: String) in
            ANSIRenderer.colorize(glyph, foreground: ink, background: field)
        }
        var source = FrameBuffer(lines: [frame("AA")], width: 2, lineWidths: [2])
        source.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 2, frames: [frame("AA"), frame("BB")],
                clock: .content)
        ]
        source.opacityRegions = [
            OpacityRegion(
                offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 1,
                inkOpacity: 0.5, fieldOpacity: 1),
            OpacityRegion(
                offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 1,
                inkOpacity: 1, fieldOpacity: 0.5),
        ]
        let resolved = source.resolvingOpacity(surface: .ansi(.black), palette: palette())
        let fadedField = backgroundCodes(field.opacity(0.5, over: .ansi(.black)))
        #expect(resolved.animatedCells.count == 1)
        for (index, drawn) in (resolved.animatedCells.first?.frames ?? []).enumerated() {
            #expect(
                drawn.contains(fadedField),
                "frame \(index) kept the field at full strength: \(drawn.debugDescription)")
        }
        // The line is the oracle: whatever it did with two claims, the frame the
        // loop splices at the tick just drawn must do too.
        #expect(
            resolved.lines[0].contains(fadedField), "\(resolved.lines[0].debugDescription)")
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
        var colour = Color.ansi(.blue)
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
                Color.ansi(.red)
                veil.colour
            })
        let expected = codes(Color.ansi(.blue).opacity(veil.exact, over: .ansi(.red)))
        #expect(
            lines[0].contains(expected),
            "40% blue over red (\(expected)): \(lines[0].debugDescription)")
        // And emphatically not the two wrong answers.
        #expect(
            !lines[0].contains(codes(Color.ansi(.blue).opacity(veil.exact, over: .ansi(.black)))),
            "not toward black")
        #expect(!lines[0].contains(codes(.ansi(.blue))), "not at full strength")
    }

    /// The same veil over a DIFFERENT sibling gives a different answer, which is
    /// the property that distinguishes composite-time resolution from every
    /// approximation of it. One assertion; the whole point.
    @Test("The same veil over a different sibling resolves differently")
    func veilDependsOnWhatIsBehind() {
        let veil = alpha(0.5)
        let overRed = rendered(ZStack { Color.ansi(.red); veil.colour })[0]
        let overGreen = rendered(ZStack { Color.ansi(.green); veil.colour })[0]
        #expect(
            overRed != overGreen,
            "the veil is not a fixed colour: \(overRed.debugDescription)")
        #expect(overRed.contains(codes(Color.ansi(.blue).opacity(veil.exact, over: .ansi(.red)))))
        #expect(overGreen.contains(codes(Color.ansi(.blue).opacity(veil.exact, over: .ansi(.green)))))
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
        let buffer = renderToBuffer(Color.ansi(.blue), context: context)
        #expect(buffer.opacityRegions.isEmpty)
        #expect(buffer.lines[0].contains(codes(.ansi(.blue))))
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
        let veil = faded(.ansi(.blue), 128)
        // One row, so the ZStack cannot centre the text onto a line the pane
        // occupies alone — the first version of this test read row 0 and found
        // only the red fill.
        let lines = screen(
            ZStack {
                Color.ansi(.red)
                Text("hi").background(veil.colour)
            }, height: 1)
        #expect(lines[0].stripped.contains("hi"), "the letters survive: \(lines[0].stripped)")
        #expect(
            lines[0].contains(bgCodes(Color.ansi(.blue).opacity(veil.exact, over: .ansi(.red)))),
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
            Text("hi").background(faded(.ansi(.blue), 0).colour), context: context)
        #expect(backed.opacityRegions.isEmpty, "nothing claimed")
        #expect(
            backed.lines[0].stripped == plain.lines[0].stripped,
            "and nothing painted: \(backed.lines[0].debugDescription)")
    }

    /// **Translucent INK.** The glyph draws — it is not in a contest with
    /// anything — and its colour blends toward the FIELD behind the cell.
    ///
    /// The red "world" underneath is not the backdrop: "hello" won the cell, so
    /// what remains behind its glyph is the field, which neither `Text` states
    /// and which is therefore the page's own surface.
    @Test("Translucent ink draws its glyph faintly over the field behind it")
    func translucentInk() {
        let ink = faded(.ansi(.green), 51)  // 20%
        let surface = makeRenderContext(width: 14, height: 3).environment.palette.background
        let lines = screen(
            ZStack {
                Text("world").foregroundStyle(.ansi(.red))
                Text("hello").foregroundStyle(ink.colour)
            })
        #expect(
            lines[0].stripped.contains("hello"),
            "the faint glyph still draws: \(lines[0].stripped)")
        #expect(
            lines[0].contains(fgCodes(Color.ansi(.green).opacity(ink.exact, over: surface))),
            "…in 20% green over the surface: \(lines[0].debugDescription)")
        #expect(
            !lines[0].contains(fgCodes(Color.ansi(.green).opacity(ink.exact, over: .ansi(.red)))),
            "and not toward the glyph it displaced")
    }

    /// **Two independent claims on one cell, which first-match-wins dropped.**
    ///
    /// A translucent foreground and a translucent background are separate claims
    /// about separate channels, stamped by separate modifiers — `Text` writes the
    /// ink region, `.background` appends the field one, over the same cells. The
    /// resolver used to take the first region covering a cell and stop, so the
    /// background rendered at FULL strength under the letters and correctly past
    /// the end of the line: on ragged wrapped text, a visible two-tone block.
    ///
    /// Ink and field multiply across every covering region now. The layer channel
    /// deliberately still takes the first — see the comment at the fold.
    @Test("A translucent foreground and background both apply")
    func bothChannelsApplyTogether() {
        var ink = Color.ansi(.green)
        ink.alpha = 102  // 0.4
        var field = Color.ansi(.red)
        field.alpha = 102
        let context = makeRenderContext(width: 14, height: 3)
        let surface = context.environment.palette.background
        // Rendered and then resolved explicitly: `screen` returns the buffer as
        // drawn, and regions are resolved at a COMPOSITE. There is no sibling
        // here — the claim is about the two channels composing with each other.
        let buffer = renderToBuffer(
            Text("hi").foregroundStyle(ink).background(field), context: context)
        #expect(buffer.opacityRegions.count == 2, "one claim each: \(buffer.opacityRegions)")
        let lines = buffer.resolvingOpacity(
            surface: surface, palette: context.environment.palette
        ).lines

        let fadedField = Color.ansi(.red).opacity(102.0 / 255, over: surface)
        #expect(
            lines[0].contains(bgCodes(fadedField)),
            "the background is 40% red over the surface: \(lines[0].debugDescription)")
        #expect(
            !lines[0].contains(bgCodes(Color.ansi(.red).opacity(1, over: surface))),
            "and not full-strength red")
        // …and the ink is 40% green over the FIELD THAT RESULTED, which is the
        // faded red — the two claims compose rather than one winning.
        #expect(
            lines[0].contains(fgCodes(Color.ansi(.green).opacity(102.0 / 255, over: fadedField))),
            "the ink blends over the faded field: \(lines[0].debugDescription)")
    }

    /// **A concatenation's fragments are rectangular after all.**
    ///
    /// The design listed an attributed run alongside a ramp as needing "a claim
    /// finer than a rectangle". That is true of the ramp and false of the
    /// fragments: a fragment occupies a contiguous column range of ONE line, so a
    /// height-1 rectangle per fragment says exactly what is true. The runs arm was
    /// declining alpha for a reason that only applied to its neighbour.
    ///
    /// Here the middle fragment is translucent and the outer two are not, so the
    /// claim has to start at column 5 and be 5 wide — not cover the line.
    @Test("A concatenation claims each translucent fragment's own columns")
    func fragmentsClaimTheirOwnColumns() {
        var faint = Color.ansi(.green)
        faint.alpha = 102
        let context = makeRenderContext(width: 30, height: 3)
        let text =
            Text("HELLO").foregroundStyle(.ansi(.red))
            + Text("world").foregroundStyle(faint)
            + Text("AGAIN").foregroundStyle(.ansi(.blue))
        let buffer = renderToBuffer(text, context: context)

        #expect(buffer.opacityRegions.count == 1, "one claim: \(buffer.opacityRegions)")
        let claim = buffer.opacityRegions.first
        #expect(claim?.offsetX == 5, "starts after HELLO: \(String(describing: claim?.offsetX))")
        #expect(claim?.width == 5, "and is world's width: \(String(describing: claim?.width))")
        #expect(claim?.offsetY == 0, "on its own line")
        #expect(
            (claim?.inkOpacity ?? 0) > 0.39 && (claim?.inkOpacity ?? 1) < 0.41,
            "at 40%: \(String(describing: claim?.inkOpacity))")
    }

    /// **The regression the runs arm actually had.** A concatenation whose
    /// fragments all take ONE translucent colour is the uniform case the plain arm
    /// already handled — and `guard runs == nil` refused it anyway. So adding
    /// `+ Text("")` to a working translucent `Text` silently made it opaque.
    @Test("A uniformly translucent concatenation claims its whole line")
    func uniformConcatenationIsNotRefused() {
        var faint = Color.ansi(.green)
        faint.alpha = 102
        let context = makeRenderContext(width: 30, height: 3)
        let plain = renderToBuffer(Text("abcdef").foregroundStyle(faint), context: context)
        let joined = renderToBuffer(
            (Text("abc").bold() + Text("def")).foregroundStyle(faint), context: context)

        #expect(!plain.opacityRegions.isEmpty, "the plain text claims: \(plain.opacityRegions)")
        #expect(
            joined.opacityRegions.count == 1,
            "and the concatenation coalesces to one: \(joined.opacityRegions)")
        #expect(
            joined.opacityRegions.first?.width == plain.opacityRegions.first?.width,
            "over the same columns: \(joined.opacityRegions)")
    }

    /// Cells, not characters. A fragment holding a 2-cell glyph pushes every later
    /// fragment's claim two columns along, and counting characters would put the
    /// claim one column short — fading the wrong cell and leaving the last one
    /// unfaded.
    @Test("A wide glyph before a translucent fragment shifts its claim by cells")
    func wideGlyphShiftsTheClaim() {
        var faint = Color.ansi(.green)
        faint.alpha = 102
        let context = makeRenderContext(width: 30, height: 3)
        // "日本" is two characters and four cells.
        let text = Text("日本").foregroundStyle(.ansi(.red)) + Text("ab").foregroundStyle(faint)
        let buffer = renderToBuffer(text, context: context)
        #expect(
            buffer.opacityRegions.first?.offsetX == 4,
            "four cells in, not two: \(buffer.opacityRegions)")
    }

    /// **A ramp fading to transparent, down the page.** The scrim idiom: a list
    /// that fades out at the bottom.
    ///
    /// A vertical linear ramp states one colour per ROW, therefore one alpha per
    /// row, so a rectangle per row says exactly what is true — no per-cell payload
    /// needed. The claims have to be in the order the rows were painted, or a
    /// fade runs the wrong way and still looks like a fade.
    @Test("A vertical translucent ramp claims one rectangle per row")
    func verticalRampClaimsPerRow() {
        let context = makeRenderContext(width: 8, height: 4)
        let scrim = LinearGradient(
            colors: [.ansi(.black), .clear], startPoint: .top, endPoint: .bottom)
        let buffer = renderToBuffer(
            VStack {
                Text("aaaa")
                Text("bbbb")
                Text("cccc")
                Text("dddd")
            }.background(scrim),
            context: context)

        let regions = buffer.opacityRegions.sorted { $0.offsetY < $1.offsetY }
        #expect(regions.count == 4, "one per row: \(regions)")
        #expect(regions.allSatisfy { $0.height == 1 }, "each a single row")
        #expect(regions.allSatisfy { $0.inkOpacity == 1 }, "field claims only")
        // Opaque at the top, transparent at the bottom, monotonically.
        let alphas = regions.map(\.fieldOpacity)
        #expect(alphas.first ?? 0 > 0.9, "opaque at the top: \(alphas)")
        #expect(alphas.last ?? 1 < 0.1, "transparent at the bottom: \(alphas)")
        #expect(zip(alphas, alphas.dropFirst()).allSatisfy { $0 >= $1 }, "descending: \(alphas)")
    }

    /// An evenly translucent ramp is one rectangle, whatever its geometry — the
    /// alpha does not vary, so nothing about the ramp's shape matters to the claim.
    @Test("A uniformly translucent ramp claims one rectangle")
    func uniformRampClaimsOneRectangle() {
        var red = Color.ansi(.red)
        var blue = Color.ansi(.blue)
        red.alpha = 128
        blue.alpha = 128
        let context = makeRenderContext(width: 8, height: 2)
        // Horizontal: the geometry that varies across a row, and still one claim.
        let ramp = LinearGradient(
            colors: [red, blue], startPoint: .leading, endPoint: .trailing)
        let buffer = renderToBuffer(
            VStack { Text("aaaa"); Text("bbbb") }.background(ramp), context: context)

        #expect(buffer.opacityRegions.count == 1, "one claim: \(buffer.opacityRegions)")
        let claim = buffer.opacityRegions.first
        #expect(claim?.height == 2, "over the whole block: \(String(describing: claim?.height))")
        #expect(
            (claim?.fieldOpacity ?? 0) > 0.49 && (claim?.fieldOpacity ?? 1) < 0.51,
            "at 50%: \(String(describing: claim?.fieldOpacity))")
    }

    /// **Copy and paste, end to end through the real view stack.**
    ///
    /// `.foregroundStyle(.clear)` has to leave its own characters in the cells —
    /// that is the point of it being a colour rather than a way of removing a
    /// view — so a reader selecting the row gets the transparent label's text and
    /// not the text it covers.
    @Test("Transparent text is still in the cells to be copied")
    func transparentTextIsStillSelectable() {
        let lines = screen(
            ZStack {
                Text("world").foregroundStyle(.ansi(.red))
                Text("hello").foregroundStyle(.clear)
            })
        #expect(
            lines[0].stripped.contains("hello"),
            "the transparent label's own text: \(lines[0].stripped.debugDescription)")
        #expect(
            !lines[0].stripped.contains("world"),
            "and not the text underneath it")
        // Invisible: its ink is the surface it sits on.
        let surface = makeRenderContext(width: 14, height: 3).environment.palette.background
        #expect(
            lines[0].contains(fgCodes(Color.clear.opaqueSpelling.opacity(0, over: surface))),
            "…painted in the surface's colour: \(lines[0].debugDescription)")
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
            Text("hi there").foregroundStyle(faded(.ansi(.green), 128).colour), context: context)
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
            renderToBuffer(Text("hi").background(Color.ansi(.blue)), context: context)
                .opacityRegions.isEmpty)
        #expect(
            renderToBuffer(Text("hi").foregroundStyle(Color.ansi(.green)), context: context)
                .opacityRegions.isEmpty)
    }
}
