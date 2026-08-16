//  🖥️ TUIKit — Terminal UI Kit for Swift
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
/// - ``bouncing``: A highlight block (`▇`) bouncing across a track with a fading trail (Knight Rider / Larson scanner)
/// - ``pie``: A rotating pie wedge (`◴◷◶◵`)
/// - ``beachball``: A spinning half-shaded circle (`◐◓◑◒`)
/// - ``box``: A rotating quadrant square (`◰◳◲◱`)
/// - ``bars``: A single bar rising and falling (`▁▂▃▄▅▆▇█`)
/// - ``blockWedge``: A rotating three-quarter block (`▙▛▜▟`)
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

    /// A single bar rising then falling: `▁▂▃▄▅▆▇█▇▆▅▄▃▂`.
    case bars

    /// A rotating three-quarter block: `▙ ▛ ▜ ▟`.
    case blockWedge

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
        case .bouncing:
            return Self.bouncingPositions(trackLength: Self.trackWidth)
                .map { String($0) }
        case .pie:
            return ["◴", "◷", "◶", "◵"]
        case .beachball:
            return ["◐", "◓", "◑", "◒"]
        case .box:
            return ["◰", "◳", "◲", "◱"]
        case .bars:
            return ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂"]
        case .blockWedge:
            return ["▙", "▛", "▜", "▟"]
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

    /// The fixed animation interval for this style.
    var interval: TimeInterval {
        switch self {
        case .dots: return 0.110
        case .line: return 0.140
        case .bouncing: return 0.100
        case .pie: return 0.120
        case .beachball: return 0.130
        case .box: return 0.125
        case .bars: return 0.080
        case .blockWedge: return 0.120
        case .moon: return 0.120
        case .earth: return 0.150
        case .clock: return 0.090
        case .custom: return 0.120
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
/// The animation runs automatically via a background task that triggers
/// re-renders at a fixed interval. The task is started when the spinner
/// first appears and cancelled when it disappears.
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
/// | `.dots` | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` | 110ms |
/// | `.line` | `\| / - \\` | 140ms |
/// | `.bouncing` | `■■▇▇▇▇■■■` (with fade trail) | 100ms |
public struct Spinner: View {
    /// The optional label displayed after the spinner.
    let label: String?

    /// The animation style.
    let style: SpinnerStyle

    /// The spinner color (uses theme accent if nil).
    let color: Color?

    /// Creates a spinner with an optional label.
    ///
    /// - Parameters:
    ///   - label: Text displayed after the spinner indicator.
    ///   - style: The animation style (default: `.dots`).
    ///   - color: The spinner color (default: theme accent).
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
        let stateStorage = context.stateStorage!

        // Retrieve or create persistent start time for this spinner.
        let timeKey = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let startTimeBox: StateBox<Double> = stateStorage.storage(for: timeKey, default: Date().timeIntervalSinceReferenceDate)
        stateStorage.markActive(context.identity)

        // The frame shown is derived from elapsed wall-clock time, so the spinner
        // only advances when re-rendered over time. Ask the run loop's scheduler
        // to re-render us at the style's own rate — replacing a per-spinner task
        // that fired ~42 Hz regardless of the ~7–10 Hz the styles actually want.
        // Keyed by structural identity; several spinners at one rate coalesce onto
        // a single render, and a spinner that scrolls off stops re-declaring and
        // is dropped (so a screen with no spinners renders nothing).
        context.requestAnimation(
            token: "spinner-\(context.identity.path)",
            frequency: 1.0 / style.interval)

        // Calculate frame index from elapsed time.
        let elapsed = Date().timeIntervalSinceReferenceDate - startTimeBox.value
        let frameCount: Int
        switch style {
        case .bouncing:
            frameCount = SpinnerStyle.bouncingPositions(trackLength: SpinnerStyle.trackWidth).count
        default:
            frameCount = style.frames.count
        }
        let frameIndex = Int(elapsed / style.interval) % max(1, frameCount)

        // Resolve color: explicit color > environment foregroundStyle > palette accent
        let effectiveColor = color ?? context.environment.foregroundStyle ?? context.environment.palette.accent
        let resolvedColor = effectiveColor.resolve(with: context.environment.palette)

        // Build spinner text — bouncing renders with colored trail, others are plain.
        let coloredSpinner: String
        switch style {
        case .bouncing:
            coloredSpinner = SpinnerStyle.renderBouncingFrame(
                frameIndex: frameIndex,
                color: resolvedColor,
                trackColor: context.environment.palette.foregroundQuaternary.opacity(
                    0.4, over: context.environment.palette.background)
            )
        default:
            coloredSpinner = ANSIRenderer.colorize(
                style.frames[frameIndex],
                foreground: resolvedColor
            )
        }

        let output: String
        if let label, !label.isEmpty {
            // A whitespace-only label is honoured, not dropped: it is an explicit
            // request for trailing space (e.g. the no-break-space padding labels
            // some apps use for alignment — U+00A0 satisfies `isWhitespace`).
            let styledLabel = ANSIRenderer.colorize(label, foreground: context.environment.palette.foreground)
            output = coloredSpinner + " " + styledLabel
        } else {
            // No label (or an empty one) — render just the spinner glyph, with no
            // trailing separator space.
            output = coloredSpinner
        }

        return FrameBuffer(text: output)
    }
}
