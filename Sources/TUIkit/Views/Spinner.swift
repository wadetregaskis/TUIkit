//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Spinner.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Spinner Style

/// The visual style of a spinner animation.
///
/// Built-in styles:
///
/// - ``dots``: Braille character rotation (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`)
/// - ``line``: ASCII line rotation (`|/-\`)
/// - ``dancingLine``: A large bracket walking around its corners (`⎛⎜⎞⎜⎝⎜⎠⎜`)
/// - ``bouncing``: A highlight block (`▇`) bouncing across a track with a fading trail (Knight Rider / Larson scanner)
/// - ``pie``: A rotating pie wedge (`◴◷◶◵`)
/// - ``beachball``: A spinning half-shaded circle (`◐◓◑◒`)
/// - ``box``: A rotating quadrant square (`◰◳◲◱`)
/// - ``curve``: A quarter-circle arc rotating around the cell (`◜◝◞◟`)
/// - ``column``: A single bar rising and falling (`▁▂▃▄▅▆▇█`)
/// - ``bar``: The same, sideways — a bar shrinking and growing (`█▉▊▋▌▍▎▏`)
/// - ``shade``: A cell fading up through the shade blocks and back (` ░▒▓▒░`)
/// - ``blockWedge``: A rotating three-quarter block (`▙▛▜▟`)
/// - ``spinningTriangle``: A triangle pointing around the compass (`▶▼◀▲`)
/// - ``moon``: Moon-phase emoji (`🌑🌒🌓🌔🌕🌖🌗🌘`)
/// - ``earth``: Rotating globe emoji (`🌎🌍🌏`)
/// - ``clock``: Clock-face emoji stepping through the day (`🕐🕜🕑…🕧`)
/// - ``custom(_:)``: An arbitrary sequence of frame characters
///
/// > Note: The emoji styles (``moon``, ``earth``, ``clock``) render as
/// > double-width glyphs. All frames of a built-in style share one width, so
/// > the spinner never jitters; a mixed-width ``custom(_:)`` sequence is the
/// > caller's responsibility.
public enum SpinnerStyle: Sendable {
    /// Braille character rotation.
    ///
    /// Cycles through: `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏`
    case dots

    /// ASCII line rotation.
    ///
    /// Cycles through: `| / - \`
    case line

    /// A large bracket walking around its four corners: `⎛ ⎜ ⎞ ⎜ ⎝ ⎜ ⎠ ⎜`.
    ///
    /// The straight extension (`⎜`) between each corner is what makes it read as
    /// one stroke travelling rather than four glyphs taking turns.
    case dancingLine

    /// A highlight block bouncing across a track of small squares with a
    /// fading trail behind it (Larson scanner / Knight Rider effect).
    ///
    /// The highlight moves back and forth across a fixed 9-position track.
    /// Three trailing positions fade out progressively, creating a smooth
    /// motion trail.
    case bouncing

    /// A rotating pie wedge: `◴ ◷ ◶ ◵`.
    case pie

    /// A spinning half-shaded circle: `◐ ◓ ◑ ◒`.
    case beachball

    /// A rotating filled quadrant of a square: `◰ ◳ ◲ ◱`.
    case box

    /// A quarter-circle arc rotating around the cell: `◜ ◝ ◞ ◟`.
    case curve

    /// A single bar rising then falling: `▁▂▃▄▅▆▇█▇▆▅▄▃▂`.
    ///
    /// Named for what it draws — one column of the cell filling upward. (It was
    /// `bars`, plural, which promised the several-bar equaliser this is not, and
    /// left no name for its sideways twin ``bar``.)
    case column

    /// A bar shrinking and growing sideways: `█▉▊▋▌▍▎▏▎▍▌▋▊▉`.
    ///
    /// ``column``'s horizontal twin, from the left-eighth blocks rather than the
    /// bottom ones. In code point order the eighths run from full to thinnest, so
    /// the sequence empties and refills rather than sweeping in one direction.
    case bar

    /// A cell fading up through the shade blocks and back: `⎵ ░ ▒ ▓ ▒ ░`.
    ///
    /// The first frame is a SPACE, deliberately: the cycle passes through empty,
    /// which is what makes it a pulse rather than a flicker between three shades.
    case shade

    /// A rotating three-quarter block: `▙ ▛ ▜ ▟`.
    case blockWedge

    /// A triangle pointing around the compass: `▶ ▼ ◀ ▲`.
    ///
    /// All four are East Asian Ambiguous, so a terminal that renders geometric
    /// shapes double-width renders all four that way and the spinner still does
    /// not jitter. TUIkit's own width model reserves one cell for each.
    case spinningTriangle

    /// Moon-phase emoji (double-width): `🌕🌖🌗🌘🌑🌒🌓🌔`.
    case moon

    /// Rotating globe emoji (double-width): `🌎🌍🌏`.
    case earth

    /// Clock-face emoji stepping through the twelve hours in half-hour steps
    /// (double-width): `🕐🕜🕑🕝…🕛🕧`.
    case clock

    /// An arbitrary spinner: each character of `sequence` is one frame, cycled
    /// in order. For example `.custom("123432")` counts up and back down.
    case custom(String)

    /// The animation frames for frame-based styles.
    var frames: [String] {
        switch self {
        case .dots:
            return ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        case .line:
            return ["|", "/", "-", "\\"]
        case .dancingLine:
            return ["⎛", "⎜", "⎞", "⎜", "⎝", "⎜", "⎠", "⎜"]
        case .bouncing:
            return Self.bouncingPositions(trackLength: Self.trackWidth)
                .map { String($0) }
        case .pie:
            return ["◴", "◷", "◶", "◵"]
        case .beachball:
            return ["◐", "◓", "◑", "◒"]
        case .box:
            return ["◰", "◳", "◲", "◱"]
        case .curve:
            return ["◜", "◝", "◞", "◟"]
        case .column:
            return ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂"]
        case .bar:
            return ["█", "▉", "▊", "▋", "▌", "▍", "▎", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
        case .shade:
            return [" ", "░", "▒", "▓", "▒", "░"]
        case .blockWedge:
            return ["▙", "▛", "▜", "▟"]
        case .spinningTriangle:
            return ["▶", "▼", "◀", "▲"]
        case .moon:
            return ["🌕", "🌖", "🌗", "🌘", "🌑", "🌒", "🌓", "🌔"]
        case .earth:
            return ["🌎", "🌍", "🌏"]
        case .clock:
            return [
                "🕐", "🕜", "🕑", "🕝", "🕒", "🕞", "🕓", "🕟", "🕔", "🕠", "🕕", "🕡",
                "🕖", "🕢", "🕗", "🕣", "🕘", "🕤", "🕙", "🕥", "🕚", "🕦", "🕛", "🕧",
            ]
        case .custom(let sequence):
            // Each grapheme is a frame; never empty, so the frame index is safe.
            let mapped = sequence.map(String.init)
            return mapped.isEmpty ? [" "] : mapped
        }
    }

    /// How long each frame of this style is shown at the standard speed, in
    /// seconds: a whole number of 1/60 s ticks, from 4 (66.7 ms) to 18 (300 ms).
    ///
    /// Each style's own pace, chosen by watching every style run on the Example's
    /// Spinners page, whose Frame stepper sets any one of them in ticks, rather
    /// than derived from one rule, which is why they span a factor of four.
    ///
    /// Whole ticks because a terminal's paint is shown on a display that refreshes
    /// 60 times a second: a frame of any other length is held for an uneven number
    /// of refreshes, and spinners whose frames are whole ticks change on the same
    /// refresh wherever their tick counts share a multiple.
    ///
    /// A spinner shows each frame for this long under
    /// ``IndicatorAnimationSpeed/standard``, and under the default,
    /// ``IndicatorAnimationSpeed/automatic``, which moves none of these intervals.
    /// Under another speed set with ``View/indicatorAnimationSpeed(_:for:)`` it
    /// shows each frame for ``IndicatorAnimationSpeed/frameTicks(standard:)`` of
    /// this interval: the whole number of ticks nearest this interval divided by the
    /// rate. So to show a style's frames for a whole number of ticks of your choosing,
    /// set the speed to this interval divided by that duration:
    ///
    /// ```swift
    /// // .dots, whose standard interval is 7 ticks (116.7 ms), at 6 ticks (100 ms) a frame
    /// let speed = IndicatorAnimationSpeed(
    ///     SpinnerStyle.dots.interval / AnimationClock.seconds(forTicks: 6))
    /// Spinner(style: .dots).indicatorAnimationSpeed(speed, for: .spinners)
    /// ```
    public var interval: TimeInterval {
        switch self {
        case .dots: return AnimationClock.seconds(forTicks: 7)
        case .line: return AnimationClock.seconds(forTicks: 8)
        case .dancingLine: return AnimationClock.seconds(forTicks: 14)
        case .bouncing: return AnimationClock.seconds(forTicks: 4)
        case .pie: return AnimationClock.seconds(forTicks: 18)
        case .beachball: return AnimationClock.seconds(forTicks: 18)
        case .box: return AnimationClock.seconds(forTicks: 18)
        case .curve: return AnimationClock.seconds(forTicks: 12)
        case .column: return AnimationClock.seconds(forTicks: 5)
        case .bar: return AnimationClock.seconds(forTicks: 5)
        case .shade: return AnimationClock.seconds(forTicks: 8)
        case .blockWedge: return AnimationClock.seconds(forTicks: 18)
        case .spinningTriangle: return AnimationClock.seconds(forTicks: 12)
        case .moon: return AnimationClock.seconds(forTicks: 7)
        case .earth: return AnimationClock.seconds(forTicks: 18)
        case .clock: return AnimationClock.seconds(forTicks: 15)
        case .custom: return AnimationClock.seconds(forTicks: 7)
        }
    }

    /// The fixed track width for the bouncing style (9 positions).
    static let trackWidth = 9

    /// The fixed trail opacities for the bouncing style.
    ///
    /// Index 0 is the highlight itself, followed by 5 fading positions.
    static let trailOpacities: [Double] = [1.0, 0.75, 0.5, 0.35, 0.22, 0.15]

    /// How many positions the highlight overshoots beyond each edge of
    /// the visible track. This lets the trail fade out smoothly at the
    /// edges instead of being cut off abruptly.
    static let edgeOvershoot = 2
}

// MARK: - Internal API

extension SpinnerStyle {
    /// Generates the bounce position sequence for the given track length.
    ///
    /// The highlight travels from `-edgeOvershoot` to
    /// `trackLength - 1 + edgeOvershoot`, then bounces back. Positions
    /// outside the visible range `0..<trackLength` are still valid — the
    /// highlight is off-screen there but its trail remains partially visible.
    ///
    /// - Parameter trackLength: The number of visible positions in the track.
    /// - Returns: An array of highlight positions for each frame.
    static func bouncingPositions(trackLength: Int) -> [Int] {
        let lower = -edgeOvershoot
        let upper = trackLength - 1 + edgeOvershoot
        var positions: [Int] = []

        // Forward: lower → upper
        for position in lower...upper {
            positions.append(position)
        }

        // Backward: upper-1 → lower+1 (skip endpoints to avoid double-pause)
        for position in stride(from: upper - 1, through: lower + 1, by: -1) {
            positions.append(position)
        }

        return positions
    }

    /// Renders a single bouncing frame with its colored afterglow.
    ///
    /// The trail is the highlight's own recent HISTORY: a cell is lit if the
    /// highlight stood on it within the last ``trailOpacities`` frames, and its
    /// brightness is how long ago. Nothing here consults a direction.
    ///
    /// That is the whole of it, and it has to be, because a Larson scanner
    /// reverses. Deriving the trail from the current direction instead — "the
    /// cells behind me, where behind means opposite to travel" — is right only
    /// mid-sweep. At each turnaround the direction flips while the glow is still
    /// on the far side, so the whole trail teleported across the highlight in one
    /// frame; the two frames where the highlight is off-track and the trail is
    /// "ahead" of it came out completely blank. On screen that read as the
    /// animation resetting before the dots reached the end.
    ///
    /// The history model also gives the edges their character for free: coming
    /// back from an overshoot the dot re-lights cells it lit on the way out, so
    /// the glow bunches up and fades at the turn instead of switching sides.
    ///
    /// - Parameters:
    ///   - frameIndex: The current frame index in the bounce sequence.
    ///   - color: The resolved highlight color for the leading dot.
    ///   - trackColor: The color for inactive track positions.
    /// - Returns: An ANSI-colored string representing the track.
    static func renderBouncingFrame(
        frameIndex: Int,
        color: Color,
        trackColor: Color
    ) -> String {
        let positions = bouncingPositions(trackLength: trackWidth)
        let cycle = positions.count

        var result = ""
        for trackIndex in 0..<trackWidth {
            // How many frames ago the highlight was last here, capped at the
            // trail's memory. The FRESHEST visit wins: at a turnaround a cell
            // has been visited twice, and the newer one is what is glowing.
            var age: Int?
            for back in 0..<trailOpacities.count {
                let index = ((frameIndex - back) % cycle + cycle) % cycle
                if positions[index] == trackIndex {
                    age = back
                    break
                }
            }

            guard let age else {
                result += ANSIRenderer.colorize("●", foreground: trackColor)
                continue
            }
            if age == 0 {
                // The highlight itself.
                result += ANSIRenderer.colorize("●", foreground: color)
            } else {
                let phase = 1.0 - trailOpacities[age]
                result += ANSIRenderer.colorize(
                    "●", foreground: Color.lerp(color, trackColor, phase: phase))
            }
        }

        return result
    }
}

// MARK: - Spinner

/// An animated loading indicator.
///
/// `Spinner` displays a continuously animating indicator to communicate
/// that a task is in progress. It supports multiple visual styles and
/// an optional label.
///
/// The animation is not a task, and nothing starts or stops with the spinner
/// appearing: the frame comes from the shared content clock, so every spinner of
/// a style is in phase, and the spinner leaves one ``AnimatedCellRun`` over its
/// own cells for the run loop to splice at the style's interval (at the speed set
/// for spinners, see below) — no re-render,
/// no re-measure, nothing asked of this view (`99b91c0f`). Only a
/// ``SpinnerStyle/custom(_:)`` sequence whose frames are not all one width
/// escapes that, since a run must claim exactly the cells every frame fills; it
/// falls back to asking the loop to re-render at the style's rate, and takes its
/// frame from the frame clock, since nothing keeps the cursor timer running for it.
///
/// # Example
///
/// ```swift
/// // Simple dots spinner
/// Spinner()
///
/// // With label
/// Spinner("Loading...")
///
/// // Bouncing style with custom color
/// Spinner("Processing...", style: .bouncing, color: .cyan)
/// ```
///
/// # Styles
///
/// | Style | Visual | Interval |
/// |-------|--------|----------|
/// | `.dots` | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` | 116.7ms (7 ticks of 1/60 s) |
/// | `.line` | `\| / - \\` | 133.3ms (8 ticks) |
/// | `.bouncing` | `■■▇▇▇▇■■■` (with fade trail) | 66.7ms (4 ticks) |
///
/// Three of many, not the set: ``SpinnerStyle`` carries the rest, each with its
/// own frames and interval, and ``SpinnerStyle/custom(_:)`` takes a sequence of
/// your own.
///
/// # Speed
///
/// Those intervals are each style's standard speed.
/// ``View/indicatorAnimationSpeed(_:for:)`` with ``IndicatorAnimations/spinners``
/// sets another for a subtree, and it reaches the spinner a `refreshable` view
/// draws too:
///
/// ```swift
/// // .dots at 233.3ms (14 ticks) a frame
/// Spinner("Loading...").indicatorAnimationSpeed(.halfSpeed, for: .spinners)
/// ```
public struct Spinner: View {
    /// The optional label displayed after the spinner.
    let label: String?

    /// The animation style.
    let style: SpinnerStyle

    /// The spinner color (uses theme accent if nil).
    let color: Color?

    /// Creates a spinner with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The label is not optional in this overload:
    /// `Spinner()` and `Spinner(nil)` have no label to look up, and defaulting
    /// it here would make them ambiguous.
    ///
    /// - Parameters:
    ///   - labelKey: The key for text displayed after the spinner indicator.
    ///   - style: The animation style (default: `.dots`).
    ///   - color: The spinner color (default: theme accent).
    public init(
        _ labelKey: LocalizedStringKey,
        style: SpinnerStyle = .dots,
        color: Color? = nil
    ) {
        self.init(labelKey.localized, style: style, color: color)
    }

    /// Creates a spinner labelled as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``. It is also SwiftUI's own spelling, so a
    /// `Substring` no longer has to be copied at the call site.
    ///
    /// Non-optional, because a generic parameter cannot be inferred from `nil`.
    /// The optional label — and with it `Spinner()`'s default — therefore stays
    /// on the concrete overload below.
    ///
    /// - Parameters:
    ///   - label: Text displayed after the spinner indicator.
    ///   - style: The animation style (default: `.dots`).
    ///   - color: The spinner color (default: theme accent).
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ label: S,
        style: SpinnerStyle = .dots,
        color: Color? = nil
    ) {
        self.label = String(label)
        self.style = style
        self.color = color
    }

    /// Creates a spinner with an optional label, displayed as written.
    ///
    /// Stays concrete, and keeps the default, because the generic overload
    /// above can express neither: a generic parameter cannot be inferred from
    /// `nil`, and cannot carry a default argument at all. So this is the
    /// overload `Spinner()`, `Spinner(nil)` and a `String?` in hand all reach.
    ///
    /// Unlike a concrete *non-optional* `String`, it cannot take a literal away
    /// from the key overload: binding one here costs an optional injection,
    /// which ranks below both siblings. That is why it did not have to be split
    /// the way ``QuitShortcut``'s label was.
    ///
    /// - Parameters:
    ///   - label: Text displayed after the spinner indicator, or `nil` for none.
    ///   - style: The animation style (default: `.dots`).
    ///   - color: The spinner color (default: theme accent).
    @_disfavoredOverload
    public init(
        _ label: String? = nil,
        style: SpinnerStyle = .dots,
        color: Color? = nil
    ) {
        self.label = label
        self.style = style
        self.color = color
    }

    public var body: some View {
        _SpinnerCore(
            label: label,
            style: style,
            color: color
        )
    }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering and animation of Spinner.
private struct _SpinnerCore: View, Renderable, Layoutable {
    let label: String?
    let style: SpinnerStyle
    let color: Color?

    var body: Never {
        fatalError("_SpinnerCore renders via Renderable")
    }

    /// A spinner is fixed-size (a fixed-width glyph plus an optional fixed label),
    /// so a single render is its exact, fixed measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        // Explicit colour > environment foregroundStyle > palette accent.
        let effectiveColor =
            color ?? context.environment.foregroundStyle?.representative ?? palette.accent
        let resolvedColor = effectiveColor.resolve(with: palette)

        /// The whole cycle, already styled — one entry per frame of the STYLE,
        /// shown for the style's own interval.
        ///
        /// Its own interval exactly, not rounded to anything: a run carries its
        /// frame duration, so `.dots` runs at the 7/60 s it asks for and the
        /// loop wakes for it then. This used to be resampled onto a fixed 0.05 s
        /// grid, which forced a choice between a visible limp (`.dots`, then
        /// 0.110 s, drew frames of 2, 2, 3, 2, 2, 3 of those steps) and a changed
        /// speed (0.110 rounded to 0.100).
        let cycle = spinnerFrames(color: resolvedColor, context: context)
        let glyphWidths = Set(cycle.map(\.strippedLength))

        // The frame clock, not a per-spinner start time: every spinner of a style is
        // then in phase, and — much more to the point — the frame drawn is the frame
        // the run loop will replay, so the first tick does not jump. The run replays on
        // the cursor timer's content clock, and every render shows the timer this
        // frame's time before the tree is walked, so here the two are one instant
        // (§74). A cycle whose frames are not all one width leaves no run and reads the
        // same clock; it used to need a branch of its own (§66), and a render with no
        // timer at all drew the run-backed spinner's first frame whatever the time.
        let elapsed = Double(context.environment.frameNowNanos) / 1_000_000_000
        // The style's interval at the speed set for spinners here. One value for the
        // frame drawn, the run left and the fallback's wake, so none of them can step
        // at a different rate from the others.
        let frameTicks = context.environment.indicatorAnimationSpeeds.speed(for: .spinners)
            .frameTicks(standard: style.interval)
        // Through the conversion the run's own index uses, so the frame drawn here is
        // the frame the loop replays: a floor in seconds put a summed `.dots` clock one
        // step short at steps 27–40, and every render on such a wake stuttered back.
        let step = AnimationClock.step(atElapsed: elapsed, frameTicks: frameTicks)
        let count = Int64(max(1, cycle.count))
        let frameIndex = cycle.isEmpty ? 0 : Int(((step % count) + count) % count)
        let coloredSpinner = cycle.isEmpty ? "" : cycle[frameIndex]

        let output: String
        /// Where the label landed, for its own claim — it is drawn in a different
        /// colour from the glyph, so it is a different rectangle.
        var labelColumns: (x: Int, width: Int)?
        if let label, !label.isEmpty {
            // A whitespace-only label is honoured, not dropped: it is an explicit
            // request for trailing space (e.g. the no-break-space padding labels
            // some apps use for alignment — U+00A0 satisfies `isWhitespace`).
            let styledLabel = ANSIRenderer.colorize(
                label, foreground: palette.foreground.opaqueSpelling)
            output = coloredSpinner + " " + styledLabel
            labelColumns = (coloredSpinner.strippedLength + 1, styledLabel.strippedLength)
        } else {
            // No label (or an empty one) — render just the spinner glyph, with no
            // trailing separator space.
            output = coloredSpinner
        }
        var buffer = FrameBuffer(text: output)
        // Two claims, because a spinner draws two things in two colours: its glyph
        // in the accent (or whatever `.foregroundStyle` said) and its label in the
        // palette's foreground. `.bouncing` is excluded because it has nothing left
        // to claim: it SPENDS its colour instead, a ramp being the one shape a
        // rectangle cannot describe — see `spinnerFrames`.
        var isBouncing: Bool { if case .bouncing = style { true } else { false } }
        if !isBouncing, let glyphWidth = cycle.first?.strippedLength,
            let claim = OpacityRegion.claim(
                width: glyphWidth, height: 1, ink: resolvedColor)
        {
            buffer.opacityRegions.append(claim)
        }
        if let labelColumns,
            let claim = OpacityRegion.claim(
                offsetX: labelColumns.x, width: labelColumns.width, height: 1,
                ink: palette.foreground)
        {
            buffer.opacityRegions.append(claim)
        }

        // A measure pass draws nothing, so a run left on it would describe cells
        // that were never on screen — and would keep the clock alive from a pass
        // that produced no frame.
        guard !context.isMeasuring, let width = glyphWidths.first, glyphWidths.count == 1,
            width > 0, cycle.count > 1
        else {
            // Either nothing to animate, or a cycle whose frames are not all one
            // width — which a run cannot express, because every frame must
            // occupy exactly the cells the run claims. A mixed-width
            // `.custom(_:)` sequence is the only way to get here, and it falls
            // back to re-rendering the whole screen: one render at the next step
            // of its frame duration on the frame clock, the step it draws from,
            // and that render asks for the one after. It used to ask for a grid at
            // the style's rate, anchored at whichever frame first asked rather
            // than at the steps, so every render landed part-way through one.
            if !context.isMeasuring, cycle.count > 1 {
                context.requestWake(
                    token: "spinner-\(context.identity.path)",
                    atNanos: AnimationClock.stepEndNanos(atElapsed: elapsed, frameTicks: frameTicks))
            }
            return buffer
        }

        // Every tick of the cycle, so the run loop can splice the right glyph
        // over these cells without asking this view anything. Nothing is
        // measured, nothing is laid out, and the screen is not re-rendered — the
        // saving this whole mechanism exists for. See ``AnimatedCellRun``.
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: width, frames: cycle,
                frameTicks: frameTicks, clock: .content)
        ]
        return buffer
    }

    /// The spinner's glyphs, styled, one per frame of the STYLE (not per tick).
    private func spinnerFrames(color: Color, context: RenderContext) -> [String] {
        switch style {
        case .bouncing:
            // BOTH ends spent against the page, so every cell of every frame states a
            // concrete colour and nothing claims. The trail LERPS between them, and a
            // lerp of a faded colour with an opaque one makes an alpha nobody
            // authored — 192, out of 128 and 255 — which is how this reached the
            // emitter (§68.6). No rectangle can describe a ramp whose cells change
            // colour every frame, so the alternative to spending is the trap that was
            // here; and spending is what §29 prescribes for a pair whose ends
            // disagree about alpha. `trackColor` was already doing it, by the `over:`
            // on its own `opacity(_:)` — this is the other end getting the same
            // treatment from the same ground.
            let palette = context.environment.palette
            let trackColor = palette.foregroundQuaternary.opacity(0.4, over: palette.background)
            let positions = SpinnerStyle.bouncingPositions(trackLength: SpinnerStyle.trackWidth)
            return positions.indices.map {
                SpinnerStyle.renderBouncingFrame(
                    frameIndex: $0, color: color.spendingAlpha(over: palette.background),
                    trackColor: trackColor)
            }
        default:
            // The opaque spelling, with the alpha claimed in `renderToBuffer`. Safe
            // across the whole cycle precisely because every frame is this one
            // colour — only the glyph changes — so one region describes them all.
            // `.bouncing` above is the exception: it cannot be claimed, so it spends
            // instead, which is why it is the one style that claims nothing.
            return style.frames.map { ANSIRenderer.colorize($0, foreground: color.opaqueSpelling) }
        }
    }
}
