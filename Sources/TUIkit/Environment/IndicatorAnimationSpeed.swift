//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndicatorAnimationSpeed.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Speed

/// How fast an ambient indicator animates: a rate against its standard speed,
/// and how far that rate may move so indicators on one screen step together.
///
/// TUI-specific. SwiftUI's indicators animate at whatever speed the platform
/// picks; here a spinner is a sequence of glyphs whose pace is a choice, and an
/// app may want it calmer, or brisker, for a whole screen at once. Set it with
/// ``View/indicatorAnimationSpeed(_:for:)``.
///
/// A rate of 1 is the indicator's standard speed, 2 is twice as fast, 0.5 half
/// as fast. It replaces whatever an ancestor set, and never multiplies it: a
/// speed of 2 inside a speed of 2 is 2.
///
/// ```swift
/// ContentView()
///     .indicatorAnimationSpeed(.halfSpeed, for: .spinners)
/// ```
///
/// ## Tolerance
///
/// `tolerance` is how far the rate may move either way, in the rate's own units:
/// `IndicatorAnimationSpeed(2, tolerance: 0.1)` accepts anything from 1.9 to
/// 2.1. Within that band the framework may choose a frame duration that is a
/// whole number of ``AnimationClock/baseTick``s, so this indicator steps at the
/// same instants as others and the run loop wakes once for all of them. With a
/// tolerance of 0 the rate is exact.
///
/// The presets are recommendations, not the only choices. Any positive rate
/// works, but indicators whose durations share a whole-tick multiple step
/// together, and ones that do not each cost wakes of their own.
public struct IndicatorAnimationSpeed: Hashable, Sendable, ExpressibleByFloatLiteral,
    ExpressibleByIntegerLiteral
{
    /// The rate against the indicator's standard speed: finite and greater
    /// than zero.
    public let rate: Double

    /// How far ``rate`` may move either way, in the rate's own units: at least
    /// zero, and less than the rate. Zero means exact.
    public let tolerance: Double

    /// Creates a speed.
    ///
    /// A rate that is not finite and greater than zero has no meaning. A debug
    /// build stops with an assertion failure; a release build reports it once
    /// and uses a rate of 1 and a tolerance of 0. A tolerance below zero, not
    /// finite, or not less than the rate is handled the same way and replaced
    /// by 0.
    ///
    /// - Parameters:
    ///   - rate: The rate against the standard speed.
    ///   - tolerance: How far the rate may move either way, in its own units.
    ///     Defaults to 0, exact.
    public init(_ rate: Double, tolerance: Double = 0) {
        self.init(rate, tolerance: tolerance, onRejection: { SoftTrap.report($0) })
    }

    /// Creates a speed, reporting a value it cannot use through `report`.
    ///
    /// The public initializer reports through a soft trap. The parameter exists
    /// so a test can see what is rejected without a debug build stopping.
    init(_ rate: Double, tolerance: Double, onRejection report: (String) -> Void) {
        guard rate.isFinite, rate > 0 else {
            report(
                "IndicatorAnimationSpeed's rate must be finite and greater than zero, "
                    + "not \(rate); using a rate of 1 and a tolerance of 0")
            self.rate = 1
            self.tolerance = 0
            return
        }
        guard tolerance.isFinite, tolerance >= 0, tolerance < rate else {
            report(
                "IndicatorAnimationSpeed's tolerance must be at least zero and less than "
                    + "its rate, \(rate), not \(tolerance); using a tolerance of 0")
            self.rate = rate
            self.tolerance = 0
            return
        }
        self.rate = rate
        self.tolerance = tolerance
    }

    /// Creates an exact speed from a literal: `.indicatorAnimationSpeed(1.5)`.
    public init(floatLiteral value: Double) {
        self.init(value)
    }

    /// Creates an exact speed from a literal: `.indicatorAnimationSpeed(2)`.
    public init(integerLiteral value: Int) {
        self.init(Double(value))
    }

    /// The speed every indicator has unless something sets another: the
    /// standard rate.
    public static let automatic = Self(1, tolerance: 0)

    /// The standard rate, exactly.
    public static let standard = Self(1)

    /// Half the standard rate, exactly.
    public static let halfSpeed = Self(0.5)

    /// Twice the standard rate, exactly.
    public static let doubleSpeed = Self(2)

    /// How long each frame of a sequence is shown at this speed, for a sequence
    /// whose frames are shown for `standard` seconds at the standard rate.
    ///
    /// `standard / rate`, exactly, when ``tolerance`` is 0. Otherwise the whole
    /// number of ``AnimationClock/baseTick``s nearest to that whose rate is within
    /// the tolerance, or `standard / rate` when there is none.
    ///
    /// - Parameter standard: The frame duration at the standard rate, in seconds.
    ///   Must be greater than zero.
    /// - Returns: The frame duration at this speed, in seconds.
    public func frameDuration(standard: TimeInterval) -> TimeInterval {
        let exact = standard / rate
        guard tolerance > 0 else { return exact }
        // The rate band in hertz of this sequence: its frequency is
        // `rate / standard`, so a tolerance in rate units is `tolerance / standard` Hz.
        return AnimationGrid.latticeFrameDuration(exact, frequencyTolerance: tolerance / standard)
    }
}

// MARK: - Kinds

/// Which ambient indicators a speed applies to.
///
/// ``all`` is the default for ``View/indicatorAnimationSpeed(_:for:)``.
public struct IndicatorAnimations: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    /// Creates a set of indicator kinds from its raw bits.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// A text field's caret, blinking or pulsing. Not yet read by the caret.
    public static let textCursor = Self(rawValue: 1 << 0)

    /// The breath a focused control draws itself with. Not yet read by the
    /// focus emphasis.
    public static let focusEmphasis = Self(rawValue: 1 << 1)

    /// ``Spinner``, including the one a `refreshable` view draws while it
    /// refreshes.
    public static let spinners = Self(rawValue: 1 << 2)

    /// An indeterminate ``ProgressView``'s bar. Not yet read by the bar.
    public static let indeterminateProgress = Self(rawValue: 1 << 3)

    /// Every kind.
    public static let all: Self = [
        .textCursor, .focusEmphasis, .spinners, .indeterminateProgress,
    ]
}

// MARK: - Speeds

/// The speed of each kind of ambient indicator: what
/// ``EnvironmentValues/indicatorAnimationSpeeds`` holds.
///
/// Each kind is set on its own. ``View/indicatorAnimationSpeed(_:for:)`` writes
/// only the kinds it names, so the nearest setting for a kind wins, and a
/// setting for another kind in between leaves it alone.
public struct IndicatorAnimationSpeeds: Hashable, Sendable {
    private var textCursor = IndicatorAnimationSpeed.automatic
    private var focusEmphasis = IndicatorAnimationSpeed.automatic
    private var spinners = IndicatorAnimationSpeed.automatic
    private var indeterminateProgress = IndicatorAnimationSpeed.automatic

    /// Every kind at ``IndicatorAnimationSpeed/automatic``.
    public init() {}

    /// The speed of one kind of indicator.
    ///
    /// - Parameter indicator: The kind. Given a set of several, the answer is for
    ///   the first of them in the order `textCursor`, `focusEmphasis`, `spinners`,
    ///   `indeterminateProgress`; given none, it is
    ///   ``IndicatorAnimationSpeed/automatic``.
    /// - Returns: That kind's speed.
    public func speed(for indicator: IndicatorAnimations) -> IndicatorAnimationSpeed {
        if indicator.contains(.textCursor) { return textCursor }
        if indicator.contains(.focusEmphasis) { return focusEmphasis }
        if indicator.contains(.spinners) { return spinners }
        if indicator.contains(.indeterminateProgress) { return indeterminateProgress }
        return .automatic
    }

    /// Sets the speed of every kind in `indicators`, leaving the others as they are.
    ///
    /// - Parameters:
    ///   - speed: The speed.
    ///   - indicators: The kinds to set it for.
    public mutating func set(_ speed: IndicatorAnimationSpeed, for indicators: IndicatorAnimations) {
        if indicators.contains(.textCursor) { textCursor = speed }
        if indicators.contains(.focusEmphasis) { focusEmphasis = speed }
        if indicators.contains(.spinners) { spinners = speed }
        if indicators.contains(.indeterminateProgress) { indeterminateProgress = speed }
    }
}

private struct IndicatorAnimationSpeedsKey: EnvironmentKey {
    static let defaultValue = IndicatorAnimationSpeeds()
}

extension EnvironmentValues {
    /// How fast each kind of ambient indicator in this subtree animates.
    ///
    /// Set it with ``View/indicatorAnimationSpeed(_:for:)``, which changes only
    /// the kinds it names.
    public var indicatorAnimationSpeeds: IndicatorAnimationSpeeds {
        get { self[IndicatorAnimationSpeedsKey.self] }
        set { self[IndicatorAnimationSpeedsKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets how fast ambient indicators in this view animate.
    ///
    /// TUI-specific. The nearest setting for a kind wins, and it replaces what an
    /// ancestor set rather than multiplying it: a speed of 2 inside a speed of 2 is
    /// 2. Kinds this call does not name keep what they inherited, so
    /// `.indicatorAnimationSpeed(0.5, for: .spinners)` around
    /// `.indicatorAnimationSpeed(2, for: .textCursor)` leaves the spinners at 0.5.
    ///
    /// ```swift
    /// Spinner("Loading")
    ///     .indicatorAnimationSpeed(.doubleSpeed, for: .spinners)
    /// ```
    ///
    /// Prefer rates whose durations share whole ``AnimationClock/baseTick``s with
    /// the rest of the screen, such as the presets, so indicators step together
    /// and the run loop wakes once for all of them.
    ///
    /// - Parameters:
    ///   - speed: The speed.
    ///   - indicators: Which kinds of indicator it applies to. Defaults to all.
    /// - Returns: A view whose indicators of those kinds animate at `speed`.
    public func indicatorAnimationSpeed(
        _ speed: IndicatorAnimationSpeed,
        for indicators: IndicatorAnimations = .all
    ) -> some View {
        // `transformEnvironment` rather than `environment`, as `scrollIndicators(_:axes:)`
        // does: a kind this call does not name has to keep whatever it inherited,
        // which is a value this call cannot see.
        transformEnvironment(\.indicatorAnimationSpeeds) { $0.set(speed, for: indicators) }
    }
}
