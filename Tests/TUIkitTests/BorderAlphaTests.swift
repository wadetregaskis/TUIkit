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

    /// Frames at different alphas share no claim, so the border states no REGION of its
    /// own — and states the alpha per frame on the runs instead (§69). It keeps its runs,
    /// so it still must not ask to be rendered every tick: a pass-wide request outlives a
    /// render whose buffer is thrown away (§59.2), which is why declining the run was
    /// never the answer. The faded frame now blends, which is what §59.2 left open.
    @Test("An animating border at several alphas blends each frame at its own alpha")
    func animatingSeveralAlphasBlendsPerFrame() throws {
        let tracker = VolatileReadTracker()
        let drawn = bordered(AnimatedColor(frames: [.red, faded(.green, 128)], step: 0), tracker: tracker)
        #expect(!drawn.animatedCells.isEmpty, "its frames are replayed")
        #expect(tracker.reads == 0, "the border asked to be rendered every tick")
        // No region of its own: the opaque frame would be faded by any rectangle that
        // described the translucent one, which is why this arm claims per frame instead.
        let carried = drawn.opacityRegions.filter { $0.offsetY == 0 }
        #expect(carried.isEmpty, "the border states no static claim here: \(carried)")

        let resolved = drawn.resolvingOpacity(surface: .blue, palette: EnvironmentValues().palette)
        let top = try #require(resolved.animatedCells.first { $0.offsetY == 0 }, "the top rule")
        let blended = Color.green.opacity(128.0 / 255, over: .blue).foregroundCodes().joined(separator: ";")
        #expect(
            top.frames[1].contains(blended),
            "the faded frame is blended: \(top.frames[1].debugDescription)")
        // And the opaque frame is untouched — the point of stating them separately.
        let plainRed = Color.red.foregroundCodes().joined(separator: ";")
        #expect(
            top.frames[0].contains(plainRed),
            "the opaque frame keeps its colour: \(top.frames[0].debugDescription)")
        #expect(resolved.animatedCells.allSatisfy { $0.alpha == nil }, "every payload is spent")
    }

    /// An ANCESTOR's translucent claim over a run carrying per-frame alpha composes; it
    /// is not a producer stating both.
    ///
    /// The resolver used to assert that no ink or field claim covered a run with a
    /// translucent payload, to catch one producer double-stating its alpha. But it sees
    /// the sum of every producer, and `.background(Color.blue.opacity(0.5))` states a
    /// field claim over the whole box — border rows included — for an entirely legitimate
    /// reason. The multiply the resolver then performs is the right answer, and the
    /// assertion trapped every debug build that wrapped an animated border (or a focused
    /// text field's caret) in a translucent background.
    @Test("A translucent background over a multi-alpha border composes without trapping")
    func translucentBackgroundOverAMultiAlphaBorderComposes() throws {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 12, availableHeight: 3, environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
        let drawn = renderToBuffer(
            Text("hi")
                .border(AnimatedColor(frames: [.red, faded(.green, 128)], step: 0))
                .background(Color.blue.opacity(0.5)),
            context: context)
        let backgroundCoversTheRule = drawn.opacityRegions.contains { $0.offsetY == 0 && $0.fieldOpacity < 1 }
        #expect(backgroundCoversTheRule, "the precondition: an ancestor claim over the rule")

        let resolved = drawn.resolvingOpacity(surface: .black, palette: EnvironmentValues().palette)

        let top = try #require(resolved.animatedCells.first { $0.offsetY == 0 }, "the top rule")
        let plainGreen = Color.green.foregroundCodes().joined(separator: ";")
        #expect(
            !top.frames[1].contains(plainGreen),
            "the translucent frame is blended, not drawn at full strength: \(top.frames[1].debugDescription)")
        let spent = resolved.animatedCells.allSatisfy { $0.alpha == nil }
        #expect(spent, "every payload is spent")
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

    // MARK: - A container with no border (§65)

    /// Every slot opaque but the border's, so a plain list's footer rule, drawn in it,
    /// is what owes an alpha — and its title, in the accent, does not.
    private struct FadedBorder: Palette {
        let id = "faded-border"
        let name = "Faded border"
        let background = Color.rgb(10, 10, 20)
        let foreground = Color.rgb(230, 230, 240)
        let accent = Color.rgb(0, 180, 200)
        let success = Color.rgb(40, 200, 40)
        let warning = Color.rgb(220, 200, 40)
        let error = Color.rgb(220, 40, 40)
        let info = Color.rgb(40, 120, 220)
        let border = Color.rgb(120, 120, 130).opacity(0.5)
    }

    /// A plain list's buffer under `palette`, twenty cells wide.
    private func plain<V: View>(_ list: V, palette: any Palette, height: Int) -> FrameBuffer {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = palette
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 20, availableHeight: height, environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
        return renderToBuffer(list.listStyle(.plain), context: context)
    }

    /// A plain list draws its title on a line of its own, in the accent by default —
    /// which a faded tint fades. It went to the emitter unclaimed (§65).
    @Test("A plain list's title claims a faded tint's alpha")
    func plainListTitleClaims() throws {
        let drawn = plain(
            List("Items", selection: Binding<Int?>.constant(nil)) { Text("a") }.tint(faded(.red, 128)),
            palette: SystemPalette.default, height: 5)
        try #require(drawn.lines.first?.stripped.hasPrefix("Items") == true, "\(drawn.lines.map(\.stripped))")
        for column in 0..<5 {
            let owes = owed(atColumn: column, row: 0, in: drawn)
            #expect(owes.ink == 128.0 / 255 && owes.field == 1, "title (\(column), 0) owes \(owes)")
        }
    }

    /// Above a footer, a plain list draws a full-width rule in the border's colour —
    /// which a faded palette fades. It went to the emitter unclaimed too (§65).
    @Test("A plain list's footer rule claims a faded border's alpha")
    func plainListFooterRuleClaims() throws {
        let palette = FadedBorder()
        let drawn = plain(
            List("Items", selection: Binding<Int?>.constant(nil)) { Text("a") } footer: { Text("f") },
            palette: palette, height: 8)
        let row = try #require(
            drawn.lines.firstIndex { !$0.stripped.isEmpty && $0.stripped.allSatisfy { $0 == "─" } },
            "no rule: \(drawn.lines.map(\.stripped))")
        for column in 0..<drawn.lines[row].stripped.count {
            let owes = owed(atColumn: column, row: row, in: drawn)
            #expect(owes.ink == owed(palette.border) && owes.field == 1, "rule (\(column), \(row)) owes \(owes)")
        }
    }
}
