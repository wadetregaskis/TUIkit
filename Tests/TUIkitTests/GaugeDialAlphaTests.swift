//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GaugeDialAlphaTests.swift
//
//  The `Gauge`'s circular dials, which paint their own cells and never touch
//  `TrackRenderer` — so finishing the track (§31) finished the bar and left
//  these four emit sites loud. §36.6.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A circular Gauge's own cells")
struct GaugeDialAlphaTests {

    private func buffer<V: View>(_ view: V, width: Int = 24, height: Int = 6) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    private var half: Double { 128.0 / 255 }

    /// The tiny dial is one glyph in the accent, and it was the shortest of the four
    /// sites: a single `colorize` with a translucent colour in it.
    @Test("The tiny dial claims its one cell")
    func tinyDialClaims() throws {
        let drawn = buffer(
            Gauge(value: 0.6) { Text("load") }
                .gaugeStyle(.accessoryCircularTiny)
                .tint(Color.red.opacity(0.5)))
        let claim = try #require(drawn.opacityRegions.first, "\(drawn.opacityRegions)")
        #expect(drawn.opacityRegions.count == 1, "\(drawn.opacityRegions)")
        #expect(claim.offsetX == 0 && claim.offsetY == 0 && claim.width == 1, "\(claim)")
        #expect(claim.inkOpacity == half, "\(claim)")
    }

    /// The ring dial paints its rim a cell at a time, in two colours: the accent for
    /// the lit arc and `foregroundTertiary` for the rest. A faded tint reaches only
    /// the accent, so the claims must be the ARC and not the whole rim — which is
    /// also what stops the merge from swallowing the difference.
    @Test("The ring dial claims its lit arc and not its dim rim")
    func ringDialClaimsTheArc() {
        let drawn = buffer(
            Gauge(value: 1.0) { Text("load") }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Color.red.opacity(0.5)))
        let claims = drawn.opacityRegions
        #expect(!claims.isEmpty, "\(claims)")
        #expect(claims.allSatisfy { $0.inkOpacity == half }, "\(claims)")
        // A full ring, so every rim cell is lit — the claims cover the top and bottom
        // edges and the two walls, on the three rows of the box.
        #expect(Set(claims.map(\.offsetY)) == [0, 1, 2], "\(claims)")
    }

    /// At a fraction that lights only part of the ring, the dim remainder must be
    /// left alone: an opaque colour owes no claim, so a rectangle over it would fade
    /// cells no colour asked to fade.
    @Test("A half-full ring leaves its unlit cells unclaimed")
    func halfRingLeavesTheRestAlone() {
        let drawn = buffer(
            Gauge(value: 0.5) { Text("load") }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Color.red.opacity(0.5)))
        let lit = drawn.opacityRegions.reduce(0) { $0 + $1.width }
        #expect(lit > 0, "\(drawn.opacityRegions)")
        // The rim of the 3 × 6 box (a 4-cell interior) is 14 cells; half of it is
        // fewer. A literal rather than the renderer's own constant, which is private:
        // a test that read the number from the code it is testing would agree with a
        // wrong one.
        #expect(lit < 14, "half the ring, not all of it: \(drawn.opacityRegions)")
    }

    @Test("An opaque tint claims nothing on either dial")
    func opaqueDialsClaimNothing() {
        // Each style in its own generic call rather than one loop over an array:
        // `.gaugeStyle(_:)` is generic over the conformer (as SwiftUI's is), so
        // the three dial styles have three different types and no array holds
        // them without erasing what the modifier needs.
        func claimsNothing<S: GaugeStyle>(_ style: S) {
            let drawn = buffer(
                Gauge(value: 0.6) { Text("load") }.gaugeStyle(style).tint(.red))
            #expect(drawn.opacityRegions.isEmpty, "\(style): \(drawn.opacityRegions)")
        }
        claimsNothing(.accessoryCircularTiny)
        claimsNothing(.accessoryCircular)
        claimsNothing(.accessoryCircularCapacity)
    }
}
