//  🖥️ TUIKit — Terminal UI Kit for Swift
//  IndeterminateRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Indeterminate Renderer

/// Utility for rendering an animated indeterminate-progress bar.
///
/// All styles read the wall-clock time and derive a phase in `0..<1` that
/// advances continuously, so the bar animates at a consistent visual
/// speed regardless of how often the view tree re-renders. The
/// ``IndeterminateStyle`` enum picks which animation is drawn.
enum IndeterminateRenderer {

    /// Renders one frame of the indeterminate animation.
    ///
    /// - Parameters:
    ///   - width: The track's total width in terminal cells.
    ///   - style: The chosen animation.
    ///   - filledColor: The colour for "lit" cells. (Used by `.sweep`,
    ///     `.pulse`, `.knightRider` as the bright endpoint of the
    ///     `dim → bright` lerp.)
    ///   - emptyColor: The colour for "unlit" cells.
    ///   - accentColor: The high-energy accent colour.
    /// - Returns: An ANSI-styled string of exactly `width` visible cells.
    static func render(
        width: Int,
        style: IndeterminateStyle,
        filledColor: Color,
        emptyColor: Color,
        accentColor: Color
    ) -> String {
        guard width > 0 else { return "" }
        switch style {
        case .sweep:
            return renderSweep(width: width, filled: filledColor, empty: emptyColor, accent: accentColor)
        case .barberPole:
            return renderBarberPole(width: width, filled: filledColor, accent: accentColor)
        case .pulse:
            return renderPulse(width: width, dim: emptyColor, bright: accentColor)
        case .knightRider:
            return renderKnightRider(width: width, empty: emptyColor, accent: accentColor)
        case .gradient:
            return renderGradient(width: width)
        }
    }

    /// A monotonically-advancing time signal in `0..<1`, completing one
    /// pass every `period` seconds. The wall clock keeps the animation
    /// speed independent of frame rate.
    private static func phase(period: Double = 1.6) -> Double {
        let now = Date().timeIntervalSinceReferenceDate
        return now.truncatingRemainder(dividingBy: period) / period
    }
}

// MARK: - Sweep

extension IndeterminateRenderer {
    /// The original animation: a bright segment with a fading trail
    /// sweeps continuously across the track.
    private static func renderSweep(
        width: Int, filled: Color, empty: Color, accent: Color
    ) -> String {
        let phase = phase()
        let segment = max(1, width / 3)
        let head = Int(phase * Double(width))
        var result = ""
        for index in 0..<width {
            let behind = (index - head + width) % width
            if behind < segment {
                let intensity = 1.0 - Double(behind) / Double(segment)
                let colour = Color.lerp(empty, accent, phase: intensity)
                result += ANSIRenderer.colorize("█", foreground: colour)
            } else {
                result += ANSIRenderer.colorize("░", foreground: empty)
            }
        }
        _ = filled  // kept in the signature for callers that need it
        return result
    }
}

// MARK: - Barber Pole

extension IndeterminateRenderer {
    /// `◢◤` triangle pattern shifted left one cell per frame, alternately
    /// coloured filled / accent to read as moving diagonal stripes.
    private static func renderBarberPole(width: Int, filled: Color, accent: Color) -> String {
        let glyphs: [Character] = ["◢", "◤"]
        // Use a fast-cycling phase so the stripes appear to scroll
        // briskly; the eye reads `0.6 s` per stripe-pair shift as
        // "moving" rather than "ticking".
        let phaseInCells = Int(phase(period: 0.6) * Double(width * 2))
        var result = ""
        for index in 0..<width {
            let slot = (index + phaseInCells) % 2
            let glyph = glyphs[slot]
            let colour = (slot == 0) ? accent : filled
            result += ANSIRenderer.colorize(String(glyph), foreground: colour)
        }
        return result
    }
}

// MARK: - Pulse

extension IndeterminateRenderer {
    /// The whole bar breathes between dim and bright accent.
    private static func renderPulse(width: Int, dim: Color, bright: Color) -> String {
        // A sine wave gives a smoother breath than a sawtooth `phase()`,
        // and clamping its `0..<2π` range to `[0, 1]` via `(1 - cos)/2`
        // makes the brightest and dimmest points sit at the start and
        // middle of each period — easier to read as "alive but waiting".
        let raw = phase(period: 1.8) * .pi * 2
        let intensity = (1.0 - cos(raw)) / 2.0
        let colour = Color.lerp(dim, bright, phase: intensity)
        let bar = String(repeating: "█", count: width)
        return ANSIRenderer.colorize(bar, foreground: colour)
    }
}

// MARK: - Knight Rider

extension IndeterminateRenderer {
    /// A single bright block bounces left-to-right and back, with a short
    /// fading trail behind the head.
    private static func renderKnightRider(width: Int, empty: Color, accent: Color) -> String {
        let segment = max(1, width / 8)
        // Bounce with a triangle wave: phase goes 0 → 1 → 0, mapped to
        // head position 0 → (width − 1) → 0.
        let raw = phase(period: 2.0)
        let triangle = raw < 0.5 ? raw * 2.0 : (1.0 - raw) * 2.0
        let head = Int(triangle * Double(max(0, width - 1)))
        let direction = raw < 0.5 ? 1 : -1
        var result = ""
        for index in 0..<width {
            // The trail extends *behind* the head — i.e. in the
            // opposite direction of motion — so the leading edge stays
            // visually sharp.
            let offset = (index - head) * -direction
            if offset >= 0 && offset < segment {
                let intensity = 1.0 - Double(offset) / Double(segment)
                let colour = Color.lerp(empty, accent, phase: intensity)
                result += ANSIRenderer.colorize("█", foreground: colour)
            } else {
                result += ANSIRenderer.colorize("░", foreground: empty)
            }
        }
        return result
    }
}

// MARK: - Gradient

extension IndeterminateRenderer {
    /// A cyclic hue ramp slid continuously across the track. Each cell
    /// picks its colour from a six-stop rainbow with the offset rotating
    /// once per period — produces a fluid, OS-style "indeterminate
    /// busy" feel without ever leaving an empty cell.
    ///
    /// Scrolls left-to-right: subtracting `phase` from each cell's
    /// position means a given colour (say amber) reappears at a higher
    /// index as time passes, so the eye reads the gradient as moving
    /// rightward.
    private static func renderGradient(width: Int) -> String {
        let stops: [(r: UInt8, g: UInt8, b: UInt8)] = [
            // swiftlint:disable comma
            (180,  30,  80),  // magenta-pink
            (220, 110,  40),  // amber
            (220, 220,  60),  // yellow
            ( 60, 200,  90),  // green
            ( 50, 140, 220),  // cyan-blue
            (140,  90, 220),  // violet
            // swiftlint:enable comma
        ]
        let phase = phase(period: 2.4)
        var result = ""
        for index in 0..<width {
            // Each cell samples at its own offset in the rainbow, minus
            // a global time-dependent shift so the pattern scrolls
            // rightward. We add 1.0 before the wrap so the subtraction
            // never produces a negative value (Swift's
            // `truncatingRemainder` keeps the sign of the dividend).
            let raw = (Double(index) / Double(max(1, width)) - phase + 1.0)
                .truncatingRemainder(dividingBy: 1.0)
            let (r, g, b) = sample(stops: stops, at: raw)
            result += ANSIRenderer.colorize("█", foreground: .rgb(r, g, b))
        }
        return result
    }

    /// Piecewise-linear lookup into a list of RGB stops, wrapped so the
    /// gradient is cyclic (the final stop interpolates back to the
    /// first).
    private static func sample(
        stops: [(r: UInt8, g: UInt8, b: UInt8)], at parameter: Double
    ) -> (UInt8, UInt8, UInt8) {
        let segments = Double(stops.count)
        let scaled = parameter * segments
        let lowerIndex = Int(scaled.rounded(.down)) % stops.count
        let upperIndex = (lowerIndex + 1) % stops.count
        let mix = scaled - Double(Int(scaled.rounded(.down)))
        let lower = stops[lowerIndex]
        let upper = stops[upperIndex]
        func lerp(_ start: UInt8, _ end: UInt8) -> UInt8 {
            let blended = Double(start) + (Double(end) - Double(start)) * mix
            return UInt8(max(0, min(255, Int(blended.rounded()))))
        }
        return (lerp(lower.r, upper.r), lerp(lower.g, upper.g), lerp(lower.b, upper.b))
    }
}
