//  🖥️ TUIKit — Terminal UI Kit for Swift
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
            accentColor: .rgb(7, 7, 7))
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
        let output = render(.gradient([.rgb(10, 20, 30), .rgb(10, 20, 30)]))
        let triples = foregroundTriples(in: output).filter { !$0.hasPrefix("9;9;9") }
        #expect(triples.allSatisfy { $0.hasPrefix("10;20;30") }, "all lit cells: \(triples)")
    }

    @Test(".gradient of distinct stops produces multiple colours across the span")
    func gradientVaries() {
        let output = render(.gradient([.rgb(255, 0, 0), .rgb(0, 0, 255)]))
        let lit = foregroundTriples(in: output).filter { !$0.hasPrefix("9;9;9") }
        #expect(lit.count >= 3, "per-cell interpolation yields several colours: \(lit)")
    }

    @Test("Indeterminate .gradient(colors:) uses the custom stops")
    func indeterminateCustomStops() {
        // Identical custom stops → every cell must be exactly that colour,
        // regardless of the animation phase.
        let output = IndeterminateRenderer.render(
            width: 16, style: .gradient(colors: [.rgb(11, 22, 33), .rgb(11, 22, 33)]),
            filledColor: .rgb(1, 1, 1), emptyColor: .rgb(2, 2, 2), accentColor: .rgb(3, 3, 3))
        let triples = foregroundTriples(in: output)
        #expect(triples.allSatisfy { $0.hasPrefix("11;22;33") }, "custom stops used: \(triples)")
    }

    @Test("Indeterminate .gradient with fewer than two usable stops falls back to the rainbow")
    func indeterminateFallback() {
        let output = IndeterminateRenderer.render(
            width: 16, style: .gradient(colors: [.rgb(11, 22, 33)]),
            filledColor: .rgb(1, 1, 1), emptyColor: .rgb(2, 2, 2), accentColor: .rgb(3, 3, 3))
        let triples = foregroundTriples(in: output)
        #expect(triples.count >= 4, "built-in rainbow spans many colours: \(triples)")
    }
}

// MARK: - Scaling

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
            style: .shadeRamp(gradient: [.rgb(0, 0, 0), .rgb(128, 128, 128), .rgb(255, 0, 0)]),
            filledColor: .rgb(1, 2, 3),
            emptyColor: .rgb(9, 9, 9),
            accentColor: .rgb(7, 7, 7),
            gradientScaling: scaling)
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

    @Test("The default is the bar")
    func defaultIsTrack() {
        // Both halves of the default: the environment value a view reads, and
        // the renderer's own parameter for callers that pass none.
        #expect(EnvironmentValues().trackGradientScaling == .track)
        let defaulted = TrackRenderer.render(
            fraction: 0.5, width: 10,
            style: .shadeRamp(gradient: [.rgb(0, 0, 0), .rgb(128, 128, 128), .rgb(255, 0, 0)]),
            filledColor: .rgb(1, 2, 3), emptyColor: .rgb(9, 9, 9), accentColor: .rgb(7, 7, 7))
        #expect(defaulted == render(0.5, .track))
        #expect(defaulted != render(0.5, .fill), "…and the two really do differ")
    }
}
