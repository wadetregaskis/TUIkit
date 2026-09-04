//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityResolutionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// ``FrameBuffer/resolvingOpacity(over:at:surface:palette:)`` — the blend that
/// happens where the destination is finally known.
///
/// These drive the resolution DIRECTLY rather than through `.opacity(_:)`,
/// which still fades at render time and emits no region: this is the machinery
/// landing ahead of the modifier that will use it. See
/// `Documentation/Opacity as composition.md` §9.5 for why the two are separate
/// commits.
@MainActor
@Suite("Opacity resolution")
struct OpacityResolutionTests {

    private func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    private func codes(_ color: Color) -> String {
        color.foregroundCodes().joined(separator: ";")
    }

    private func backgroundCodes(_ color: Color) -> String {
        color.backgroundCodes().joined(separator: ";")
    }

    /// Opacity resolution collapses the rows it rebuilds, so a faded span
    /// begins with the FUSED reset `ESC[0;…m`. The persistent-style wrappers
    /// re-stated their style after the literal `ESC[0m` only, so a dimmed row
    /// un-dimmed from its fade onward and a container background stopped at
    /// the same point.
    @Test("A persistent background and dim survive a collapsed reset")
    func persistentStylesSurviveACollapsedReset() {
        let fused = "\u{1B}[0;38;5;46mx"
        let filled = ANSIRenderer.applyPersistentBackground(fused, color: .rgb(20, 20, 200))
        let blue = backgroundCodes(.rgb(20, 20, 200))
        #expect(filled.range(of: blue).map { filled[$0.upperBound...].contains("x") } == true, "\(filled.debugDescription)")
        #expect(filled.components(separatedBy: blue).count >= 3, "restated after the fused reset: \(filled.debugDescription)")
        let dimmed = ANSIRenderer.applyPersistentDim(fused)
        #expect(dimmed.components(separatedBy: ANSIRenderer.dim).count >= 3, "\(dimmed.debugDescription)")
        // …and end-to-end: a resolved fade, then the background wrapper.
        var source = FrameBuffer(lines: ["faded" + ANSIRenderer.colorize("plain", foreground: .rgb(40, 200, 40))])
        source.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.5)]
        let resolved = source.resolvingOpacity(
            over: FrameBuffer(lines: [String(repeating: " ", count: 10)]), at: (x: 0, y: 0),
            surface: .black, palette: palette())
        let row = ANSIRenderer.applyPersistentBackground(resolved.lines[0], color: .rgb(20, 20, 200)) + ANSIRenderer.reset
        #expect(!row.ansiSGRStateAt(visibleColumn: 5).renderedBackground.isEmpty, "the container background is in force under 'p': \(row.debugDescription)")
    }

    /// A one-line buffer carrying one region over the whole of it.
    private func faded(_ line: String, _ alpha: Double, width: Int) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [line])
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: width, height: 1, opacity: alpha)
        ]
        return buffer
    }

    @Test("An opaque region over nothing is spent without touching the layer")
    func opaqueOverNothingIsTheIdentity() {
        let line = ANSIRenderer.colorize("hello", foreground: .green)
        let source = faded(line, 1, width: 5)
        let resolved = source.resolvingOpacity(surface: .black, palette: palette())

        // Byte-for-byte, not merely pixel-for-pixel: this is the root, where
        // nearly every `.opacity(1)` in an app is resolved, and rewriting a row
        // to arrive back at the same picture is repaint volume for nothing.
        #expect(resolved.lines == [line])
        // Spent, not carried: a region that has been asked and answered must
        // not be asked again by whatever composites the result next.
        #expect(resolved.opacityRegions.isEmpty)
    }

    /// Fully opaque is not the same thing as "replaces the cell".
    ///
    /// A cell that names no background has none to blend, so the destination's
    /// shows at every alpha — including 1. Skipping the walk there (which the
    /// alpha `< 1` filter used to do) made the top of the range the one value
    /// where the cells were punched out to the ambient surface instead: text
    /// over a coloured field that read correctly at 99% and gained a black
    /// rectangle at 100%.
    @Test("An opaque region still lets the destination's background through")
    func opaqueKeepsWhatIsBehind() {
        let field = Color.rgb(160, 30, 30)
        let source = faded(ANSIRenderer.colorize("hello", foreground: .green), 1, width: 5)
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("     ", background: field)])
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        // Whatever spelling this build's renderer picks for the field — truecolor
        // or the 256 cube — the resolved row has to name the same one.
        let expected = field.backgroundCodes().joined(separator: ";")
        #expect(resolved.lines.first?.stripped == "hello")
        #expect(
            resolved.lines.first?.contains(expected) == true,
            "the field under the letters (\(expected)): \(resolved.lines)")
        #expect(resolved.opacityRegions.isEmpty)
    }

    @Test("Below the threshold the destination keeps its character, not its colour")
    func belowTheThresholdTheDestinationKeepsItsCharacter() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .red, background: .blue)
        ])
        let source = faded(ANSIRenderer.colorize("hello", foreground: .green), 0.2, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        // The glyph contest goes to the destination, and only the glyph was
        // ever contested: the ink channel still blends, because colours blend
        // at every alpha. The field does NOT — the source states no background
        // of its own, so it composites none and the destination's stands.
        #expect(resolved.lines[0].stripped == "world")
        #expect(resolved.lines[0].contains(codes(Color.green.compositing(0.2, over: .red))))
        #expect(!resolved.lines[0].contains(codes(.green)))
        #expect(resolved.lines[0].contains(backgroundCodes(.blue)))
    }

    @Test("Text fades toward a block swatch's colour, not its background")
    func aBlockSwatchCountsAsItsInk() {
        // A full block's ink covers the whole cell, so the cell's average IS
        // its foreground — the case that motivated coverage: a swatch drawn
        // with █ behaves as a solid pane of its colour, exactly like one
        // painted as background.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("█████", foreground: .rgb(0, 0, 255))
        ])
        let source = faded(
            ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0)), 0.6, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "hello")
        let towardTheBlocks = Color.rgb(0, 255, 0).compositing(0.6, over: .rgb(0, 0, 255))
        let towardTheSurface = Color.rgb(0, 255, 0).compositing(0.6, over: .rgb(0, 0, 0))
        #expect(resolved.lines[0].contains(codes(towardTheBlocks)))
        #expect(!resolved.lines[0].contains(codes(towardTheSurface)))
    }

    @Test("Matching characters cross-fade in parallel, with no threshold")
    func matchingGlyphsAreNoContest() {
        // The source's ink sits exactly where the destination's does, so
        // foreground blends toward foreground — not toward the field — and
        // the character draws at EVERY alpha. A colour change on unchanged
        // text is exact, never a midpoint snap.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("hello", foreground: .rgb(255, 0, 0))
        ])
        let source = faded(
            ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0)), 0.3, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "hello")
        let expected = Color.rgb(0, 255, 0).compositing(0.3, over: .rgb(255, 0, 0))
        #expect(resolved.lines[0].contains(codes(expected)))
        #expect(!resolved.lines[0].contains(codes(.rgb(255, 0, 0))))
        #expect(!resolved.lines[0].contains(codes(.rgb(0, 255, 0))))
    }

    @Test("A matched cell's weight follows whichever side alpha favours")
    func matchedStyleSnapsAtTheMidpoint() {
        // Colours blend; bold cannot. Below ½ the glyph wears the
        // destination's styling, at or above it the source's.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("hi", foreground: .rgb(255, 0, 0))
        ])
        let bold = ANSIRenderer.colorize("hi", foreground: .rgb(0, 255, 0), bold: true)

        // Bold renders as parameter 1 inside the (reset-prefixed) escape.
        let below = faded(bold, 0.3, width: 2).resolvingOpacity(
            over: destination, surface: .black, palette: palette())
        #expect(!below.lines[0].contains("[0;1;"))

        let above = faded(bold, 0.7, width: 2).resolvingOpacity(
            over: destination, surface: .black, palette: palette())
        #expect(above.lines[0].contains("[0;1;"))
    }

    @Test("A yielded glyph contest still takes the veil, in both channels")
    func aContestedCellIsStillTinted() {
        // Losing the glyph does not exempt a cell from the fade. Without this
        // a translucent panel over text would tint every blank cell and skip
        // every character-holding one, and read as a sieve rather than a veil.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .red, background: .rgb(255, 0, 0))
        ])
        let source = faded(
            ANSIRenderer.colorize("hello", foreground: .green, background: .rgb(0, 0, 255)),
            0.25, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        // The destination's character stands; each channel takes the veil from
        // its own counterpart — the source's ink over the destination's ink,
        // its field over the destination's field. Neither is mixed into the
        // other, so no estimate of how much of a cell a glyph inks is needed.
        #expect(resolved.lines[0].stripped == "world")
        #expect(resolved.lines[0].contains(codes(Color.green.compositing(0.25, over: .red))))
        #expect(!resolved.lines[0].contains(codes(.green)))
        let field = Color.rgb(0, 0, 255).compositing(0.25, over: .rgb(255, 0, 0))
        #expect(resolved.lines[0].contains(backgroundCodes(field)))
        #expect(!resolved.lines[0].contains(backgroundCodes(.rgb(255, 0, 0))))
    }

    @Test("A reversed space is a solid fill, and composites as one")
    func aReversedSpaceIsAFill() {
        // SGR 7 makes the foreground the colour the cell is painted: a
        // reversed blue-foreground space displays as a blue block. Read as a
        // blank it would vanish from the veil entirely; read as what it
        // DISPLAYS it composites its fill like any other pane of background.
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("world", foreground: .red)])
        let reversedFill = "\u{1B}[7;38;2;0;0;255m     \u{1B}[0m"
        let source = faded(reversedFill, 0.5, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .rgb(0, 0, 0), palette: palette())

        #expect(resolved.lines[0].stripped == "world")
        // A fill has no glyph, so what it shows where one would draw is its
        // own colour — the same reading on this side of the blend as on the
        // other. Both channels therefore carry it.
        #expect(resolved.lines[0].contains(codes(Color.rgb(0, 0, 255).compositing(0.5, over: .red))))
        let expected = Color.rgb(0, 0, 255).compositing(0.5, over: .rgb(0, 0, 0))
        #expect(resolved.lines[0].contains(backgroundCodes(expected)))
    }

    @Test("The field behind a reversed cell is its foreground")
    func aReversedDestinationShowsItsForeground() {
        // The destination's ink is painted AS the field under reverse video,
        // so the blend must fade toward the colour the viewer actually sees
        // behind the source, not the one the escape calls \"background\".
        let reversed = "\u{1B}[7;38;2;0;0;255;48;2;255;0;0m     \u{1B}[0m"
        let destination = FrameBuffer(lines: [reversed])
        let source = faded(
            ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0)), 0.6, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "hello")
        // Toward BLUE — the displayed field — not toward the stored red.
        let expected = Color.rgb(0, 255, 0).compositing(0.6, over: .rgb(0, 0, 255))
        #expect(resolved.lines[0].contains(codes(expected)))
        #expect(!resolved.lines[0].contains(codes(.rgb(0, 255, 0).compositing(0.6, over: .rgb(255, 0, 0)))))
    }

    @Test("A reversed cell passed through unchanged still displays swapped")
    func aReversedPassThroughKeepsItsDisplay() {
        // Two regions with a gap: the span runs across all of them, and the
        // uncovered cells in the gap pass through re-emitted. Normalisation
        // strips SGR 7 at parse — so the re-emitted style must carry the
        // SWAPPED colours, or the cell displays its ink and field exchanged.
        // Original: reverse + blue fg + red bg displays RED ink on BLUE field.
        let reversed = "\u{1B}[7;38;2;0;0;255;48;2;255;0;0mABCDEF\u{1B}[0m"
        var buffer = FrameBuffer(lines: [reversed])
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 0.5),
            OpacityRegion(offsetX: 4, offsetY: 0, width: 2, height: 1, opacity: 0.5),
        ]
        let resolved = buffer.resolvingOpacity(
            over: FrameBuffer(), surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "ABCDEF")
        // The gap cells display red ink on a blue field, exactly as before.
        #expect(resolved.lines[0].contains(codes(.rgb(255, 0, 0))))
        #expect(resolved.lines[0].contains(backgroundCodes(.rgb(0, 0, 255))))
        // And never the exchange: blue ink or a red field.
        #expect(!resolved.lines[0].contains(codes(.rgb(0, 0, 255))))
        #expect(!resolved.lines[0].contains(backgroundCodes(.rgb(255, 0, 0))))
    }

    @Test("A veil over reversed text keeps the ink the viewer saw")
    func aVeilOverReversedTextKeepsItsInk() {
        // Reversed destination: blue fg + red bg displays RED ink on BLUE
        // field. A translucent pane keeps the glyph and fades both channels
        // — and the ink channel must fade from the RED the viewer saw, not
        // from the blue the cell stored.
        let reversed = "\u{1B}[7;38;2;0;0;255;48;2;255;0;0mhello\u{1B}[0m"
        let destination = FrameBuffer(lines: [reversed])
        let source = faded(
            ANSIRenderer.colorize("     ", background: .rgb(0, 200, 0)), 0.25, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "hello")
        let ink = Color.rgb(0, 200, 0).compositing(0.25, over: .rgb(255, 0, 0))
        let stored = Color.rgb(0, 200, 0).compositing(0.25, over: .rgb(0, 0, 255))
        #expect(resolved.lines[0].contains(codes(ink)))
        #expect(!resolved.lines[0].contains(codes(stored)))
        let expected = Color.rgb(0, 200, 0).compositing(0.25, over: .rgb(0, 0, 255))
        #expect(resolved.lines[0].contains(backgroundCodes(expected)))
    }

    @Test("An underlined space has ink, and is something to reveal")
    func anUnderlinedBlankIsInk() {
        // Underline draws a pattern in the foreground colour with no glyph
        // present — on either side of the blend. As the destination it is
        // revealed below the threshold rather than treated as blank space.
        let underlined = "\u{1B}[4;38;2;255;0;0m     \u{1B}[0m"
        let destination = FrameBuffer(lines: [underlined])
        let source = faded(
            ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0)), 0.3, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        // The source's glyphs yield and the underline survives — and it is
        // read as INK on this side too, so the source's ink fades from the
        // underline's own red rather than from the field behind it.
        #expect(resolved.lines[0].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(resolved.lines[0].contains(";4;"))
        let ink = Color.rgb(0, 255, 0).compositing(0.3, over: .rgb(255, 0, 0))
        #expect(resolved.lines[0].contains(codes(ink)))
    }

    @Test("Zero opacity is the same case, which is the bug being fixed")
    func zeroRevealsWhatIsBehind() {
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("world", foreground: .red)])
        let source = faded(ANSIRenderer.colorize("hello", foreground: .green), 0, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        // Today's render-time fade paints "hello" in near-black here, hiding
        // the red text it is supposed to be revealing.
        #expect(resolved.lines[0].stripped == "world")
        #expect(resolved.lines[0].contains(codes(.red)))
    }

    @Test("At the threshold the source draws, faded toward what is BEHIND it")
    func halfFadesTowardTheDestinationNotThePalette() {
        // A red field, which is the case the render-time fade gets wrong: it
        // blends toward the palette background regardless of what is there.
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("     ", background: .rgb(255, 0, 0))])
        let source = faded(ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0)), 0.5, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "hello")
        // Half green, half red — neither endpoint, and nowhere near black.
        let expected = Color.rgb(0, 255, 0).compositing(0.5, over: .rgb(255, 0, 0))
        #expect(resolved.lines[0].contains(codes(expected)))
        #expect(!resolved.lines[0].contains(codes(.rgb(0, 255, 0))))
    }

    @Test("A source space keeps the destination's character and its colour")
    func aSpaceIsNotAGlyph() {
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("world", foreground: .red)])
        // Most of what a faded layer contributes is blank: a `VStack`'s padding,
        // the gap between a label and its value, the run out to the right edge.
        let source = faded("     ", 0.5, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "world")
        #expect(resolved.lines[0].contains(codes(.red)))
    }

    @Test("A source space WITH a background tints both channels, keeping the text")
    func aSpaceCompositesItsBackground() {
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("world", foreground: .red)])
        let source = faded(
            ANSIRenderer.colorize("     ", background: .rgb(0, 0, 255)), 0.5, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .rgb(0, 0, 0), palette: palette())

        // The text survives as a character; both of its colours move half way
        // to blue. A pane covers the ink under it exactly as much as the field
        // around it, so the cell fades evenly rather than leaving crisp text
        // standing on a washed-out field.
        #expect(resolved.lines[0].stripped == "world")
        #expect(resolved.lines[0].contains(codes(Color.rgb(0, 0, 255).compositing(0.5, over: .red))))
        let expected = Color.rgb(0, 0, 255).compositing(0.5, over: .rgb(0, 0, 0))
        #expect(resolved.lines[0].contains(backgroundCodes(expected)))
    }

    @Test("A space's background composites below the threshold too")
    func aSpaceFadesContinuously() {
        // The threshold decides which GLYPH shows, and a space is not a glyph
        // contest — so a translucent panel thins out smoothly instead of
        // vanishing whole at the midpoint.
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("world", foreground: .red)])
        let source = faded(
            ANSIRenderer.colorize("     ", background: .rgb(0, 0, 255)), 0.25, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .rgb(0, 0, 0), palette: palette())

        #expect(resolved.lines[0].stripped == "world")
        #expect(
            resolved.lines[0].contains(codes(Color.rgb(0, 0, 255).compositing(0.25, over: .red))))
        let expected = Color.rgb(0, 0, 255).compositing(0.25, over: .rgb(0, 0, 0))
        #expect(resolved.lines[0].contains(backgroundCodes(expected)))
    }

    @Test("A blank column and a lettered one carry the same background")
    func blanksAndLettersAgreeOnTheField() {
        // The report the model change came from: with neither layer painting a
        // background, the cells holding letters picked up a greenish tint that
        // the blank ones did not, and the difference was visible as stripes.
        // The old blend averaged the source's ink INTO its field by an
        // estimated coverage, so a letter contributed to the field and a space
        // did not. Nothing mixes the channels now, so a layer with no
        // background composites no background — under a letter exactly as
        // under a blank.
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("world", foreground: .red)])
        let source = faded(ANSIRenderer.colorize("a b c", foreground: .green), 0.43, width: 5)
        // An off-black surface, so every background this row states is spelled
        // as an explicit triple and none of them can hide in a named code.
        let surface = Color.rgb(1, 2, 3)
        let resolved = source.resolvingOpacity(
            over: destination, surface: surface, palette: palette())

        #expect(resolved.lines[0].stripped == "world")
        // One background across the row, and it is the surface — which is what
        // a cell naming none shows anyway. (The span states it rather than
        // leaving it to SGR 49, which is the terminal's default and not the
        // page's; see `blendedSpan`.)
        let fields = Set(resolved.lines[0].matches(of: /48;2;\d+;\d+;\d+/).map { String($0.output) })
        #expect(fields == [backgroundCodes(surface)], "\(fields)")
        // The ink channel does differ per column, and honestly so: the source
        // paints ink where it has a letter and none where it has a space, so
        // only the lettered columns take its colour. That is emptiness rather
        // than blankness — the same answer a fully transparent layer gets.
        #expect(resolved.lines[0].contains(codes(Color.green.compositing(0.43, over: .red))))
        #expect(resolved.lines[0].contains(codes(.red)))
        #expect(!resolved.lines[0].contains("49m"), "no cell falls back to the terminal default")
    }

    @Test("With nothing behind it, the surface is what is behind it")
    func atARootTheSurfaceStandsIn() {
        let surface = Color.rgb(0, 0, 255)
        let source = faded(ANSIRenderer.colorize("hello", foreground: .rgb(255, 255, 0)), 0.5, width: 5)
        let resolved = source.resolvingOpacity(
            over: FrameBuffer(), surface: surface, palette: palette())

        let expected = Color.rgb(255, 255, 0).compositing(0.5, over: surface)
        #expect(resolved.lines[0].contains(codes(expected)))
    }

    @Test("Where two regions overlap, the inner one wins")
    func theInnerRegionWins() {
        // Nesting multiplies, and the modifier does that multiplication when it
        // stamps: an inner 0.5 inside an outer 0.5 arrives as a 0.25 region
        // FIRST and a 0.5 rectangle after it. So the resolution takes the first
        // match rather than the last, or the outer would overwrite the product.
        var source = FrameBuffer(lines: [ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0))])
        source.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 0.25),
            OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.75),
        ]
        let resolved = source.resolvingOpacity(
            over: FrameBuffer(), surface: .black, palette: palette())

        // Nothing contests these cells, so every character draws — the first
        // two at the inner product, the rest at the outer alpha alone.
        #expect(resolved.lines[0].stripped == "hello")
        #expect(resolved.lines[0].contains(codes(.rgb(0, 255, 0).compositing(0.25, over: .black))))
        #expect(resolved.lines[0].contains(codes(.rgb(0, 255, 0).compositing(0.75, over: .black))))
    }

    @Test("Over a blank cell there is no contest, and text fades all the way out")
    func noContestMeansNoThreshold() {
        // The destination paints a background but no character: nothing to
        // reveal, so the source's glyph draws at ANY alpha rather than
        // vanishing at the midpoint of a fade.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("     ", background: .rgb(255, 0, 0))
        ])
        let source = faded(ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0)), 0.2, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "hello")
        let expected = Color.rgb(0, 255, 0).compositing(0.2, over: .rgb(255, 0, 0))
        #expect(resolved.lines[0].contains(codes(expected)))
    }

    @Test("Bold survives the blend")
    func attributesAreNotColours() {
        let source = faded(
            ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0), bold: true), 0.5, width: 5)
        let resolved = source.resolvingOpacity(
            over: FrameBuffer(), surface: .black, palette: palette())

        // Everything SGR says that is not a colour is a property of the glyph,
        // and the glyph is still being drawn.
        #expect(resolved.lines[0].contains("1"))
        #expect(resolved.lines[0].stripped == "hello")
    }

    @Test("A wide character keeps its two cells")
    func wideCharactersDoNotShiftTheRow() {
        let source = faded(ANSIRenderer.colorize("日本語", foreground: .rgb(0, 255, 0)), 0.5, width: 6)
        let resolved = source.resolvingOpacity(
            over: FrameBuffer(lines: ["......"]), surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "日本語")
        #expect(resolved.lines[0].strippedLength == 6)
    }

    @Test("A revealed wide character cannot swallow a narrow column")
    func wideRevealDoesNotStompItsNeighbour() {
        // Narrow text yielding to wide text underneath: each source column is
        // its own decision, and a two-column 日 emitted from one of them would
        // swallow the next column's answer. The stand-in is one column of the
        // destination's field — half a glyph cannot be drawn.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("日本語", foreground: .red)
        ])
        let source = faded(
            ANSIRenderer.colorize("abcdef", foreground: .rgb(0, 255, 0)), 0.2, width: 6)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        // Columns 0/2/4 held wide starts (field stands in); 1/3/5 sat over
        // continuations — nothing to reveal there, so the source draws, faded.
        #expect(resolved.lines[0].stripped == " b d f")
        #expect(resolved.lines[0].strippedLength == 6)
    }

    @Test("A wide character that yields releases BOTH its columns")
    func wideYieldRevealsEveryColumn() {
        // The walk skips a wide character's continuation column on the
        // assumption the character was emitted and claims it. When the wide
        // character LOSES the contest, the narrow destination glyph emitted in
        // its place claims one column — the continuation must then yield on
        // its own, not vanish. Skipping it left the span short, so the splice
        // replaced too few columns and the row kept unfaded source glyphs.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("abcdef", foreground: .red)
        ])
        let source = faded(
            ANSIRenderer.colorize("日本語", foreground: .rgb(0, 255, 0)), 0.2, width: 6)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "abcdef")
        #expect(resolved.lines[0].strippedLength == 6)
        #expect(resolved.lines[0].contains(codes(.red)))
    }

    @Test("Zero opacity reveals through a wide source exactly")
    func wideSourceAtZeroRevealsExactly() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("abcdef", foreground: .red)
        ])
        let source = faded(
            ANSIRenderer.colorize("日本語", foreground: .rgb(0, 255, 0)), 0, width: 6)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "abcdef")
        #expect(resolved.lines[0].strippedLength == 6)
    }

    @Test("A zero-width scalar occupies no column of the cell model")
    func zeroWidthScalarsClaimNoColumn() {
        // A combining mark separated from its base by an escape is its own
        // segment. Giving it a column of the model displaced every COLOUR
        // decision after it one cell to the right of the real row — the
        // glyphs still came out in order, which is what let this hide.
        let green = "\u{1B}[38;2;0;255;0m"
        let source = green + "a" + green + "\u{0301}bc"  // displays á b c: 3 columns
        // Three distinct fields, so each column's blend target is its own.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize(" ", background: .rgb(9, 9, 9))
                + ANSIRenderer.colorize(" ", background: .rgb(200, 0, 0))
                + ANSIRenderer.colorize(" ", background: .rgb(0, 0, 200))
        ])

        var buffer = FrameBuffer(lines: [source])
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 3, height: 1, opacity: 0.8)
        ]
        let drawn = buffer.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(drawn.lines[0].strippedLength == 3)
        // The mark survives, attached to its base.
        #expect(drawn.lines[0].unicodeScalars.contains("\u{0301}"))
        // b fades toward ITS field (red, column 1) and c toward its own
        // (blue, column 2) — not each toward its neighbour's.
        let sourceColor = Color.rgb(0, 255, 0)
        #expect(drawn.lines[0].contains(codes(sourceColor.compositing(0.8, over: .rgb(200, 0, 0)))))
        #expect(drawn.lines[0].contains(codes(sourceColor.compositing(0.8, over: .rgb(0, 0, 200)))))
        // And the first column blended toward its own field too — all three
        // cells inside the region were faded. (The source's full-strength
        // green may still appear once, in the splice's restored trailing
        // state after the last cell, where it styles nothing.)
        #expect(drawn.lines[0].contains(codes(sourceColor.compositing(0.8, over: .rgb(9, 9, 9)))))
    }

    @Test("Aligned wide characters reveal whole")
    func alignedWideRevealIsWhole() {
        // Wide over wide: the source's continuation columns were already
        // nobody's decision, so the revealed character keeps both its cells.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("中文字", foreground: .red)
        ])
        let source = faded(
            ANSIRenderer.colorize("日本語", foreground: .rgb(0, 255, 0)), 0.2, width: 6)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        #expect(resolved.lines[0].stripped == "中文字")
        #expect(resolved.lines[0].strippedLength == 6)
        #expect(
            resolved.lines[0].contains(codes(Color.rgb(0, 255, 0).compositing(0.2, over: .red))))
    }

    @Test("Compositing punches the covered footprint out of pending regions")
    func compositingPunchesPendingRegions() {
        // A pending region names cells of the BASE. When an overlay replaces
        // some of those cells, the region must stop claiming them — or the
        // root resolver fades content that was never under the fade.
        var base = FrameBuffer(lines: [ANSIRenderer.colorize("abcdef", foreground: .red)])
        base.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 6, height: 1, opacity: 0.5)
        ]
        let overlay = FrameBuffer(lines: [ANSIRenderer.colorize("XY", foreground: .green)])
        let out = base.composited(with: overlay, at: (x: 2, y: 0))

        let rects = out.opacityRegions
            .map { [$0.offsetX, $0.offsetY, $0.width, $0.height] }
            .sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
        #expect(rects == [[0, 0, 2, 1], [4, 0, 2, 1]])
        #expect(out.opacityRegions.allSatisfy { $0.opacity == 0.5 })
    }

    @Test("A sibling drawn on top of a faded view is not faded with it")
    func aSiblingOnTopIsNotFaded() {
        // ZStack draws later children on top: "hi" sits OVER the faded
        // "hello", outside the fade's subtree, and must draw at full
        // strength while the uncovered tail stays faded.
        let context = makeRenderContext(width: 24, height: 2)
        let background = context.environment.palette.background
        let composed = renderToScreen(
            ZStack(alignment: .leading) {
                Text("hello").foregroundStyle(.rgb(200, 40, 40)).opacity(0.5)
                Text("hi").foregroundStyle(.rgb(40, 200, 40))
            },
            context: context)

        #expect(composed.lines[0].contains(codes(.rgb(40, 200, 40))))
        #expect(!composed.lines[0].contains(codes(.rgb(40, 200, 40).compositing(0.5, over: background))))
        #expect(composed.lines[0].contains(codes(.rgb(200, 40, 40).compositing(0.5, over: background))))
    }

    @Test("An overlay applied after opacity draws at full strength")
    func anOverlayAfterOpacityIsNotFaded() {
        // .opacity(0.5).overlay { … }: the overlay is applied to the
        // already-faded view, as in SwiftUI, so its content is not faded.
        let context = makeRenderContext(width: 24, height: 2)
        let background = context.environment.palette.background
        let composed = renderToScreen(
            Text("Hello").foregroundStyle(.rgb(200, 40, 40)).opacity(0.5)
                .overlay { Text("!").foregroundStyle(.rgb(40, 200, 40)) },
            context: context)

        #expect(composed.lines[0].contains(codes(.rgb(40, 200, 40))))
        #expect(!composed.lines[0].contains(codes(.rgb(40, 200, 40).compositing(0.5, over: background))))
    }

    @Test("A row no region covers is left exactly as it was")
    func untouchedRowsAreUntouched() {
        let first = ANSIRenderer.colorize("hello", foreground: .green)
        let second = ANSIRenderer.colorize("world", foreground: .red)
        var source = FrameBuffer(lines: [first, second])
        source.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 1, width: 5, height: 1, opacity: 0.5)
        ]
        let resolved = source.resolvingOpacity(
            over: FrameBuffer(), surface: .black, palette: palette())

        #expect(resolved.lines[0] == first)
        #expect(resolved.lines[1] != second)
    }
}

// MARK: - Foreign runs

@MainActor
@Suite("Opacity and other views' animations")
struct OpacityForeignRunTests {

    private func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    private func codes(_ color: Color) -> String {
        color.foregroundCodes().joined(separator: ";")
    }

    @Test("A run inside a faded region replays FADED, not dropped")
    func foreignRunsAreFaded() {
        // The frames were coloured by a view that never saw the fade — but
        // dropping them froze every run-only animator under .opacity: a
        // Spinner and an indeterminate ProgressView emit their run and
        // request no fallback animation, so with the run gone nothing kept
        // the clock alive and they sat motionless at one faded frame. The
        // frames instead pass through the same blend the lines did, and the
        // run replays faded.
        var buffer = FrameBuffer(lines: [ANSIRenderer.colorize("hello", foreground: .green)])
        let bright = ANSIRenderer.colorize("aaaaa", foreground: .rgb(0, 255, 0))
        let dim = ANSIRenderer.colorize("bbbbb", foreground: .rgb(0, 120, 0))
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 5, frames: [bright, dim], clock: .cursor)
        ]
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.6)
        ]
        let resolved = buffer.resolvingOpacity(surface: .black, palette: palette())

        #expect(resolved.animatedCells.count == 1)
        let faded = resolved.animatedCells.first
        #expect(faded?.frames.count == 2)
        #expect(faded?.frames.first?.stripped == "aaaaa")
        let expected = Color.rgb(0, 255, 0).compositing(0.6, over: .black)
        #expect(faded?.frames.first?.contains(codes(expected)) == true)
        #expect(faded?.frames.first?.contains(codes(Color.rgb(0, 255, 0))) == false)
        // The cadence is the producer's; fading the pictures must not touch it.
        #expect(faded?.clock == .cursor)
    }

    /// A frame from `colorize(glyph, foreground:)` states no background: the
    /// splice gives it the LINE's. Blended against what is behind the layer
    /// alone it took the destination's field unblended — or the bare surface
    /// — and then stated it, so a run on a backgrounded row inside `.opacity`
    /// repainted the wrong field on every tick.
    @Test("A faded run keeps the LINE's field, not the destination's")
    func fadedRunKeepsTheLinesField() throws {
        var buffer = FrameBuffer(lines: [
            ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0), background: .rgb(0, 0, 255))
        ])
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 5,
                frames: [
                    ANSIRenderer.colorize("hello", foreground: .rgb(0, 255, 0)),
                    ANSIRenderer.colorize("HELLO", foreground: .rgb(0, 200, 0)),
                ],
                clock: .cursor)
        ]
        buffer.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.5)]
        let behind = FrameBuffer(lines: [
            ANSIRenderer.colorize("xxxxx", foreground: .rgb(255, 255, 255), background: .rgb(255, 0, 0))
        ])
        let resolved = buffer.resolvingOpacity(over: behind, at: (x: 0, y: 0), surface: .black, palette: palette())
        let frame = try #require(resolved.animatedCells.first?.frames.first)
        let lineField = Color.rgb(0, 0, 255).compositing(0.5, over: .rgb(255, 0, 0))
        #expect(frame.contains(backgroundCodes(lineField)), "frame: \(frame.debugDescription)")
        #expect(!frame.contains(backgroundCodes(.rgb(255, 0, 0))), "the destination's field, unblended")
    }

    /// A region is stamped as wide as its buffer — the longest line — over
    /// lines that may be shorter. `blendedSpan` could not tell "past the end
    /// of the line" from "the continuation of a wide glyph", manufactured
    /// cells there wearing the last real cell's field, and grew the row.
    @Test("A region wider than its line fades the line, not the space past it")
    func regionPastTheLineEndAddsNoCells() {
        var buffer = FrameBuffer(lines: [ANSIRenderer.colorize("ab", background: .blue)])
        buffer.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 6, height: 1, opacity: 0.5)]
        let resolved = buffer.resolvingOpacity(surface: .black, palette: palette())
        #expect(resolved.lines[0].strippedLength == 2, "\(resolved.lines[0].debugDescription)")
        // …and a region entirely past a short line is a no-op for it.
        var two = FrameBuffer(lines: [ANSIRenderer.colorize("abcdef", background: .blue), "ab"])
        two.opacityRegions = [OpacityRegion(offsetX: 3, offsetY: 0, width: 3, height: 2, opacity: 0.5)]
        let second = two.resolvingOpacity(surface: .black, palette: palette())
        #expect(second.lines[1] == "ab")
    }

    @Test("A repeating fade still yields a foreign run — two clocks, one cell")
    func aCyclingFadeStillDropsForeignRuns() {
        // The fade's phases and the run's frames tick independently, and
        // their product is not representable as one run. The run yields; its
        // cells freeze at the frame the lines were drawn with, inside a fade
        // that itself keeps animating.
        var buffer = FrameBuffer(lines: [ANSIRenderer.colorize("hello", foreground: .green)])
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 5, frames: ["aaaaa", "bbbbb"], clock: .cursor)
        ]
        var region = OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 1)
        region.cycle = OpacityCycle(phases: [1, 0.6], clock: .cursor)
        buffer.opacityRegions = [region]
        let resolved = buffer.resolvingOpacity(surface: .black, palette: palette())
        // The fade's own runs replace it; the foreign run itself is gone.
        #expect(!resolved.animatedCells.contains { $0.frames.contains { $0.stripped == "bbbbb" } })
    }

    @Test("A run beside the region is left alone")
    func runsOutsideTheRegionSurvive() {
        var buffer = FrameBuffer(lines: [ANSIRenderer.colorize("hello world", foreground: .green)])
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: 6, offsetY: 0, width: 5, frames: ["aaaaa", "bbbbb"], clock: .cursor)
        ]
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.6)
        ]
        let resolved = buffer.resolvingOpacity(surface: .black, palette: palette())
        #expect(resolved.animatedCells.count == 1)
        #expect(resolved.animatedCells.first?.offsetX == 6)
    }
}
