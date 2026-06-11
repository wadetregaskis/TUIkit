//  🖥️ TUIKit — Terminal UI Kit for Swift
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
