//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BorderAlphaTests.swift
//
//  `.border(.red.opacity(0.5))` — the entry point with the most emit sites
//  behind it, and the one whose claim is a frame rather than a rectangle.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A translucent border")
struct BorderAlphaTests {

    private func faded(_ base: Color, _ alpha: UInt8) -> Color {
        var colour = base
        colour.alpha = alpha
        return colour
    }

    /// Every cell of a box, as `(column, row)`, so a claim set can be checked for
    /// covering each exactly once.
    private func covered(_ claims: [OpacityRegion]) -> [(x: Int, y: Int)] {
        claims.flatMap { claim in
            (claim.offsetY..<(claim.offsetY + claim.height)).flatMap { y in
                (claim.offsetX..<(claim.offsetX + claim.width)).map { (x: $0, y: y) }
            }
        }
    }

    // MARK: - The frame, and only the frame

    @Test("The claim is the frame, not the box")
    func frameNotBox() {
        let claims = BorderRenderer.opacityClaims(
            outerWidth: 6, height: 4, style: .line, color: faded(.red, 128))
        let cells = covered(claims)
        // The interior — where the CONTENT is — must be untouched. A single region
        // over the whole box would fade the very thing the border was drawn
        // around, which no colour asked for.
        for y in 1..<3 {
            for x in 1..<5 {
                #expect(
                    !cells.contains { $0.x == x && $0.y == y },
                    "interior cell (\(x), \(y)) must not be claimed")
            }
        }
        // …and every frame cell must be claimed.
        let frame =
            (0..<6).map { (x: $0, y: 0) } + (0..<6).map { (x: $0, y: 3) }
            + (1..<3).flatMap { [(x: 0, y: $0), (x: 5, y: $0)] }
        for cell in frame {
            #expect(
                cells.contains { $0.x == cell.x && $0.y == cell.y },
                "frame cell \(cell) must be claimed")
        }
    }

    @Test("No cell is claimed twice, so no alpha is squared")
    func noDoubleClaims() {
        // Overlapping claims MULTIPLY at the resolver, so a cell claimed twice at
        // 0.5 resolves at 0.25 — a visibly darker pip. The shapes that invite it
        // are a divider row crossing the walls and a box small enough that its
        // bands coincide.
        // A box holds at most one `├───┤` — the footer separator — which is why
        // `dividerRow` is an `Int?`. The out-of-range values are in the sweep because
        // a caller computing one from a footer's position can hand over a row that is
        // the bottom band, and claiming that row twice is the failure this guards.
        let shapes: [(width: Int, height: Int, divider: Int?)] = [
            (6, 4, nil), (6, 5, 2), (1, 4, nil), (6, 1, nil), (1, 1, nil), (2, 2, nil),
            (8, 6, 3), (6, 4, 0), (6, 4, 3), (6, 4, 99),
        ]
        for shape in shapes {
            let claims = BorderRenderer.opacityClaims(
                outerWidth: shape.width, height: shape.height, style: .line,
                color: faded(.red, 128), dividerRow: shape.divider)
            let cells = covered(claims)
            let unique = Set(cells.map { "\($0.x),\($0.y)" })
            #expect(
                cells.count == unique.count,
                "\(shape): \(cells.count) claims over \(unique.count) cells")
        }
    }

    @Test("An opaque border claims nothing at all")
    func opaqueClaimsNothing() {
        #expect(
            BorderRenderer.opacityClaims(
                outerWidth: 6, height: 4, style: .line, color: .red
            ).isEmpty)
        // …including a titled one whose title is also opaque.
        #expect(
            BorderRenderer.opacityClaims(
                outerWidth: 12, height: 4, style: .line, color: .red, title: "Hi",
                titleColor: .blue
            ).isEmpty)
    }

    // MARK: - The title and the dot are their own ink

    @Test("A faded border with an opaque title leaves the letters alone")
    func opaqueTitleInFadedBand() {
        let claims = BorderRenderer.opacityClaims(
            outerWidth: 14, height: 3, style: .line, color: faded(.red, 128),
            title: "Hi", titleColor: .blue)
        // `╭─ Hi ────────╮` — the title span is cells 2 through 5 (" Hi ").
        let topRow = claims.filter { $0.offsetY == 0 }
        let titleCells = covered(topRow).filter { (2...5).contains($0.x) && $0.y == 0 }
        #expect(titleCells.isEmpty, "the title's own cells carry no claim")
        // The band either side of it does.
        let bandCells = covered(topRow).filter { $0.y == 0 }.map(\.x)
        #expect(bandCells.contains(0), "the corner is claimed")
        #expect(bandCells.contains(13), "so is the far corner")
    }

    @Test("An opaque border with a faded title fades only the letters")
    func fadedTitleInOpaqueBand() throws {
        let claims = BorderRenderer.opacityClaims(
            outerWidth: 14, height: 3, style: .line, color: .red, title: "Hi",
            titleColor: faded(.blue, 64))
        let claim = try #require(claims.first, "the title span is claimed")
        #expect(claims.count == 1, "and nothing else is: \(claims)")
        #expect(claim.offsetX == 2)
        #expect(claim.width == 4, "` Hi ` — the padding is painted in the band too")
        #expect(claim.inkOpacity == 64.0 / 255)
        #expect(claim.fieldOpacity == 1, ".line paints no field")
    }

    @Test("A title truncated by a narrow box is claimed at the width it was drawn")
    func truncatedTitle() throws {
        // Claimed from `fittedTitle`, the same call the band draws through. From
        // the untruncated title it would fade cells the title never reached — and
        // past the far corner, where nothing of this box exists at all.
        let outerWidth = 10
        let claims = BorderRenderer.opacityClaims(
            outerWidth: outerWidth, height: 3, style: .line, color: .red,
            title: "A very long title indeed", titleColor: faded(.blue, 64))
        let claim = try #require(claims.first)
        #expect(claim.offsetX + claim.width <= outerWidth, "inside the box: \(claim)")
    }

    @Test("A blank title collapses, and claims nothing of its own")
    func blankTitle() {
        // `fittedTitle` answers nil, the band is drawn continuous, and the claim
        // agrees — otherwise four cells in the middle of an unbroken band would
        // resolve at the title colour's alpha.
        let claims = BorderRenderer.opacityClaims(
            outerWidth: 14, height: 3, style: .line, color: .red, title: "   ",
            titleColor: faded(.blue, 64))
        #expect(claims.isEmpty, "\(claims)")
    }

    @Test("A style that paints its cells claims the field too")
    func paintedBand() throws {
        // `.block` is a band of colour rather than a line, so its cells have a
        // field as well as a glyph, and both are the border colour.
        #expect(BorderStyle.block.paintsBackground, "the premise of this test")
        let claims = BorderRenderer.opacityClaims(
            outerWidth: 6, height: 3, style: .block, color: faded(.red, 128))
        let claim = try #require(claims.first)
        #expect(claim.fieldOpacity == 128.0 / 255)
        #expect(claim.inkOpacity == 128.0 / 255)
        // …and a line style says nothing about a field, so a faded `.border`
        // leaves the gaps between its glyphs alone.
        let line = try #require(
            BorderRenderer.opacityClaims(
                outerWidth: 6, height: 3, style: .line, color: faded(.red, 128)
            ).first)
        #expect(line.fieldOpacity == 1)
    }

    // MARK: - End to end

    @Test("`.border` sends its alpha up as a region and its colour at full strength")
    func borderModifierClaims() {
        let context = RenderContext(
            availableWidth: 12, availableHeight: 3, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(
            Text("hi").border(faded(.red, 128)), context: context)
        #expect(!buffer.opacityRegions.isEmpty, "the frame is claimed")
        // The BYTES are the colour at full strength: an SGR emitter has no
        // backdrop, so a translucent one there is a debug trap rather than a
        // blend. The alpha is in the region instead.
        let opaque = Color.red.foregroundCodes().joined(separator: ";")
        #expect(
            buffer.lines[0].contains(opaque),
            "the top band states the opaque spelling: \(buffer.lines[0].debugDescription)")
        // Nothing claims the interior, where the text is.
        let interior = covered(buffer.opacityRegions).filter { $0.x == 1 && $0.y == 1 }
        #expect(interior.isEmpty, "the text inside the box is not faded")
    }

    @Test("An opaque `.border` still claims nothing")
    func opaqueBorderModifier() {
        let context = RenderContext(
            availableWidth: 12, availableHeight: 3, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(Text("hi").border(.red), context: context)
        #expect(buffer.opacityRegions.isEmpty)
    }

    @Test("A faded border resolves against what is actually behind it")
    func resolvesAgainstBackdrop() {
        let context = RenderContext(
            availableWidth: 12, availableHeight: 3, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(
            Text("hi").border(faded(.red, 128)), context: context)
        // The frame is drawn over nothing, so the backdrop the band blends toward
        // is the ambient SURFACE — which is exactly the case the old render-time
        // fade guessed at, and got right only over an empty page.
        let resolved = buffer.resolvingOpacity(
            surface: .blue, palette: context.environment.palette)
        let halfway = Color.red.opacity(128.0 / 255, over: .blue)
            .foregroundCodes().joined(separator: ";")
        let band = resolved.lines[0]
        #expect(
            band.contains(halfway),
            "the band is halfway to the backdrop: \(band.debugDescription)")
    }

    // MARK: - An animating border (§59)

    /// `Text("hi")` in a border of `colour`, rendered with a volatile-read tracker so a
    /// test can see whether the border asked to be drawn again.
    private func bordered(
        _ colour: AnimatedColor, tracker: VolatileReadTracker = VolatileReadTracker()
    ) -> FrameBuffer {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.volatileReadTracker = tracker
        let context = RenderContext(
            availableWidth: 12, availableHeight: 3, environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
        return renderToBuffer(Text("hi").border(colour), context: context)
    }

    @Test("An animated colour is one alpha only when every frame is")
    func hasOneAlpha() {
        #expect(AnimatedColor(faded(.red, 128)).hasOneAlpha)
        #expect(AnimatedColor(frames: [faded(.red, 128), faded(.green, 128)], step: 0).hasOneAlpha)
        #expect(AnimatedColor(frames: [.red, .green], step: 0).hasOneAlpha)
        #expect(!AnimatedColor(frames: [.red, faded(.blue, 128)], step: 0).hasOneAlpha)
    }

    /// The type's own documented breath, from `border` to `accent`. A faded tint fades
    /// only the accent, so its frames disagree; a palette fading both alike does not.
    @Test("The documented focus breath is one alpha only where its two slots agree")
    func documentedBreath() {
        let emphasis = EnvironmentValues().selectionEmphasis
        let tinted = TintedPalette(base: SystemPalette.default, tint: Color.red.opacity(0.5))
        let breath = emphasis.animatedColor(true, dim: tinted.border, bright: tinted.accent)
        #expect(breath.isAnimating && !breath.hasOneAlpha, "\(breath.frames.map(\.alpha))")
        let palette = FadedAll()
        #expect(emphasis.animatedColor(true, dim: palette.border, bright: palette.accent).hasOneAlpha)
    }

    /// A border whose frames share one alpha keeps its runs and claims what a still
    /// border in its first frame's colour claims, which every frame owes. It claimed
    /// nothing while it animated, and the alpha went in silence (§59).
    @Test("An animating border at one alpha keeps its runs and claims its frame")
    func animatingOneAlphaClaims() {
        let tracker = VolatileReadTracker()
        let breathing = bordered(
            AnimatedColor(frames: [faded(.red, 128), faded(.green, 128)], step: 0), tracker: tracker)
        let still = bordered(AnimatedColor(faded(.red, 128)))
        #expect(!breathing.animatedCells.isEmpty, "its frames are replayed")
        #expect(!still.opacityRegions.isEmpty, "the premise: a faded frame is claimed")
        #expect(breathing.opacityRegions == still.opacityRegions, "\(breathing.opacityRegions)")
        #expect(tracker.reads == 0, "a replayed border asks for no render")
    }

    /// Frames at different alphas share no claim, so the border states none of its own and
    /// keeps its runs: the open arm (§59.2). Pinned both ways. It must not ask to be
    /// rendered every tick — a pass-wide request outlives a render whose buffer is thrown
    /// away — and it does not yet blend its faded frame, which the known issue records.
    @Test("An animating border at several alphas keeps its runs and asks for no render")
    func animatingSeveralAlphasStaysOpen() {
        let tracker = VolatileReadTracker()
        let drawn = bordered(AnimatedColor(frames: [.red, faded(.green, 128)], step: 0), tracker: tracker)
        #expect(!drawn.animatedCells.isEmpty, "its frames are replayed")
        #expect(tracker.reads == 0, "the border asked to be rendered every tick")
        let resolved = drawn.resolvingOpacity(surface: .blue, palette: EnvironmentValues().palette)
        let top = resolved.animatedCells.first { $0.offsetY == 0 }
        let blended = Color.green.opacity(128.0 / 255, over: .blue).foregroundCodes().joined(separator: ";")
        withKnownIssue("frames at several alphas are not blended (§59.2)") {
            #expect(
                top?.frames[1].contains(blended) == true,
                "\(top?.frames[1].debugDescription ?? "no top run")")
        }
    }

    /// A replayed frame is blended as the drawn line is: each against the backdrop, at
    /// the one claim they share.
    @Test("A one-alpha border's replayed frames resolve against the backdrop")
    func replayedFramesResolve() throws {
        let drawn = bordered(AnimatedColor(frames: [faded(.red, 128), faded(.green, 128)], step: 0))
        let resolved = drawn.resolvingOpacity(surface: .blue, palette: EnvironmentValues().palette)
        let top = try #require(resolved.animatedCells.first { $0.offsetY == 0 }, "the top band's run")
        for (index, colour) in [Color.red, .green].enumerated() {
            let blended = colour.opacity(128.0 / 255, over: .blue).foregroundCodes().joined(separator: ";")
            #expect(
                top.frames[index].contains(blended),
                "frame \(index): \(top.frames[index].debugDescription)")
        }
    }
}
