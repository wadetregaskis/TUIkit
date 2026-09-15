//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RampAlphaShapeTests.swift
//
//  The two ramp cases §16.3 listed as not honoured: `Text`'s ramped INK, and a
//  ramp whose alpha varies along a row. One of those turns out to have been two
//  cases wearing one name.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A ramp's alpha, by shape")
struct RampAlphaShapeTests {

    private func buffer<V: View>(_ view: V, width: Int = 12, height: Int = 4) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    private func sampler(_ gradient: LinearGradient, width: Int, height: Int) -> RampSampler? {
        RampSampler(
            paint: gradient.paint(in: EnvironmentValues()),
            extent: GradientFrame(width: width, height: height), depth: .truecolor, cellAspect: 2)
    }

    private var faded: Color { Color.rgb(200, 40, 40).opacity(0.5) }
    private var half: Double { 128.0 / 255 }

    // MARK: - The taxonomy

    /// **A horizontal ramp was classified `perCell` and declined for a cost it does
    /// not have.**
    ///
    /// The classifier asked only whether the colour varies ACROSS a row. It does, for
    /// a horizontal ramp — but the colour is the same all the way DOWN each column, so
    /// its alpha is one full-height rectangle per column, which is the mirror of
    /// `perRow` and every bit as cheap. `variesDownColumn` is the fact that was
    /// missing, and it sits beside its twin so the two cannot drift.
    @Test("A horizontal ramp is perColumn, not perCell")
    func horizontalRampIsPerColumn() throws {
        let ramp = try #require(
            sampler(
                LinearGradient(
                    colors: [faded, Color.rgb(40, 40, 200)],
                    startPoint: .leading, endPoint: .trailing),
                width: 20, height: 4))
        #expect(ramp.variesAcrossRow)
        #expect(!ramp.variesDownColumn)
        #expect(ramp.alphaShape == .perColumn)
    }

    /// `perCell` is still its own case after §36 honoured it, because the two shapes
    /// cost different amounts: `perColumn` is answered once for the block and
    /// `perCell` once per row. Telling them apart is free, so it is worth doing.
    @Test("A vertical ramp is perRow, and a diagonal one is perCell")
    func theOtherShapes() throws {
        let vertical = try #require(
            sampler(
                LinearGradient(colors: [faded, .rgb(40, 40, 200)], startPoint: .top, endPoint: .bottom),
                width: 20, height: 4))
        #expect(vertical.alphaShape == .perRow)
        let diagonal = try #require(
            sampler(
                LinearGradient(
                    colors: [faded, .rgb(40, 40, 200)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                width: 20, height: 4))
        #expect(diagonal.alphaShape == .perCell)
    }

    /// `runs(row:cells:)` breaks at every change of ramp ENTRY, which is right for
    /// emitting colour and wrong for a claim: adjacent entries usually share an alpha,
    /// so one claim per colour run over-splits. `alphaRuns` coalesces on the alpha.
    @Test("alphaRuns coalesces where runs does not")
    func alphaRunsCoalesce() throws {
        var blue = Color.rgb(40, 40, 200)
        blue.alpha = 128
        let ramp = try #require(
            sampler(
                LinearGradient(colors: [faded, blue], startPoint: .leading, endPoint: .trailing),
                width: 40, height: 2))
        // Both ends at one alpha, so `Color.lerp` holds it constant across the ramp.
        #expect(ramp.alphaShape == .uniform(128))
        let colourRuns = ramp.runs(row: 0, cells: 40)
        let alphaRuns = ramp.alphaRuns(row: 0, columns: 0..<40)
        #expect(colourRuns.count > 1, "the colour really does change: \(colourRuns.count)")
        #expect(alphaRuns.count == 1, "one rectangle, not \(alphaRuns.count)")
        #expect(alphaRuns.first?.alpha == 128)
    }

    // MARK: - `.background` gains the new shape

    @Test("A horizontal translucent ramp background claims full-height strips")
    func horizontalBackgroundClaims() {
        let drawn = buffer(
            Text("hello").background(
                LinearGradient(
                    colors: [faded, Color.rgb(40, 40, 200)],
                    startPoint: .leading, endPoint: .trailing)))
        #expect(!drawn.opacityRegions.isEmpty, "declined as perCell before: \(drawn.opacityRegions)")
        #expect(
            drawn.opacityRegions.allSatisfy { $0.height == drawn.lines.count },
            "full-height strips: \(drawn.opacityRegions)")
        #expect(drawn.opacityRegions.allSatisfy { $0.inkOpacity == 1 }, "field claims only")
    }

    // MARK: - `Text`'s ramped ink

    /// §16.3 listed "`Text`'s ramped ink" as not honoured, and it was — for all FOUR
    /// alpha shapes, not just the per-cell one, because `PaintRenderer.styled` returned
    /// bytes and nothing else. A uniformly faded ramp on ink is one rectangle per line.
    @Test("A uniformly faded ramp on ink claims one rectangle per line")
    func rampedInkUniformClaims() {
        var blue = Color.rgb(40, 40, 200)
        blue.alpha = 128
        let drawn = buffer(
            Text("hello\nworld").foregroundStyle(
                LinearGradient(colors: [faded, blue], startPoint: .leading, endPoint: .trailing)))
        #expect(drawn.opacityRegions.count == 2, "one per line: \(drawn.opacityRegions)")
        #expect(drawn.opacityRegions.allSatisfy { $0.inkOpacity == half }, "\(drawn.opacityRegions)")
        #expect(drawn.opacityRegions.allSatisfy { $0.fieldOpacity == 1 }, "ink claims only")
    }

    @Test("A vertical ramp on ink claims per line, at that line's own alpha")
    func rampedInkPerRowClaims() {
        let drawn = buffer(
            Text("hello\nworld").foregroundStyle(
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)))
        let sorted = drawn.opacityRegions.sorted { $0.offsetY < $1.offsetY }
        #expect(sorted.count >= 1, "\(drawn.opacityRegions)")
        // Descending down the block, which is what makes it a fade rather than a wash.
        #expect(
            zip(sorted, sorted.dropFirst()).allSatisfy { $0.inkOpacity >= $1.inkOpacity },
            "\(sorted.map(\.inkOpacity))")
    }

    /// A claim must not outrun the line it is about: a text block is ragged, so a
    /// short line's claim stops at its own width and not at the block's.
    @Test("A ramped claim stops at its own line's width")
    func rampedClaimDoesNotOutrunItsLine() {
        var blue = Color.rgb(40, 40, 200)
        blue.alpha = 128
        let drawn = buffer(
            Text("hi\nlonger").foregroundStyle(
                LinearGradient(colors: [faded, blue], startPoint: .leading, endPoint: .trailing)),
            width: 20)
        let sorted = drawn.opacityRegions.sorted { $0.offsetY < $1.offsetY }
        #expect(sorted.count == 2, "\(drawn.opacityRegions)")
        #expect(sorted.first?.width == 2, "\"hi\": \(sorted)")
        #expect(sorted.last?.width == 6, "\"longer\": \(sorted)")
    }

    /// **The field is a rectangle whether or not the ink over it is one.**
    ///
    /// An earlier version of this folded the field's alpha into the ramp's `AlphaShape`
    /// and got both ends wrong: an OPAQUE ramp over a faded background reported
    /// `.opaque` and claimed nothing at all, and a per-cell one left the background's
    /// own bytes translucent while claiming it — a double fade in release and an
    /// assertion in debug, on a path that IS honoured. The field is now always claimed
    /// and always spelled opaque, and the ramp's own colours are spelled opaque by `band` itself.
    @Test("An opaque ramp over a faded cascade background still claims the field")
    func opaqueRampStillClaimsItsField() throws {
        let drawn = buffer(
            Text("hello")
                .foregroundStyle(
                    LinearGradient(
                        colors: [.rgb(200, 40, 40), .rgb(40, 40, 200)],
                        startPoint: .leading, endPoint: .trailing))
                .style(.text) { $0.background = Color.rgb(10, 10, 10).opacity(0.5) })
        let claim = try #require(drawn.opacityRegions.first, "\(drawn.opacityRegions)")
        #expect(claim.fieldOpacity == half, "\(claim)")
        #expect(claim.inkOpacity == 1, "the ramp itself is opaque: \(claim)")
        #expect(
            drawn.lines.joined().contains("48;2;10;10;10"),
            "the field's bytes must be its opaque spelling: \(drawn.lines)")
    }

    /// A ONE-STOP gradient is not a ramp — `RampSampler.init?` refuses it — and
    /// `Paint.solid` does not divert it either, so it came through the flat fallback
    /// and rendered at full strength.
    @Test("A one-stop translucent gradient on ink is claimed by the flat arm")
    func oneStopGradientClaims() {
        let drawn = buffer(
            Text("hello").foregroundStyle(
                LinearGradient(colors: [faded], startPoint: .leading, endPoint: .trailing)))
        #expect(!drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
        #expect(drawn.opacityRegions.allSatisfy { $0.inkOpacity == half }, "\(drawn.opacityRegions)")
    }

    // MARK: - The shape that varies in both directions (§36)

    /// **A diagonal ramp's ink was unclaimed and LOUD, and this test could not exist.**
    ///
    /// Rendering one used to trap the suite: the bytes were left unspelled on purpose,
    /// so the emitter's debug assertion fired, and an assertion is a trap rather than a
    /// throw. That it runs at all is half the assertion.
    ///
    /// The claim is a run of equal alpha per ROW. Not one rectangle per cell: the ramp
    /// is quantised, so neighbouring columns often land on the same entry and always on
    /// the same alpha for stretches of it — which is the difference between the count
    /// this costs and the count §34.3 estimated.
    @Test("A diagonal ramp on ink claims runs per row, and spells its bytes opaque")
    func diagonalRampedInkClaims() {
        let drawn = buffer(
            Text("hello there\nsecond line\nthird line!").foregroundStyle(
                LinearGradient(
                    colors: [faded, Color.rgb(40, 40, 200).opacity(0.1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)),
            width: 12, height: 4)
        #expect(!drawn.opacityRegions.isEmpty, "declined before §36: \(drawn.opacityRegions)")
        #expect(
            drawn.opacityRegions.allSatisfy { $0.height == 1 },
            "a run cannot span rows that disagree: \(drawn.opacityRegions)")
        // Every row of the block, and every claim translucent — an opaque run would
        // have been dropped by `claim`'s nil contract, which is right here because
        // these rectangles are a set and not a sequence.
        #expect(Set(drawn.opacityRegions.map(\.offsetY)).count == 3, "\(drawn.opacityRegions)")
        #expect(drawn.opacityRegions.allSatisfy { $0.inkOpacity < 1 })
        // And the two directions really do disagree, or this is `perColumn` in disguise.
        let byRow = Dictionary(grouping: drawn.opacityRegions, by: \.offsetY)
        let firstRowAlphas = (byRow[0] ?? []).map(\.inkOpacity)
        let lastRowAlphas = (byRow[2] ?? []).map(\.inkOpacity)
        #expect(firstRowAlphas != lastRowAlphas, "\(firstRowAlphas) vs \(lastRowAlphas)")
    }

    /// The field twin, in `BackgroundModifier` rather than `PaintRenderer` — a second
    /// derivation of the same shape, which is why it gets its own assertion.
    @Test("A radial translucent ramp background claims per row")
    func radialBackgroundClaims() {
        let drawn = buffer(
            Text("hello\nworld").background(
                RadialGradient(
                    gradient: Gradient(colors: [faded, Color.rgb(40, 40, 200).opacity(0.1)]),
                    center: .center, startRadius: 0, endRadius: 6)),
            width: 12, height: 4)
        #expect(!drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
        #expect(
            drawn.opacityRegions.allSatisfy { $0.height == 1 && $0.inkOpacity == 1 },
            "field claims, a row at a time: \(drawn.opacityRegions)")
        #expect(Set(drawn.opacityRegions.map(\.offsetY)).count == drawn.lines.count)
    }

    /// `alphaRuns` takes a column RANGE because a `Table` claims the span its cells
    /// occupy, which starts past the selection gutter. A run that began at column 0
    /// would state each cell's alpha one column to the left of where it was painted.
    @Test("alphaRuns over a span reports that span's own columns and alphas")
    func alphaRunsHonourTheirOffset() throws {
        let ramp = try #require(
            sampler(
                LinearGradient(
                    colors: [faded, Color.rgb(40, 40, 200).opacity(0.1)],
                    startPoint: .leading, endPoint: .trailing),
                width: 20, height: 2))
        let whole = ramp.alphaRuns(row: 0, columns: 0..<20)
        let span = ramp.alphaRuns(row: 0, columns: 4..<20)
        #expect(span.first?.columns.lowerBound == 4, "\(span)")
        #expect(span.last?.columns.upperBound == 20, "\(span)")
        // The alpha at a given column is the same question either way, so the span's
        // runs are the whole row's runs clipped — never re-derived from column zero.
        for run in span {
            let expected = whole.first { $0.columns.contains(run.columns.lowerBound) }?.alpha
            #expect(run.alpha == expected, "column \(run.columns.lowerBound): \(span) vs \(whole)")
        }
        #expect(ramp.alphaRuns(row: 0, columns: 4..<4).isEmpty, "an empty span claims nothing")
    }
}
