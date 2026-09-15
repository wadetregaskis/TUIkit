//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationTickTests.swift
//
//  The 1/60 s tick every animation frame is a whole number of: which tick an
//  instant is in, when a tick begins in whole nanoseconds, and the conversions
//  between seconds and tick counts. Checked against an independent 128-bit
//  computation rather than against the function's own arithmetic.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("The 1/60 s animation tick")
struct AnimationTickTests {
    /// ⌊t·60/10⁹⌋ in 128 bits, floored for negative t. No `AnimationClock` arithmetic.
    private static func referenceTick(_ nanoseconds: Int64) -> Int64 {
        let (quotient, remainder) = Int64(1_000_000_000)
            .dividingFullWidth(nanoseconds.multipliedFullWidth(by: 60))
        return remainder < 0 ? quotient - 1 : quotient
    }

    /// ⌈k·10⁹/60⌉ in 128 bits, for a k whose instant fits in an `Int64`.
    private static func referenceInstant(_ tick: Int64) -> Int64 {
        let (quotient, remainder) = Int64(60).dividingFullWidth(tick.multipliedFullWidth(by: 1_000_000_000))
        return remainder > 0 ? quotient + 1 : quotient
    }

    /// SplitMix64, so the sampled ticks are the same on every run and platform.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    @Test("A second is 60 ticks, and ticks 1, 2 and 3 begin at 16,666,667, 33,333,334 and 50,000,000 ns")
    func firstTicks() {
        #expect(AnimationClock.ticksPerSecond == 60)
        #expect(AnimationClock.nanoseconds(atTick: 0) == 0)
        #expect(AnimationClock.nanoseconds(atTick: 1) == 16_666_667)
        #expect(AnimationClock.nanoseconds(atTick: 2) == 33_333_334)
        #expect(AnimationClock.nanoseconds(atTick: 3) == 50_000_000)
        #expect(AnimationClock.nanoseconds(atTick: 60) == 1_000_000_000)
        #expect(AnimationClock.nanoseconds(atTick: -1) == -16_666_666)
        #expect(AnimationClock.tick(atNanoseconds: 16_666_666) == 0)
        #expect(AnimationClock.tick(atNanoseconds: 16_666_667) == 1)
        #expect(AnimationClock.tick(atNanoseconds: -1) == -1)
    }

    /// The pair is an exact inverse: the instant a tick begins reads as that tick, and
    /// the nanosecond before it reads as the tick before. So a wake at a tick's instant
    /// draws that tick, which rounding the instant down or to nearest would not give.
    @Test("A tick's instant reads as that tick and the nanosecond before as the one before, from −10,000 to 10,000")
    func inversePairNearZero() {
        var failures: [Int64] = []
        var gaps: Set<Int64> = []
        for tick in Int64(-10_000)...10_000 {
            let instant = AnimationClock.nanoseconds(atTick: tick)
            if instant != Self.referenceInstant(tick)
                || AnimationClock.tick(atNanoseconds: instant) != tick
                || AnimationClock.tick(atNanoseconds: instant - 1) != tick - 1
            {
                failures.append(tick)
            }
            gaps.insert(AnimationClock.nanoseconds(atTick: tick + 1) - instant)
        }
        #expect(failures.isEmpty, "first failures: \(failures.prefix(5))")
        #expect(gaps == [16_666_666, 16_666_667])
    }

    @Test("The inverse pair holds for a thousand seeded ticks up to ±5·10¹¹, about 264 years")
    func inversePairFarOut() {
        var generator = SeededGenerator(state: 0x60_1D_7C_C5)
        var failures: [Int64] = []
        for _ in 0..<1_000 {
            let tick = Int64.random(in: -500_000_000_000...500_000_000_000, using: &generator)
            let instant = AnimationClock.nanoseconds(atTick: tick)
            if instant != Self.referenceInstant(tick)
                || AnimationClock.tick(atNanoseconds: instant) != tick
                || AnimationClock.tick(atNanoseconds: instant - 1) != tick - 1
                || AnimationClock.tick(atNanoseconds: instant) != Self.referenceTick(instant)
            {
                failures.append(tick)
            }
        }
        #expect(failures.isEmpty, "first failures: \(failures.prefix(5))")
    }

    @Test("The tick of any instant is defined, out to Int64.max and Int64.min")
    func tickIsTotal() {
        #expect(AnimationClock.tick(atNanoseconds: .max) == Self.referenceTick(.max))
        #expect(AnimationClock.tick(atNanoseconds: .min) == Self.referenceTick(.min))
        #expect(AnimationClock.tick(atNanoseconds: .max) == 553_402_322_211)
        #expect(AnimationClock.tick(atNanoseconds: .min) == -553_402_322_212)
    }

    /// Past ±553,402,322,211 ticks, about 292 years, a tick's instant is not an `Int64`.
    @Test("A tick whose instant is past Int64's range begins at Int64.max or Int64.min, and does not trap")
    func instantSaturates() {
        #expect(AnimationClock.nanoseconds(atTick: 553_402_322_211) == Self.referenceInstant(553_402_322_211))
        #expect(AnimationClock.nanoseconds(atTick: -553_402_322_211) == Self.referenceInstant(-553_402_322_211))
        #expect(AnimationClock.nanoseconds(atTick: 553_402_322_212) == .max)
        #expect(AnimationClock.nanoseconds(atTick: -553_402_322_212) == .min)
        #expect(AnimationClock.nanoseconds(atTick: .max) == .max)
        #expect(AnimationClock.nanoseconds(atTick: .min) == .min)
    }

    @Test(
        "Seconds become the nearest whole number of ticks, at least one and at most Int32.max",
        arguments: [
            (0.35, 21), (1.0 / 30, 2), (0.11, 7), (0.125, 8), (0.001, 1), (0, 1), (-1, 1),
            (Double.nan, 1), (Double.infinity, 1), (1e30, Int(Int32.max)),
        ] as [(Double, Int)])
    func frameTicksForSeconds(_ seconds: Double, _ ticks: Int) {
        #expect(AnimationClock.frameTicks(forSeconds: seconds) == ticks)
    }

    @Test("3 ticks are 0.05 s and 21 ticks are 0.35 s, bit for bit")
    func secondsForTicks() {
        #expect(AnimationClock.seconds(forTicks: 3).bitPattern == 0.05.bitPattern)
        #expect(AnimationClock.seconds(forTicks: 21).bitPattern == 0.35.bitPattern)
        #expect(AnimationClock.seconds(forTicks: 60) == 1)
    }

    @Test("The next instant on a lattice of whole tick multiples is strictly after the one given")
    func nextTickMultiple() {
        #expect(AnimationClock.nanoseconds(ofNextTickMultiple: 2, after: 1_037_000_000) == 1_066_666_667)
        // Already on the 3-tick lattice: the next one, not this one.
        #expect(AnimationClock.nanoseconds(ofNextTickMultiple: 3, after: 1_050_000_000) == 1_100_000_000)
        #expect(AnimationClock.nanoseconds(ofNextTickMultiple: 3, after: 1_049_999_999) == 1_050_000_000)
        #expect(AnimationClock.nanoseconds(ofNextTickMultiple: 1, after: 0) == 16_666_667)
        #expect(AnimationClock.nanoseconds(ofNextTickMultiple: 2, after: -1) == 0)
        #expect(AnimationClock.nanoseconds(ofNextTickMultiple: 2, after: .max) == .max)
    }

    @Test("A held repeat's next step is the first multiple of its period a whole period past the step's tick")
    func repeatTicks() {
        // Tick 63, on the 3-tick lattice: the next multiple, tick 66.
        #expect(AnimationClock.nanoseconds(ofRepeatTicks: 3, afterStepAt: 1_052_000_000) == 1_100_000_000)
        // Tick 65, a step taken off the lattice: tick 69, not the next multiple, 66.
        #expect(AnimationClock.nanoseconds(ofRepeatTicks: 3, afterStepAt: 1_099_000_000) == 1_150_000_000)
        #expect(AnimationClock.nanoseconds(ofRepeatTicks: 3, afterStepAt: 1_100_000_000) == 1_150_000_000)
        #expect(AnimationClock.nanoseconds(ofRepeatTicks: 4, afterStepAt: -1) == AnimationClock.nanoseconds(atTick: 4))
        #expect(AnimationClock.nanoseconds(ofRepeatTicks: 0, afterStepAt: 0) == 16_666_667)
        #expect(AnimationClock.nanoseconds(ofRepeatTicks: 3, afterStepAt: .max) == .max)

        // From every tick of −300…300 and 5 ms into it: a tick instant on the period's
        // lattice, at least a period and under two periods past the step's tick.
        var misses: [String] = []
        for period in 1...5 {
            for tick in Int64(-300)...300 {
                for offset in [Int64(0), 5_000_000] {
                    let step = AnimationClock.nanoseconds(atTick: tick) + offset
                    let next = AnimationClock.nanoseconds(ofRepeatTicks: period, afterStepAt: step)
                    let nextTick = AnimationClock.tick(atNanoseconds: next)
                    let p = Int64(period)
                    let isRepeat = AnimationClock.nanoseconds(atTick: nextTick) == next
                        && nextTick.isMultiple(of: p) && nextTick - tick >= p && nextTick - tick < 2 * p
                    if !isRepeat { misses.append("period \(period) from \(step): \(next)") }
                }
            }
        }
        #expect(misses.isEmpty, "\(misses.prefix(5))")
    }
}
