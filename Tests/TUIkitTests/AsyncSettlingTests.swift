//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AsyncSettlingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

/// The wait the refresh tests use, and the rule it gives up by.
///
/// A wait that gives up wrongly fails whichever test was using it, and blames
/// that test's assertion rather than the wait. In a full run on 2026-09-23 the
/// refresh suites failed that way — "gave up after 1 iterations in 100.67
/// seconds": a wait's first main-actor turn took the whole deadline and more,
/// and it gave up before the work queued behind that turn had had one of its
/// own.
@MainActor
@Suite("settle(until:)")
struct AsyncSettlingTests {

    /// Occupies the main actor for `duration` without suspending, the way a
    /// long render does, so nothing else queued on it can run meanwhile.
    private static func holdMainActor(for duration: Duration) {
        let until = ContinuousClock.now + duration
        while ContinuousClock.now < until {
            // Spin.
        }
    }

    /// That run's shape, at a tenth of a second instead of a hundred: the wait's
    /// first turn is queued behind a task that holds the main actor ten times
    /// longer than the wait's whole deadline, and the work it waits for is
    /// queued behind the turn. Main-actor jobs run in the order they were
    /// queued, so the turn comes back to a deadline long past and the work
    /// still undone, which used to be a failure: "gave up after 1 iterations".
    @Test("A wait whose first turn outlasts its deadline still sees the work it waited for")
    func starvedWaitIsNotStuck() async {
        let done = MainActorBox(false)
        Task { @MainActor in
            Self.holdMainActor(for: .milliseconds(100))
            Task { @MainActor in done.value = true }
        }
        await settle(until: { done.value }, timeout: .milliseconds(10))
        #expect(done.value)
    }

    /// The same shape, in the rule itself: the deadline passing during a turn
    /// starts the grace, and only the turns that begin after it are counted.
    @Test("A deadline passed during a turn starts a grace, not a failure")
    func deadlineStartsAGrace() {
        let start = ContinuousClock.now
        var wait = HangBreaker(timeout: .seconds(60), now: start)
        // A turn begun before the deadline — which, as `starvedWaitIsNotStuck`
        // shows through the real main actor, may come back long after it — is
        // no part of the grace.
        wait.nextTurn(at: start)
        #expect(!wait.isOverdue)

        // The grace's turns, spread across more than its minimum length.
        for grace in 0..<HangBreaker.graceTurns {
            #expect(!wait.hasTripped, "gave up after \(grace) of \(HangBreaker.graceTurns) grace turns")
            wait.nextTurn(at: start + .seconds(100) + .milliseconds(100 * grace))
            #expect(wait.isOverdue)
        }
        #expect(wait.hasTripped, "a wait still false after its whole grace must give up")
        #expect(wait.turns == 1 + HangBreaker.graceTurns)
        // The report tells the two phases apart: a hundred seconds went on one
        // turn, and the whole grace took one.
        let grace = HangBreaker.graceTurns
        #expect(
            wait.report(at: start + .seconds(101))
                == "\(1 + grace) turns in 101.0 seconds, the last \(grace) past its deadline in 1.0 seconds")
    }

    /// A grace whose turns came back fast is not over until it has lasted
    /// ``HangBreaker/minimumGrace``: the turns cover the main actor's legs of
    /// the work, and the time covers a hop to the pool not yet picked up.
    @Test("A grace of quick turns lasts its minimum time before giving up")
    func quickGraceLastsItsMinimum() {
        let start = ContinuousClock.now
        var wait = HangBreaker(timeout: .seconds(60), now: start)
        let overdue = start + .seconds(60)
        for grace in 0..<HangBreaker.graceTurns {
            wait.nextTurn(at: overdue + .milliseconds(grace))
        }
        #expect(!wait.hasTripped, "gave up after \(HangBreaker.graceTurns) turns in 9 ms")
        wait.nextTurn(at: overdue + HangBreaker.minimumGrace - .milliseconds(1))
        #expect(!wait.hasTripped, "gave up a millisecond before the grace's minimum")
        wait.nextTurn(at: overdue + HangBreaker.minimumGrace)
        #expect(wait.hasTripped, "a grace past both its turns and its time must give up")
    }

    /// The deadline is still the hang-breaker for a wait that is served: no
    /// number of prompt turns before it gives up, and the grace after it is its
    /// turns and its minimum time, not another minute.
    @Test("Turns before the deadline never give up, however many")
    func turnsBeforeTheDeadlineNeverTrip() {
        let start = ContinuousClock.now
        var wait = HangBreaker(timeout: .seconds(60), now: start)
        for turn in 0..<100_000 {
            wait.nextTurn(at: start + .microseconds(turn * 500))
        }
        #expect(!wait.isOverdue)
        #expect(!wait.hasTripped)

        for grace in 0..<HangBreaker.graceTurns {
            wait.nextTurn(at: start + .seconds(60) + HangBreaker.minimumGrace * grace)
        }
        #expect(wait.hasTripped)
    }
}
