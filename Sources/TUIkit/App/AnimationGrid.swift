//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationGrid.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A frozen, uniform schedule of firing instants: `anchor + k·period` for every
/// integer `k ≥ 0`, in monotonic-clock nanoseconds.
///
/// A grid is the *resolved* form of an animation request — once chosen, its
/// `anchor` and `period` never change. That is what guarantees a constant,
/// drift-free frequency: every firing is computed directly from its index, never
/// accumulated, so a render that lands late (because the frame-rate cap delayed
/// it, say) does not shift the firings that follow it. The cap can nudge an
/// individual render within one frame interval; it can never bend the grid.
///
/// Two grids coincide exactly wherever their firing instants are equal — which is
/// how the scheduler coalesces aligned timers into a single render. Locked grids
/// are built with commensurate `period`s and a shared `anchor` precisely so that
/// coincidence is exact integer arithmetic, not a floating-point near-miss.
struct AnimationGrid: Equatable, Sendable {
    /// The first firing instant (monotonic-clock nanoseconds). Firings exist only
    /// at or after the anchor (`k ≥ 0`); there is no firing before it.
    let anchor: Int64

    /// The spacing between consecutive firings, in nanoseconds. Always `> 0`.
    let period: Int64

    /// Creates a grid. `period` must be strictly positive.
    init(anchor: Int64, period: Int64) {
        precondition(period > 0, "AnimationGrid.period must be > 0, got \(period)")
        self.anchor = anchor
        self.period = period
    }

    /// The earliest firing at or exactly on `time`.
    ///
    /// If `time` is on a firing, that firing is returned. If `time` is before the
    /// anchor, the anchor is returned (the grid has no earlier firing). Otherwise
    /// `time` is rounded up to the next grid instant.
    func firing(atOrAfter time: Int64) -> Int64 {
        guard time > anchor else { return anchor }
        let elapsed = time - anchor
        // Round `elapsed` up to a whole number of periods (ceil division of
        // positive integers), then step that far from the anchor.
        let periods = (elapsed + (period - 1)) / period
        return anchor + periods * period
    }

    /// The earliest firing strictly after `time` (never equal to it).
    func firing(after time: Int64) -> Int64 {
        firing(atOrAfter: time + 1)
    }

    /// Whether `time` lands exactly on a firing of this grid.
    func fires(at time: Int64) -> Bool {
        time >= anchor && (time - anchor).isMultiple(of: period)
    }
}

// MARK: - The base lattice

extension AnimationGrid {
    /// Every whole ``AnimationClock/baseTick`` from zero: the one lattice the
    /// framework's own indicator durations are chosen on.
    ///
    /// Anchored at zero because that is where a run's steps are counted from, on
    /// both clocks, so a duration that is a whole number of these ticks steps on
    /// this grid wherever it is on screen.
    static let base = AnimationGrid(
        anchor: 0, period: AnimationClock.nanoseconds(AnimationClock.baseTick))

    /// The frame duration to use for `duration` when its rate may move by up to
    /// `frequencyTolerance` hertz either way: a whole number of base ticks when
    /// one is inside that band, otherwise `duration` itself.
    ///
    /// This is the scheduler's lock (`resolve(_:lockingOnto:now:)`) with one
    /// candidate that is always there, ``base``, spent once to choose a duration.
    /// It deliberately does not lock onto the grids that are live this frame:
    /// registering a request is a render side effect, which a memoized row cannot
    /// replay, and the first request of a frame would decide the grid, so the
    /// answer would depend on render order.
    ///
    /// With no tolerance, `duration` comes back bit for bit. Going through the
    /// lock would round it to whole nanoseconds, so `1.0 / 30` would come back as
    /// 0.033333333. The same holds when no base multiple is in the band.
    ///
    /// - Parameters:
    ///   - duration: The frame duration asked for, in seconds.
    ///   - frequencyTolerance: How far the rate (`1 / duration`) may move either
    ///     way, in hertz.
    /// - Returns: A duration whose rate is within the band.
    static func latticeFrameDuration(_ duration: Double, frequencyTolerance: Double) -> Double {
        guard frequencyTolerance > 0, frequencyTolerance.isFinite, duration.isFinite, duration > 0
        else { return duration }
        let request = AnimationRequest(
            frequency: 1 / duration, frequencyTolerance: frequencyTolerance)
        let grid = resolve(request, lockingOnto: [base], now: 0)
        // A lock returns a whole number of base periods; no lock returns the
        // nominal period. Either way, a grid at the nominal period is `duration`,
        // and handing that back keeps it exact.
        guard grid.period != request.nominalPeriod else { return duration }
        return Double(grid.period) / 1_000_000_000
    }
}
