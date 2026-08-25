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
        ANSIRenderer.foregroundCodes(for: color).joined(separator: ";")
    }

    private func backgroundCodes(_ color: Color) -> String {
        ANSIRenderer.backgroundCodes(for: color).joined(separator: ";")
    }

    /// A one-line buffer carrying one region over the whole of it.
    private func faded(_ line: String, _ alpha: Double, width: Int) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [line])
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: width, height: 1, opacity: alpha)
        ]
        return buffer
    }

    @Test("An opaque region is the identity, and is spent")
    func opaqueIsTheIdentity() {
        let line = ANSIRenderer.colorize("hello", foreground: .green)
        let source = faded(line, 1, width: 5)
        let resolved = source.resolvingOpacity(
            over: FrameBuffer(lines: ["....."]), surface: .black, palette: palette())

        #expect(resolved.lines == [line])
        // Spent, not carried: a region that has been asked and answered must
        // not be asked again by whatever composites the result next.
        #expect(resolved.opacityRegions.isEmpty)
    }

    @Test("Below the threshold the destination is untouched, not merely revealed")
    func belowTheThresholdTheDestinationSurvives() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .red, background: .blue)
        ])
        let source = faded(ANSIRenderer.colorize("hello", foreground: .green), 0.2, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        // Its character, its foreground AND its background: the source paints
        // no background of its own, so there is nothing of it to see — a
        // source WITH one would tint the field, and only the field.
        #expect(resolved.lines[0].stripped == "world")
        #expect(resolved.lines[0].contains(codes(.red)))
        #expect(resolved.lines[0].contains(backgroundCodes(.blue)))
        #expect(!resolved.lines[0].contains(codes(.green)))
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

    @Test("A yielded glyph contest still composites the veil's background")
    func aContestedCellIsStillTinted() {
        // To the cell it lost, the source is a pane of background — the same
        // rule a space follows. Without this a translucent panel over text
        // would tint every blank cell and skip every character-holding one,
        // and read as a sieve rather than a veil.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("world", foreground: .red, background: .rgb(255, 0, 0))
        ])
        let source = faded(
            ANSIRenderer.colorize("hello", foreground: .green, background: .rgb(0, 0, 255)),
            0.25, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .black, palette: palette())

        // The text and its colour stand; the field carries the veil.
        #expect(resolved.lines[0].stripped == "world")
        #expect(resolved.lines[0].contains(codes(.red)))
        #expect(!resolved.lines[0].contains(codes(.green)))
        let expected = Color.rgb(0, 0, 255).compositing(0.25, over: .rgb(255, 0, 0))
        #expect(resolved.lines[0].contains(backgroundCodes(expected)))
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
        #expect(resolved.lines[0].contains(codes(.red)))
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

        // The source's glyphs yield; the underline survives, un-tinted.
        #expect(resolved.lines[0].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(resolved.lines[0].contains(";4;"))
        #expect(resolved.lines[0].contains(codes(.rgb(255, 0, 0))))
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

    @Test("A source space WITH a background tints the cell and keeps the text")
    func aSpaceCompositesItsBackground() {
        let destination = FrameBuffer(lines: [ANSIRenderer.colorize("world", foreground: .red)])
        let source = faded(
            ANSIRenderer.colorize("     ", background: .rgb(0, 0, 255)), 0.5, width: 5)
        let resolved = source.resolvingOpacity(
            over: destination, surface: .rgb(0, 0, 0), palette: palette())

        // The text survives, in its own colour — a translucent pane over text
        // does not tint the text — on a background half way to blue.
        #expect(resolved.lines[0].stripped == "world")
        #expect(resolved.lines[0].contains(codes(.red)))
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
        #expect(resolved.lines[0].contains(codes(.red)))
        let expected = Color.rgb(0, 0, 255).compositing(0.25, over: .rgb(0, 0, 0))
        #expect(resolved.lines[0].contains(backgroundCodes(expected)))
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

    @Test("A run inside a faded region is dropped, not left to replay unfaded")
    func foreignRunsAreDropped() {
        // The frames were coloured by a view that never saw the fade, so the
        // render draws the faded picture and the next replay tick paints the
        // unfaded frames back over it — a control that pops to full strength
        // one tick after every render.
        var buffer = FrameBuffer(lines: [ANSIRenderer.colorize("hello", foreground: .green)])
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 5, frames: ["aaaaa", "bbbbb"], clock: .cursor)
        ]
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.6)
        ]
        let resolved = buffer.resolvingOpacity(surface: .black, palette: palette())
        #expect(resolved.animatedCells.isEmpty)
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
