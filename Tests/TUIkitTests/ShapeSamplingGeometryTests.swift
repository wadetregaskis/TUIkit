//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ShapeSamplingGeometryTests.swift
//
//  Pins the shape-sampling geometry shared by the runtime renderer and the
//  offline calibration tool (Tools/GenerateImageGlyphs). `swift test` never runs
//  that macOS/CoreText-only tool, so an edit to `ShapeSampling.swift` would
//  silently desync the live runtime from the committed `generatedGlyphCalibration`
//  until someone regenerated on a Mac. These goldens are the cross-platform
//  tripwire: change the geometry deliberately and they fail here (on macOS *and*
//  Linux CI), reminding you to re-run `generate.sh` and update the goldens.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage

@Suite("Shape sampling geometry")
struct ShapeSamplingGeometryTests {
    /// Absolute tolerance for the pinned coordinates.
    private let tolerance = 1e-6

    @Test("The sample grid is 6 centres × 16 samples, laid out centre-major")
    func gridShape() {
        #expect(ShapeRegion.centres.count == 6)
        #expect(ShapeRegion.samplesPerCircle == 16)
        #expect(ShapeRegion.radius == 0.30)

        let points = ShapeRegion.normalizedSamplePoints()
        #expect(points.count == ShapeRegion.centres.count * ShapeRegion.samplesPerCircle)

        // Sample 0 of every circle sits exactly on the circle's centre (the
        // spiral radius is 0 at index 0), which also proves the centre-major
        // stride: point `centreIndex * samplesPerCircle` is centre `centreIndex`.
        for (centreIndex, centre) in ShapeRegion.centres.enumerated() {
            let first = points[centreIndex * ShapeRegion.samplesPerCircle]
            #expect(abs(first.x - centre.x) < tolerance)
            #expect(abs(first.y - centre.y) < tolerance)
        }
    }

    @Test("Interior spiral points are pinned (catches golden-angle / radius drift)")
    func pinnedSpiralPoints() {
        // Precomputed from angle = i · 2.39996, r = 0.30 · √(i/15). If these fail
        // because you intentionally changed the geometry, re-run
        // Tools/GenerateImageGlyphs/generate.sh and update both these goldens and
        // the committed calibration table.
        let points = ShapeRegion.normalizedSamplePoints()
        let expected: [(index: Int, x: Double, y: Double)] = [
            (1, 0.212883821, 0.272323438),   // centre 0, sample 1
            (8, 0.475796927, 0.295150681),   // centre 0, sample 8
            (53, 0.876141203, 0.387033614),  // centre 3, sample 5
            (95, 0.691432380, 0.482489431),  // centre 5, sample 15
        ]
        for pin in expected {
            let point = points[pin.index]
            #expect(abs(point.x - pin.x) < tolerance)
            #expect(abs(point.y - pin.y) < tolerance)
        }
    }

    @Test("pixel(for:) truncates toward zero and clamps into the grid")
    func pixelMapping() {
        func check(
            _ point: (x: Double, y: Double), _ width: Int, _ height: Int, _ x: Int, _ y: Int
        ) {
            let mapped = ShapeRegion.pixel(for: point, width: width, height: height)
            #expect(mapped.x == x)
            #expect(mapped.y == y)
        }
        // Non-negative coordinates map by truncation. (Values chosen dyadic so
        // the product is exact — e.g. 0.29·100 is 28.9999… and truncates to 28,
        // which is correct but a poor golden.)
        check((0.5, 0.5), 10, 20, 5, 10)
        check((0.25, 0.75), 100, 100, 25, 75)
        // Below 0 and at/over the top edge clamp to the valid index range.
        check((-0.10, 1.50), 10, 20, 0, 19)
        // Degenerate 1×1 grid always resolves to (0, 0).
        check((0.99, 0.99), 1, 1, 0, 0)
    }
}
