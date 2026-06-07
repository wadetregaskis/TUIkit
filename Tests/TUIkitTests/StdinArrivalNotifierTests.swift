//  🖥️ TUIKit — Terminal UI Kit for Swift
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
}
