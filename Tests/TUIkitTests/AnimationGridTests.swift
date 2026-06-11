//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnimationGridTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@Suite("AnimationGrid")
struct AnimationGridTests {

    // MARK: firing(atOrAfter:)

    @Test("A time before the anchor yields the anchor")
    func beforeAnchor() {
        let grid = AnimationGrid(anchor: 1000, period: 100)
        #expect(grid.firing(atOrAfter: 0) == 1000)
        #expect(grid.firing(atOrAfter: 999) == 1000)
        #expect(grid.firing(atOrAfter: -5000) == 1000)
    }

    @Test("A time exactly on a firing returns that firing")
    func exactlyOnFiring() {
        let grid = AnimationGrid(anchor: 1000, period: 100)
        #expect(grid.firing(atOrAfter: 1000) == 1000)
        #expect(grid.firing(atOrAfter: 1100) == 1100)
        #expect(grid.firing(atOrAfter: 1500) == 1500)
        #expect(grid.firing(atOrAfter: 9000) == 9000)
    }

    @Test("A time between firings rounds up to the next")
    func betweenFirings() {
        let grid = AnimationGrid(anchor: 1000, period: 100)
        #expect(grid.firing(atOrAfter: 1001) == 1100)
        #expect(grid.firing(atOrAfter: 1099) == 1100)
        #expect(grid.firing(atOrAfter: 1101) == 1200)
        #expect(grid.firing(atOrAfter: 1199) == 1200)
    }

    @Test("Large gaps land on the correct firing")
    func largeGaps() {
        let grid = AnimationGrid(anchor: 0, period: 33_333_333)  // ~30 Hz in ns
        #expect(grid.firing(atOrAfter: 1) == 33_333_333)
        #expect(grid.firing(atOrAfter: 33_333_333) == 33_333_333)
        #expect(grid.firing(atOrAfter: 33_333_334) == 66_666_666)
        // A full second in: 1e9 / 33_333_333 = 30.00000003 → 30th firing is at 1_000_000_000 - 10? Check explicitly.
        #expect(grid.firing(atOrAfter: 999_999_990) == 1_000_000_000 - 10)  // 30 * 33_333_333 = 999_999_990
        #expect(grid.firing(atOrAfter: 999_999_991) == 1_033_333_323)       // 31 * 33_333_333
    }

    @Test("Period of 1 ns fires every nanosecond")
    func unitPeriod() {
        let grid = AnimationGrid(anchor: 500, period: 1)
        #expect(grid.firing(atOrAfter: 500) == 500)
        #expect(grid.firing(atOrAfter: 501) == 501)
        #expect(grid.firing(atOrAfter: 499) == 500)
    }

    @Test("Anchor at zero")
    func anchorAtZero() {
        let grid = AnimationGrid(anchor: 0, period: 100)
        #expect(grid.firing(atOrAfter: 0) == 0)
        #expect(grid.firing(atOrAfter: 1) == 100)
        #expect(grid.firing(atOrAfter: 100) == 100)
    }

    // MARK: firing(after:)

    @Test("firing(after:) is strictly later than the given time")
    func strictlyAfter() {
        let grid = AnimationGrid(anchor: 1000, period: 100)
        // On a firing → the NEXT firing, not this one.
        #expect(grid.firing(after: 1000) == 1100)
        #expect(grid.firing(after: 1100) == 1200)
        // Between → next firing (same as atOrAfter here).
        #expect(grid.firing(after: 1050) == 1100)
        // Before the anchor → the anchor (strictly after the given time).
        #expect(grid.firing(after: 0) == 1000)
        #expect(grid.firing(after: 999) == 1000)
    }

    // MARK: fires(at:)

    @Test("fires(at:) is true only on grid instants at or after the anchor")
    func firesAt() {
        let grid = AnimationGrid(anchor: 1000, period: 100)
        #expect(grid.fires(at: 1000))
        #expect(grid.fires(at: 1100))
        #expect(grid.fires(at: 5000))
        #expect(!grid.fires(at: 1050))
        #expect(!grid.fires(at: 1001))
        #expect(!grid.fires(at: 999))     // before the anchor, even if on the lattice
        #expect(!grid.fires(at: 900))
    }

    // MARK: coincidence (the property the scheduler relies on)

    @Test("A 3× sub-harmonic grid's firings are all firings of the base")
    func subHarmonicCoincidence() {
        let base = AnimationGrid(anchor: 7_000, period: 33_333_333)        // ~30 Hz
        let third = AnimationGrid(anchor: 7_000, period: 33_333_333 * 3)   // ~10 Hz, locked

        // Every firing of the slower grid lands exactly on a firing of the base.
        for k in 0..<50 {
            let slowFiring = third.anchor + Int64(k) * third.period
            #expect(base.fires(at: slowFiring))
        }
    }

    @Test("Equatable")
    func equatable() {
        let base = AnimationGrid(anchor: 1, period: 2)
        let same = AnimationGrid(anchor: 1, period: 2)
        let otherPeriod = AnimationGrid(anchor: 1, period: 3)
        let otherAnchor = AnimationGrid(anchor: 9, period: 2)
        #expect(base == same)
        #expect(base != otherPeriod)
        #expect(base != otherAnchor)
    }
}
