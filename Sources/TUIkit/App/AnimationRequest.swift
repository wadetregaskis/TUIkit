//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnimationRequest.swift
//
//  Created by LAYERED.work
//  License: MIT

/// What a view asks for when it wants the run loop to re-render it periodically.
///
/// The two tolerances are what let the scheduler *coalesce* this request onto an
/// already-scheduled one so a single render serves both:
///
/// - `frequencyTolerance` — the ± band of rates it will accept. With a 30 Hz
///   timer already live, a `29 ±1 Hz` request can adopt 30 Hz and ride its grid.
/// - `phaseTolerance` — how long its *first* firing may be delayed so its grid
///   lands on an existing one. A grid is only ever placed once, at registration;
///   after that its frequency is exact and constant. Both tolerances are spent
///   *together*, once, to choose where the grid sits — never to nudge it while
///   it runs (that would be the frequency jitter humans notice).
///
/// A request with **zero** tolerances is honoured literally: it runs at its exact
/// rate forever, coinciding with others only where their grids naturally cross.
struct AnimationRequest: Equatable, Sendable {
    /// The desired rate, in hertz. Must be `> 0`.
    var frequency: Double

    /// The ± rate band, in hertz, the requester will accept in order to align
    /// with an existing timer. `0` means "exactly `frequency`, no coalescing of
    /// the rate." Must be `≥ 0`.
    var frequencyTolerance: Double

    /// How long, in nanoseconds, the requester will let its *first* firing be
    /// delayed so its grid aligns with an existing one. `0` means "start now."
    /// Must be `≥ 0`.
    var phaseTolerance: Int64

    init(frequency: Double, frequencyTolerance: Double = 0, phaseTolerance: Int64 = 0) {
        precondition(frequency > 0, "AnimationRequest.frequency must be > 0")
        precondition(frequencyTolerance >= 0, "frequencyTolerance must be ≥ 0")
        precondition(phaseTolerance >= 0, "phaseTolerance must be ≥ 0")
        self.frequency = frequency
        self.frequencyTolerance = frequencyTolerance
        self.phaseTolerance = phaseTolerance
    }

    /// The nominal period in nanoseconds (the rate honoured when the request
    /// stands alone).
    var nominalPeriod: Int64 {
        Int64((1_000_000_000.0 / frequency).rounded())
    }

    /// The shortest period the requester accepts — its *fastest* allowed rate,
    /// `frequency + frequencyTolerance`. Rounded **down** so a grid sitting
    /// exactly on the boundary (e.g. a true 30 Hz grid vs. a `29 ±1` request,
    /// where ns-rounding makes the grid read as 30.0000003 Hz) still counts as
    /// inside the band rather than a hair outside it.
    var fastestAcceptablePeriod: Int64 {
        Int64((1_000_000_000.0 / (frequency + frequencyTolerance)).rounded(.down))
    }

    /// The longest period the requester accepts — its *slowest* allowed rate,
    /// `frequency − frequencyTolerance` (rounded **up**, symmetrically). If the
    /// tolerance reaches 0 Hz or below, there is no slow bound.
    var slowestAcceptablePeriod: Int64 {
        let slowest = frequency - frequencyTolerance
        guard slowest > 0 else { return .max }
        return Int64((1_000_000_000.0 / slowest).rounded(.up))
    }
}

// MARK: - Resolving a request to a grid

extension AnimationGrid {
    /// Resolves `request` into a concrete grid at time `now`, locking onto one of
    /// the already-scheduled `existing` grids when frequency and phase tolerance
    /// allow, otherwise standing alone at the nominal rate starting now.
    ///
    /// A lock is the joint decision the design turns on: pick an existing grid `E`
    /// and an integer `m ≥ 1` so that `E`'s rate divided by `m` lands inside the
    /// requested frequency band, *and* the next firing of `E` is reachable within
    /// the phase budget. The result is `E`'s grid sampled every `m`-th firing —
    /// the same lattice, so the two coincide exactly forever. Equal-rate locks
    /// (`m = 1`) are preferred (the common "many things at the same rate" case);
    /// among those, the densest base grid wins, then the earliest-registered.
    static func resolve(
        _ request: AnimationRequest,
        lockingOnto existing: [AnimationGrid],
        now: Int64
    ) -> AnimationGrid {
        let nominalPeriod = request.nominalPeriod
        let periodMin = request.fastestAcceptablePeriod
        let periodMax = request.slowestAcceptablePeriod

        var best: (grid: AnimationGrid, multiplier: Int64, basePeriod: Int64)?
        for candidate in existing {
            guard let m = Self.multiplier(
                basePeriod: candidate.period,
                nominalPeriod: nominalPeriod,
                periodMin: periodMin,
                periodMax: periodMax
            ) else { continue }

            // Start on the candidate's grid, at its soonest firing — but only if
            // that firing is reachable within the phase budget.
            let anchor = candidate.firing(atOrAfter: now)
            guard anchor - now <= request.phaseTolerance else { continue }

            let grid = AnimationGrid(anchor: anchor, period: candidate.period * m)
            if let current = best {
                let better = m < current.multiplier
                    || (m == current.multiplier && candidate.period < current.basePeriod)
                if better { best = (grid, m, candidate.period) }
            } else {
                best = (grid, m, candidate.period)
            }
        }

        if let best { return best.grid }
        return AnimationGrid(anchor: now, period: nominalPeriod)
    }

    /// The integer multiplier `m ≥ 1` for which `basePeriod · m` lands inside
    /// `[periodMin, periodMax]` and sits closest to `nominalPeriod`, or `nil` if
    /// no such `m` exists (the base grid can't be sub-sampled into the band).
    private static func multiplier(
        basePeriod: Int64,
        nominalPeriod: Int64,
        periodMin: Int64,
        periodMax: Int64
    ) -> Int64? {
        // In-band multiples form a contiguous range [mLow, mHigh] because
        // `basePeriod · m` increases with m.
        let mLow = max(1, ceilDivide(periodMin, basePeriod))
        let mHigh = periodMax == .max ? Int64.max : basePeriod > 0 ? periodMax / basePeriod : .max
        guard mLow <= mHigh else { return nil }
        // The multiple closest to the nominal period, clamped into the band.
        let mIdeal = max(1, roundDivide(nominalPeriod, basePeriod))
        return min(max(mIdeal, mLow), mHigh)
    }
}

/// Ceil of `a / b` for non-negative `a` and positive `b`.
private func ceilDivide(_ a: Int64, _ b: Int64) -> Int64 {
    (a + (b - 1)) / b
}

/// Nearest integer to `a / b` (round half up) for non-negative `a`, positive `b`.
private func roundDivide(_ a: Int64, _ b: Int64) -> Int64 {
    (a + b / 2) / b
}
