//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackGradientTests.swift
//
//  Gradient colour support across the track family: `.threeSegment`'s
//  SegmentColoring (solid / per-segment / gradient), and the customisable
//  indeterminate gradient — all sharing one stop model ([Color], ≥ 2 stops).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Track gradient colouring")
struct TrackGradientTests {

    /// Renders a threeSegment track at 60% of 20 cells with the given coloring.
    private func render(_ coloring: SegmentColoring) -> String {
        TrackRenderer.render(
            fraction: 0.6, width: 20,
            style: .threeSegment(
                leading: "Sw", middle: "i", trailing: "ft", emptyFill: "·",
                coloring: coloring),
            filledColor: .rgb(1, 2, 3),
            emptyColor: .rgb(9, 9, 9),
            accentColor: .rgb(7, 7, 7),
            palette: SystemPalette.green).text
    }

    /// `span` counts cells and a segment can be any string, so a wide glyph
    /// covers two. Stepping the ramp per CHARACTER traversed it at half rate
    /// and never emitted its last stops.
    @Test("A gradient over wide glyphs reaches its last stop")
    func gradientOverWideGlyphsReachesTheEnd() {
        let full = TrackRenderer.render(
            fraction: 1.0, width: 20,
            style: .threeSegment(
                leading: "🌑", middle: "🌕", trailing: "🌖", emptyFill: "·",
                coloring: .gradient(Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)]))),
            filledColor: .rgb(1, 2, 3), emptyColor: .rgb(9, 9, 9), accentColor: .rgb(7, 7, 7),
            palette: SystemPalette.green).text
        // A wide glyph is coloured at its FIRST cell, so the last glyph (cells
        // 18–19) wears ramp[18] of 20 — not the final stop itself, but eighteen
        // steps along. Per character it wore ramp[9], the middle of the ramp.
        let gradient = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        func code(_ index: Int) -> String {
            let c = TrackRenderer.gradientColor(
                gradient, index: index, span: 20, fallback: .rgb(1, 2, 3), depth: ColorDepth.current).rgbComponents!
            return "38;2;\(c.red);\(c.green);\(c.blue)"
        }
        let lastGlyph = full.components(separatedBy: "\u{1B}[0m").dropLast().last ?? ""
        #expect(lastGlyph.contains(code(18)), "the last glyph wears ramp[18]: \(lastGlyph.debugDescription)")
        #expect(!lastGlyph.contains(code(9)), "…not the per-character ramp[9]")
    }

    /// The set of distinct `38;2;r;g;b` foreground codes in `output`.
    private func foregroundTriples(in output: String) -> Set<String> {
        var found: Set<String> = []
        var search = output[...]
        while let range = search.range(of: "38;2;") {
            let tail = search[range.upperBound...]
            let triple = tail.prefix { $0.isNumber || $0 == ";" }
            found.insert(String(triple))
            search = tail
        }
        return found
    }

    @Test(".automatic uses the control's filled colour (unchanged behaviour)")
    func automaticUsesFilledColor() {
        let output = render(.automatic)
        #expect(foregroundTriples(in: output).contains { $0.hasPrefix("1;2;3") })
    }

    @Test(".solid colours all lit cells with the given colour")
    func solidColour() {
        let output = render(.solid(.rgb(200, 100, 50)))
        let triples = foregroundTriples(in: output)
        #expect(triples.contains { $0.hasPrefix("200;100;50") })
        #expect(!triples.contains { $0.hasPrefix("1;2;3") }, "filled colour replaced")
    }

    @Test(".perSegment colours leading, middle and trailing independently")
    func perSegmentColours() {
        let output = render(
            .perSegment(
                leading: .rgb(255, 0, 0), middle: .rgb(0, 255, 0), trailing: .rgb(0, 0, 255)))
        let triples = foregroundTriples(in: output)
        #expect(triples.contains { $0.hasPrefix("255;0;0") }, "leading colour present")
        #expect(triples.contains { $0.hasPrefix("0;255;0") }, "middle colour present")
        #expect(triples.contains { $0.hasPrefix("0;0;255") }, "trailing colour present")
    }

    @Test(".gradient of identical stops colours every lit cell that exact colour")
    func gradientFixedPoint() {
        // Interpolating between identical stops is the identity — a
        // deterministic probe of the per-cell path (a real gradient's
        // interpolated values depend on cell count).
        let output = render(.gradient(Gradient(colors: [.rgb(10, 20, 30), .rgb(10, 20, 30)])))
        let triples = foregroundTriples(in: output).filter { !$0.hasPrefix("9;9;9") }
        #expect(triples.allSatisfy { $0.hasPrefix("10;20;30") }, "all lit cells: \(triples)")
    }

    @Test(".gradient of distinct stops produces multiple colours across the span")
    func gradientVaries() {
        let output = render(.gradient(Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])))
        let lit = foregroundTriples(in: output).filter { !$0.hasPrefix("9;9;9") }
        #expect(lit.count >= 3, "per-cell interpolation yields several colours: \(lit)")
    }

    @Test("Indeterminate .gradient(colors:) uses the custom stops")
    func indeterminateCustomStops() {
        // Identical custom stops → every cell must be exactly that colour,
        // regardless of the animation phase.
        let output = IndeterminateRenderer.render(
            width: 16, style: .gradient(Gradient(colors: [.rgb(11, 22, 33), .rgb(11, 22, 33)])),
            filledColor: .rgb(1, 1, 1), emptyColor: .rgb(2, 2, 2), accentColor: .rgb(3, 3, 3),
            elapsed: 0,
            palette: SystemPalette.green)
        let triples = foregroundTriples(in: output)
        #expect(triples.allSatisfy { $0.hasPrefix("11;22;33") }, "custom stops used: \(triples)")
    }

    @Test("Indeterminate .gradient blends in the ramp's own colour space")
    func indeterminateColorSpace() {
        // Blue → yellow is the pair the two spaces disagree about most: a
        // device blend passes through grey, a perceptual one does not.
        let stops: [Color] = [.rgb(0, 0, 255), .rgb(255, 255, 0)]
        func triples(_ space: Gradient.ColorSpace) -> [String] {
            ordered(
                in: IndeterminateRenderer.render(
                    width: 8, style: .gradient(Gradient(colors: stops, colorSpace: space)),
                    filledColor: .rgb(1, 1, 1), emptyColor: .rgb(2, 2, 2),
                    accentColor: .rgb(3, 3, 3), elapsed: 0,
                    palette: SystemPalette.green))
        }
        let device = triples(.device)
        let perceptual = triples(.perceptual)
        #expect(device.contains("128;128;128"), "device blend goes through grey: \(device)")
        #expect(
            !perceptual.contains { $0.hasPrefix("127;127;12") },
            "perceptual blend does not: \(perceptual)")
    }

    @Test("Indeterminate .gradient honours where the stops sit")
    func indeterminateStopLocations() {
        // Green a tenth of the way along, not a third: the cycle squeezes the
        // stops to leave room for the wrap, but keeps their proportions.
        let squashed = Gradient(stops: [
            Gradient.Stop(color: .rgb(255, 0, 0), location: 0),
            Gradient.Stop(color: .rgb(0, 255, 0), location: 0.1),
            Gradient.Stop(color: .rgb(0, 0, 255), location: 1),
        ])
        let output = IndeterminateRenderer.render(
            width: 30, style: .gradient(squashed), filledColor: .rgb(1, 1, 1),
            emptyColor: .rgb(2, 2, 2), accentColor: .rgb(3, 3, 3), elapsed: 0,
            palette: SystemPalette.green)
        let cells = ordered(in: output)
        let greenest = cells.indices.max { greenness(of: cells[$0]) < greenness(of: cells[$1]) }
        // 0.1 of the ramp × 2/3 of the cycle × 30 cells = column 2.
        #expect(greenest == 2, "green sits where it was put: \(cells)")
    }

    /// How green `triple` is, against its other two channels.
    private func greenness(of triple: String) -> Int {
        let channels = triple.split(separator: ";").map { Int($0) ?? 0 }
        guard channels.count == 3 else { return 0 }
        return channels[1] - max(channels[0], channels[2])
    }

    /// The `38;2;r;g;b` foreground codes in `output`, in the order they are
    /// emitted — one per RUN, and this motion lights every cell in a colour of
    /// its own, so the run index is the column.
    private func ordered(in output: String) -> [String] {
        var found: [String] = []
        var search = output[...]
        while let range = search.range(of: "38;2;") {
            let tail = search[range.upperBound...]
            found.append(String(tail.prefix { $0.isNumber || $0 == ";" }))
            search = tail
        }
        return found
    }

    @Test("Indeterminate .gradient with fewer than two usable stops falls back to the rainbow")
    func indeterminateFallback() {
        let output = IndeterminateRenderer.render(
            width: 16, style: .gradient(Gradient(colors: [.rgb(11, 22, 33)])),
            filledColor: .rgb(1, 1, 1), emptyColor: .rgb(2, 2, 2), accentColor: .rgb(3, 3, 3),
            elapsed: 0,
            palette: SystemPalette.green)
        let triples = foregroundTriples(in: output)
        #expect(triples.count >= 4, "built-in rainbow spans many colours: \(triples)")
    }
}

// MARK: - Scaling

/// The unfilled half of a bar, which a style could say nothing about until now:
/// the control passed its own recessive colour and that was the end of it.
@MainActor
@Suite("Track empty styling")
struct TrackEmptyStylingTests {

    private func render(_ config: TrackConfiguration, _ scaling: TrackGradientScaling = .track)
        -> String
    {
        TrackRenderer.render(
            fraction: 0.5, width: 10, style: .custom(config),
            filledColor: .rgb(1, 2, 3),
            emptyColor: .rgb(9, 9, 9),
            accentColor: .rgb(7, 7, 7),
            fillScaling: scaling, emptyScaling: scaling,
            palette: SystemPalette.green).text
    }

    private func hasForeground(_ output: String, _ code: String) -> Bool {
        output.contains("38;2;\(code)")
    }

    @Test("Without one, the control's own empty colour is used")
    func defaultsToTheControlsColour() {
        #expect(hasForeground(render(.bar), "9;9;9"))
    }

    @Test("A style's own empty colour replaces it")
    func styleColourWins() {
        var config = TrackConfiguration.bar
        config.emptyColor = .rgb(40, 50, 60)
        let output = render(config)
        #expect(hasForeground(output, "40;50;60"))
        #expect(!hasForeground(output, "9;9;9"), "the control's colour is gone: \(output.debugDescription)")
    }

    @Test("An empty gradient pinned to the bar takes the ramp its position names")
    func emptyGradientIsPositional() {
        var config = TrackConfiguration.bar
        config.emptyGradient = Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 0, 0)])
        let output = render(config, .track)
        // Half full, so the unfilled run covers the SECOND half of the ramp:
        // it reaches the last stop and never shows the first.
        #expect(hasForeground(output, "255;0;0"))
        #expect(!hasForeground(output, "0;0;0"), "the ramp's start belongs to the filled half")
    }

    @Test("Compressed, the same gradient is squeezed into the unfilled run")
    func emptyGradientCompresses() {
        var config = TrackConfiguration.bar
        config.emptyGradient = Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 0, 0)])
        let output = render(config, .fill)
        #expect(hasForeground(output, "0;0;0"), "…so it starts at the first stop instead")
        #expect(hasForeground(output, "255;0;0"))
    }

    @Test("A solid-background track gradients its background too")
    func backgroundStyleGradients() {
        var config = TrackConfiguration.block
        config.emptyGradient = Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 0, 0)])
        let output = render(config, .track)
        #expect(output.contains("48;2;255;0;0"), "the unfilled remainder is a FILL, not a glyph")
    }
}

/// What the gradient is measured across — the bar, or the lit part of it.
///
/// The distinction is the difference between a gradient that means something
/// ("red past 80%") and one that is decoration: compressed into the fill, the
/// last lit cell is the last colour at every value, so a half-full bar ends in
/// the same red a full one does.
@MainActor
@Suite("Track gradient scaling")
struct TrackGradientScalingTests {

    /// A three-stop ramp with unmistakable endpoints, on a 10-cell bar.
    private func render(_ fraction: Double, _ scaling: TrackGradientScaling) -> String {
        TrackRenderer.render(
            fraction: fraction, width: 10,
            style: .shadeRamp(gradient: Gradient(colors: [.rgb(0, 0, 0), .rgb(128, 128, 128), .rgb(255, 0, 0)])),
            filledColor: .rgb(1, 2, 3),
            emptyColor: .rgb(9, 9, 9),
            accentColor: .rgb(7, 7, 7),
            fillScaling: scaling,
            palette: SystemPalette.green).text
    }

    private func hasForeground(_ output: String, _ code: String) -> Bool {
        output.contains("38;2;\(code)")
    }

    @Test("Pinned to the bar, half full stops halfway along the ramp")
    func trackScalingStopsHalfway() {
        let output = render(0.5, .track)
        #expect(hasForeground(output, "0;0;0"), "the ramp still starts at its first stop")
        #expect(
            !hasForeground(output, "255;0;0"),
            "…and a half-full bar has not reached the last one: \(output.debugDescription)")
    }

    @Test("Compressed into the fill, half full still ends at the last stop")
    func fillScalingReachesTheEnd() {
        let output = render(0.5, .fill)
        #expect(hasForeground(output, "0;0;0"))
        #expect(
            hasForeground(output, "255;0;0"),
            "the ramp is squeezed into the lit part: \(output.debugDescription)")
    }

    @Test("A full bar looks the same either way")
    func fullBarAgrees() {
        // Nothing to compress at 100%, so the two spellings must not diverge —
        // the property that makes `.track` a safe default.
        #expect(render(1.0, .track) == render(1.0, .fill))
    }

    /// The same question for `.threeSegment`, which answered it wrongly by
    /// answering it not at all: it took no scaling parameter, so every gradient
    /// it drew was compressed into the fill however the caller had asked.
    @Test("A three-segment gradient honours the scaling too")
    func threeSegmentHonoursScaling() {
        func segments(_ fraction: Double, _ scaling: TrackGradientScaling) -> String {
            TrackRenderer.render(
                fraction: fraction, width: 10,
                style: .threeSegment(
                    leading: "[", middle: "=", trailing: "]", emptyFill: "·",
                    coloring: .gradient(Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 0, 0)]))),
                filledColor: .rgb(1, 2, 3),
                emptyColor: .rgb(9, 9, 9),
                accentColor: .rgb(7, 7, 7),
                fillScaling: scaling,
                palette: SystemPalette.green).text
        }
        let pinned = segments(0.5, .track)
        #expect(
            !hasForeground(pinned, "255;0;0"),
            "a half-full bar has not reached the last stop: \(pinned.debugDescription)")
        let compressed = segments(0.5, .fill)
        #expect(
            hasForeground(compressed, "255;0;0"),
            "…but compressed into the fill it has: \(compressed.debugDescription)")
        #expect(segments(1.0, .track) == segments(1.0, .fill), "and a full bar agrees")
    }

    @Test("The default is the bar")
    func defaultIsTrack() {
        // Both halves of the default: the environment value a view reads, and
        // the renderer's own parameter for callers that pass none.
        #expect(EnvironmentValues().trackGradientScaling == .track)
        #expect(EnvironmentValues().trackEmptyGradientScaling == .track)
        let defaulted = TrackRenderer.render(
            fraction: 0.5, width: 10,
            style: .shadeRamp(gradient: Gradient(colors: [.rgb(0, 0, 0), .rgb(128, 128, 128), .rgb(255, 0, 0)])),
            filledColor: .rgb(1, 2, 3), emptyColor: .rgb(9, 9, 9), accentColor: .rgb(7, 7, 7),
            palette: SystemPalette.green).text
        #expect(defaulted == render(0.5, .track))
        #expect(defaulted != render(0.5, .fill), "…and the two really do differ")
    }

    // MARK: - The unfilled gradient under the boundary cell

    /// Black → white, so a cell's background states its own position in the
    /// ramp and a wrong one is unmistakable.
    private static let fade = Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 255, 255)])

    /// A ten-cell track 55% full: eight sub-cell steps per cell puts five whole
    /// cells down and leaves the boundary cell at step 4 of 8, so there is
    /// always a boundary cell to look at.
    private func fadedTrack(scaling: TrackGradientScaling) -> String {
        TrackRenderer.render(
            fraction: 0.55, width: 10,
            style: .custom(
                TrackConfiguration(
                    fullGlyph: "█", partialRamp: ["▏", "▎", "▍", "▌", "▋", "▊", "▉"],
                    emptyStyle: .background, emptyGradient: Self.fade)),
            filledColor: .rgb(1, 2, 3), emptyColor: .rgb(9, 9, 9),
            accentColor: .rgb(7, 7, 7), fillScaling: scaling, emptyScaling: scaling,
            palette: SystemPalette.green).text
    }

    /// The `(text, background)` pair of every coloured run, in order.
    private func runs(in output: String) -> [(text: String, background: String)] {
        output.components(separatedBy: "\u{1b}[0m").compactMap { chunk in
            guard let start = chunk.range(of: "48;2;"),
                let end = chunk[start.upperBound...].firstIndex(of: "m")
            else { return nil }
            return (String(chunk[chunk.index(after: end)...]),
                String(chunk[start.upperBound..<end]))
        }
    }

    /// `colour` as the `r;g;b` it is emitted as, read back from the renderer
    /// rather than restated — the expectation is then the ramp itself.
    private func triple(_ colour: Color) -> String {
        runs(in: ANSIRenderer.colorize(" ", foreground: colour, background: colour))[0].background
    }

    @Test("The boundary cell takes the unfilled ramp's colour at its own position")
    func boundaryCellJoinsTheTrackRamp() {
        let output = fadedTrack(scaling: .track)
        let ramp = Color.quantisedRamp(Self.fade, count: 10, depth: .truecolor)
        // Cells 5…9 are the boundary cell and the four unfilled cells after
        // it, and pinned to the TRACK each takes the colour its position
        // names. The boundary cell used to take the flat empty colour instead,
        // which broke the ramp exactly where the eye is drawn to it.
        let painted = runs(in: output).suffix(5).map(\.background)
        #expect(painted == (5...9).map { triple(ramp[$0]) })
        #expect(!painted.contains(triple(.rgb(9, 9, 9))), "no cell falls back to the flat colour")
    }

    @Test("A compressed unfilled ramp starts AT the boundary cell, not after it")
    func boundaryCellStartsTheCompressedRamp() {
        let output = fadedTrack(scaling: .fill)
        // Five cells are unfilled to any degree — the boundary cell and the
        // four behind it — so the compressed ramp is five cells long and
        // begins on the boundary. It used to be squeezed into the four cells
        // after the boundary, which stretched it across a region a cell
        // narrower than the one it was describing.
        let ramp = Color.quantisedRamp(Self.fade, count: 5, depth: .truecolor)
        let painted = runs(in: output).suffix(5).map(\.background)
        #expect(painted == ramp.map { triple($0) })
    }

    @Test("With no boundary cell the unfilled ramp is unchanged")
    func wholeCellFillLeavesTheRampAlone() {
        // 50% of ten cells lands exactly on a cell edge, so there is no
        // boundary cell and the unfilled run is the five cells it always was.
        let output = TrackRenderer.render(
            fraction: 0.5, width: 10,
            style: .custom(
                TrackConfiguration(
                    fullGlyph: "█", partialRamp: ["▏", "▎", "▍", "▌", "▋", "▊", "▉"],
                    emptyStyle: .background, emptyGradient: Self.fade)),
            filledColor: .rgb(1, 2, 3), emptyColor: .rgb(9, 9, 9),
            accentColor: .rgb(7, 7, 7), fillScaling: .fill, emptyScaling: .fill,
            palette: SystemPalette.green).text
        let ramp = Color.quantisedRamp(Self.fade, count: 5, depth: .truecolor)
        #expect(runs(in: output).suffix(5).map(\.background) == ramp.map { triple($0) })
    }

    // MARK: - The two ramps answer separately

    /// A fill ramp and an unfilled ramp on one bar, each with its own scaling.
    private func twoRamps(fill: TrackGradientScaling, empty: TrackGradientScaling) -> String {
        TrackRenderer.render(
            fraction: 0.5, width: 10,
            style: .custom(
                TrackConfiguration(
                    fullGlyph: "█", emptyStyle: .background,
                    fillGradient: Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 0, 0)]),
                    emptyGradient: Self.fade)),
            filledColor: .rgb(1, 2, 3), emptyColor: .rgb(9, 9, 9),
            accentColor: .rgb(7, 7, 7), fillScaling: fill, emptyScaling: empty,
            palette: SystemPalette.green).text
    }

    /// The fill's scaling decides only the fill; the unfilled ramp is the same
    /// whichever way the fill is measured — and the other way round.
    @Test("The fill's scaling leaves the unfilled ramp alone, and vice versa")
    func scalingsAreIndependent() {
        let unfilledPinned = runs(in: twoRamps(fill: .track, empty: .track)).suffix(5).map(\.background)
        let unfilledPinnedUnderCompressedFill = runs(in: twoRamps(fill: .fill, empty: .track)).suffix(5).map(\.background)
        #expect(unfilledPinned == unfilledPinnedUnderCompressedFill)
        // Pinned to the bar the unfilled ramp's last cell is the ramp's end
        // (white); compressed into its five cells it is too, but its FIRST cell
        // is the ramp's start (black) rather than the bar's midpoint.
        let compressedEmpty = runs(in: twoRamps(fill: .track, empty: .fill)).suffix(5).map(\.background)
        #expect(compressedEmpty.first == triple(.rgb(0, 0, 0)), "\(compressedEmpty)")
        #expect(unfilledPinned.first != triple(.rgb(0, 0, 0)), "\(unfilledPinned)")
        #expect(compressedEmpty.last == unfilledPinned.last, "both reach the ramp's end")
        // The fill, read the same way: pinned it stops halfway (no pure red),
        // compressed it reaches red — whatever the unfilled side asks.
        func hasForeground(_ output: String, _ code: String) -> Bool { output.contains("38;2;\(code)") }
        #expect(!hasForeground(twoRamps(fill: .track, empty: .fill), "255;0;0"))
        #expect(hasForeground(twoRamps(fill: .fill, empty: .track), "255;0;0"))
    }

    /// `trackGradientScaling(_:)` answers both halves at once; the two-argument
    /// form answers each.
    @Test("The one-argument modifier sets both halves; the two-argument form sets each")
    func modifiersSetTheHalves() {
        // Read back through a real render rather than the setter: the modifier
        // is what callers write.
        final class Seen { var scalings: (fill: TrackGradientScaling, empty: TrackGradientScaling)? }
        let seen = Seen()
        struct Probe: View, Renderable {
            let seen: Seen
            var body: Never { fatalError("renders via Renderable") }
            func renderToBuffer(context: RenderContext) -> FrameBuffer {
                seen.scalings = (
                    context.environment.trackGradientScaling, context.environment.trackEmptyGradientScaling)
                return FrameBuffer()
            }
        }
        _ = renderToBuffer(
            Probe(seen: seen).trackGradientScaling(.fill), context: makeRenderContext(width: 10, height: 1))
        #expect(seen.scalings?.fill == .fill && seen.scalings?.empty == .fill)
        _ = renderToBuffer(
            Probe(seen: seen).trackGradientScaling(fill: .track, empty: .fill),
            context: makeRenderContext(width: 10, height: 1))
        #expect(seen.scalings?.fill == .track && seen.scalings?.empty == .fill)
    }
}
