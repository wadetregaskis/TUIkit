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
/// ## Whole ticks
///
/// Every frame an indicator shows lasts a whole number of 1/60 s ticks, at any
/// rate. A terminal's paint is shown on a display that refreshes 60 times a
/// second, and a frame of any other length is held for an uneven number of
/// refreshes. So a rate is met as nearly as whole ticks allow: a spinner's 7-tick
/// frames are 4 ticks at twice the speed, not 3.5.
///
/// ## Tolerance
///
/// `tolerance` is how far the rate may move either way, in the rate's own units:
/// `IndicatorAnimationSpeed(2, tolerance: 0.1)` accepts anything from 1.9 to
/// 2.1. Within that band the framework may give a spinner's or a blink's frames a
/// tick count divisible by 2 or 3, the counts indeterminate bars, breaths and the
/// framework's other animations step on, so this indicator changes on the same
/// ticks as they do and the run loop wakes once for all of them. With a tolerance
/// of 0 a frame is the nearest whole number of ticks.
///
/// The presets are recommendations, not the only choices. Any positive rate
/// works, but indicators whose frames share a multiple of ticks step together,
/// and ones that do not each cost wakes of their own.
public struct IndicatorAnimationSpeed: Hashable, Sendable, ExpressibleByFloatLiteral,
    ExpressibleByIntegerLiteral
{
    /// The rate against the indicator's standard speed: finite and greater
    /// than zero.
    public let rate: Double

    /// How far ``rate`` may move either way, in the rate's own units: at least
    /// zero, and less than the rate. Zero means the nearest whole number of ticks.
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
    ///     Defaults to 0, the nearest whole number of ticks.
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

    /// Creates a speed from a literal, with no tolerance: `.indicatorAnimationSpeed(1.5)`.
    public init(floatLiteral value: Double) {
        self.init(value)
    }

    /// Creates a speed from a literal, with no tolerance: `.indicatorAnimationSpeed(2)`.
    public init(integerLiteral value: Int) {
        self.init(Double(value))
    }

    /// The speed every indicator has unless something sets another: the
    /// standard rate, allowed to move by up to 0.05 either way.
    ///
    /// Inside that band a spinner's or a blink's frame may move onto a tick count
    /// divisible by 2 or 3 when there is one, so indicators on one screen step
    /// together and the run loop wakes once for them. At the standard durations
    /// that moves none of them: every spinner interval is 4 to 18 ticks and the
    /// blink half is 21, and of those, the 5- and 7-tick ones have no such count
    /// within 0.05 of their rate while the others are such a count already. Use
    /// ``standard`` for no tolerance.
    public static let automatic = Self(1, tolerance: 0.05)

    /// The standard rate, with no tolerance.
    public static let standard = Self(1)

    /// Half the standard rate, with no tolerance.
    public static let halfSpeed = Self(0.5)

    /// Twice the standard rate, with no tolerance.
    public static let doubleSpeed = Self(2)

    /// How many 1/60 s ticks each frame of a sequence is shown for at this speed,
    /// for a sequence whose frames are shown for `standard` seconds at the standard
    /// rate.
    ///
    /// The whole number of ticks nearest `standard / rate`, a half rounding up, and
    /// at least 1: a sequence of 7-tick frames is 4 ticks at twice the speed, and 6
    /// at 1.1. Whole ticks because a display holds a frame of any other length for
    /// an uneven number of refreshes.
    ///
    /// With a ``tolerance``, when that nearest count is divisible by neither 2 nor 3,
    /// the frame may be a count that is, whose rate is within the tolerance: of
    /// those, the one nearest in rate, and the larger on a tie. Indeterminate bars
    /// step in frames of 2 ticks, and breaths and the framework's other animations
    /// in frames of 3, so a frame of such a count changes on ticks theirs do. 7 ticks
    /// at 1 ± 0.2 is 8 ticks, a rate of 0.875. With no such count in reach the frame
    /// is the nearest.
    ///
    /// - Parameter standard: The frame duration at the standard rate, in seconds.
    ///   Must be greater than zero.
    /// - Returns: The frame at this speed, in ticks of 1/60 s: at least 1, and at
    ///   most `Int32.max`.
    public func frameTicks(standard: TimeInterval) -> Int {
        let ticksPerSecond = Double(AnimationClock.ticksPerSecond)
        let exact = standard * ticksPerSecond / rate
        // A standard that is not finite, or not greater than zero, is the shortest frame
        // there is, as `AnimationClock.frameTicks(forSeconds:)` has it.
        guard exact.isFinite, exact > 0 else { return 1 }
        // Compared as a Double, which holds Int32.max exactly: converting first would
        // trap, and so would the candidate one past the count rounded up, below, on a
        // 32-bit `Int`.
        guard exact.rounded(.up) < Double(Int32.max) else { return Int(Int32.max) }
        let nearest = max(1, Int(exact.rounded()))
        guard tolerance > 0, !Self.isDivisibleByTwoOrThree(nearest) else { return nearest }
        // A frame's rate falls as its count rises, so the candidate nearest in rate is
        // the largest count below `exact` or the smallest above it that qualifies, and
        // of any two consecutive counts one is even. Above first, so a tie keeps the
        // larger count.
        let floor = Int(exact.rounded(.down))
        let ceiling = Int(exact.rounded(.up))
        let above = Self.isDivisibleByTwoOrThree(ceiling) ? ceiling : ceiling + 1
        let below = Self.isDivisibleByTwoOrThree(floor) ? floor : floor - 1
        var chosen = nearest
        var chosenDistance = Double.infinity
        for candidate in [above, below] where candidate >= 1 {
            let distance = abs(standard * ticksPerSecond / Double(candidate) - rate)
            if distance <= tolerance, distance < chosenDistance {
                chosen = candidate
                chosenDistance = distance
            }
        }
        return chosen
    }

    /// Whether a frame of `ticks` ticks shares the 2- or 3-tick lattice the framework's
    /// own frames step on.
    private static func isDivisibleByTwoOrThree(_ ticks: Int) -> Bool {
        ticks.isMultiple(of: 2) || ticks.isMultiple(of: 3)
    }
}

// MARK: - Ramps

extension IndicatorAnimationSpeed {
    /// A continuous ramp's layout at a speed: how many frames it is sampled at, and how
    /// many ticks each is shown for.
    struct RampLayout: Equatable, Sendable {
        let frameCount: Int

        /// How many 1/60 s ticks each frame is shown for: a whole number of the ramp's
        /// lattice.
        let frameTicks: Int

        /// The most frames a ramp's cycle is sampled at. A longer cycle keeps this
        /// many or fewer, each longer.
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

    /// How a continuous ramp (an indeterminate bar's pass, a breath) is laid out at
    /// this speed: in frames of `lattice` ticks, as many as come nearest its cycle
    /// divided by the rate, at least two and at most ``RampLayout/maximumFrameCount``.
    ///
    /// Frames are not stretched or squeezed, the way a sequence's are
    /// (``frameTicks(standard:)``). Each lasts the lattice, so a slowed ramp stays
    /// smooth, a quickened one does not wake the loop more often than a standard one
    /// does, and every frame changes on a tick every other ramp on that lattice
    /// changes on. The cycle is the whole number of frames nearest its length, so one
    /// that is not a whole number of frames moves by up to half a frame: 1.73 s in
    /// 2-tick frames is 52 of them, 1.7333 s.
    ///
    /// Past ``RampLayout/maximumFrameCount`` frames, each frame is the fewest whole
    /// lattice frames that bring the count to that bound or fewer, and the count is the
    /// nearest to the cycle in those frames: an hour in 2-tick frames is a thousand of
    /// 216 ticks, and a minute is 900 of 4. So a very slow ramp costs no more to build
    /// than one of a thousand frames.
    ///
    /// The tolerance plays no part. It lets a sequence move onto a lattice, and every
    /// frame of a ramp is on one already.
    ///
    /// - Parameters:
    ///   - standardCycle: The cycle at the standard rate, in seconds. Greater than
    ///     zero.
    ///   - lattice: How many 1/60 s ticks a frame is, at least 1: 2 for an
    ///     indeterminate bar, 3 for a breath.
    func rampLayout(standardCycle: TimeInterval, frameTicks lattice: Int) -> RampLayout {
        let lattice = max(1, lattice)
        let ticksPerSecond = Double(AnimationClock.ticksPerSecond)
        let cycleTicks = standardCycle * ticksPerSecond / rate
        // Counted in `Double` until bounded: `Int(_:)` traps on a count or a frame too
        // large for an `Int`, which a rate of 1e-9 reaches. A cycle too long to count at
        // all (not finite) takes the bounded path too, because the comparison is false.
        let limit = Double(RampLayout.maximumFrameCount)
        let wholeFrames = (cycleTicks / Double(lattice)).rounded()
        var frameTicks = lattice
        var count = wholeFrames
        if !(wholeFrames <= limit) {
            let multiple = (wholeFrames / limit).rounded(.up)
            // The largest multiple of the lattice an `Int32` holds, past which a frame
            // is never reached anyway.
            let longest = Int(Int32.max) / lattice
            frameTicks = multiple < Double(longest) ? Int(multiple) * lattice : longest * lattice
            count = (cycleTicks / Double(frameTicks)).rounded()
        }
        let frameCount = count >= limit ? RampLayout.maximumFrameCount : (count >= 2 ? Int(count) : 2)
        return RampLayout(frameCount: frameCount, frameTicks: frameTicks)
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
    /// A blink is two frames that stretch: each half is 21 ticks of 1/60 s (350 ms)
    /// at the standard rate, divided by the rate and rounded to whole ticks. A pulse
    /// is a ramp: its 800 ms cycle is divided by the rate and still shown in frames of
    /// 3 ticks (50 ms), as many as come nearest, up to a thousand frames a cycle, past
    /// which each frame is several of those.
    public static let textCursor = Self(rawValue: 1 << 0)

    /// The breath or blink a focused control draws itself with, whatever
    /// animation ``View/selectionIndicatorStyle(_:)`` gives it.
    ///
    /// A blink is two frames that stretch: each half is 21 ticks of 1/60 s (350 ms)
    /// at the standard rate, divided by the rate and rounded to whole ticks. A breath
    /// is a ramp: its 800 ms cycle is divided by the rate and still shown in frames of
    /// 3 ticks (50 ms), as many as come nearest, so a slow breath stays smooth, up to
    /// a thousand frames a cycle, past which each frame is several of those.
    public static let focusEmphasis = Self(rawValue: 1 << 1)

    /// ``Spinner``, including the one a `refreshable` view draws while it
    /// refreshes.
    public static let spinners = Self(rawValue: 1 << 2)

    /// An indeterminate ``ProgressView``'s bar: one pass of its motion takes its
    /// period divided by the rate, in frames of 2 ticks of 1/60 s, as many as come
    /// nearest, up to a thousand frames a pass. A longer pass keeps a thousand frames
    /// or fewer, each a whole number of 2-tick frames.
    ///
    /// A named ``IndeterminateStyle`` preset's period and one an app sets, through
    /// ``IndeterminateStyle/custom(_:)``, are laid out alike.
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
    /// Prefer rates whose frames come out as tick counts that share multiples with
    /// the rest of the screen, such as the presets, or give the speed a tolerance, so
    /// indicators step together and the run loop wakes once for all of them.
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
