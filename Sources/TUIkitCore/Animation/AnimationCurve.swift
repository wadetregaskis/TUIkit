//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationCurve.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The shape of an ``Animation`` — how far along the value is, given how far
/// along the time is.
///
/// Two kinds, because the two are genuinely different functions and flattening
/// one into the other loses what makes it useful. A Bézier is a map from unit
/// time to unit progress and ends exactly at 1; a spring is a physical
/// trajectory that overshoots, oscillates, and only *approaches* 1.
enum AnimationCurve: Sendable, Equatable, Hashable {
    /// A cubic Bézier through `(0, 0)`, `(p1x, p1y)`, `(p2x, p2y)`, `(1, 1)` —
    /// the same parameterisation as CSS `cubic-bezier` and
    /// `CAMediaTimingFunction`, so the named curves are the standard ones.
    case bezier(p1x: Double, p1y: Double, p2x: Double, p2y: Double)

    /// A damped harmonic oscillator, by undamped natural angular frequency
    /// (`omega`, rad/s) and damping ratio (`zeta`).
    case spring(omega: Double, zeta: Double)

    /// The value at `fraction` of the way through an animation lasting
    /// `duration` seconds.
    ///
    /// `fraction` is the normalised time so the two cases share one signature;
    /// the spring needs real seconds, and multiplies back out.
    func value(atFraction fraction: Double, duration: TimeInterval) -> Double {
        switch self {
        case .bezier(let p1x, let p1y, let p2x, let p2y):
            Self.bezierValue(atX: fraction, p1x: p1x, p1y: p1y, p2x: p2x, p2y: p2y)
        case .spring(let omega, let zeta):
            Self.springValue(at: fraction * duration, omega: omega, zeta: zeta)
        }
    }
}

// MARK: - Cubic Bézier

extension AnimationCurve {
    /// One coordinate of a cubic Bézier through `(0, c1, c2, 1)` at parameter
    /// `t`, in Horner form.
    private static func bezier(_ t: Double, _ c1: Double, _ c2: Double) -> Double {
        // (1-t)³·0 + 3(1-t)²t·c1 + 3(1-t)t²·c2 + t³·1
        let a = 3 * c1
        let b = 3 * c2 - 6 * c1
        let c = 3 * c1 - 3 * c2 + 1
        return ((c * t + b) * t + a) * t
    }

    /// The derivative of ``bezier(_:_:_:)`` with respect to `t`.
    private static func bezierSlope(_ t: Double, _ c1: Double, _ c2: Double) -> Double {
        let a = 3 * c1
        let b = 3 * c2 - 6 * c1
        let c = 3 * c1 - 3 * c2 + 1
        return (3 * c * t + 2 * b) * t + a
    }

    /// The curve's `y` at the given `x`.
    ///
    /// A cubic Bézier is parametric — both coordinates are functions of a
    /// parameter `t` that is *not* the x axis — so evaluating it as a timing
    /// function means first solving `x(t) = x` for `t`. Newton–Raphson
    /// converges in a handful of steps for the shapes a timing curve has;
    /// bisection is the fallback for the ones where it does not (a control
    /// point at or past the ends makes the slope vanish, and Newton then steps
    /// to infinity).
    static func bezierValue(
        atX x: Double, p1x: Double, p1y: Double, p2x: Double, p2y: Double
    ) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        // Control points ON the diagonal make x(t) and y(t) the same
        // polynomial, so y as a function of x is exactly the identity. Worth
        // saying outright: `.linear` is the commonest curve, and solving it
        // numerically leaves it a rounding error either side of exact — enough
        // to put a value that lands on a cell boundary on the wrong side of it.
        if p1x == p1y && p2x == p2y { return x }

        var t = x  // x is a good first guess: the curve is near-diagonal.
        for _ in 0..<8 {
            let error = bezier(t, p1x, p2x) - x
            if abs(error) < 1e-7 { return bezier(t, p1y, p2y) }
            let slope = bezierSlope(t, p1x, p2x)
            if abs(slope) < 1e-7 { break }  // Flat: Newton cannot help here.
            t -= error / slope
        }

        // Bisection: slower, but it cannot diverge, and 30 halvings of [0, 1]
        // is finer than a terminal can show by many orders of magnitude.
        var low = 0.0
        var high = 1.0
        t = x
        for _ in 0..<30 {
            let value = bezier(t, p1x, p2x)
            if abs(value - x) < 1e-7 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return bezier(t, p1y, p2y)
    }
}

// MARK: - Spring

extension AnimationCurve {
    /// The unit step response of a damped harmonic oscillator at time `t`,
    /// starting at rest at 0 and settling at 1.
    ///
    /// Closed form rather than integrated per frame, for the same reason
    /// ``AnimatedCellRun`` carries whole frames: a value that depends only on
    /// the elapsed time can be asked for at any point, in any order, and
    /// answers identically. A stepped simulation cannot — it would drift with
    /// the frame rate, and could not be pre-rendered at all.
    static func springValue(at t: TimeInterval, omega: Double, zeta: Double) -> Double {
        guard t > 0 else { return 0 }
        guard omega > 0 else { return 1 }

        if zeta < Self.criticalBand {
            // Underdamped: decaying oscillation about 1 — the overshoot.
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * t)
            return 1 - decay * (cos(damped * t) + (zeta * omega / damped) * sin(damped * t))
        } else if zeta <= 1 / Self.criticalBand {
            // Critically damped: the fastest approach with no overshoot. A
            // BAND, not `== 1`: see `criticalBand`.
            let decay = exp(-omega * t)
            return 1 - decay * (1 + omega * t)
        } else {
            // Overdamped: two real roots, no overshoot, a long slow tail.
            let root = omega * (zeta * zeta - 1).squareRoot()
            let r1 = -zeta * omega + root
            let r2 = -zeta * omega - root
            return 1 - (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1)
        }
    }

    /// How long the spring takes to become indistinguishable from settled.
    ///
    /// A spring approaches its target asymptotically, so "when does it end?" has
    /// no exact answer — but an animation the run loop cannot end is an
    /// animation that re-renders forever. The threshold is where the answer
    /// stops mattering: a terminal draws whole cells and 256 shades, so a
    /// residual of 0.2% cannot change a single one.
    ///
    /// Solved from each regime's decay envelope rather than by sampling the
    /// response. The envelope is monotonic where the response is not — an
    /// underdamped spring passes exactly through 1 on every oscillation, so the
    /// first sample within the threshold is not the end of anything.
    static func springSettleDuration(omega: Double, zeta: Double) -> TimeInterval {
        guard omega > 0 else { return 0 }
        let threshold = 0.002
        let limit = 10.0

        let settle: TimeInterval
        if zeta < Self.criticalBand {
            // |x − 1| ≤ e^(−ζωt)·√(1 + (ζω/ω_d)²): the oscillation's envelope.
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let amplitude = (1 + (zeta * omega / damped) * (zeta * omega / damped)).squareRoot()
            settle = zeta > 0 ? log(amplitude / threshold) / (zeta * omega) : limit
        } else if zeta <= 1 / Self.criticalBand {
            // Critically damped: |x − 1| = e^(−ωt)(1 + ωt), monotonically
            // decreasing, so bisection finds the crossing exactly.
            settle = Self.crossing(limit: limit) { t in
                exp(-omega * t) * (1 + omega * t) - threshold
            }
        } else {
            // Overdamped: the slower of the two roots dominates the tail.
            let root = omega * (zeta * zeta - 1).squareRoot()
            let r1 = -zeta * omega + root
            let r2 = -zeta * omega - root
            settle = log(abs(r2 / (r2 - r1)) / threshold) / -r1
        }
        return min(max(settle, 0), limit)
    }

    /// The damping ratio within which a spring is treated as critically damped.
    ///
    /// `zeta == 1` exactly is the analytic boundary and a floating-point
    /// coincidence: either neighbouring formula divides by a vanishing
    /// `√|1 − ζ²|` as it is approached, so the band keeps both away from it.
    /// `bounce: 0` — the common case, and the default — lands here.
    private static var criticalBand: Double { 0.9999 }

    /// The `t` in `(0, limit]` where the monotonically decreasing `excess`
    /// crosses zero, or `limit` if it never does.
    private static func crossing(limit: Double, _ excess: (Double) -> Double) -> Double {
        guard excess(limit) < 0 else { return limit }
        var low = 0.0
        var high = limit
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if excess(mid) > 0 { low = mid } else { high = mid }
        }
        return high
    }
}

// MARK: - Value Hash

/// A trivial non-generic enum, internal, whose cases only this module builds:
/// every byte of every value is written, so the per-pass memos' value hash
/// reads it whole. See `_AllBytesDefined`.
extension AnimationCurve: _AllBytesDefined {}
