//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MonotonicClockTests.swift
//
//  `MonotonicClock`'s origin is fixed at its first use, which made the FIRST
//  reading of a process the elapsed time between initialising the origin and
//  reading the clock again — a handful of nanoseconds, and on a 41 ns timebase
//  frequently exactly ZERO. Measured over 4,000 debug-built processes: 392 of
//  them, 9.8%, read 0 on the first call.
//
//  Zero is not a free value here. Three places already spell it as "no reading
//  at all": `LinkActivationGate.lastNanos == 0` ("the first activation of this
//  link's life"), `AnimationFrame(nowNanos:)`'s default ("0 outside the run
//  loop"), and `CursorTimer.snapshotNanos`'s initial value. A clock that can
//  hand out the same value its consumers use for "never" is the defect; these
//  pin that it cannot.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("Monotonic clock")
struct MonotonicClockTests {

    /// The degenerate case the property cannot be asked for twice: a reading
    /// taken at the very instant the origin was fixed. That is the process's
    /// first call, and it must still be a reading.
    @Test("A reading taken at the origin instant is not zero")
    func originReadingIsNotZero() {
        let instant = SuspendingClock.now
        #expect(MonotonicClock.nanoseconds(from: instant, to: instant) > 0)
    }

    /// The same statement one tick out, since a 41 ns timebase means the first
    /// call lands either on the origin or a very small number of ticks past it.
    @Test("A reading one nanosecond after the origin is not zero")
    func readingJustAfterOriginIsNotZero() {
        let origin = SuspendingClock.now
        let now = origin.advanced(by: .nanoseconds(1))
        #expect(MonotonicClock.nanoseconds(from: origin, to: now) > 0)
    }

    /// Where the origin sits is arbitrary — every reader subtracts two readings
    /// — so moving it must not change any interval. This is what makes the
    /// clock's zero safe to reserve.
    @Test("Moving the origin leaves every interval unchanged")
    func intervalsAreUnaffectedByTheOrigin() {
        let origin = SuspendingClock.now
        let early = MonotonicClock.nanoseconds(
            from: origin, to: origin.advanced(by: .nanoseconds(1_000_000)))
        let late = MonotonicClock.nanoseconds(
            from: origin, to: origin.advanced(by: .nanoseconds(3_000_000)))
        #expect(late - early == 2_000_000)
    }

    /// The conversion itself, pinned at a round figure so the reserved zero is
    /// spelled out rather than inferred: a reading is the elapsed nanoseconds
    /// plus one, because the origin sits one nanosecond before the first
    /// reading.
    @Test("A reading is the elapsed nanoseconds, offset off zero")
    func readingIsElapsedPlusTheOffset() {
        let origin = SuspendingClock.now
        #expect(
            MonotonicClock.nanoseconds(from: origin, to: origin.advanced(by: .seconds(2)))
                == 2_000_000_000 + 1)
    }

    /// A clock that has run backwards has no reading to give, and says so with
    /// the one value a working clock never returns.
    @Test("A backwards reading answers zero, the value a working clock never gives")
    func backwardsReadingIsZero() {
        let origin = SuspendingClock.now
        let before = origin.advanced(by: .nanoseconds(-1_000_000))
        #expect(MonotonicClock.nanoseconds(from: origin, to: before) == 0)
    }

    /// The property itself, which is what every caller actually reads. In a
    /// process that has read the clock before this is trivially true; it is the
    /// end-to-end statement of the two above, which are not.
    @Test("The clock reads non-zero and never goes backwards")
    func readingsAreNonZeroAndMonotonic() {
        let first = MonotonicClock.nowNanoseconds
        #expect(first > 0)
        #expect(MonotonicClock.nowNanoseconds >= first)
    }
}
