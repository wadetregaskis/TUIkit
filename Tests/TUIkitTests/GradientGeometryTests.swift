//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientGeometryTests.swift
//
//  The four answers to "given a cell, what is t?". Every expectation here was
//  measured against real SwiftUI first, with `ImageRenderer` and a pixel
//  readback — see `Documentation/Gradients where a colour is accepted.md` §3.
//  The interesting ones are the two nobody guesses: a sweep clamps to its
//  NEARER end outside itself rather than wrapping, and a radial gradient's
//  radius is horizontal cells with the vertical derived from the cell aspect.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@Suite("Gradient geometry")
struct GradientGeometryTests {

    private let ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])

    /// A 21×21 extent puts the centre exactly on the middle cell's centre
    /// (`cx = 0.5 × 21 = 10.5`, and cell 10 spans 10…11), so every offset in
    /// these tests is a whole number of cells rather than a half-cell.
    private let square = GradientFrame(width: 21, height: 21)

    /// Where a cell falls along the ramp, 0…1, as the sampler actually
    /// resolves it — the quantisation is part of the answer, so this reads it
    /// back through the entry index rather than recomputing the maths.
    private func position(
        _ geometry: GradientGeometry, at column: Int, _ row: Int,
        extent: GradientFrame? = nil, cellAspect: Double = 2
    ) -> Double {
        let sampler = RampSampler(
            paint: .gradient(GradientPaint(ramp, geometry)), extent: extent ?? square,
            depth: .truecolor, cellAspect: cellAspect)
        guard let sampler, sampler.ramp.count > 1 else {
            Issue.record("no sampler for \(geometry)")
            return .nan
        }
        return Double(sampler.entry(column: column, rowTerm: sampler.rowTerm(row)))
            / Double(sampler.ramp.count - 1)
    }

    // MARK: - Radial

    /// The deviation, and the reason for it: a radius is cells along the
    /// HORIZONTAL axis, and a row counts for `imageCellAspect` of them. Draw a
    /// "circle" without that and it comes out twice as tall as it is wide.
    @Test("A radial ramp is round on screen, not round in the grid")
    func radialCorrectsForTheCellAspect() {
        let geometry = GradientGeometry.radial(center: .center, startRadius: 0, endRadius: 10)
        // Ten columns out and five rows out are the same distance at aspect 2.
        #expect(position(geometry, at: 20, 10) == position(geometry, at: 10, 15))
        // And five rows out is NOT five columns out, which is what an
        // uncorrected implementation would say.
        #expect(position(geometry, at: 15, 10) != position(geometry, at: 10, 15))
    }

    /// SwiftUI clamps at both ends: inside the start radius everything is the
    /// first stop, past the end radius everything is the last. The ramp does
    /// not repeat.
    @Test("A radial ramp clamps inside its start and past its end")
    func radialClamps() {
        let geometry = GradientGeometry.radial(center: .center, startRadius: 4, endRadius: 8)
        #expect(position(geometry, at: 10, 10) == 0, "the centre is inside the start radius")
        #expect(position(geometry, at: 12, 10) == 0, "two cells out is still inside")
        #expect(position(geometry, at: 19, 10) == 1, "nine cells out is past the end radius")
        #expect(position(geometry, at: 20, 10) == 1, "and further out is no further along")
        // In between it climbs, and only in between: the ramp's four entries
        // are one per cell of the 4…8 span, so the exact fractions are the
        // rounding's to choose and the ORDER is the claim.
        let inside = position(geometry, at: 15, 10)
        let outside = position(geometry, at: 17, 10)
        #expect(0 < inside && inside < outside && outside < 1, "\(inside) then \(outside)")
    }

    /// Equal radii are a mistake a caller can make, and SwiftUI draws them as
    /// a hard edge rather than trapping. What must not happen is a NaN
    /// reaching the entry clamp, which would trap on the `Int` conversion.
    @Test("Equal radii are an edge, not a crash")
    func radialWithNoSpan() {
        let geometry = GradientGeometry.radial(center: .center, startRadius: 5, endRadius: 5)
        #expect(position(geometry, at: 10, 10) == 1, "inside the edge")
        #expect(position(geometry, at: 20, 10) == 0, "outside it")
    }

    // MARK: - Elliptical

    /// The twin's whole point: fractions of the box, so the box's proportions
    /// are the shape, and the cell aspect must NOT be applied.
    @Test("An elliptical ramp follows the box, not the cell")
    func ellipticalIsUnitSpace() {
        let geometry = GradientGeometry.elliptical(
            center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
        // Same fraction of the width and of the height — equal only because
        // nothing corrected for the cell's shape.
        #expect(position(geometry, at: 15, 10) == position(geometry, at: 10, 15))
    }

    /// The default `0 … 0.5` reaches the last stop at the middle of each edge
    /// whatever shape the box is — measured: at half the width across and half
    /// the height down, both ends of a 81×41 rect were the final colour.
    @Test("The default fractions reach the last stop at the edges")
    func ellipticalDefaultsSpanTheBox() {
        let wide = GradientFrame(width: 41, height: 11)
        let geometry = GradientGeometry.elliptical(
            center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
        #expect(position(geometry, at: 40, 5, extent: wide) == 1, "the trailing edge")
        #expect(position(geometry, at: 20, 10, extent: wide) > 0.85, "the bottom edge")
        #expect(position(geometry, at: 20, 5, extent: wide) == 0, "the centre")
    }

    // MARK: - Angular

    /// Zero points at the trailing edge and the sweep runs clockwise, because
    /// rows grow downward. Measured: red at 0°, a quarter along at 90° (down),
    /// half at 180°, three quarters at 270° (up).
    @Test("An angular sweep starts at the trailing edge and turns clockwise")
    func angularStartsAtTrailing() {
        let full = GradientGeometry.angular(
            center: .center, startAngle: .zero, endAngle: .degrees(360))
        #expect(position(full, at: 20, 10) == 0, "trailing is 0°")
        #expect(abs(position(full, at: 10, 20) - 0.25) < 0.01, "down is 90°")
        #expect(abs(position(full, at: 0, 10) - 0.5) < 0.01, "leading is 180°")
        #expect(abs(position(full, at: 10, 0) - 0.75) < 0.01, "up is 270°")
    }

    /// The same correction the radial case needs, for the same reason: 45°
    /// should be the diagonal it looks like. At aspect 2 that is two cells
    /// across for every one down.
    @Test("An angular sweep's diagonals are the ones they look like")
    func angularCorrectsForTheCellAspect() {
        let full = GradientGeometry.angular(
            center: .center, startAngle: .zero, endAngle: .degrees(360))
        // Eight columns right, four rows down: 45° on screen at aspect 2.
        #expect(abs(position(full, at: 18, 14) - 0.125) < 0.01)
        // Eight and eight is 45° only in the grid, and reads as 63°.
        #expect(abs(position(full, at: 18, 18) - 0.176) < 0.01)
    }

    /// The rule nobody guesses: outside the sweep a cell takes whichever END
    /// is angularly nearer — it does NOT wrap back through the ramp. A 0…180°
    /// sweep of red→blue stays blue past 180° and is abruptly red again after
    /// 270°, and that seam is SwiftUI's.
    @Test("Outside a sweep, a cell takes the nearer end")
    func angularClampsToTheNearerEnd() {
        let half = GradientGeometry.angular(
            center: .center, startAngle: .zero, endAngle: .degrees(180))
        #expect(position(half, at: 20, 10) == 0, "0°, the start")
        #expect(abs(position(half, at: 10, 20) - 0.5) < 0.01, "90°, halfway")
        #expect(position(half, at: 0, 10) == 1, "180°, the end")
        // Either side of the seam at 270°, with the aspect making a row worth
        // two columns: (−1, −8) is 263° and (+1, −8) is 277°.
        #expect(position(half, at: 9, 6, cellAspect: 2) == 1, "just before the seam")
        #expect(position(half, at: 11, 6, cellAspect: 2) == 0, "just after it")
    }

    /// `startAngle` and `endAngle` both default to `.zero`, so the default
    /// sweep is degenerate — SwiftUI draws it as a half-and-half split, and
    /// `AngularGradient(gradient:center:angle:)` is the full turn.
    @Test("A zero sweep is a split, and the angle: spelling is the full turn")
    func angularWithNoSpan() {
        let none = GradientGeometry.angular(center: .center, startAngle: .zero, endAngle: .zero)
        #expect(position(none, at: 20, 10) == 0, "on the ray itself")
        #expect(position(none, at: 10, 20) == 1, "the half the sweep ran out into")
        #expect(position(none, at: 10, 0) == 0, "the half it came from")

        let turn = AngularGradient(gradient: ramp, center: .center, angle: .degrees(90))
        #expect(
            turn.endAngle.degrees - turn.startAngle.degrees == 360,
            "angle: is a full turn from the angle given")
    }

    // MARK: - The fast path

    /// One colour per row is what collapses the per-cell walk to a single run,
    /// and it is a property of the GEOMETRY: only a vertical linear ramp has
    /// it. Everything with a centre varies along every row.
    @Test("Only a vertical linear ramp is constant along a row")
    func onlyVerticalLinearIsFlatAcrossARow() {
        let cases: [(GradientGeometry, Bool)] = [
            (.linear(from: .top, to: .bottom), false),
            (.linear(from: .leading, to: .trailing), true),
            (.linear(from: .topLeading, to: .bottomTrailing), true),
            (.radial(center: .center, startRadius: 0, endRadius: 5), true),
            (.elliptical(center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5), true),
            (.angular(center: .center, startAngle: .zero, endAngle: .degrees(360)), true),
        ]
        for (geometry, varies) in cases {
            let sampler = RampSampler(
                paint: .gradient(GradientPaint(ramp, geometry)), extent: square,
                depth: .truecolor, cellAspect: 2)
            #expect(sampler?.variesAcrossRow == varies, "\(geometry)")
        }
    }
}
