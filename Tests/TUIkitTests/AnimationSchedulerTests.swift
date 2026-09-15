//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationSchedulerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("AnimationScheduler")
struct AnimationSchedulerTests {
    private let second: Int64 = 1_000_000_000

    // MARK: mark-and-sweep lifecycle

    @Test("A token that stops re-declaring is dropped at endFrame")
    func sweepDropsStale() {
        let s = AnimationScheduler()
        #expect(s.isIdle)
        s.beginFrame()
        s.request("x", AnimationRequest(frameTicks: 2))
        s.request("y", AnimationRequest(frameTicks: 2))
        s.endFrame()
        #expect(s.liveCount == 2)

        // Next frame only x re-declares.
        s.beginFrame(); s.request("x", AnimationRequest(frameTicks: 2)); s.endFrame()
        #expect(s.liveCount == 1)

        // Next frame nothing re-declares → idle.
        s.beginFrame(); s.endFrame()
        #expect(s.isIdle)
    }

    // MARK: nextFiring

    @Test("Empty scheduler has no next firing")
    func emptyNextFiring() {
        let s = AnimationScheduler()
        #expect(s.nextFiring(after: 12_345) == nil)
    }

    // MARK: lattices

    @Test("A lattice fires where the next multiple of its period in ticks begins, wherever it was asked for")
    func latticeFiresOnTickMultiples() {
        let s = AnimationScheduler()
        s.beginFrame()
        s.request("two", AnimationRequest(frameTicks: 2))
        s.endFrame()
        // 1.037 s is in tick 62; the next even tick is 64.
        #expect(s.nextFiring(after: 1_037_000_000) == 1_066_666_667)
        #expect(s.nextFiring(after: 1_066_666_667) == AnimationClock.nanoseconds(atTick: 66))

        let t = AnimationScheduler()
        t.beginFrame()
        t.request("three", AnimationRequest(frameTicks: 3))
        t.endFrame()
        #expect(t.nextFiring(after: 1_050_000_000) == 1_100_000_000)
    }

    @Test("A lattice fires where a run's steps of the same frame end, from any instant")
    func latticeMeetsRunSteps() {
        var misses: [String] = []
        for frameTicks in [2, 3, 4] {
            // 7.919 ms apart, which no tick divides, so the instants fall at every
            // offset into a tick over the 4.75 s they span.
            for step in 0..<600 {
                let now = Int64(step) * 7_919_000
                let s = AnimationScheduler()
                s.beginFrame()
                s.request("run-rate", AnimationRequest(frameTicks: frameTicks))
                s.endFrame()
                let run = AnimationClock.stepEndNanos(atElapsed: Double(now) / 1e9, frameTicks: frameTicks)
                if s.nextFiring(after: now) != run { misses.append("\(frameTicks) ticks from \(now)") }
            }
        }
        #expect(misses.isEmpty, "\(misses.prefix(5))")
    }

    @Test("Lattices of 2 and 3 ticks fire only where 2 or 3 divides the tick: 40 instants a second")
    func latticesCoincideWhereTheirMultiplesMeet() {
        let s = AnimationScheduler()
        s.beginFrame()
        s.request("two", AnimationRequest(frameTicks: 2))
        s.request("three", AnimationRequest(frameTicks: 3))
        s.endFrame()
        var t: Int64 = -1
        var firings: [Int64] = []
        while let next = s.nextFiring(after: t), next < second {
            firings.append(next)
            t = next
        }
        #expect(firings.count == 40)
        #expect(firings.allSatisfy { instant in
            let tick = AnimationClock.tick(atNanoseconds: instant)
            return AnimationClock.nanoseconds(atTick: tick) == instant
                && (tick.isMultiple(of: 2) || tick.isMultiple(of: 3))
        })
    }

    @Test("A lattice is live while re-declared, and is dropped when it is not")
    func latticeLifecycle() {
        let s = AnimationScheduler()
        s.beginFrame(); s.request("two", AnimationRequest(frameTicks: 2)); s.endFrame()
        #expect(!s.isIdle)
        #expect(s.liveCount == 1)
        s.beginFrame(); s.request("two", AnimationRequest(frameTicks: 2)); s.endFrame()
        #expect(s.liveCount == 1)
        s.beginFrame(); s.endFrame()
        #expect(s.isIdle)
        #expect(s.nextFiring(after: 0) == nil)
    }

    // MARK: one-shot wakes

    @Test("A one-shot wake fires at its instant, and counts as liveness")
    func wakeFires() {
        let s = AnimationScheduler()
        s.beginFrame()
        s.requestWake("clock", at: 5 * second)
        s.endFrame()
        #expect(!s.isIdle)
        #expect(s.liveWakeCount == 1)
        #expect(s.liveCount == 0)
        #expect(s.nextFiring(after: 0) == 5 * second)
    }

    @Test("A wake the frame has already reached is not a firing")
    func wakeInThePastIsNotAFiring() {
        // Otherwise the loop would render, find the instant still behind it, and
        // render again — a spin. The view re-declares its next wake on the frame
        // this one produced.
        let s = AnimationScheduler()
        s.beginFrame()
        s.requestWake("clock", at: 5 * second)
        s.endFrame()
        #expect(s.nextFiring(after: 5 * second) == nil)
        #expect(s.nextFiring(after: 6 * second) == nil)
    }

    @Test("Re-declaring a token moves its wake rather than adding one")
    func wakeIsReplaced() {
        let s = AnimationScheduler()
        s.beginFrame(); s.requestWake("clock", at: 5 * second); s.endFrame()
        s.beginFrame(); s.requestWake("clock", at: 9 * second); s.endFrame()
        #expect(s.liveWakeCount == 1)
        #expect(s.nextFiring(after: 0) == 9 * second)
    }

    @Test("A wake that stops being re-declared is dropped")
    func wakeIsDropped() {
        let s = AnimationScheduler()
        s.beginFrame(); s.requestWake("clock", at: 5 * second); s.endFrame()
        s.beginFrame(); s.endFrame()
        #expect(s.isIdle)
        #expect(s.nextFiring(after: 0) == nil)
    }

    @Test("The soonest of a lattice and a wake wins, whichever it is")
    func latticesAndWakesUnion() {
        let s = AnimationScheduler()
        s.beginFrame()
        s.request("spinner", AnimationRequest(frameTicks: 2))  // fires every 33.3 ms
        s.requestWake("clock", at: 5 * second)
        s.endFrame()
        #expect(s.nextFiring(after: 0) == AnimationClock.nanoseconds(atTick: 2))
        // Asked from a moment past the last lattice firing before the wake, the
        // wake is still not the answer — the lattice keeps firing.
        #expect(s.nextFiring(after: 4 * second) ?? 0 < 5 * second)
        // With the lattice gone, the wake is.
        s.beginFrame(); s.requestWake("clock", at: 5 * second); s.endFrame()
        #expect(s.nextFiring(after: 0) == 5 * second)
    }
}
