//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ShapeSampling.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  The sampling geometry shared by the shape-based ASCII renderer
//  (ASCIIConverter+ShapeBased.swift) and the offline glyph-calibration tool
//  (Tools/GenerateImageGlyphs). Keeping the circle centres, radius, sample
//  count, and the spiral that places the samples in ONE place means the
//  runtime and the tool that measures the reference-font coverage vectors can
//  never drift apart: the tool compiles this very file (see generate.sh)
//  rather than copying the constants.
//
//  Pure math — no image, font, or platform-UI dependency — so it builds
//  identically inside TUIkitImage (every platform) and inside the standalone
//  macOS tool.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The six staggered "sampling circles" that make up a cell's 6-D shape
/// vector, and the golden-angle spiral that distributes samples within each.
///
/// Layout, matching alexharri.com/blog/ascii-rendering — left circles dropped
/// a little, right circles raised, so staggering them fills the cell with
/// minimal gaps:
///
/// ```
///  [0]   [1]      ← upper row  (upper-left, upper-right)
///  [2]   [3]      ← middle row
///  [4]   [5]      ← lower row
/// ```
enum ShapeRegion {
    /// Normalised sampling-circle centres `(x, y)` in `[0, 1]` cell space.
    static let centres: [(x: Double, y: Double)] = [
        (0.27, 0.22),  // 0 upper-left
        (0.73, 0.15),  // 1 upper-right
        (0.27, 0.52),  // 2 middle-left
        (0.73, 0.48),  // 3 middle-right
        (0.27, 0.82),  // 4 lower-left
        (0.73, 0.78),  // 5 lower-right
    ]

    /// Sampling-circle radius in normalised cell-width units.
    static let radius: Double = 0.30

    /// Number of samples taken per circle when computing a vector.
    static let samplesPerCircle: Int = 16

    /// The normalised `(x, y)` sample points in `[0, 1]` cell space, laid out
    /// centre-major then sample-minor (centre 0's samples, then centre 1's, …).
    ///
    /// This is the single source of truth for *where* a cell's shape vector is
    /// sampled. The runtime maps these points into source-image pixels
    /// (`SampleOffsets`); the calibration tool maps the same points into a
    /// rasterised-glyph bitmap. Samples sit on a Vogel / sunflower spiral
    /// (golden-angle step, radius ∝ √index) so they cover each circle evenly.
    /// A point may fall marginally outside `[0, 1]`; each consumer clamps into
    /// its own pixel grid.
    static func normalizedSamplePoints() -> [(x: Double, y: Double)] {
        let denom = Double(max(1, samplesPerCircle - 1))
        var points = [(x: Double, y: Double)]()
        points.reserveCapacity(centres.count * samplesPerCircle)
        for centre in centres {
            for sampleIndex in 0..<samplesPerCircle {
                let angle = Double(sampleIndex) * 2.39996  // golden angle
                let r = radius * (Double(sampleIndex) / denom).squareRoot()
                points.append((centre.x + r * cos(angle), centre.y + r * sin(angle)))
            }
        }
        return points
    }

    /// Maps a normalised sample point into an integer pixel coordinate within a
    /// `width × height` grid — truncation toward zero, then clamped to
    /// `0 ... dimension − 1`. Shared by both consumers (the runtime maps into
    /// source-image pixels, the calibration tool into a rasterised-glyph
    /// bitmap) so the map-and-clamp convention, like the geometry above, has a
    /// single definition and cannot drift. Each caller applies its own row
    /// stride to the returned `(x, y)`.
    static func pixel(
        for point: (x: Double, y: Double), width: Int, height: Int
    ) -> (x: Int, y: Int) {
        let px = min(max(0, width - 1), max(0, Int(point.x * Double(width))))
        let py = min(max(0, height - 1), max(0, Int(point.y * Double(height))))
        return (px, py)
    }
}
