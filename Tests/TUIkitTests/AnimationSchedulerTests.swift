//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnimationSchedulerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("AnimationScheduler")
struct AnimationSchedulerTests {
    private let p30: Int64 = 33_333_333
    private let second: Int64 = 1_000_000_000

    private func req(_ hz: Double, tol: Double = 1, phase: Int64 = 1_000_000_000) -> AnimationRequest {
        AnimationRequest(frequency: hz, frequencyTolerance: tol, phaseTolerance: phase)
    }

    // MARK: registration

    @Test("A new token resolves and is stored; isIdle reflects liveness")
    func registerNew() {
        let s = AnimationScheduler()
        #expect(s.isIdle)
        s.beginFrame()
        s.request("spinner", req(30), now: 0)
        s.endFrame()
        #expect(!s.isIdle)
        #expect(s.liveCount == 1)
        #expect(s.grid(for: "spinner") == AnimationGrid(anchor: 0, period: p30))
    }

    @Test("Re-declaring a token keeps its frozen grid (never re-resolves)")
    func reDeclareKeepsGrid() {
        let s = AnimationScheduler()
        s.beginFrame(); s.request("a", req(30), now: 0); s.endFrame()
        let first = s.grid(for: "a")
        // Next frame, much later, with other grids present — must NOT re-phase.
        s.beginFrame()
        s.request("b", req(30), now: 5_000)          // a newcomer
        s.request("a", req(30), now: 500_000_000)    // re-declare a
        s.endFrame()
        #expect(s.grid(for: "a") == first)           // unchanged
    }

    // MARK: mark-and-sweep lifecycle

    @Test("A token that stops re-declaring is dropped at endFrame")
    func sweepDropsStale() {
        let s = AnimationScheduler()
        s.beginFrame(); s.request("x", req(30), now: 0); s.request("y", req(30), now: 0); s.endFrame()
        #expect(s.liveCount == 2)

        // Next frame only x re-declares.
        s.beginFrame(); s.request("x", req(30), now: p30); s.endFrame()
        #expect(s.liveCount == 1)
        #expect(s.grid(for: "x") != nil)
        #expect(s.grid(for: "y") == nil)

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

    @Test("nextFiring is the soonest firing across all grids, strictly after the time")
    func nextFiringIsMin() {
        let s = AnimationScheduler()
        s.beginFrame()
        s.request("slow", req(10, tol: 0, phase: 0), now: 0)   // standalone 10 Hz, anchor 0
        s.request("fast", req(30, tol: 0, phase: 0), now: 7)   // standalone 30 Hz, anchor 7
        s.endFrame()
        // 10 Hz grid: 0, 1e8, ...  30 Hz grid: 7, 7+p30, ...  Soonest after 0 is 7.
        #expect(s.nextFiring(after: 0) == 7)
        // After the 30 Hz first firing, soonest is its next (7 + p30) vs 10 Hz's 1e8.
        #expect(s.nextFiring(after: 7) == 7 + p30)
    }

    @Test("Locked grids coincide: many 30 Hz timers fire as one 30 Hz stream")
    func lockedGridsCoincide() {
        let s = AnimationScheduler()
        s.beginFrame()
        for i in 0..<8 {
            s.request("pv\(i)", req(30), now: Int64(i) * 1_000)
        }
        s.endFrame()
        #expect(s.liveCount == 8)

        // Walk a second of wall-clock: every distinct firing should be ~33 ms
        // apart (one 30 Hz stream), never the 8× denser thing you'd get unaligned.
        var t: Int64 = -1
        var firings: [Int64] = []
        while let next = s.nextFiring(after: t), next < second {
            firings.append(next)
            t = next
        }
        // ~30 firings in a second, and consecutive gaps are exactly one period.
        #expect(firings.count >= 28 && firings.count <= 31)
        for i in 1..<firings.count {
            #expect(firings[i] - firings[i - 1] == p30)
        }
    }

    @Test("A 10 Hz sub-harmonic adds no extra firings to a live 30 Hz stream")
    func subHarmonicRidesAlong() {
        let s = AnimationScheduler()
        s.beginFrame()
        s.request("thirty", req(30), now: 0)
        s.request("ten", req(10), now: 1)     // locks as 30/3, on the same lattice
        s.endFrame()

        // The union of firings is still exactly the 30 Hz stream.
        var t: Int64 = -1
        var count = 0
        while let next = s.nextFiring(after: t), next < second {
            count += 1
            t = next
        }
        #expect(count >= 28 && count <= 31)   // 30 Hz, not 40
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

    @Test("The soonest of a grid and a wake wins, whichever it is")
    func gridsAndWakesUnion() {
        let s = AnimationScheduler()
        s.beginFrame()
        s.request("spinner", req(30, tol: 0, phase: 0), now: 0)  // fires every 33.3 ms
        s.requestWake("clock", at: 5 * second)
        s.endFrame()
        #expect(s.nextFiring(after: 0) == p30)
        // Asked from a moment past the last grid firing before the wake, the
        // wake is still not the answer — the grid keeps firing.
        #expect(s.nextFiring(after: 4 * second) ?? 0 < 5 * second)
        // With the grid gone, the wake is.
        s.beginFrame(); s.requestWake("clock", at: 5 * second); s.endFrame()
        #expect(s.nextFiring(after: 0) == 5 * second)
    }
}
