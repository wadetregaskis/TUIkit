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
