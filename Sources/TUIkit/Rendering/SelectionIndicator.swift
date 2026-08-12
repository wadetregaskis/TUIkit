//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SelectionIndicator.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Style

/// How a focused selection indicator (a swatch-grid cursor, and any control that
/// adopts this convention) animates to show it holds the keyboard focus.
///
/// Reuses the text cursor's ``TextCursorStyle/Animation`` cases and
/// ``TextCursorStyle/Speed`` so the convention reads the same as the cursor — but
/// it defaults to ``TextCursorStyle/Animation/pulse`` (a focused selection should
/// breathe), and is configured independently via ``View/selectionIndicatorStyle(_:)``.
///
/// In the ``TextCursorStyle/Animation/none`` case there is no animation, so focus
/// is shown by colour / bold alone.
///
/// TUI-specific: SwiftUI has no equivalent.
public struct SelectionIndicatorStyle: Equatable, Sendable {
    /// The animation applied to a focused indicator.
    public var animation: TextCursorStyle.Animation

    /// The animation rate — shared with the text cursor's speed scale.
    public var speed: TextCursorStyle.Speed

    /// Creates a selection-indicator style.
    ///
    /// - Parameters:
    ///   - animation: `none`, `blink`, or `pulse` (default `pulse`).
    ///   - speed: the animation rate (default `regular`).
    public init(animation: TextCursorStyle.Animation = .pulse, speed: TextCursorStyle.Speed = .regular) {
        self.animation = animation
        self.speed = speed
    }
}

private struct SelectionIndicatorStyleKey: EnvironmentKey {
    static let defaultValue = SelectionIndicatorStyle()
}

extension EnvironmentValues {
    /// How focused selection indicators animate within this view.
    public var selectionIndicatorStyle: SelectionIndicatorStyle {
        get { self[SelectionIndicatorStyleKey.self] }
        set { self[SelectionIndicatorStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets how focused selection indicators animate (the swatch-grid cursor, etc.).
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    public func selectionIndicatorStyle(_ style: SelectionIndicatorStyle) -> some View {
        environment(\.selectionIndicatorStyle, style)
    }

    /// Sets the selection-indicator animation and (optionally) speed.
    public func selectionIndicatorStyle(
        _ animation: TextCursorStyle.Animation, speed: TextCursorStyle.Speed = .regular
    ) -> some View {
        environment(\.selectionIndicatorStyle, SelectionIndicatorStyle(animation: animation, speed: speed))
    }
}

// MARK: - Resolver

/// Resolves the per-frame colour of a focused selection indicator, honouring the
/// ``SelectionIndicatorStyle`` (none / blink / pulse) at the configured rate.
///
/// Resolve once per render (the animation phase is shared across cells); then call
/// ``Resolution/color(dim:bright:)`` per element with that element's own dim/bright
/// endpoints (e.g. a swatch's own colour → a contrasting mark).
enum SelectionIndicator {
    typealias Resolution = SelectionEmphasis

    /// Resolves the animation state for this frame. Reads the cursor clock only
    /// when actually animating (focused + not `.none`) — that volatile read is what
    /// keeps the clock ticking, so an idle indicator costs nothing.
    @MainActor
    static func resolve(isFocused: Bool, context: RenderContext) -> SelectionEmphasis {
        resolve(isFocused: isFocused, environment: context.environment)
    }

    /// The environment-only resolution. `RenderContext` adds nothing here — only
    /// its environment is ever read — and a plain `View` body (a `ButtonStyle`,
    /// say) has no context to offer, which is why this is the primitive and the
    /// context overload forwards to it.
    @MainActor
    static func resolve(isFocused: Bool, environment: EnvironmentValues) -> SelectionEmphasis {
        let style = environment.selectionIndicatorStyle
        guard isFocused, style.animation != .none else {
            return SelectionEmphasis(
                isFocused: isFocused, animation: style.animation, phase: 1, blinkOn: true)
        }
        let timer = environment.cursorTimer
        let phase = timer?.pulsePhase(for: style.speed) ?? environment.pulsePhase
        let blinkOn = timer?.blinkVisible(for: style.speed) ?? true
        return SelectionEmphasis(
            isFocused: isFocused, animation: style.animation, phase: phase, blinkOn: blinkOn)
    }
}

// MARK: - Per-frame emphasis

/// One frame of the shared focus emphasis — what a focused element should look
/// like *right now*, given the in-force ``SelectionIndicatorStyle``.
///
/// Ask ``EnvironmentValues/selectionEmphasis`` for one and then call
/// ``color(dim:bright:)`` with the element's own two endpoints. That single call
/// covers every setting: a pulse lerps between them, a blink swaps between them,
/// `.none` sits at `bright`, and an unfocused element sits at `bright` too — so a
/// caller never has to branch on the style itself.
public struct SelectionEmphasis: Equatable, Sendable {
    /// Whether the element this describes holds the focus.
    public let isFocused: Bool

    /// The animation in force (`.none` / `.blink` / `.pulse`).
    public let animation: TextCursorStyle.Animation

    /// The pulse position this frame, 0...1 (1 when not pulsing).
    public let phase: Double

    /// The blink state this frame (always `true` when not blinking).
    public let blinkOn: Bool

    /// A non-animated emphasis (the element sits steady at `bright`), for the
    /// given focus state. Handy when there is no clock to read.
    public static func steady(isFocused: Bool) -> Self {
        Self(isFocused: isFocused, animation: .none, phase: 1, blinkOn: true)
    }

    /// The colour this frame.
    ///
    /// - `dim`: the "off"/recessive endpoint (e.g. the element's own colour, so
    ///   the mark fades into it).
    /// - `bright`: the "on"/visible endpoint (e.g. a contrasting mark colour).
    ///
    /// An unfocused-but-selected indicator stays at `bright` (steady, visible);
    /// a focused one animates between the two per the style.
    public func color(dim: Color, bright: Color) -> Color {
        guard isFocused else { return bright }
        switch animation {
        case .none: return bright
        case .blink: return blinkOn ? bright : dim
        case .pulse: return Self.pulsed(dim: dim, bright: bright, phase: phase)
        }
    }

    /// The pulse position, snapped to the shades this terminal can actually
    /// show.
    ///
    /// A plain `lerp` sampled on an even time grid is right only where the
    /// colour space is continuous. On a 256-colour terminal it is not: the ramp
    /// rounds onto a handful of cube entries, so the fade sits still and then
    /// jumps, and — because the cube has no dark tinted colours — its bottom end
    /// turns GREY, which reads as a glitch rather than a dim. Walking the
    /// distinct, in-hue shades at even intervals instead gives every one of them
    /// the same screen time. See ``Color/pulseRamp(from:to:depth:samples:)``.
    private static func pulsed(dim: Color, bright: Color, phase: Double) -> Color {
        let depth = ColorDepth.current
        guard depth < .truecolor else { return Color.lerp(dim, bright, phase: phase) }
        let ramp = Color.pulseRamp(from: dim, to: bright, depth: depth)
        guard ramp.count > 1 else { return ramp[0] }
        let step = Int((phase * Double(ramp.count)).rounded(.down))
        return ramp[min(max(0, step), ramp.count - 1)]
    }
}

/// The frame's focus-emphasis clock, read from the environment.
///
/// ```swift
/// @Environment(\.selectionEmphasis) private var emphasis
/// …
/// let colour = emphasis(isFocused).color(dim: quiet, bright: loud)
/// ```
///
/// Resolving is what keeps the clock ticking — the phase read is volatile, so a
/// frame that asks for an animating emphasis schedules the next frame, and one
/// that doesn't lets the loop idle. Nothing is read at all unless the element is
/// focused AND the style actually animates.
public struct SelectionEmphasisClock {
    let environment: EnvironmentValues

    /// The emphasis for an element that is (or isn't) focused right now.
    @MainActor
    public func callAsFunction(_ isFocused: Bool) -> SelectionEmphasis {
        SelectionIndicator.resolve(isFocused: isFocused, environment: environment)
    }
}

// MARK: - The whole cycle

/// Every frame of the focus emphasis, plus where it is right now.
///
/// The counterpart to ``SelectionEmphasis``, which is one frame. A view that
/// draws a focus indicator has two ways to animate it:
///
/// - Ask for the emphasis and colour with it. Simple, and it costs a full
///   re-render of the screen on every tick of the clock.
/// - Ask for the cycle, draw `frames[step]` now, and leave an
///   ``AnimatedCellRun`` behind. The run loop then advances those cells alone,
///   with no view involved at all.
///
/// Building the cycle does **not** consult the live clock (it computes each
/// frame from `CursorTimer`'s static formula), which is exactly what makes the
/// second route legal: nothing about this frame's appearance depends on *when*
/// it was rendered, so it can be reproduced without rendering.
public struct SelectionEmphasisCycle: Sendable {
    /// One emphasis per tick of a full cycle.
    public let frames: [SelectionEmphasis]

    /// Where the clock is now — the index to draw immediately.
    public let step: Int

    /// Whether this actually animates. A `.none` style, or an unfocused
    /// element, is a single frame: a still picture, not an animation.
    public var isAnimating: Bool { frames.count > 1 }

    /// The colour at each frame, for an element with these two endpoints.
    @MainActor
    public func colors(dim: Color, bright: Color) -> [Color] {
        frames.map { $0.color(dim: dim, bright: bright) }
    }

    /// The colour to draw *right now* — `colors(dim:bright:)` at ``step``.
    ///
    /// The modulo matters: the clock's tick count is unbounded and keeps
    /// running while nothing is focused, so `step` routinely exceeds the
    /// cycle's length.
    @MainActor
    public func colorNow(dim: Color, bright: Color) -> Color {
        frames[step % frames.count].color(dim: dim, bright: bright)
    }

    /// A run that breathes a single glyph at `(offsetX, offsetY)`, or `nil`
    /// when this cycle is still.
    ///
    /// The nil case is not an omission to paper over: a still glyph was already
    /// drawn by the ordinary render, and a run would have the loop rewrite it
    /// on every tick to no visible effect. Only movement earns a run.
    ///
    /// The run's width is the glyph's own width in *cells*, which is what
    /// ``AnimatedCellRun`` promises and not always what the glyph's character
    /// count suggests — `●` is East Asian Ambiguous, and the radio bullet and a
    /// box-drawing cap do not measure alike everywhere.
    @MainActor
    public func run(
        _ glyph: String, dim: Color, bright: Color, offsetX: Int, offsetY: Int
    ) -> AnimatedCellRun? {
        guard isAnimating else { return nil }
        return AnimatedCellRun(
            offsetX: offsetX,
            offsetY: offsetY,
            width: glyph.strippedLength,
            // One finished, styled string per step, so the loop's per-tick work
            // is an array index.
            frames: colors(dim: dim, bright: bright).map {
                ANSIRenderer.colorize(glyph, foreground: $0)
            },
            // The cursor clock, because that is the one this cycle's frames were
            // laid out on (`CursorTimer.cycleTicks`) — a run handed to the pulse
            // clock would advance at a different rate than it was built for.
            clock: .cursor)
    }
}

extension SelectionEmphasisClock {
    /// Every frame of the cycle for an element that is (or isn't) focused.
    ///
    /// See ``SelectionEmphasisCycle``.
    @MainActor
    public func cycle(_ isFocused: Bool) -> SelectionEmphasisCycle {
        let style = environment.selectionIndicatorStyle
        guard isFocused, style.animation != .none else {
            return SelectionEmphasisCycle(
                frames: [
                    SelectionEmphasis(
                        isFocused: isFocused, animation: style.animation, phase: 1, blinkOn: true)
                ],
                step: 0)
        }
        let ticks = CursorTimer.cycleTicks(for: style.speed, animation: style.animation)
        let frames = (0..<ticks).map { tick in
            SelectionEmphasis(
                isFocused: true,
                animation: style.animation,
                phase: CursorTimer.pulsePhase(atTick: tick, speed: style.speed),
                blinkOn: CursorTimer.blinkVisible(atTick: tick, speed: style.speed))
        }
        // `elapsedTicks` is a plain read: unlike `pulsePhase(for:)` it does not
        // mark the frame as having consulted the clock, so a producer that uses
        // it stays replayable.
        return SelectionEmphasisCycle(frames: frames, step: environment.cursorTimer?.elapsedTicks ?? 0)
    }
}

extension EnvironmentValues {
    /// The shared focus-emphasis clock — the one place that decides how a
    /// focused element breathes, blinks, or simply sits bright.
    ///
    /// Every built-in control resolves through this, so anything an app builds
    /// keeps step with them and honours
    /// ``View/selectionIndicatorStyle(_:)`` for free. TUI-specific:
    /// SwiftUI has no equivalent, because it has no shared terminal-wide pulse.
    public var selectionEmphasis: SelectionEmphasisClock {
        SelectionEmphasisClock(environment: self)
    }
}
