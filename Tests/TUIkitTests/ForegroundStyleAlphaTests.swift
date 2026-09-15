//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ForegroundStyleAlphaTests.swift
//
//  `.foregroundStyle(.red.opacity(0.5))` reaching something that is not a
//  `Text` — the leaves that paint their own glyph and read the environment for
//  the colour to paint it in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A translucent foregroundStyle on a leaf that is not Text")
struct ForegroundStyleAlphaTests {

    private func buffer<V: View>(_ view: V, width: Int = 10, height: Int = 3) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    private func faded(_ base: Color, _ alpha: UInt8) -> Color {
        var colour = base
        colour.alpha = alpha
        return colour
    }

    // MARK: - Divider

    @Test("A horizontal rule claims the cells it drew, and no more")
    func horizontalDivider() throws {
        let drawn = buffer(Divider().foregroundStyle(faded(.ansi(.red), 128)), width: 7, height: 1)
        let claim = try #require(drawn.opacityRegions.first)
        #expect(drawn.opacityRegions.count == 1)
        #expect(claim.width == 7, "one cell per column of the rule")
        #expect(claim.height == 1)
        #expect(claim.inkOpacity == 128.0 / 255)
        // A rule paints no field, so it says nothing about one — which is what
        // keeps a faded rule from punching a hole in whatever it is drawn over.
        #expect(claim.fieldOpacity == 1)
        #expect(
            drawn.lines[0].contains(Color.ansi(.red).foregroundCodes().joined(separator: ";")),
            "the bytes are the colour at full strength: \(drawn.lines[0].debugDescription)")
    }

    @Test("An opaque rule claims nothing")
    func opaqueDivider() {
        #expect(buffer(Divider().foregroundStyle(Color.ansi(.red)), width: 7, height: 1)
            .opacityRegions.isEmpty)
        // …and so does the default, which takes the palette's own border colour.
        #expect(buffer(Divider(), width: 7, height: 1).opacityRegions.isEmpty)
    }

    @Test("A vertical rule claims its column")
    func verticalDivider() throws {
        // The axis comes from the enclosing stack, so an `HStack` is what makes
        // this the vertical arm.
        let drawn = buffer(
            HStack {
                Text("a")
                Divider().foregroundStyle(faded(.ansi(.red), 64)).frame(height: 3)
            }, width: 6, height: 3)
        let claim = try #require(drawn.opacityRegions.first)
        #expect(claim.width == 1, "one column")
        #expect(drawn.lines.count > 1, "the premise: a vertical rule spans rows")
        // The invariant, rather than a guessed height: the claim covers exactly
        // the rows the rule drew. Asserting a number instead would pass or fail on
        // how the enclosing stack chose to size a flexible child.
        #expect(claim.height == drawn.lines.count, "every row the rule drew")
        #expect(claim.inkOpacity == 64.0 / 255)
    }

    @Test("A rule with no room draws nothing and claims nothing")
    func degenerateDivider() {
        #expect(buffer(Divider().foregroundStyle(faded(.ansi(.red), 128)), width: 0, height: 1)
            .opacityRegions.isEmpty)
    }

    // MARK: - Spinner

    @Test("A spinner's glyph claims its own cells at its own alpha")
    func spinnerGlyph() throws {
        let drawn = buffer(Spinner().foregroundStyle(faded(.ansi(.red), 128)), width: 10, height: 1)
        let claim = try #require(drawn.opacityRegions.first)
        #expect(claim.offsetX == 0)
        #expect(claim.width > 0, "the glyph's width")
        #expect(claim.inkOpacity == 128.0 / 255)
        // The claim has to be valid for every frame the run will splice, not just
        // the one drawn now — which it is, because every frame of a spinner's
        // cycle is the same colour and only the glyph changes.
        #expect(!drawn.animatedCells.isEmpty, "the premise: this style animates")
    }

    @Test("A spinner's label is its own claim, in its own colour")
    func spinnerLabel() {
        // The label is drawn in the palette's foreground, not in the spinner's
        // colour, so one region over both would fade it at the wrong alpha.
        let drawn = buffer(
            Spinner("Loading").foregroundStyle(faded(.ansi(.red), 128)), width: 20, height: 1)
        #expect(
            drawn.opacityRegions.count == 1,
            "an opaque label adds no claim of its own: \(drawn.opacityRegions)")
        let glyph = drawn.opacityRegions[0]
        #expect(glyph.offsetX == 0, "and the claim that IS there is the glyph's")
        #expect(glyph.width < 20, "not the whole row")
    }

    @Test("An opaque spinner claims nothing")
    func opaqueSpinner() {
        #expect(buffer(Spinner(), width: 10, height: 1).opacityRegions.isEmpty)
    }

    @Test("A bouncing spinner SPENDS its alpha rather than claiming it")
    func bouncingSpinnerSpends() throws {
        // Its trail lerps a different colour into every cell of every frame, so no
        // rectangle can say what is true and the run's one static claim per cell
        // cannot exist. This used to be left unhonoured on purpose — its frames
        // reached the emitter as they were, so the assertion in
        // `Color+ANSICodes.swift` fired rather than a wrong colour appearing
        // silently. It fired for real, on the example's own page, under a faded
        // palette (§68.6), so the decision changed: both ends of the ramp are now
        // spent against the page, which is §29's remedy for a pair that cannot agree
        // about alpha, and is what `trackColor` was already doing beside it. Per-CELL
        // claims stay declined; this is what replaces the trap, not them.
        try withColorDepth(.truecolor) {
            // Its own context, because the spent colour depends on the ground it was
            // spent over and that is this palette's background, not a named default's.
            let context = RenderContext(
                availableWidth: 20, availableHeight: 1, tuiContext: TUIContext()
            ).isolatingRenderCache()
            let palette = context.environment.palette
            let tint = Color.ansi(.red).opacity(0.5)
            let drawn = renderToBuffer(
                Spinner(style: .bouncing).foregroundStyle(tint), context: context)
            #expect(drawn.opacityRegions.isEmpty, "a spent ramp claims nothing")
            let run = try #require(drawn.animatedCells.first, "the track animates")
            // The head is drawn in the tint SPENT against the page, and the raw tint —
            // whose bytes are plain red, alpha living nowhere in them — appears in no
            // frame at all. Not every frame has a head: the bounce's turnaround holds
            // the highlight off the track for a few, leaving only trail cells.
            let spent = code(tint.spendingAlpha(over: palette.background), palette)
            #expect(
                run.frames.contains { $0.contains(spent) }, "the head states the spent colour")
            #expect(
                !run.frames.contains { $0.contains(code(Color.ansi(.red), palette)) },
                "and no frame states the unspent one")
        }
    }

    // MARK: - Resolution, end to end

    @Test("A faded rule resolves against what is behind it")
    func ruleResolves() {
        let context = makeRenderContext(width: 7, height: 1)
        let drawn = buffer(Divider().foregroundStyle(faded(.ansi(.red), 128)), width: 7, height: 1)
        let resolved = drawn.resolvingOpacity(
            surface: .ansi(.blue), palette: context.environment.palette)
        let halfway = Color.ansi(.red).opacity(128.0 / 255, over: .ansi(.blue))
            .foregroundCodes().joined(separator: ";")
        #expect(
            resolved.lines[0].contains(halfway),
            "halfway to the backdrop: \(resolved.lines[0].debugDescription)")
    }
}
