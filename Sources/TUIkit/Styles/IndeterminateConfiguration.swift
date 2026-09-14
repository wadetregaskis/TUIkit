//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateConfiguration.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Indeterminate Configuration

/// A fully-configurable recipe for an indeterminate progress animation — the
/// "no known total" twin of ``TrackConfiguration``.
///
/// Every built-in ``IndeterminateStyle`` is a preset of this (see the static
/// members below), so the named styles and a hand-rolled
/// ``IndeterminateStyle/custom(_:)`` share one renderer. That is what lets a
/// caller keep the motion it likes and change only the glyphs, or keep the
/// glyphs and slow the motion down, without the framework predefining every
/// combination.
///
/// ```swift
/// // Knight Rider's bounce, drawn in dots, at half speed:
/// ProgressView()
///     .indeterminateStyle(.custom(
///         IndeterminateConfiguration(
///             motion: .knightRider, fill: "●", background: "·", period: 4)))
/// ```
public struct IndeterminateConfiguration: Sendable, Equatable {

    /// The shape of the movement — what the animation DOES, as distinct from
    /// what it is drawn with.
    public enum Motion: String, Sendable, Equatable, CaseIterable {
        /// A lit run with a fading trail travels the track and wraps.
        case sweep
        /// The fill pattern shifts one cell per step, its glyphs coloured in
        /// turn from ``IndeterminateConfiguration/gradient`` — diagonal stripes
        /// that appear to scroll.
        case barberPole
        /// The whole track breathes between the two ends of the ramp.
        case pulse
        /// A lit run bounces end to end, its trail behind the direction of
        /// travel so the leading edge stays sharp.
        case knightRider
        /// The ramp is laid across the whole track and slid along it, cyclically
        /// — no unlit cells at all.
        case gradient
    }

    /// What the animation does.
    public var motion: Motion

    /// The pattern drawn where the track is LIT, repeated cyclically and
    /// anchored to the track: cell *j* always takes the same pattern character,
    /// so the texture stays put while the motion sweeps over it.
    ///
    /// A single character is the classic solid run. For ``Motion/barberPole``
    /// the pattern IS the stripe — its characters are what shifts — so `"◢◤"`
    /// gives the built-in look and `"╱ "` a sparser one.
    ///
    /// Multi-cell characters (emoji, CJK) are laid whole: one that would cross
    /// the track's last column is dropped and the shortfall padded with spaces,
    /// so the animation is always exactly as wide as it was asked to be.
    public var fill: String

    /// The pattern drawn where the track is not lit, in the control's background
    /// colour. Unused by ``Motion/pulse``, ``Motion/barberPole`` and
    /// ``Motion/gradient``, which light every cell.
    public var background: String

    /// The colours the motion draws from, or `nil` for the control's own.
    ///
    /// What they mean is the motion's business, and in each case it is the
    /// obvious one:
    ///
    /// - ``Motion/sweep``, ``Motion/knightRider`` and ``Motion/pulse`` take
    ///   them as a RAMP, sampled from the dim end (first) to the bright end
    ///   (last). `nil` ramps from the control's background colour to its accent.
    /// - ``Motion/barberPole`` takes them as the stripe colours, one per glyph
    ///   of ``fill`` in turn. `nil` alternates accent and filled.
    /// - ``Motion/gradient`` takes them as CYCLIC stops — the last interpolates
    ///   back to the first, so the slide is seamless. Where each stop sits
    ///   counts, and the wrap takes the average of the gaps between them, so
    ///   evenly spaced stops stay evenly spaced. `nil` uses the built-in
    ///   rainbow. Fewer than two usable stops falls back the same way.
    public var gradient: Gradient?

    /// How long one full pass takes, in seconds. Must be finite and greater
    /// than zero.
    ///
    /// Any other value is a mistake in the app. A debug build stops with an
    /// assertion failure. A release build reports it once and uses 1.6 seconds,
    /// the ``sweep`` preset's period, whichever preset the configuration was
    /// built from.
    public var period: Double

    /// The lit run's length as a fraction of the track, for the two motions
    /// that have one (``Motion/sweep`` and ``Motion/knightRider``). Always at
    /// least one cell however small.
    ///
    /// Ignored by the motions that light the whole track.
    public var extent: Double

    /// Creates an indeterminate configuration.
    ///
    /// - Parameters:
    ///   - motion: What the animation does.
    ///   - fill: The lit pattern (see ``fill``).
    ///   - background: The unlit pattern (see ``background``).
    ///   - gradient: The ramp the motion draws from, or `nil` for the
    ///     control's own colours.
    ///   - period: Seconds for one full pass.
    ///   - extent: The lit run's length as a fraction of the track.
    public init(
        motion: Motion,
        fill: String = "█",
        background: String = "░",
        gradient: Gradient? = nil,
        period: Double = 1.6,
        extent: Double = 1.0 / 3.0
    ) {
        self.motion = motion
        self.fill = fill
        self.background = background
        self.gradient = gradient
        self.period = period
        self.extent = extent
    }
}

// MARK: - The built-in presets

extension IndeterminateConfiguration {
    /// The default: a bright run with a fading trail, a third of the track
    /// long, wrapping every 1.6 s.
    public static let sweep = Self(motion: .sweep, period: 1.6, extent: 1.0 / 3.0)

    /// `◢◤` shifted one cell per step. Fast on purpose: the eye reads 0.6 s per
    /// stripe-pair shift as "moving" rather than "ticking".
    public static let barberPole = Self(motion: .barberPole, fill: "◢◤", period: 0.6)

    /// The whole bar breathing between the background colour and the accent.
    public static let pulse = Self(motion: .pulse, period: 1.8)

    /// A single bright block bouncing end to end with a short trail.
    public static let knightRider = Self(motion: .knightRider, period: 2.0, extent: 1.0 / 8.0)

    /// A cyclic ramp slid across the track. `gradient` supplies the stops;
    /// `nil` uses the built-in rainbow.
    public static func gradient(_ gradient: Gradient? = nil) -> Self {
        Self(motion: .gradient, gradient: gradient, period: 2.4)
    }
}
