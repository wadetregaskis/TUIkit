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
    struct Resolution {
        let isFocused: Bool
        let animation: TextCursorStyle.Animation
        let phase: Double
        let blinkOn: Bool

        /// A non-animated resolution (the indicator sits steady at `bright`), for
        /// the given focus state. Handy when there is no clock to read.
        static func steady(isFocused: Bool) -> Self {
            Self(isFocused: isFocused, animation: .none, phase: 1, blinkOn: true)
        }

        /// The indicator colour this frame.
        ///
        /// - `dim`: the "off"/recessive endpoint (e.g. the element's own colour, so
        ///   the mark fades into it).
        /// - `bright`: the "on"/visible endpoint (e.g. a contrasting mark colour).
        ///
        /// An unfocused-but-selected indicator stays at `bright` (steady, visible);
        /// a focused one animates between the two per the style.
        func color(dim: Color, bright: Color) -> Color {
            guard isFocused else { return bright }
            switch animation {
            case .none: return bright
            case .blink: return blinkOn ? bright : dim
            case .pulse: return Color.lerp(dim, bright, phase: phase)
            }
        }
    }

    /// Resolves the animation state for this frame. Reads the cursor clock only
    /// when actually animating (focused + not `.none`) — that volatile read is what
    /// keeps the clock ticking, so an idle indicator costs nothing.
    @MainActor
    static func resolve(isFocused: Bool, context: RenderContext) -> Resolution {
        let style = context.environment.selectionIndicatorStyle
        guard isFocused, style.animation != .none else {
            return Resolution(isFocused: isFocused, animation: style.animation, phase: 1, blinkOn: true)
        }
        let timer = context.environment.cursorTimer
        let phase = timer?.pulsePhase(for: style.speed) ?? context.environment.pulsePhase
        let blinkOn = timer?.blinkVisible(for: style.speed) ?? true
        return Resolution(
            isFocused: isFocused, animation: style.animation, phase: phase, blinkOn: blinkOn)
    }
}
