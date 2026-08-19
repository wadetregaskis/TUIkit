//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Animation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// How a value changes over time when it changes inside ``withAnimation(_:_:)``
/// or under ``View/animation(_:value:)``.
///
/// ```swift
/// withAnimation(.easeInOut(duration: 0.4)) { isExpanded.toggle() }
/// ```
///
/// An `Animation` is a pure description — a curve, a duration, and the
/// modifiers stacked on it. It holds no state and starts nothing; what turns
/// one into movement is a change to an ``Animatable`` value while it is in
/// force. That separation is what lets the same value be a `static let`, be
/// compared, and — the part that matters in a terminal — be asked in advance
/// what its whole cycle looks like.
///
/// ## What it costs
///
/// A finite animation costs one render pass per frame **for its duration**: a
/// 0.4 s ease is eight or nine passes and then nothing. A
/// ``repeatForever(autoreverses:)`` animation would cost that forever, so the
/// framework serves it differently where it can — by rendering the cycle once
/// and handing the run loop finished frames to replay (``AnimatedCellRun``).
/// See <doc:AnimatingYourOwnView>.
public struct Animation: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// How many times, and in which directions, the curve is played.
    enum Repeat: Sendable, Equatable, Hashable {
        /// A number of one-way passes. `autoreverses` plays every second pass
        /// backwards, so `.count(2, autoreverses: true)` ends where it started.
        case count(Int, autoreverses: Bool)

        /// Passes without end, alternating direction when `autoreverses`.
        case forever(autoreverses: Bool)
    }

    /// The shape of one pass.
    let curve: AnimationCurve

    /// How long one pass takes, before ``speed(_:)``.
    ///
    /// For a spring this is the settling time, not the `duration:` argument —
    /// that one names the spring's *pace* (its natural period), and the spring
    /// keeps moving after it.
    let passDuration: TimeInterval

    /// How long to wait before the first pass, before ``speed(_:)``.
    let delayInterval: TimeInterval

    /// The rate multiplier. 2 runs it twice as fast.
    let speedFactor: Double

    /// How the pass repeats.
    let repeatMode: Repeat

    init(
        curve: AnimationCurve,
        passDuration: TimeInterval,
        delayInterval: TimeInterval = 0,
        speedFactor: Double = 1,
        repeatMode: Repeat = .count(1, autoreverses: false)
    ) {
        self.curve = curve
        self.passDuration = max(0, passDuration)
        self.delayInterval = max(0, delayInterval)
        self.speedFactor = speedFactor > 0 ? speedFactor : 1
        self.repeatMode = repeatMode
    }
}

// MARK: - Bézier curves

extension Animation {
    /// The default duration, in seconds, of every curve that does not name one.
    ///
    /// Matches SwiftUI's, so `.easeInOut` means the same length of time in both.
    public static let defaultDuration: TimeInterval = 0.35

    /// The animation to use when none is named: an ease-in-out over
    /// ``defaultDuration``.
    public static let `default` = Animation.easeInOut

    /// A constant rate over `duration`.
    public static func linear(duration: TimeInterval) -> Animation {
        Animation(curve: .bezier(p1x: 0, p1y: 0, p2x: 1, p2y: 1), passDuration: duration)
    }

    /// A constant rate over ``defaultDuration``.
    public static var linear: Animation { linear(duration: defaultDuration) }

    /// Starts slowly and accelerates.
    public static func easeIn(duration: TimeInterval) -> Animation {
        Animation(curve: .bezier(p1x: 0.42, p1y: 0, p2x: 1, p2y: 1), passDuration: duration)
    }

    /// Starts slowly and accelerates, over ``defaultDuration``.
    public static var easeIn: Animation { easeIn(duration: defaultDuration) }

    /// Starts quickly and decelerates.
    public static func easeOut(duration: TimeInterval) -> Animation {
        Animation(curve: .bezier(p1x: 0, p1y: 0, p2x: 0.58, p2y: 1), passDuration: duration)
    }

    /// Starts quickly and decelerates, over ``defaultDuration``.
    public static var easeOut: Animation { easeOut(duration: defaultDuration) }

    /// Eases in and out of the change.
    public static func easeInOut(duration: TimeInterval) -> Animation {
        Animation(curve: .bezier(p1x: 0.42, p1y: 0, p2x: 0.58, p2y: 1), passDuration: duration)
    }

    /// Eases in and out of the change, over ``defaultDuration``.
    public static var easeInOut: Animation { easeInOut(duration: defaultDuration) }

    /// A cubic Bézier through `(0, 0)`, `(p1x, p1y)`, `(p2x, p2y)` and `(1, 1)`
    /// — the same parameterisation as CSS `cubic-bezier`.
    public static func timingCurve(
        _ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double,
        duration: TimeInterval = defaultDuration
    ) -> Animation {
        Animation(
            curve: .bezier(p1x: p1x, p1y: p1y, p2x: p2x, p2y: p2y), passDuration: duration)
    }
}

// MARK: - Springs

extension Animation {
    /// A spring with the given pace and springiness.
    ///
    /// - Parameters:
    ///   - duration: The spring's *pace* — the period of its undamped
    ///     oscillation — not how long it moves for. A bouncy spring is still
    ///     settling well after it.
    ///   - bounce: How springy. `0` is the fastest approach that does not
    ///     overshoot; positive values overshoot and oscillate; negative values
    ///     are sluggish. Clamped to `-1...1`.
    public static func spring(
        duration: TimeInterval = 0.5, bounce: Double = 0
    ) -> Animation {
        let clamped = min(1, max(-1, bounce))
        // Apple's mapping: bounce ≥ 0 reduces damping towards zero (more
        // oscillation), bounce < 0 raises it above 1 (overdamped).
        let zeta = clamped >= 0 ? 1 - clamped : 1 / (1 + clamped)
        let omega = duration > 0 ? 2 * Double.pi / duration : 0
        return Animation(
            curve: .spring(omega: omega, zeta: zeta),
            passDuration: AnimationCurve.springSettleDuration(omega: omega, zeta: zeta))
    }

    /// A spring at the default pace, with no bounce.
    public static var spring: Animation { spring() }

    /// A spring with no bounce — the one to reach for when a change should feel
    /// physical but not playful.
    public static var smooth: Animation { smooth() }

    /// ``smooth`` with an explicit pace, and optional bounce added.
    public static func smooth(
        duration: TimeInterval = 0.5, extraBounce: Double = 0
    ) -> Animation {
        spring(duration: duration, bounce: extraBounce)
    }

    /// A spring that settles quickly with a small overshoot.
    public static var snappy: Animation { snappy() }

    /// ``snappy`` with an explicit pace, and optional bounce added.
    public static func snappy(
        duration: TimeInterval = 0.5, extraBounce: Double = 0
    ) -> Animation {
        spring(duration: duration, bounce: 0.15 + extraBounce)
    }

    /// A spring with a pronounced overshoot.
    public static var bouncy: Animation { bouncy() }

    /// ``bouncy`` with an explicit pace, and optional bounce added.
    public static func bouncy(
        duration: TimeInterval = 0.5, extraBounce: Double = 0
    ) -> Animation {
        spring(duration: duration, bounce: 0.3 + extraBounce)
    }
}

// MARK: - Modifiers

extension Animation {
    /// This animation, started `delay` seconds later.
    public func delay(_ delay: TimeInterval) -> Animation {
        Animation(
            curve: curve, passDuration: passDuration, delayInterval: delayInterval + delay,
            speedFactor: speedFactor, repeatMode: repeatMode)
    }

    /// This animation, run `speed` times as fast. The delay scales with it, as
    /// it does in SwiftUI.
    public func speed(_ speed: Double) -> Animation {
        Animation(
            curve: curve, passDuration: passDuration, delayInterval: delayInterval,
            speedFactor: speedFactor * speed, repeatMode: repeatMode)
    }

    /// This animation, played `repeatCount` times.
    ///
    /// The count is *passes*, not round trips: with `autoreverses`, every second
    /// pass runs backwards, so an even count ends where it started and an odd
    /// one ends at the target.
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        Animation(
            curve: curve, passDuration: passDuration, delayInterval: delayInterval,
            speedFactor: speedFactor,
            repeatMode: .count(max(1, repeatCount), autoreverses: autoreverses))
    }

    /// This animation, played until something stops it.
    ///
    /// - Important: Nothing stops it — an animation has no end, and the value it
    ///   animates never arrives. This is the shape of a decoration (a pulse, a
    ///   blink), not of a change. Where the framework can, it serves one by
    ///   pre-rendering the cycle and replaying it (see ``AnimatedCellRun``);
    ///   where it cannot, it re-renders the affected subtree for as long as the
    ///   view is on screen.
    public func repeatForever(autoreverses: Bool = true) -> Animation {
        Animation(
            curve: curve, passDuration: passDuration, delayInterval: delayInterval,
            speedFactor: speedFactor, repeatMode: .forever(autoreverses: autoreverses))
    }
}

// MARK: - Evaluation

extension Animation {
    /// One pass, after ``speed(_:)``.
    public var effectivePassDuration: TimeInterval { passDuration / speedFactor }

    /// The wait before the first pass, after ``speed(_:)``.
    public var effectiveDelay: TimeInterval { delayInterval / speedFactor }

    /// How long from the animation's start until it stops moving, or `nil` if it
    /// never does.
    public var totalDuration: TimeInterval? {
        switch repeatMode {
        case .count(let n, _): effectiveDelay + effectivePassDuration * Double(n)
        case .forever: nil
        }
    }

    /// Whether this animation runs without end.
    public var repeatsForever: Bool {
        if case .forever = repeatMode { return true }
        return false
    }

    /// The length of the repeating cycle, for an animation that has one.
    ///
    /// Two passes when it autoreverses (out and back), one when it does not.
    /// `nil` for an animation that ends. This is what makes a repeating
    /// animation pre-renderable: a finite cycle can be sampled once and
    /// replayed.
    public var cyclePeriod: TimeInterval? {
        switch repeatMode {
        case .count: nil
        case .forever(let autoreverses):
            effectivePassDuration * (autoreverses ? 2 : 1)
        }
    }

    /// How far the value has moved from its old value towards its new one,
    /// `elapsed` seconds after the animation started.
    ///
    /// `0` is entirely the old value and `1` entirely the new one. A spring
    /// **overshoots**: values above 1 are correct and mean the value has gone
    /// past its target and is on the way back.
    public func fraction(at elapsed: TimeInterval) -> Double {
        let time = (elapsed - effectiveDelay)
        guard time > 0 else { return 0 }
        guard passDuration > 0 else { return 1 }
        let scaled = time * speedFactor

        let pass = Int(scaled / passDuration)
        let within = (scaled - Double(pass) * passDuration) / passDuration

        switch repeatMode {
        case .count(let n, let autoreverses):
            guard pass < n else {
                // Finished. An even number of autoreversing passes lands back
                // at the start; anything else lands on the target.
                return autoreverses && n.isMultiple(of: 2) ? 0 : 1
            }
            return value(atPass: pass, within: within, autoreverses: autoreverses)
        case .forever(let autoreverses):
            return value(atPass: pass, within: within, autoreverses: autoreverses)
        }
    }

    /// Whether the animation has stopped moving by `elapsed`.
    public func isFinished(at elapsed: TimeInterval) -> Bool {
        guard let totalDuration else { return false }
        return elapsed >= totalDuration
    }

    /// The curve's value on a given pass, reversing the odd ones when asked.
    ///
    /// A reversed pass runs the curve backwards *in time* — `curve(1 - within)`
    /// — rather than mirroring its output. For an asymmetric curve those differ,
    /// and time reversal is what "plays in reverse" means (and what Core
    /// Animation does).
    private func value(atPass pass: Int, within: Double, autoreverses: Bool) -> Double {
        let reversed = autoreverses && !pass.isMultiple(of: 2)
        return curve.value(
            atFraction: reversed ? 1 - within : within, duration: passDuration)
    }
}

// MARK: - Description

extension Animation {
    public var description: String {
        var text: String
        switch curve {
        case .bezier(let p1x, let p1y, let p2x, let p2y):
            text = "timingCurve(\(p1x), \(p1y), \(p2x), \(p2y), duration: \(passDuration))"
        case .spring(let omega, let zeta):
            text = "spring(omega: \(omega), zeta: \(zeta), settles: \(passDuration))"
        }
        if delayInterval != 0 { text += ".delay(\(delayInterval))" }
        if speedFactor != 1 { text += ".speed(\(speedFactor))" }
        switch repeatMode {
        case .count(1, _): break
        case .count(let n, let autoreverses):
            text += ".repeatCount(\(n), autoreverses: \(autoreverses))"
        case .forever(let autoreverses):
            text += ".repeatForever(autoreverses: \(autoreverses))"
        }
        return text
    }
}
