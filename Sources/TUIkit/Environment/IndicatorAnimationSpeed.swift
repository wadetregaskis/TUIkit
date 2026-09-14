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
    /// standard rate, allowed to move by up to 0.05 either way.
    ///
    /// Inside that band the framework picks a frame duration that is a whole
    /// number of ``AnimationClock/baseTick``s when there is one, so indicators on
    /// one screen step together and the run loop wakes once for them. At the
    /// standard durations as they are, that moves only the spinner styles whose
    /// interval is 120 ms or 130 ms, to 125 ms. Use ``standard`` for the exact
    /// rate.
    public static let automatic = Self(1, tolerance: 0.05)

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

// MARK: - Ramps

extension IndicatorAnimationSpeed {
    /// A continuous ramp's layout at a speed: how many frames it is sampled at, how
    /// long each is shown, and how many of the ramp's own seconds pass in each second
    /// shown.
    struct RampLayout: Equatable, Sendable {
        let frameCount: Int
        let frameDuration: TimeInterval

        /// ``IndicatorAnimationSpeed/rate``, or the rate a cycle moved onto whole
        /// frames runs at. A view that draws the ramp at an arbitrary instant, rather
        /// than from its frames, draws it at the clock's elapsed time times this.
        let timeScale: Double

        /// The most frames a ramp's cycle is sampled at. A longer cycle keeps this
        /// many, each longer.
        ///
        /// Every frame of a cycle is built at its first render and held while it is on
        /// screen: an indeterminate bar's styled row, or its picture sent to the
        /// terminal. At 30 frames a second an hour-long pass was 108,000 of them,
        /// measured at 9.4 s and 214 MB for an 80-cell `.gradient` bar in a debug build,
        /// and a 600 s one drawn as pictures took 68 s. Nothing that slow changes
        /// visibly 30 times a second. A glyph bar has at most four positions a cell
        /// (the `.gradient` motion's quarter-cell steps; a sweep has one), so a thousand
        /// frames still show every step of a bar up to 250 cells wide.
        static let maximumFrameCount = 1000
    }

    /// How a continuous ramp (an indeterminate bar's pass) is laid out at this
    /// speed: over its cycle divided by the rate, sampled as often as at the
    /// standard rate, up to ``RampLayout/maximumFrameCount`` frames.
    ///
    /// Frames are not stretched or squeezed, the way a sequence's are
    /// (``frameDuration(standard:)``). The frame count is the cycle times
    /// `framesPerSecond`, rounded, at least two and at most
    /// ``RampLayout/maximumFrameCount``, and each frame lasts the cycle over the
    /// count. So a slowed ramp stays smooth, a quickened one does not wake the loop
    /// more often than a standard one does, and a very slow one costs no more to
    /// build than one of a thousand frames. The cycle lasts exactly its length
    /// whichever bound applies.
    ///
    /// With `snapping` and a tolerance, a cycle of whole frames
    /// (`count / framesPerSecond`) is used instead, when its rate is within the
    /// tolerance and it moves the cycle by at least a nanosecond. Every frame then
    /// lasts `1 / framesPerSecond`, and steps with every other ramp sampled at that
    /// rate. A caller asks for no snapping for a cycle the app chose, which stays
    /// exact.
    ///
    /// - Parameters:
    ///   - standardCycle: The cycle at the standard rate, in seconds. Greater than
    ///     zero.
    ///   - framesPerSecond: How often the ramp is sampled, per second shown.
    ///   - snapping: Whether the tolerance may move the cycle onto whole frames.
    func rampLayout(
        standardCycle: TimeInterval, framesPerSecond: Double, snapping: Bool
    ) -> RampLayout {
        let cycle = standardCycle / rate
        // Bounded in `Double` before `Int(_:)`, which would trap on a count too large
        // for an `Int`. Past the bound the frames lengthen instead (`cycle / count`
        // below), so the cycle stays exact.
        let count = max(
            2, Int(min((cycle * framesPerSecond).rounded(), Double(RampLayout.maximumFrameCount))))
        if snapping, tolerance > 0 {
            let whole = Double(count) / framesPerSecond
            let fastest = standardCycle / (rate + tolerance)
            let slowest = standardCycle / (rate - tolerance)
            if whole >= fastest, whole <= slowest,
                AnimationClock.nanoseconds(whole) != AnimationClock.nanoseconds(cycle)
            {
                return RampLayout(
                    frameCount: count, frameDuration: 1 / framesPerSecond,
                    timeScale: standardCycle / whole)
            }
        }
        return RampLayout(frameCount: count, frameDuration: cycle / Double(count), timeScale: rate)
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

    /// The caret of a ``TextField``, a ``SecureField`` or a ``TextEditor``,
    /// whatever ``TextCursorStyle`` it has.
    ///
    /// A blink is two frames that stretch: each half is 350 ms at the standard
    /// rate, divided by the rate. A pulse is a ramp: its 800 ms cycle is divided by
    /// the rate and still sampled every 50 ms, up to a thousand frames a cycle, past
    /// which the frames lengthen. Within the speed's tolerance the
    /// pulse may move onto whole 50 ms frames.
    public static let textCursor = Self(rawValue: 1 << 0)

    /// The breath or blink a focused control draws itself with, whatever
    /// ``SelectionIndicatorStyle`` it has.
    ///
    /// A blink is two frames that stretch: each half is 350 ms at the standard
    /// rate, divided by the rate. A breath is a ramp: its 800 ms cycle is divided
    /// by the rate and still sampled every 50 ms, so a slow breath stays smooth, up
    /// to a thousand frames a cycle, past which the frames lengthen.
    /// Within the speed's tolerance the breath may move onto whole 50 ms frames.
    public static let focusEmphasis = Self(rawValue: 1 << 1)

    /// ``Spinner``, including the one a `refreshable` view draws while it
    /// refreshes.
    public static let spinners = Self(rawValue: 1 << 2)

    /// An indeterminate ``ProgressView``'s bar: one pass of its motion takes its
    /// period divided by the rate, sampled at 30 frames a second, up to a thousand
    /// frames a pass. A longer pass keeps a thousand frames, each longer, and still
    /// takes exactly that time.
    ///
    /// A named ``IndeterminateStyle`` preset's pass may move within the speed's
    /// tolerance onto whole frames of the bar's 30 frames a second. A period an app
    /// sets, through ``IndeterminateStyle/custom(_:)``, stays exact.
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

extension IndicatorAnimationSpeeds {
    /// One speed for some kinds of indicator, as a ``Theme`` lists them in
    /// ``Theme/indicatorAnimationSpeeds``.
    ///
    /// Spelled as ``View/indicatorAnimationSpeed(_:for:)`` is:
    /// `Entry(.halfSpeed, for: .spinners)`.
    public struct Entry: Hashable, Sendable {
        /// The speed.
        public var speed: IndicatorAnimationSpeed

        /// The kinds of indicator it applies to.
        public var indicators: IndicatorAnimations

        /// Creates an entry.
        ///
        /// - Parameters:
        ///   - speed: The speed.
        ///   - indicators: Which kinds of indicator it applies to. Defaults to all.
        public init(_ speed: IndicatorAnimationSpeed, for indicators: IndicatorAnimations = .all) {
            self.speed = speed
            self.indicators = indicators
        }
    }
}

private struct IndicatorAnimationSpeedsKey: EnvironmentKey {
    static let defaultValue = IndicatorAnimationSpeeds()
}

extension EnvironmentValues {
    /// How fast each kind of ambient indicator in this subtree animates.
    ///
    /// Set it with ``View/indicatorAnimationSpeed(_:for:)``, which changes only
    /// the kinds it names, or for a whole theme with
    /// ``Theme/indicatorAnimationSpeeds``.
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
