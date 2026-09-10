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

    /// The declined shape has no render-level test, and cannot have one: leaving it
    /// unclaimed is exactly what makes the emitter's debug assertion fire, and an
    /// assertion is a trap rather than a throw. Rendering a diagonal translucent ramp
    /// here crashes the suite — which is the design working. So the decline is
    /// asserted at the classifier, where it is a value rather than a trap.
    @Test("A vertical ramp is still perRow, and a diagonal one is still perCell")
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
        let alphaRuns = ramp.alphaRuns(row: 0, cells: 40)
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
    /// and always spelled opaque, and `carriesAlpha` governs the ramp alone.
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
}
