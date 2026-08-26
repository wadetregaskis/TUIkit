//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        accentColor: Color,
        elapsed: Double
    ) -> String {
        guard width > 0 else { return "" }
        switch style {
        case .sweep:
            return renderSweep(
                width: width, filled: filledColor, empty: emptyColor, accent: accentColor,
                elapsed: elapsed)
        case .barberPole:
            return renderBarberPole(
                width: width, filled: filledColor, accent: accentColor, elapsed: elapsed)
        case .pulse:
            return renderPulse(
                width: width, dim: emptyColor, bright: accentColor, elapsed: elapsed)
        case .knightRider:
            return renderKnightRider(
                width: width, empty: emptyColor, accent: accentColor, elapsed: elapsed)
        case .gradient(let colors):
            return renderGradient(width: width, colors: colors, elapsed: elapsed)
        }
    }

    /// Every frame of `style`'s cycle, already styled.
    ///
    /// Sampled at 30 frames a second — the rate these bars used to ask to be
    /// re-rendered at — so the animation looks exactly as it did. Frames that
    /// come out identical cost nothing at replay: ``AnimatedCellRun`` skips
    /// straight past them.
    static func cycle(
        width: Int, style: IndeterminateStyle,
        filledColor: Color, emptyColor: Color, accentColor: Color
    ) -> (frames: [String], frameDuration: Double) {
        let period = period(of: style)
        let count = max(2, Int((period * 30).rounded()))
        let duration = period / Double(count)
        let frames = (0..<count).map { index in
            render(
                width: width, style: style, filledColor: filledColor,
                emptyColor: emptyColor, accentColor: accentColor,
                elapsed: Double(index) * duration)
        }
        return (frames, duration)
    }

    /// A monotonically-advancing signal in `0..<1`, completing one pass every
    /// `period` seconds.
    ///
    /// `elapsed` is HANDED IN rather than read from the wall clock, which is
    /// what makes a whole cycle pre-renderable: a frame at an arbitrary point
    /// in the animation is now a pure function, so the caller can build every
    /// frame at once and leave them as an ``AnimatedCellRun`` instead of asking
    /// to be re-rendered thirty times a second.
    private static func phase(elapsed: Double, period: Double = 1.6) -> Double {
        let wrapped = elapsed.truncatingRemainder(dividingBy: period)
        return (wrapped < 0 ? wrapped + period : wrapped) / period
    }

    /// How long one full pass of `style` takes.
    ///
    /// Each style's own period, in one place, because the cycle builder needs
    /// exactly what the renderer uses and two copies would drift.
    static func period(of style: IndeterminateStyle) -> Double {
        switch style {
        case .sweep: 1.6
        case .barberPole: 0.6
        case .pulse: 1.8
        case .knightRider: 2.0
        case .gradient: 2.4
        }
    }
}

// MARK: - Sweep

extension IndeterminateRenderer {
    /// The original animation: a bright segment with a fading trail
    /// sweeps continuously across the track.
    private static func renderSweep(
        width: Int, filled: Color, empty: Color, accent: Color, elapsed: Double
    ) -> String {
        let phase = phase(elapsed: elapsed)
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
    private static func renderBarberPole(
        width: Int, filled: Color, accent: Color, elapsed: Double
    ) -> String {
        let glyphs: [Character] = ["◢", "◤"]
        // Use a fast-cycling phase so the stripes appear to scroll
        // briskly; the eye reads `0.6 s` per stripe-pair shift as
        // "moving" rather than "ticking".
        let phaseInCells = Int(phase(elapsed: elapsed, period: 0.6) * Double(width * 2))
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
    private static func renderPulse(
        width: Int, dim: Color, bright: Color, elapsed: Double
    ) -> String {
        // A sine wave gives a smoother breath than a sawtooth `phase()`,
        // and clamping its `0..<2π` range to `[0, 1]` via `(1 - cos)/2`
        // makes the brightest and dimmest points sit at the start and
        // middle of each period — easier to read as "alive but waiting".
        let raw = phase(elapsed: elapsed, period: 1.8) * .pi * 2
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
    private static func renderKnightRider(
        width: Int, empty: Color, accent: Color, elapsed: Double
    ) -> String {
        let segment = max(1, width / 8)
        // Bounce with a triangle wave: phase goes 0 → 1 → 0, mapped to
        // head position 0 → (width − 1) → 0.
        let raw = phase(elapsed: elapsed, period: 2.0)
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
    private static func renderGradient(
        width: Int, colors: [Color]?, elapsed: Double
    ) -> String {
        // Custom stops need resolvable RGB (semantic colours have none until a
        // palette is applied); anything unresolvable is skipped, and fewer
        // than two usable stops falls back to the built-in rainbow.
        let custom = colors?.compactMap { color -> (r: UInt8, g: UInt8, b: UInt8)? in
            guard let components = color.rgbComponents else { return nil }
            return (components.red, components.green, components.blue)
        }
        let builtIn: [(r: UInt8, g: UInt8, b: UInt8)] = [
            // swiftlint:disable comma
            (180,  30,  80),  // magenta-pink
            (220, 110,  40),  // amber
            (220, 220,  60),  // yellow
            ( 60, 200,  90),  // green
            ( 50, 140, 220),  // cyan-blue
            (140,  90, 220),  // violet
            // swiftlint:enable comma
        ]
        let stops = (custom?.count ?? 0) >= 2 ? custom! : builtIn
        let phase = phase(elapsed: elapsed, period: 2.4)
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
