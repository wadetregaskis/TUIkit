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
    /// - Returns: The row's bytes — exactly `width` visible cells — and the cells
    ///   owing a blend. Every colour goes in at its opaque spelling, so a
    ///   translucent one is claimed rather than dropped.
    static func render(
        width: Int,
        style: IndeterminateStyle,
        filledColor: Color,
        emptyColor: Color,
        accentColor: Color,
        elapsed: Double,
        palette: any Palette
    ) -> ClaimingRow {
        guard width > 0 else { return ClaimingRow() }
        // A motion's own gradient is read straight from the style, so it has
        // never met the palette. See `StyleGradientResolution.swift`.
        let configuration = style.configuration.resolvingColours(with: palette)
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
        filledColor: Color, emptyColor: Color, accentColor: Color,
        palette: any Palette
    ) -> (frames: [String], frameDuration: Double) {
        let period = period(of: style)
        let count = frameCount(of: style)
        let duration = period / Double(count)
        let frames = (0..<count).map { index in
            render(
                width: width, style: style, filledColor: filledColor,
                emptyColor: emptyColor, accentColor: accentColor,
                elapsed: Double(index) * duration, palette: palette
            ).text
        }
        return (frames, duration)
    }

    /// How many frames one pass is sampled at — and therefore the rate the
    /// FALLBACK path asks to be re-rendered at, so a bar that cannot be
    /// pre-rendered still animates at exactly the speed one that can does.
    ///
    /// Both numbers used to be a literal 30 in two places, which is the shape a
    /// divergence arrives in.
    static func frameCount(of style: IndeterminateStyle) -> Int {
        max(2, Int((period(of: style) * framesPerSecond).rounded()))
    }

    /// The sampling rate of a pre-rendered cycle, in hertz — the rate these bars
    /// asked the run loop to re-render them at before `AnimatedCellRun` existed,
    /// kept so the animation looks exactly as it did.
    static let framesPerSecond: Double = 30

    /// Whether every colour this bar could paint is opaque.
    ///
    /// **The condition for pre-rendering the cycle at all**, and the reason is the
    /// run rather than the colours: an ``AnimatedCellRun`` carries frames and no
    /// alpha, and a sweep MOVES — a given column is lit in some frames and unlit in
    /// others — so one static region cannot describe every frame unless every colour
    /// any frame can paint shares one alpha. §31.4 stopped there and left the bar
    /// loud. It need not: a `Spinner` whose frames a run cannot express already
    /// falls back to `requestAnimation`, and a bar can do the same, where each frame
    /// is rendered with its own exact claim.
    ///
    /// Asked of the INPUTS rather than of a built frame, because a frame paints only
    /// the colours that frame reached and the next one may reach another. That makes
    /// it conservative in one direction only — a translucent colour that is never
    /// actually painted costs the bar its pre-rendered cycle, and nothing else.
    static func isOpaqueThroughout(
        style: IndeterminateStyle,
        filledColor: Color, emptyColor: Color, accentColor: Color,
        palette: any Palette
    ) -> Bool {
        guard filledColor.isOpaque, emptyColor.isOpaque, accentColor.isOpaque else { return false }
        let configuration = style.configuration.resolvingColours(with: palette)
        guard let gradient = configuration.gradient else { return true }
        return gradient.stops.allSatisfy { $0.color.isOpaque }
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
    ) -> ClaimingRow {
        var result = ClaimingRow()
        var run = ""
        var runCells = 0
        var runColor: Color?
        func flush() {
            guard !run.isEmpty, let runColor else { return }
            // Through `ClaimingRow`, so the run's bytes state the colour's opaque
            // spelling and its alpha travels as a region — the one funnel a frame's
            // cells pass through, which is what lets a translucent bar be honoured
            // at all (§36.7).
            result.append(run, cells: runCells, ink: runColor)
            run = ""
            runCells = 0
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
            runCells += glyphWidth
            column += glyphWidth
        }
        if column < width {
            // The shortfall a multi-cell pattern leaves, in whatever colour was
            // last drawn — it is the continuation of that run, not a new thing.
            let shortfall = width - column
            run += String(repeating: " ", count: shortfall)
            runCells += shortfall
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
    ) -> ClaimingRow {
        let phase = phase(elapsed: elapsed, period: configuration.period)
        let segment = segment(of: configuration, across: width)
        let head = Int(phase * Double(width))
        let fill = Array(configuration.fill)
        let unlit = Array(configuration.empty)
        // Sampled as a RAMP, not cell by cell: `Color.quantisedRamp` is what
        // keeps a 256-colour host from banding, and the determinate track goes
        // through it too (`TrackRenderer`). `segment + 1` entries, so that entry
        // `segment - behind` is the same `1 - behind / segment` the trail has
        // always sampled at.
        let trail = Color.quantisedRamp(
            ramp(configuration, dim: empty, bright: accent), count: segment + 1, depth: ColorDepth.current)
        return laid(width: width) { column in
            let behind = (column - head + width) % width
            guard behind < segment else {
                return (glyph(unlit, at: column), empty)
            }
            return (glyph(fill, at: column), trail[segment - behind])
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
    ) -> ClaimingRow {
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
    ) -> ClaimingRow {
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
    /// A lead cell bouncing between the two ends at a constant speed, with a tail
    /// that fades behind it by TIME: each cell glows by how many steps ago the lead
    /// last stood on it. So when the lead turns at an end it runs back over its own
    /// tail, and the cells it passes light up again from the start of their fade.
    ///
    /// The trail used to be laid out by DIRECTION instead — the `segment` cells
    /// opposite the way the head was moving, shaded by distance. That model has no
    /// memory, and it showed at both ends: on the frame the direction flipped, the
    /// lead stood alone (its trail now pointing off the track), and on the next the
    /// trail appeared fully formed on the other side, lighting cells the lead had
    /// not stood on. And the head was `Int(triangle × (W − 1))`, a truncation, so
    /// its steps were uneven and it reached the far end for barely a frame.
    ///
    /// The lead now walks 0 … W−1 … 1, one step per `period / (2(W − 1))` seconds,
    /// standing on each end once — what a one-cell block hitting a wall does, and
    /// what `Spinner`'s bounce does. The "freshest visit wins" age is the same rule
    /// `Spinner.renderBouncingFrame` applies to its trail. Frames still sample the
    /// phase at the cycle's own rate, so the documented `period` holds whatever the
    /// width.
    private static func renderKnightRider(
        width: Int, configuration: IndeterminateConfiguration,
        empty: Color, accent: Color, elapsed: Double
    ) -> ClaimingRow {
        // At least one tail cell behind the lead wherever the track has room for
        // one: the preset's eighth of a track is under two cells below 16 columns,
        // and a lead with no tail is a different animation.
        let length = min(width, max(2, segment(of: configuration, across: width)))
        let steps = bounceSteps(width: width)
        let step = min(
            steps - 1,
            Int(phase(elapsed: elapsed, period: configuration.period) * Double(steps)))
        let fill = Array(configuration.fill)
        let unlit = Array(configuration.empty)
        // The ramp, quantised as one — see `renderSweep`.
        let trail = Color.quantisedRamp(
            ramp(configuration, dim: empty, bright: accent), count: length + 1, depth: ColorDepth.current)
        return laid(width: width) { column in
            guard let age = age(ofColumn: column, atStep: step, width: width, memory: length) else {
                return (glyph(unlit, at: column), empty)
            }
            return (glyph(fill, at: column), trail[length - age])
        }
    }

    /// Steps in one out-and-back bounce across `width` cells: 2(W − 1), each end
    /// stood on once. At least one, so a one-cell track still has a cycle.
    static func bounceSteps(width: Int) -> Int {
        max(1, 2 * (width - 1))
    }

    /// Where the lead stands at `step` of a bounce across `width` cells: out along
    /// 0 … W−1, back along W−2 … 1. Any integer step, negative included, wraps.
    static func leadColumn(atStep step: Int, width: Int) -> Int {
        guard width > 1 else { return 0 }
        let span = width - 1
        let cycle = 2 * span
        let wrapped = ((step % cycle) + cycle) % cycle
        return wrapped <= span ? wrapped : cycle - wrapped
    }

    /// How many steps ago the lead last stood on `column`, when that is fewer than
    /// `memory` — the FRESHEST visit, so a cell the lead has just passed back over
    /// glows from the start of its fade again.
    static func age(ofColumn column: Int, atStep step: Int, width: Int, memory: Int) -> Int? {
        for back in 0..<max(0, memory) where leadColumn(atStep: step - back, width: width) == column {
            return back
        }
        return nil
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
    ) -> ClaimingRow {
        let ramp = cyclic(configuration.gradient)
        let phase = phase(elapsed: elapsed, period: configuration.period)
        let fill = Array(configuration.fill)
        // The ramp, sampled once as a whole — four entries per cell, so the
        // motion still slides in quarter-cell steps — and quantised through
        // `Color.quantisedRamp`, which is what keeps a 256-colour host from
        // banding. Sampling `ramp.color(at:)` per cell went to the cube one
        // cell at a time and reversed four times across a 40-cell track.
        let steps = samplesPerCell * max(1, width)
        let samples = Color.quantisedRamp(ramp, count: steps + 1, depth: ColorDepth.current)
        return laid(width: width) { column in
            // Each cell samples at its own offset in the ramp, minus a
            // global time-dependent shift so the pattern scrolls
            // rightward. We add 1.0 before the wrap so the subtraction
            // never produces a negative value (Swift's
            // `truncatingRemainder` keeps the sign of the dividend).
            let raw = (Double(column) / Double(max(1, width)) - phase + 1.0)
                .truncatingRemainder(dividingBy: 1.0)
            return (glyph(fill, at: column), samples[min(steps, Int((raw * Double(steps)).rounded()))])
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
    /// How finely `renderGradient` samples its ramp per cell. Internal, like
    /// ``cyclic(_:)``, so the banding test can rebuild the exact sample set.
    static let samplesPerCell = 4

    static func cyclic(_ requested: Gradient?) -> Gradient {
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
