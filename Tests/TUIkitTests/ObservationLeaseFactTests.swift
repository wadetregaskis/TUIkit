//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservationLeaseFactTests.swift
//
//  The facts about Swift's Observation that cancelling a scope rests on,
//  pinned so that a toolchain — or a platform — where they differ fails here
//  rather than leaking or losing a change. They are Observation's behaviour,
//  not TUIkit's, and Linux's Observation is built from the toolchain's own
//  sources where macOS runs the OS's: these run on every CI lane.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkitView

/// What the scopes below read.
@Observable
private final class FactModel {
    var count = 0
}

/// How often each kind of `onChange` ran.
private final class Runs: @unchecked Sendable {
    var cancelled = 0
    var changed = 0
}

/// Arms one scope that reads `sentinel` and `model.count`, counting its
/// `onChange` by what it finds: a retired sentinel (cancelled), or a live one
/// (a change).
private func armScope(reading sentinel: ScopeSentinel, and model: FactModel, into runs: Runs) {
    withObservationTracking {
        sentinel.touch()
        _ = model.count
    } onChange: {
        if sentinel.isRetired {
            runs.cancelled += 1
        } else {
            runs.changed += 1
        }
    }
}

@Suite("The facts cancelling an observation scope rests on")
struct ObservationLeaseFactTests {
    /// Writing a sentinel fires every scope that read it — each finding it
    /// retired — and frees them: a later write of what they read finds none.
    @Test("A retiring lease cancels every scope that read its sentinel")
    func retiringLeaseCancels() {
        let model = FactModel()
        let runs = Runs()
        var lease: ObservationLease? = ObservationLease()
        for _ in 0..<1_000 { armScope(reading: lease!.scopeSentinel(), and: model, into: runs) }
        #expect(runs.cancelled == 0, "nothing runs while the lease lives")
        lease = nil
        #expect(runs.cancelled == 1_000, "the retirement ran every one, finding its sentinel retired")
        model.count += 1
        #expect(runs.changed == 0, "and freed them: the model's write finds none")
    }

    /// Releasing a sentinel WITHOUT writing it cancels nothing: the scopes are
    /// registered with the model too, and outlive it. So a lease writes.
    @Test("A sentinel released unwritten cancels nothing")
    func unwrittenSentinelCancelsNothing() {
        let model = FactModel()
        let runs = Runs()
        for _ in 0..<100 { armScope(reading: ScopeSentinel(), and: model, into: runs) }
        model.count += 1
        #expect(runs.changed == 100, "every scope was still armed on the model")
        #expect(runs.cancelled == 0)
    }

    /// A scope under a live lease is a scope like any other: the model's write
    /// fires it, as a change.
    @Test("A scope under a live lease still reports a change")
    func liveLeaseReports() {
        let model = FactModel()
        let runs = Runs()
        let lease = ObservationLease()
        for _ in 0..<10 { armScope(reading: lease.scopeSentinel(), and: model, into: runs) }
        model.count += 1
        #expect(runs.changed == 10)
        #expect(runs.cancelled == 0)
        withExtendedLifetime(lease) {}
    }

    /// A lease another holds is not retired until the holder goes: what a
    /// kept result used lives as long as the result.
    @Test("A held lease retires only when its holder does")
    func heldLeaseOutlivesItsOwnReference() {
        let model = FactModel()
        let runs = Runs()
        var holder: ObservationLease? = ObservationLease()
        do {
            let held = ObservationLease()
            armScope(reading: held.scopeSentinel(), and: model, into: runs)
            holder?.hold(held)
            holder?.hold(held)
            #expect(holder?.heldCount == 1, "held once, however often in a row")
        }
        #expect(runs.cancelled == 0, "the holder keeps it")
        holder = nil
        #expect(runs.cancelled == 1, "gone with its holder")
    }

    /// A lease under which nothing was armed makes no sentinel, and writes
    /// nothing when it goes.
    @Test("A lease nothing read costs no sentinel")
    func unusedLeaseCostsNothing() {
        let lease = ObservationLease()
        #expect(!lease.hasSentinel)
        #expect(lease.heldCount == 0)
        withExtendedLifetime(lease) {}
    }

    /// A retirement racing a write on another thread can run a registration's
    /// closure twice (measured on macOS: 300 of 1,000 under 6.2.4). The census
    /// counts each registration once, whichever came first.
    @Test("The census counts a registration once, fired or cancelled, however often its closure runs")
    func censusCountsOnce() {
        let census = ObservationCensus()
        let cancelledFirst = census.arm(.bodyRender)
        cancelledFirst.cancel()
        cancelledFirst.fire()
        cancelledFirst.cancel()
        let firedFirst = census.arm(.bodyRender, unleased: true)
        firedFirst.fire()
        firedFirst.cancel()
        let counts = census.snapshot
        #expect(counts.armed(.bodyRender) == 2)
        #expect(counts.cancelled(.bodyRender) == 1)
        #expect(counts.fired(.bodyRender) == 1)
        #expect(counts.unleased(.bodyRender) == 1)
        #expect(counts.live == 0)
        withExtendedLifetime((cancelledFirst, firedFirst)) {}
        #expect(census.snapshot.dropped(.bodyRender) == 0, "neither is dropped as well")
    }
}
