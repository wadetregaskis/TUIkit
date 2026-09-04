//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StdinArrivalNotifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Tests for `StdinArrivalNotifier` — the main-loop "wait for stdin OR a
/// timeout" race.
///
/// Only the deterministic behaviours are exercised: the timeout firing and
/// `stop()` waking a pending waiter. The stdin-data path can't be unit
/// tested without redirecting `STDIN_FILENO` (flaky and process-global), so
/// these tests never call `start()` — without a dispatch source attached,
/// the timeout and `stop()` are the only wake sources, which is exactly
/// what's being verified. The notifier is `@MainActor`, so the tests are
/// too.
@Suite("StdinArrivalNotifier")
struct StdinArrivalNotifierTests {

    @MainActor
    @Test("waitForArrival returns once the timeout elapses")
    func timeoutResumesWaiter() async {
        let notifier = StdinArrivalNotifier()
        let clock = ContinuousClock()

        let start = clock.now
        await notifier.waitForArrival(timeoutNanoseconds: 10_000_000)  // 10 ms
        let elapsed = clock.now - start

        // `Task.sleep` never resumes early, so the wait must have lasted at
        // least most of the requested timeout. Only a lower bound is
        // asserted — an upper bound would be jitter-prone under load.
        #expect(elapsed >= .milliseconds(5))
    }

    @MainActor
    @Test("stop() promptly resumes a waiter that would otherwise wait a long time")
    func stopResumesPendingWaiter() async {
        let notifier = StdinArrivalNotifier()

        let waiter = Task { @MainActor in
            // A 60-second timeout: if stop() fails to resume us, the test
            // hangs far past any reasonable runtime, surfacing the bug
            // rather than passing spuriously.
            await notifier.waitForArrival(timeoutNanoseconds: 60_000_000_000)
        }

        // Give the waiter a chance to register its continuation first.
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20 ms
        notifier.stop()

        await waiter.value  // returns only because stop() resumed the waiter
    }

    @MainActor
    @Test("stop() is safe to call with no waiter and is idempotent")
    func stopIsSafeWithoutWaiter() {
        let notifier = StdinArrivalNotifier()
        // No waiter registered, never started — these must not crash.
        notifier.stop()
        notifier.stop()
    }

    @MainActor
    @Test("wake() before waiting makes the next waitForArrival return at once")
    func wakeBeforeWaitReturnsImmediately() async {
        let notifier = StdinArrivalNotifier()
        notifier.wake()  // no waiter yet — remembered as pendingWake

        let clock = ContinuousClock()
        let start = clock.now
        // A 60-second timeout: it must NOT block (the pending wake short-circuits
        // it), or this test hangs far past any reasonable runtime.
        await notifier.waitForArrival(timeoutNanoseconds: 60_000_000_000)
        #expect(clock.now - start < .milliseconds(100))
    }

    @MainActor
    @Test("wake() promptly resumes a suspended waiter")
    func wakeResumesPendingWaiter() async {
        let notifier = StdinArrivalNotifier()
        let waiter = Task { @MainActor in
            await notifier.waitForArrival(timeoutNanoseconds: 60_000_000_000)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)  // let it register
        notifier.wake()
        await waiter.value  // returns only because wake() resumed it
    }

    @MainActor
    @Test("wake() that resumes a waiter leaves no spurious pending wake")
    func wakeResumeLeavesNoPendingWake() async {
        let notifier = StdinArrivalNotifier()
        let waiter = Task { @MainActor in
            await notifier.waitForArrival(timeoutNanoseconds: 60_000_000_000)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        notifier.wake()  // resumes the waiter; the wake is consumed
        await waiter.value

        // Regression guard: a wake that resumed a waiter must NOT also set
        // pendingWake, or the next wait would return instantly — the busy spin
        // that pegged animating screens. So this wait must actually block.
        let clock = ContinuousClock()
        let start = clock.now
        await notifier.waitForArrival(timeoutNanoseconds: 30_000_000)  // 30 ms
        #expect(clock.now - start >= .milliseconds(15))
    }

    /// The defensive branch at the top of `waitForArrival`'s continuation body.
    /// It is unreachable through the real run loop — that loop is single-waiter
    /// by construction — which is exactly why it reads as dead code and why
    /// nothing pinned it. What it prevents is not a wrong pixel but a hang: a
    /// dropped `CheckedContinuation` is never resumed, so the first waiter's
    /// task is suspended for the life of the process and the loop it belongs to
    /// stops waking. A second `await waitForArrival` added later — a resize
    /// watcher, a paste drain — is all it takes.
    @MainActor
    @Test("A second waiter resumes the first rather than dropping its continuation")
    func secondWaiterResumesTheStaleOne() async {
        @MainActor final class Flags {
            var firstStarted = false
            var firstReturned = false
            var secondStarted = false
            var secondReturned = false
        }
        let notifier = StdinArrivalNotifier()
        let flags = Flags()

        /// Polls for a condition instead of sleeping a fixed interval.
        ///
        /// Every actor in this test is the MAIN one, and under the full suite
        /// it is contended by hundreds of other `@MainActor` tests — a fixed
        /// 20 ms sleep was enough when this suite ran alone and nowhere near it
        /// when the whole suite ran, so the test failed on scheduling rather
        /// than on behaviour. The bound is generous because it costs nothing
        /// when the condition holds: the loop returns the moment it does.
        func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(30))
            while clock.now < deadline {
                if condition() { return true }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            return condition()
        }

        // 60-second timeouts throughout: nothing here may be resumed BY a
        // timeout, or the test would pass without the guard.
        let first = Task { @MainActor in
            flags.firstStarted = true
            await notifier.waitForArrival(timeoutNanoseconds: 60_000_000_000)
            flags.firstReturned = true
        }
        // Observing `firstStarted` means the task has also run ON to its
        // suspension: `waitForArrival` is same-actor, so it registers the
        // continuation synchronously and the test body cannot get the actor
        // back until it has.
        #expect(await waitUntil { flags.firstStarted })

        let second = Task { @MainActor in
            flags.secondStarted = true
            await notifier.waitForArrival(timeoutNanoseconds: 60_000_000_000)
            flags.secondReturned = true
        }
        #expect(await waitUntil { flags.secondStarted })

        // The guard fires while `second` registers, so `first` comes back with
        // no wake of any kind having been delivered.
        #expect(
            await waitUntil { flags.firstReturned },
            "the stale continuation was dropped instead of resumed")
        #expect(!flags.secondReturned, "the newer waiter must still be waiting")

        // And the newer waiter is the one a single wake now finishes — the
        // guard leaves it installed, not the one it displaced.
        notifier.wake()
        #expect(await waitUntil { flags.secondReturned })

        // Awaited only once the flags say both have returned: without the guard
        // the first task is parked on a continuation nobody will ever resume,
        // and awaiting it would hang the suite instead of failing it.
        if flags.firstReturned { await first.value }
        if flags.secondReturned { await second.value }
    }

    @MainActor
    @Test("a cancelled timeout never resumes a later waiter (no cascade spin)")
    func cancelledTimeoutDoesNotCascade() async {
        // Reproduces the run-loop shape that exposed the bug: a task that waits,
        // is woken, and immediately waits again. Each wake() cancels the pending
        // timeout; if a cancelled timeout still fell through to signal(), it would
        // resume the NEXT wait early and cancel ITS timeout — a self-sustaining
        // cascade. One real wake would then spin the loop indefinitely, each
        // "wait" returning at once. We detect that by counting completed waits:
        // with correct behaviour only a handful complete in the window; a cascade
        // races straight to the loop's safety cap.
        @MainActor final class Counter {
            var completed = 0
            var stop = false
        }
        let notifier = StdinArrivalNotifier()
        let counter = Counter()

        let loop = Task { @MainActor in
            // Each wait is 50 ms; in the ~300 ms window below a correct notifier
            // completes only a handful (timeouts + the explicit wakes).
            for _ in 0..<10_000 {
                if counter.stop { break }
                await notifier.waitForArrival(timeoutNanoseconds: 50_000_000)
                counter.completed += 1
            }
        }

        // Wake repeatedly, as stdin / animation deadlines would. Each wake cancels
        // the in-flight timeout — the precondition for the old cascade, where the
        // cancelled timeout's stale signal() resumed the NEXT wait and cancelled
        // ITS timeout, self-sustaining. Many tight wakes make the triggering race
        // overwhelmingly likely to land at least once if the bug is present.
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 5_000_000)  // 5 ms
            notifier.wake()
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        counter.stop = true
        notifier.wake()  // release the final wait so the loop exits
        await loop.value

        // Correct behaviour completes ~one wait per wake (≈40) plus a few 50 ms
        // timeouts — well under 100. The cascade instead spins between wakes; the
        // pre-fix code recorded 300+. The wide gap keeps the bound robust under
        // load while still failing decisively on a regression.
        #expect(counter.completed < 100)
    }
}
