//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Indeterminate Renderer

/// Utility for rendering an animated indeterminate-progress bar.
///
/// Every animation derives a phase in `0..<1` from an elapsed time, so the bar
/// animates at a consistent visual speed regardless of how often the view tree
/// re-renders. What is drawn comes from an ``IndeterminateConfiguration``, of
/// which each ``IndeterminateStyle`` case is a preset — so a named style and a
/// hand-rolled `.custom(_:)` go down the same path.
enum IndeterminateRenderer {

    /// Renders one frame of the indeterminate animation.
    ///
    /// - Parameters:
    ///   - width: The track's total width in terminal cells.
    ///   - style: The chosen animation.
    ///   - filledColor: The control's own "lit" colour, used where the
    ///     configuration names no colours of its own.
    ///   - emptyColor: The colour for unlit cells, and the dim end of a ramp.
    ///   - accentColor: The bright end of a ramp.
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
        let configuration = style.configuration
        switch configuration.motion {
        case .sweep:
            return renderSweep(
                width: width, configuration: configuration, empty: emptyColor,
                accent: accentColor, elapsed: elapsed)
        case .barberPole:
            return renderBarberPole(
                width: width, configuration: configuration, filled: filledColor,
                accent: accentColor, elapsed: elapsed)
        case .pulse:
            return renderPulse(
                width: width, configuration: configuration, dim: emptyColor,
                bright: accentColor, elapsed: elapsed)
        case .knightRider:
            return renderKnightRider(
                width: width, configuration: configuration, empty: emptyColor,
                accent: accentColor, elapsed: elapsed)
        case .gradient:
            return renderGradient(
                width: width, configuration: configuration, elapsed: elapsed)
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
        let period = period > 0 ? period : 1.6
        let wrapped = elapsed.truncatingRemainder(dividingBy: period)
        return (wrapped < 0 ? wrapped + period : wrapped) / period
    }

    /// How long one full pass of `style` takes.
    ///
    /// The cycle builder needs exactly what the renderer uses, so both read it
    /// off the configuration rather than keeping a table of their own.
    static func period(of style: IndeterminateStyle) -> Double {
        let period = style.configuration.period
        return period > 0 ? period : 1.6
    }

    /// The lit run's length in cells — at least one, however small the
    /// fraction or the track.
    private static func segment(
        of configuration: IndeterminateConfiguration, across width: Int
    ) -> Int {
        max(1, Int(Double(width) * max(0, configuration.extent)))
    }

    /// A ramp, from the dim end to the bright end. Fewer than two usable
    /// stops falls back to the control's own pair.
    private static func ramp(
        _ configuration: IndeterminateConfiguration, dim: Color, bright: Color
    ) -> Gradient {
        guard let gradient = configuration.gradient, gradient.stops.count >= 2 else {
            return Gradient(colors: [dim, bright])
        }
        return gradient
    }
}

// MARK: - Laying a row

extension IndeterminateRenderer {
    /// Builds a row of exactly `width` cells, asking `cell` what to draw at
    /// each column it reaches.
    ///
    /// The pattern index is the COLUMN, not the glyph count, so the texture is
    /// anchored to the track: cell *j* always shows the same pattern character
    /// while the motion sweeps over it — the same rule
    /// ``TrackConfiguration/fill`` follows.
    ///
    /// A glyph that would cross the last column is dropped and the shortfall
    /// padded with spaces, so a multi-cell pattern coarsens the animation
    /// without ever changing how wide it is.
    ///
    /// Adjacent cells of the SAME colour are emitted under one escape. That is
    /// not a micro-optimisation: these frames are pre-rendered by the cycle
    /// builder and replayed from an ``AnimatedCellRun``, so a per-cell escape
    /// is paid again on every tick for as long as the bar is on screen. A
    /// `pulse` frame is one colour across the whole track and comes out as one
    /// run; a `sweep` frame is a short ramp and then a long flat tail.
    private static func laid(
        width: Int, cell: (Int) -> (glyph: Character, color: Color)
    ) -> String {
        var result = ""
        var run = ""
        var runColor: Color?
        func flush() {
            guard !run.isEmpty, let runColor else { return }
            result += ANSIRenderer.colorize(run, foreground: runColor)
            run = ""
        }
        var column = 0
        while column < width {
            let (glyph, color) = cell(column)
            // The colour is taken BEFORE the fit is tested, so that a glyph too
            // wide for the room left still names the colour its padding is
            // drawn in. Testing first left `runColor` nil when the very first
            // glyph did not fit — a two-cell fill in a one-cell track — and the
            // padding was then dropped by the flush, so the row came out empty.
            if color != runColor {
                flush()
                runColor = color
            }
            let glyphWidth = max(1, glyph.terminalWidth)
            guard column + glyphWidth <= width else { break }
            run.append(glyph)
            column += glyphWidth
        }
        if column < width {
            // The shortfall a multi-cell pattern leaves, in whatever colour was
            // last drawn — it is the continuation of that run, not a new thing.
            run += String(repeating: " ", count: width - column)
        }
        flush()
        return result
    }

    /// The character of `pattern` anchored at `column`. An empty pattern draws
    /// a space, which is what "nothing here" means in a cell grid.
    private static func glyph(_ pattern: [Character], at column: Int) -> Character {
        pattern.isEmpty ? " " : pattern[column % pattern.count]
    }
}

// MARK: - Sweep

extension IndeterminateRenderer {
    /// The original animation: a bright segment with a fading trail
    /// sweeps continuously across the track.
    private static func renderSweep(
        width: Int, configuration: IndeterminateConfiguration,
        empty: Color, accent: Color, elapsed: Double
    ) -> String {
        let phase = phase(elapsed: elapsed, period: configuration.period)
        let segment = segment(of: configuration, across: width)
        let head = Int(phase * Double(width))
        let fill = Array(configuration.fill)
        let unlit = Array(configuration.empty)
        let gradient = ramp(configuration, dim: empty, bright: accent)
        return laid(width: width) { column in
            let behind = (column - head + width) % width
            guard behind < segment else {
                return (glyph(unlit, at: column), empty)
            }
            let intensity = 1.0 - Double(behind) / Double(segment)
            return (glyph(fill, at: column), gradient.color(at: intensity))
        }
    }
}

// MARK: - Barber Pole

extension IndeterminateRenderer {
    /// The fill pattern shifted one cell per step, its glyphs coloured in turn
    /// so the row reads as moving diagonal stripes.
    private static func renderBarberPole(
        width: Int, configuration: IndeterminateConfiguration,
        filled: Color, accent: Color, elapsed: Double
    ) -> String {
        let fill = Array(configuration.fill)
        let stripes = configuration.gradient.map { $0.stops.map(\.color) }.flatMap {
            $0.isEmpty ? nil : $0
        } ?? [accent, filled]
        // A fast-cycling phase so the stripes appear to scroll briskly; the eye
        // reads the built-in `0.6 s` per stripe-pair shift as "moving" rather
        // than "ticking".
        let shift = Int(phase(elapsed: elapsed, period: configuration.period) * Double(width * 2))
        return laid(width: width) { column in
            let slot = fill.isEmpty ? 0 : (column + shift) % fill.count
            return (glyph(fill, at: column + shift), stripes[slot % stripes.count])
        }
    }
}

// MARK: - Pulse

extension IndeterminateRenderer {
    /// The whole bar breathes between the two ends of the ramp.
    private static func renderPulse(
        width: Int, configuration: IndeterminateConfiguration,
        dim: Color, bright: Color, elapsed: Double
    ) -> String {
        // A sine wave gives a smoother breath than a sawtooth `phase()`,
        // and clamping its `0..<2π` range to `[0, 1]` via `(1 - cos)/2`
        // makes the brightest and dimmest points sit at the start and
        // middle of each period — easier to read as "alive but waiting".
        let raw = phase(elapsed: elapsed, period: configuration.period) * .pi * 2
        let intensity = (1.0 - cos(raw)) / 2.0
        let colour = ramp(configuration, dim: dim, bright: bright).color(at: intensity)
        let fill = Array(configuration.fill)
        return laid(width: width) { column in (glyph(fill, at: column), colour) }
    }
}

// MARK: - Knight Rider

extension IndeterminateRenderer {
    /// A single bright block bounces left-to-right and back, with a short
    /// fading trail behind the head.
    private static func renderKnightRider(
        width: Int, configuration: IndeterminateConfiguration,
        empty: Color, accent: Color, elapsed: Double
    ) -> String {
        let segment = segment(of: configuration, across: width)
        // Bounce with a triangle wave: phase goes 0 → 1 → 0, mapped to
        // head position 0 → (width − 1) → 0.
        let raw = phase(elapsed: elapsed, period: configuration.period)
        let triangle = raw < 0.5 ? raw * 2.0 : (1.0 - raw) * 2.0
        let head = Int(triangle * Double(max(0, width - 1)))
        let direction = raw < 0.5 ? 1 : -1
        let fill = Array(configuration.fill)
        let unlit = Array(configuration.empty)
        let gradient = ramp(configuration, dim: empty, bright: accent)
        return laid(width: width) { column in
            // The trail extends *behind* the head — i.e. in the
            // opposite direction of motion — so the leading edge stays
            // visually sharp.
            let offset = (column - head) * -direction
            guard offset >= 0, offset < segment else {
                return (glyph(unlit, at: column), empty)
            }
            let intensity = 1.0 - Double(offset) / Double(segment)
            return (glyph(fill, at: column), gradient.color(at: intensity))
        }
    }
}

// MARK: - Gradient

extension IndeterminateRenderer {
    /// A cyclic hue ramp slid continuously across the track. Each cell
    /// picks its colour from the stops with the offset rotating once per
    /// period — produces a fluid, OS-style "indeterminate busy" feel
    /// without ever leaving an empty cell.
    ///
    /// Scrolls left-to-right: subtracting `phase` from each cell's
    /// position means a given colour (say amber) reappears at a higher
    /// index as time passes, so the eye reads the gradient as moving
    /// rightward.
    private static func renderGradient(
        width: Int, configuration: IndeterminateConfiguration, elapsed: Double
    ) -> String {
        let ramp = cyclic(configuration.gradient)
        let phase = phase(elapsed: elapsed, period: configuration.period)
        let fill = Array(configuration.fill)
        return laid(width: width) { column in
            // Each cell samples at its own offset in the ramp, minus a
            // global time-dependent shift so the pattern scrolls
            // rightward. We add 1.0 before the wrap so the subtraction
            // never produces a negative value (Swift's
            // `truncatingRemainder` keeps the sign of the dividend).
            let raw = (Double(column) / Double(max(1, width)) - phase + 1.0)
                .truncatingRemainder(dividingBy: 1.0)
            return (glyph(fill, at: column), ramp.color(at: raw))
        }
    }

    /// The rainbow this motion slides when the caller names no colours of
    /// their own.
    private static let rainbow = Gradient(colors: [
        // swiftlint:disable comma
        .rgb(180,  30,  80),  // magenta-pink
        .rgb(220, 110,  40),  // amber
        .rgb(220, 220,  60),  // yellow
        .rgb( 60, 200,  90),  // green
        .rgb( 50, 140, 220),  // cyan-blue
        .rgb(140,  90, 220),  // violet
        // swiftlint:enable comma
    ])

    /// `requested` laid out as a CYCLE — a ramp that can be slid across the
    /// track for ever without a seam.
    ///
    /// A cycle has one segment more than the stops describe: the wrap, from
    /// the last stop back to the first. The stops are squeezed to leave room
    /// for it, by the average of the gaps they already have — so *n* evenly
    /// spaced stops come out as *n* equal segments, and unevenly spaced ones
    /// keep their proportions.
    ///
    /// Sampling then goes through ``Gradient/color(at:)`` like every other
    /// ramp in the framework, which is what makes ``Gradient/colorSpace``
    /// count here as it does under ``IndeterminateConfiguration/Motion/sweep``
    /// and its siblings.
    ///
    /// - Parameter requested: The caller's stops, or `nil` for the built-in
    ///   rainbow.
    /// - Returns: A gradient spanning `0...1` whose ends are the same colour.
    private static func cyclic(_ requested: Gradient?) -> Gradient {
        // Stops need resolvable RGB (a semantic colour has none until a
        // palette is applied); anything unresolvable is skipped, and fewer
        // than two usable stops falls back to the built-in rainbow.
        var source = requested ?? rainbow
        var stops = resolvable(in: source)
        if stops.count < 2 {
            source = rainbow
            stops = rainbow.stops
        }

        let count = Double(stops.count)
        let origin = stops[0].location
        let span = stops[stops.count - 1].location - origin
        // The stops occupy this much of the cycle; the wrap gets the rest.
        let extent = (count - 1) / count
        var cycled = stops.enumerated().map { index, stop in
            // Every stop in one place describes no ramp at all, so they fall
            // back to even spacing — which is what a bare list of colours
            // means, and what this motion did before it read the locations.
            Gradient.Stop(
                color: stop.color,
                location: span > 0 ? (stop.location - origin) / span * extent : Double(index) / count
            )
        }
        cycled.append(Gradient.Stop(color: stops[0].color, location: 1))
        // `withStops`, not `Gradient(stops:)`: the layout changes, everything
        // else the caller's ramp carries — its colour space — does not.
        return source.withStops(cycled)
    }

    /// `gradient`'s stops that name a real colour, in location order.
    private static func resolvable(in gradient: Gradient) -> [Gradient.Stop] {
        gradient.stops.enumerated()
            .filter { $0.element.color.rgbComponents != nil }
            // Ordered by location, ties broken by the order they were given
            // in — the same rule `Gradient` itself sorts by, so a hard edge
            // built from two stops in one place stays the way round it was
            // written.
            .sorted { ($0.element.location, $0.offset) < ($1.element.location, $1.offset) }
            .map(\.element)
    }
}
