//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationLatticeTests.swift
//
//  The base lattice a framework-chosen indicator duration may bend onto when a
//  tolerance allows: `AnimationClock.baseTick`, `AnimationGrid.base`, and
//  `AnimationGrid.latticeFrameDuration(_:frequencyTolerance:)`. Durations are
//  compared in whole nanoseconds, the unit a run's steps are counted in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@Suite("The base animation lattice")
struct AnimationLatticeTests {
    private func nanos(_ seconds: Double) -> Int64 {
        AnimationClock.nanoseconds(seconds)
    }

    @Test("The base tick is 25 ms, and the base grid is every tick from zero")
    func baseTickAndGrid() {
        #expect(nanos(AnimationClock.baseTick) == 25_000_000)
        #expect(AnimationGrid.base == AnimationGrid(anchor: 0, period: 25_000_000))
    }

    /// 120 ms at a rate of 1 ± 0.05 accepts 114.3 ms to 126.3 ms: 125 ms is in it.
    @Test("A 120 ms frame allowed ±0.05 of its rate moves to 125 ms")
    func movesOntoTheLattice() {
        let duration = AnimationGrid.latticeFrameDuration(0.12, frequencyTolerance: 0.05 / 0.12)
        #expect(nanos(duration) == 125_000_000)
    }

    /// 110 ms at 1 ± 0.05 accepts 104.8 ms to 115.8 ms, and holds no 25 ms multiple.
    @Test("A 110 ms frame allowed ±0.05 of its rate has no tick in reach, and stays exactly 110 ms")
    func staysWhenNoTickIsInReach() {
        let duration = AnimationGrid.latticeFrameDuration(0.11, frequencyTolerance: 0.05 / 0.11)
        #expect(duration.bitPattern == 0.11.bitPattern)
    }

    /// 110 ms at 1 ± 0.12 accepts 98.2 ms to 125 ms. 100 ms is nearest to 110 ms.
    /// Clear of the band's edge, where rounding would decide the answer.
    @Test("A 110 ms frame allowed ±0.12 of its rate moves to the nearer tick multiple, 100 ms")
    func picksTheNearestMultiple() {
        let duration = AnimationGrid.latticeFrameDuration(0.11, frequencyTolerance: 0.12 / 0.11)
        #expect(nanos(duration) == 100_000_000)
    }

    @Test(
        "With no tolerance the duration comes back bit for bit",
        arguments: [0.11, 0.12, 0.125, 1.0 / 30, 1.73, 0.0173, 0.35, 0.05, 0.08, 2.0 / 3])
    func zeroToleranceIsIdentity(_ duration: Double) {
        let result = AnimationGrid.latticeFrameDuration(duration, frequencyTolerance: 0)
        #expect(result.bitPattern == duration.bitPattern)
    }

    @Test(
        "Whatever it picks is in the band it was given, and is either the duration or a tick multiple",
        arguments: [0.08, 0.09, 0.1, 0.11, 0.12, 0.13, 0.14, 0.15, 1.0 / 30, 0.35, 0.0173, 0.8],
        [0.01, 0.05, 0.1, 0.2, 0.5])
    func resultIsInsideItsBand(_ duration: Double, toleranceOfRate: Double) {
        // A rate of 1 ± `toleranceOfRate`, in hertz of this duration.
        let tolerance = toleranceOfRate / duration
        let result = AnimationGrid.latticeFrameDuration(duration, frequencyTolerance: tolerance)
        let band = AnimationRequest(frequency: 1 / duration, frequencyTolerance: tolerance)
        let period = nanos(result)
        #expect(period >= band.fastestAcceptablePeriod, "\(period) ns is faster than the band allows")
        #expect(period <= band.slowestAcceptablePeriod, "\(period) ns is slower than the band allows")
        #expect(
            result.bitPattern == duration.bitPattern || period.isMultiple(of: 25_000_000),
            "\(period) ns is neither the duration asked for nor on the lattice")
    }
}
