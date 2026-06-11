//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnimationResolveTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@Suite("AnimationGrid.resolve")
struct AnimationResolveTests {
    // ~30 Hz and friends, as integer-ns periods.
    private let p30: Int64 = 33_333_333
    private let second: Int64 = 1_000_000_000

    private func grid(hz: Double, anchor: Int64) -> AnimationGrid {
        AnimationGrid(anchor: anchor, period: Int64((1e9 / hz).rounded()))
    }

    // MARK: standalone

    @Test("With no existing grids, a request stands alone at its nominal rate, starting now")
    func standaloneNoExisting() {
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 30, frequencyTolerance: 1, phaseTolerance: second),
            lockingOnto: [], now: 5_000)
        #expect(g.anchor == 5_000)
        #expect(g.period == p30)
    }

    @Test("Zero tolerances never coalesce — exact rate, starts now")
    func zeroTolerancesStandalone() {
        let existing = grid(hz: 30, anchor: 0)
        // 29 Hz, no frequency slack and no phase slack → cannot adopt 30 or align.
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 29, frequencyTolerance: 0, phaseTolerance: 0),
            lockingOnto: [existing], now: 1_000)
        #expect(g.anchor == 1_000)
        #expect(g.period == Int64((1e9 / 29).rounded()))
    }

    // MARK: equal-rate lock (the dominant case)

    @Test("An equal-rate request locks onto the existing grid (same lattice)")
    func equalRateLock() {
        let existing = AnimationGrid(anchor: 0, period: p30)
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 30, frequencyTolerance: 0, phaseTolerance: second),
            lockingOnto: [existing], now: 10_000)
        #expect(g.period == p30)                       // same rate
        #expect(existing.fires(at: g.anchor))          // anchored on the existing lattice
        #expect(g.anchor == existing.firing(atOrAfter: 10_000))
    }

    @Test("Eight 30 Hz timers all collapse onto one shared lattice")
    func manyEqualRateCollapse() {
        var grids: [AnimationGrid] = []
        for i in 0..<8 {
            let now = Int64(i) * 1_111  // each registers a little later
            let g = AnimationGrid.resolve(
                AnimationRequest(frequency: 30, frequencyTolerance: 1, phaseTolerance: second),
                lockingOnto: grids, now: now)
            grids.append(g)
        }
        // All share the first grid's lattice: every grid's anchor is one of its
        // firings, and every grid has the same period.
        let base = grids[0]
        for g in grids {
            #expect(g.period == base.period)
            #expect(base.fires(at: g.anchor))
        }
    }

    // MARK: the worked example

    @Test("29±1 Hz with 1 s phase budget locks perfectly onto a live 30 Hz timer")
    func twentyNinePlusMinusOneLocksToThirty() {
        // Existing 30 Hz timer whose next firing is 0.76 s out.
        let existing = AnimationGrid(anchor: 760_000_000, period: p30)
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 29, frequencyTolerance: 1, phaseTolerance: second),
            lockingOnto: [existing], now: 0)
        // Adopts 30 Hz (frequency budget) and the existing phase (phase budget).
        #expect(g.period == p30)
        #expect(g.anchor == 760_000_000)
        #expect(g == existing)   // literally the same grid → coincides forever
    }

    // MARK: sub-harmonic lock

    @Test("A 10±1 Hz request locks as a 3× sub-harmonic of a 30 Hz timer")
    func subHarmonicLock() {
        let existing = AnimationGrid(anchor: 0, period: p30)
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 10, frequencyTolerance: 1, phaseTolerance: second),
            lockingOnto: [existing], now: 1)
        #expect(g.period == p30 * 3)                   // 10 Hz = 30/3, exact
        #expect(existing.fires(at: g.anchor))          // on the 30 Hz lattice
        // Every firing of the sub-harmonic lands on the 30 Hz lattice.
        for k in 0..<20 {
            #expect(existing.fires(at: g.anchor + Int64(k) * g.period))
        }
    }

    @Test("A fast newcomer cannot super-lock onto a slower grid (v1) → stands alone")
    func fasterThanExistingStandsAlone() {
        let existing = AnimationGrid(anchor: 0, period: p30)  // 30 Hz
        // 60 Hz would need to *subdivide* the 30 Hz grid (super-harmonic), not
        // supported yet → stands alone.
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 60, frequencyTolerance: 1, phaseTolerance: second),
            lockingOnto: [existing], now: 7)
        #expect(g.anchor == 7)
        #expect(g.period == Int64((1e9 / 60).rounded()))
    }

    // MARK: rejection paths

    @Test("Out of frequency tolerance → no lock")
    func outOfFrequencyTolerance() {
        let existing = AnimationGrid(anchor: 0, period: p30)  // 30 Hz
        // 25 ±1 Hz: neither 30 (m=1) nor 15 (m=2) is within [24, 26].
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 25, frequencyTolerance: 1, phaseTolerance: second),
            lockingOnto: [existing], now: 3)
        #expect(g.anchor == 3)
        #expect(g.period == Int64((1e9 / 25).rounded()))
    }

    @Test("Phase budget too small to reach the next firing → no lock")
    func phaseBudgetTooSmall() {
        // Existing 30 Hz grid whose next firing is 0.5 s out, but only 1 ms of
        // phase budget → can't wait for it.
        let existing = AnimationGrid(anchor: 500_000_000, period: p30)
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 30, frequencyTolerance: 1, phaseTolerance: 1_000_000),
            lockingOnto: [existing], now: 0)
        #expect(g.anchor == 0)                         // stood alone, started now
        #expect(g.period == p30)
    }

    @Test("A fast newcomer reaches back to a slow existing timer within its phase budget")
    func fastReachesSlow() {
        // 1 Hz existing, next firing 0.4 s out. New 1 Hz with 1 s phase budget.
        let oneHz = AnimationGrid(anchor: 400_000_000, period: second)
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 1, frequencyTolerance: 0.1, phaseTolerance: second),
            lockingOnto: [oneHz], now: 0)
        #expect(g == oneHz)   // locks: 0.4 s ≤ 1 s budget
    }

    // MARK: preference

    @Test("Equal-rate lock is preferred over a sub-harmonic one")
    func prefersEqualRate() {
        // Two existing grids: a 30 Hz and a 60 Hz. A 30±1 request could lock
        // equal-rate onto the 30 Hz, or 2× sub-harmonic onto the 60 Hz; equal
        // rate (m = 1) must win.
        let g30 = AnimationGrid(anchor: 0, period: p30)
        let g60 = AnimationGrid(anchor: 0, period: Int64((1e9 / 60).rounded()))
        let g = AnimationGrid.resolve(
            AnimationRequest(frequency: 30, frequencyTolerance: 1, phaseTolerance: second),
            lockingOnto: [g60, g30], now: 1)   // 60 first to prove m=1 still wins
        #expect(g.period == p30)
    }
}
