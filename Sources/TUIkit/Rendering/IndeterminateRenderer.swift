//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Indeterminate Renderer

/// Utility for rendering an animated indeterminate-progress bar.
///
/// A frame is drawn at a ``Position`` in its pass: one of the steps a stepped
/// motion walks through, or a phase in `0..<1` for the pulse, whose colour is
/// continuous. An elapsed time maps to a position, so the bar animates at a
/// consistent visual speed regardless of how often the view tree re-renders.
/// What is drawn comes from an ``IndeterminateConfiguration``, of which each
/// ``IndeterminateStyle`` case is a preset — so a named style and a hand-rolled
/// `.custom(_:)` go down the same path.
enum IndeterminateRenderer {

    /// Where in its pass a frame is drawn.
    enum Position: Equatable {
        /// Step `n` of the ``IndeterminateRenderer/states(of:width:cellPixels:)`` a
        /// motion walks through in one pass, wrapped into that range, so a caller can
        /// name a state in integers rather than as a time that has to land inside it.
        /// The pulse has no steps, and draws the start of its pass.
        case step(Int)
        /// A point in the pass, in `0..<1`. A stepped motion draws the step that
        /// point falls in.
        case phase(Double)
    }

    /// Renders one frame of the indeterminate animation, `elapsed` seconds into the
    /// motion's own time.
    ///
    /// - Parameters:
    ///   - width: The track's total width in terminal cells.
    ///   - style: The chosen animation.
    ///   - fillColor: The control's own "lit" colour, used where the
    ///     configuration names no colours of its own.
    ///   - backgroundColor: The colour for unlit cells, and the dim end of a ramp.
    ///   - accentColor: The bright end of a ramp.
    /// - Returns: The row's bytes — exactly `width` visible cells — and the cells
    ///   owing a blend. Every colour goes in at its opaque spelling, so a
    ///   translucent one is claimed rather than dropped.
    static func render(
        width: Int,
        style: IndeterminateStyle,
        fillColor: Color,
        backgroundColor: Color,
        accentColor: Color,
        elapsed: Double,
        palette: any Palette
    ) -> ClaimingRow {
        // Before the phase, whose period check reports an unusable period, so a track
        // with no cells reports nothing, as it always has.
        guard width > 0 else { return ClaimingRow() }
        return render(
            width: width, style: style, fillColor: fillColor, backgroundColor: backgroundColor,
            accentColor: accentColor,
            position: .phase(phase(elapsed: elapsed, period: style.configuration.period)),
            palette: palette)
    }

    /// Renders one frame of the indeterminate animation at `position` in its pass.
    ///
    /// The parameters and the result are ``render(width:style:fillColor:backgroundColor:accentColor:elapsed:palette:)``'s.
    static func render(
        width: Int,
        style: IndeterminateStyle,
        fillColor: Color,
        backgroundColor: Color,
        accentColor: Color,
        position: Position,
        palette: any Palette
    ) -> ClaimingRow {
        guard width > 0 else { return ClaimingRow() }
        // A motion's own gradient is read straight from the style, so it has
        // never met the palette. See `StyleGradientResolution.swift`.
        let configuration = style.configuration.resolvingColours(with: palette)
        // Every stepped motion's count is at least 1, so the wrap below cannot divide
        // by zero; the pulse has none.
        let states = states(of: configuration, width: width, cellPixels: nil) ?? 1
        func wrapped(_ step: Int) -> Int { ((step % states) + states) % states }
        switch (configuration.motion, position) {
        case (.sweep, .step(let step)):
            return renderSweep(
                width: width, configuration: configuration, empty: backgroundColor,
                accent: accentColor, head: wrapped(step))
        case (.sweep, .phase(let phase)):
            // Unwrapped: a phase a hair under 1 can reach `width`, which the trail's
            // own wrap reads as column 0.
            return renderSweep(
                width: width, configuration: configuration, empty: backgroundColor,
                accent: accentColor, head: Int(phase * Double(width)))
        case (.barberPole, _):
            // The pattern shifted by `shift` characters is the pattern shifted by
            // `shift` modulo its length, which is all a step has to name. A phase is
            // the step it falls in, of the pattern's own length.
            let shift: Int
            switch position {
            case .step(let step): shift = wrapped(step)
            case .phase(let phase): shift = wrapped(Int(phase * Double(states)))
            }
            return renderBarberPole(
                width: width, configuration: configuration, filled: fillColor,
                accent: accentColor, shift: shift)
        case (.pulse, _):
            let phase: Double
            if case .phase(let given) = position { phase = given } else { phase = 0 }
            return renderPulse(
                width: width, configuration: configuration, dim: backgroundColor,
                bright: accentColor, phase: phase)
        case (.knightRider, .step(let step)):
            return renderKnightRider(
                width: width, configuration: configuration, empty: backgroundColor,
                accent: accentColor, step: wrapped(step))
        case (.knightRider, .phase(let phase)):
            return renderKnightRider(
                width: width, configuration: configuration, empty: backgroundColor,
                accent: accentColor, step: min(states - 1, Int(phase * Double(states))))
        case (.gradient, .step(let step)):
            return renderGradient(width: width, configuration: configuration, shift: wrapped(step))
        case (.gradient, .phase(let phase)):
            return renderGradient(
                width: width, configuration: configuration, shift: wrapped(Int(phase * Double(states))))
        }
    }

    /// How many distinct states one pass of `configuration` steps through across
    /// `width` cells, or `nil` for the pulse, whose colour is continuous.
    ///
    /// - `sweep`: the width, a head on each column.
    /// - `knightRider`: ``bounceSteps(width:)``, 2(W − 1) and at least 1.
    /// - `barberPole`: the characters in `fill` (at least 1), since the pattern
    ///   shifted by its own length is the pattern again.
    /// - `gradient`: ``samplesPerCell`` a cell in glyphs, or the picture's width in
    ///   pixels when it is drawn as pictures.
    ///
    /// - Parameters:
    ///   - cellPixels: A cell's size in pixels when the bar is drawn as pictures, or
    ///     `nil` when it is drawn in glyphs.
    static func states(
        of configuration: IndeterminateConfiguration, width: Int, cellPixels: TerminalCellPixels?
    ) -> Int? {
        let width = max(1, width)
        switch configuration.motion {
        case .sweep: return width
        case .knightRider: return bounceSteps(width: width)
        case .barberPole: return max(1, configuration.fill.count)
        case .pulse: return nil
        case .gradient:
            if let cellPixels,
                let picture = GradientRaster.resolution(columns: width, rows: 1, cellPixels: cellPixels)
            {
                return picture.width
            }
            return samplesPerCell * width
        }
    }

    /// Every frame of `style`'s cycle at `speed`, already styled, and how many ticks
    /// of 1/60 s each is shown for.
    ///
    /// Frames of `frameTicks` ticks, a thirtieth of a second — the rate these bars used
    /// to ask to be re-rendered at — so the animation looks as it did, at any speed,
    /// up to `IndicatorAnimationSpeed.RampLayout.maximumFrameCount` frames, past which
    /// each lasts longer; a barberPole's frames are one per step instead
    /// (``layout(of:speed:)``). Frames that come out identical cost nothing at replay:
    /// ``AnimatedCellRun`` skips straight past them. Nor does each cost a render: a
    /// frame showing a state an earlier frame showed
    /// (``state(ofFrame:of:configuration:width:)``) is that frame's row, so a stepped
    /// motion of N states draws at most min(N, F) rows for F frames, and a 2-cell
    /// sweep's pass of 48 frames draws 2. Every frame of the pulse is its own, which,
    /// with the frames' memory, is what the bound is for.
    static func cycle(
        width: Int, style: IndeterminateStyle,
        fillColor: Color, backgroundColor: Color, accentColor: Color,
        palette: any Palette, speed: IndicatorAnimationSpeed
    ) -> (frames: [String], frameTicks: Int) {
        let layout = layout(of: style, speed: speed)
        let configuration = style.configuration
        // Sampled over the configuration's OWN period, whatever the speed: a faster
        // bar shows the same motion in less time, not a different motion. A stepped
        // motion's frame i of F is its step, counted in integers
        // (`state(ofFrame:of:configuration:width:)`); only the pulse, which has no
        // steps, is timed.
        let sample = period(of: style) / Double(layout.frameCount)
        var drawn: [Int: String] = [:]
        var frames: [String] = []
        frames.reserveCapacity(layout.frameCount)
        for index in 0..<layout.frameCount {
            let state = state(ofFrame: index, of: layout.frameCount, configuration: configuration, width: width)
            if let row = drawn[state] {
                frames.append(row)
                continue
            }
            let row =
                configuration.motion == .pulse
                ? render(
                    width: width, style: style, fillColor: fillColor,
                    backgroundColor: backgroundColor, accentColor: accentColor,
                    elapsed: Double(index) * sample, palette: palette
                ).text
                : render(
                    width: width, style: style, fillColor: fillColor,
                    backgroundColor: backgroundColor, accentColor: accentColor,
                    position: .step(state), palette: palette
                ).text
            drawn[state] = row
            frames.append(row)
        }
        return (frames, layout.frameTicks)
    }

    /// The frame of `style`'s cycle at `speed` showing `elapsed` seconds in, drawn with
    /// its own claims, and the instant the next frame showing a different state begins,
    /// in whole nanoseconds on the clock `elapsed` is read from; `nil` when every frame
    /// of the pass shows one state, so nothing it draws will change.
    ///
    /// For a bar no run can carry, which is drawn one render at a time. It draws frame
    /// `AnimationClock.step(atElapsed:frameTicks:)` of the pass, wrapped, which is the
    /// frame the run would show then
    /// (``cycle(width:style:fillColor:backgroundColor:accentColor:palette:speed:)``),
    /// and needs drawing again only when that frame's state changes. It used to draw
    /// the motion at the elapsed time scaled by the pass's rate, which between frame
    /// boundaries is not the frame the run shows, and to ask for a render at the end
    /// of every frame: a 2-cell sweep's 48 frames show 2 states, and it was drawn 48
    /// times a pass to change twice.
    static func frame(
        atElapsed elapsed: Double, width: Int, style: IndeterminateStyle,
        fillColor: Color, backgroundColor: Color, accentColor: Color,
        palette: any Palette, speed: IndicatorAnimationSpeed
    ) -> (row: ClaimingRow, nextChangeNanos: Int64?) {
        guard width > 0 else { return (ClaimingRow(), nil) }
        let layout = layout(of: style, speed: speed)
        let configuration = style.configuration
        let count = max(1, layout.frameCount)
        let step = AnimationClock.step(atElapsed: elapsed, frameTicks: layout.frameTicks)
        // Floor modulo, so a negative elapsed counts back through the pass.
        let frame = Int((step % Int64(count) + Int64(count)) % Int64(count))
        let state = state(ofFrame: frame, of: count, configuration: configuration, width: width)
        let row: ClaimingRow
        if configuration.motion == .pulse {
            // The pulse's frame at the time `cycle` samples it, spelled as `cycle` does.
            let sample = period(of: style) / Double(layout.frameCount)
            row = render(
                width: width, style: style, fillColor: fillColor, backgroundColor: backgroundColor,
                accentColor: accentColor, elapsed: Double(frame) * sample, palette: palette)
        } else {
            row = render(
                width: width, style: style, fillColor: fillColor, backgroundColor: backgroundColor,
                accentColor: accentColor, position: .step(state), palette: palette)
        }
        // At most one pass on, where the frames repeat. `Self.`, because the local
        // `state` hides the function inside the closure.
        let later = (1..<count).first { offset in
            Self.state(ofFrame: (frame + offset) % count, of: count, configuration: configuration, width: width)
                != state
        }
        let next = later.map { offset in
            AnimationClock.nanoseconds(atTick: (step + Int64(offset)) * Int64(layout.frameTicks))
        }
        return (row, next)
    }

    /// Which state frame `frame` of a pass of `frameCount` frames shows, of
    /// `configuration` across `width` cells: the step a stepped motion draws there,
    /// ⌊frame·N/F⌋ (``step(ofFrame:of:states:)``) with a knightRider's turn at the far
    /// wall kept (``bounceStep(ofFrame:of:width:)``), or for the pulse, whose colour
    /// is continuous, the frame itself.
    ///
    /// Two frames of one state draw the same row, so a cycle draws each state once.
    static func state(
        ofFrame frame: Int, of frameCount: Int, configuration: IndeterminateConfiguration, width: Int
    ) -> Int {
        switch configuration.motion {
        case .pulse:
            return frame
        case .knightRider:
            return bounceStep(ofFrame: frame, of: frameCount, width: width)
        case .sweep, .barberPole, .gradient:
            let states = states(of: configuration, width: width, cellPixels: nil) ?? 1
            return step(ofFrame: frame, of: frameCount, states: states)
        }
    }

    /// The step frame `frame` of a knightRider's pass of `frameCount` frames shows
    /// across `width` cells: `step(ofFrame:of:states:)` of its
    /// ``bounceSteps(width:)``, except that when the pass has fewer frames than steps,
    /// frame ⌊F/2⌋ shows the far wall, step W − 1.
    ///
    /// A pass with fewer frames than steps skips steps, and when F is odd
    /// ⌊i·2(W − 1)/F⌋ can skip W − 1 itself: at 80 cells a 1.975 s pass is 59 frames
    /// for 158 steps, and no frame reaches step 79, so the lead turned one cell short
    /// of the end. W − 1 is half the steps, so it belongs to the middle frame, and only
    /// that frame moves; with F even it is already W − 1.
    static func bounceStep(ofFrame frame: Int, of frameCount: Int, width: Int) -> Int {
        let states = bounceSteps(width: width)
        guard frameCount < states, frame == frameCount / 2 else {
            return step(ofFrame: frame, of: frameCount, states: states)
        }
        return max(0, width - 1)
    }

    /// The step frame `frame` of a pass laid out in `frameCount` frames shows, of the
    /// `states` its motion steps through: ⌊frame · states / frameCount⌋, in integers.
    ///
    /// Counted from the index rather than found by timing the frame, at
    /// `frame × period / frameCount` seconds, and truncating its phase × `states`:
    /// that product is a float, and on a frame that begins exactly on a state it can
    /// come out a hair short and draw the state before. A 4-cell sweep's frame 36 of
    /// 48 is three quarters of the way through its pass, and its phase × 4 was
    /// 2.9999999999999996.
    static func step(ofFrame frame: Int, of frameCount: Int, states: Int) -> Int {
        frame * states / max(1, frameCount)
    }

    /// How one pass of `style` is laid out at `speed`: how many frames it is sampled
    /// at, and how many ticks each is shown. The FALLBACK path draws the same frames
    /// (``frame(atElapsed:width:style:fillColor:backgroundColor:accentColor:palette:speed:)``),
    /// so a bar that cannot be pre-rendered animates exactly as one that can does, and
    /// `ProgressView`'s cycle of pictures is laid out by it too.
    ///
    /// A pass takes the configuration's period divided by the rate, in whole frames
    /// of `frameTicks` ticks, as many as come nearest
    /// (`IndicatorAnimationSpeed.rampLayout`). A named preset's period and a `.custom`
    /// configuration's are laid out alike, so the frames of every bar but a barberPole
    /// change on the same 2-tick lattice.
    ///
    /// A barberPole's pass is a sequence rather than a ramp: one frame for each of its
    /// states, each shown for the whole number of ticks nearest the pass divided by the
    /// states, and at least `frameTicks` (`IndicatorAnimationSpeed.frameTicks(standard:)`),
    /// so every shift is held the same time. Laid out in 2-tick frames, a pass its
    /// states do not divide held them unevenly: "abcd" over 0.5 s was 15 frames, and
    /// ⌊i·4/15⌋ held its four states for 4, 4, 4 and 3 of them. A fill of more than
    /// `IndicatorAnimationSpeed.RampLayout.maximumFrameCount` characters is laid out as
    /// a ramp, which bounds its frames.
    ///
    /// The frame count used to be a literal 30 in three places, which is the shape
    /// a divergence arrives in.
    static func layout(
        of style: IndeterminateStyle, speed: IndicatorAnimationSpeed
    ) -> IndicatorAnimationSpeed.RampLayout {
        let period = period(of: style)
        let configuration = style.configuration
        guard configuration.motion == .barberPole,
            let states = states(of: configuration, width: 1, cellPixels: nil),
            states <= IndicatorAnimationSpeed.RampLayout.maximumFrameCount
        else {
            return speed.rampLayout(standardCycle: period, frameTicks: frameTicks)
        }
        let ticks = max(frameTicks, speed.frameTicks(standard: period / Double(states)))
        return IndicatorAnimationSpeed.RampLayout(frameCount: states, frameTicks: ticks)
    }

    /// How many 1/60 s ticks a frame of a pre-rendered cycle is shown for: 2, the
    /// thirtieth of a second these bars asked the run loop to re-render them at
    /// before `AnimatedCellRun` existed, kept so the animation looks as it did. A
    /// barberPole's frames are one per step, and this long at the least.
    static let frameTicks = 2

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
        fillColor: Color, backgroundColor: Color, accentColor: Color,
        palette: any Palette
    ) -> Bool {
        guard fillColor.isOpaque, backgroundColor.isOpaque, accentColor.isOpaque else { return false }
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
    private static func phase(elapsed: Double, period: Double) -> Double {
        let period = usablePeriod(period)
        let wrapped = elapsed.truncatingRemainder(dividingBy: period)
        return (wrapped < 0 ? wrapped + period : wrapped) / period
    }

    /// How long one full pass of `style` takes.
    ///
    /// The cycle builder needs exactly what the renderer uses, so both read it
    /// off the configuration rather than keeping a table of their own.
    static func period(of style: IndeterminateStyle) -> Double {
        usablePeriod(style.configuration.period)
    }

    /// The period a pass takes when a configuration's cannot be used: the
    /// ``IndeterminateConfiguration/sweep`` preset's.
    static let fallbackPeriod: Double = 1.6

    /// `period` if it is finite and greater than zero; otherwise
    /// ``fallbackPeriod``, reported through `onRejection`.
    ///
    /// One rule for every reader, because there used to be two copies of
    /// `period > 0 ? period : 1.6`, and neither rejected infinity, which passes
    /// `> 0` and then trapped converting the frame count to an `Int`.
    ///
    /// The default report is a soft trap: an assertion failure in a debug build,
    /// a report once per distinct message in a release build. The parameter
    /// exists so a test can see what is rejected without stopping.
    static func usablePeriod(
        _ period: Double, onRejection report: (String) -> Void = { SoftTrap.report($0) }
    ) -> Double {
        guard period.isFinite, period > 0 else {
            report(
                "IndeterminateConfiguration.period must be finite and greater than zero, "
                    + "not \(period); using \(fallbackPeriod) s")
            return fallbackPeriod
        }
        return period
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
        empty: Color, accent: Color, head: Int
    ) -> ClaimingRow {
        let segment = segment(of: configuration, across: width)
        let fill = Array(configuration.fill)
        let unlit = Array(configuration.background)
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
    ///
    /// A pass is one step for each of the pattern's characters, since the pattern
    /// shifted by its own length is the pattern again: `"◢◤"` is two steps a pass,
    /// each held for half of it. A pass used to shift the pattern by twice the bar's
    /// WIDTH, and a cycle's 18 frames sampled that and read it modulo 2, so what the
    /// bar showed depended on the width it aliased with: at 36 cells every frame
    /// but one was the same picture, and at 20 it held for five frames, then four.
    private static func renderBarberPole(
        width: Int, configuration: IndeterminateConfiguration,
        filled: Color, accent: Color, shift: Int
    ) -> ClaimingRow {
        let fill = Array(configuration.fill)
        let stripes = configuration.gradient.map { $0.stops.map(\.color) }.flatMap {
            $0.isEmpty ? nil : $0
        } ?? [accent, filled]
        // `shift` is at least 0, so neither remainder below goes negative.
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
        dim: Color, bright: Color, phase: Double
    ) -> ClaimingRow {
        // A sine wave gives a smoother breath than a sawtooth `phase()`,
        // and clamping its `0..<2π` range to `[0, 1]` via `(1 - cos)/2`
        // makes the brightest and dimmest points sit at the start and
        // middle of each period — easier to read as "alive but waiting".
        let raw = phase * .pi * 2
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
    /// `Spinner.renderBouncingFrame` applies to its trail. `step` is which of the
    /// ``bounceSteps(width:)`` the lead is on, and a cycle's frames name them in
    /// order, so the documented `period` holds whatever the width. A pass with fewer
    /// frames than steps shows the far wall at its middle frame
    /// (``bounceStep(ofFrame:of:width:)``), so the lead reaches both ends however few
    /// frames it is drawn in.
    private static func renderKnightRider(
        width: Int, configuration: IndeterminateConfiguration,
        empty: Color, accent: Color, step: Int
    ) -> ClaimingRow {
        // At least one tail cell behind the lead wherever the track has room for
        // one: the preset's eighth of a track is under two cells below 16 columns,
        // and a lead with no tail is a different animation.
        let length = min(width, max(2, segment(of: configuration, across: width)))
        let fill = Array(configuration.fill)
        let unlit = Array(configuration.background)
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
    /// Scrolls left-to-right: subtracting `shift` from each cell's
    /// position means a given colour (say amber) reappears at a higher
    /// index as time passes, so the eye reads the gradient as moving
    /// rightward.
    ///
    /// `shift` is a whole number of samples, in `0..<samplesPerCell × width`, and cell
    /// c shows sample (`samplesPerCell` · c − shift), wrapped: every cell of a frame
    /// moves by the same amount, so one frame is the next one's ramp slid along. Each
    /// cell used to round its own float position in the ramp, and where that
    /// position was a tie the cells of one frame rounded different ways.
    private static func renderGradient(
        width: Int, configuration: IndeterminateConfiguration, shift: Int
    ) -> ClaimingRow {
        let ramp = cyclic(configuration.gradient)
        let fill = Array(configuration.fill)
        // The ramp, sampled once as a whole — four entries per cell, so the
        // motion still slides in quarter-cell steps — and quantised through
        // `Color.quantisedRamp`, which is what keeps a 256-colour host from
        // banding. Sampling `ramp.color(at:)` per cell went to the cube one
        // cell at a time and reversed four times across a 40-cell track.
        // Sampled `steps + 1` times, so that sample `steps` is the wrap back to
        // the first colour, and each sample sits where it always has; a frame
        // reads the first `steps` of them.
        let steps = samplesPerCell * max(1, width)
        let samples = Color.quantisedRamp(ramp, count: steps + 1, depth: ColorDepth.current)
        return laid(width: width) { column in
            let sample: Int = ((samplesPerCell * column - shift) % steps + steps) % steps
            return (glyph(fill, at: column), samples[sample])
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
