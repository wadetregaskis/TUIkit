//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AsyncSettling.swift
//
//  Waiting for work a test spawned, without guessing how long it will take.
//
//  `for _ in 0..<20 { await Task.yield() }` is what the suites here used, and
//  it is a BUDGET rather than a wait. A refresh action is `@Sendable` and runs
//  off the test's actor, so what a test waits for is a round trip — main actor
//  to the cooperative pool and back. Twenty yields is plenty while that pool is
//  idle and not enough when other PROCESSES, each with an oversubscribed pool
//  of its own, compete for the same cores: measured at 2 failures in 12 with
//  six competing helper processes, and 0 in 18 without them, which is also why
//  plain CPU load does not reproduce it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

/// Waits until `condition` holds, or gives up after `timeout`.
///
/// Mostly by yielding, because a yield is the thing that actually helps here:
/// what these tests wait for is usually a `Task { @MainActor in … }`, and
/// yielding is how a test on that actor hands it over. Every fiftieth
/// iteration naps instead — when the work is on the cooperative pool and the
/// pool is starved by other PROCESSES, no amount of yielding this actor helps
/// and briefly parking it does.
///
/// (Measured the expensive way: a first version napped for everything past
/// twenty yields, and full-suite runs went from green to failing four of five,
/// in these same assertions. A wait that stops yielding stops handing the actor
/// to the task it is waiting for, so it burned its whole deadline and — since
/// these tests hold a refresh body open while they wait — took other suites
/// down with it.)
///
/// The deadline is a HANG-BREAKER, NOT A SCHEDULE, and it is long for a
/// measured reason: in a full run this package's main actor is saturated — 81%
/// of its tests are `@MainActor` — and a single `Task.yield()` hop has been
/// measured taking **17.4 s** to come back (also 21.7, 5.0, 3.6). A wait whose
/// deadline is shorter than one hop gives up on work that was merely queued,
/// which is a slower way of not waiting at all. Sixty seconds is far past
/// anything healthy, so it fires only when something is genuinely stuck; the
/// cost of being generous is paid by broken tests alone.
///
/// Giving up is reported here, with the iteration count and the elapsed time:
/// the caller's `#expect` says what was not true, and only this can say whether
/// the wait was served slowly, spun without being served, or never really ran.
///
/// - Important: wait on an edge the code under test actually crosses. "A run
///   has started" is sound to observe from inside a refresh body, because the
///   run state is claimed before the body runs. "A run has ended" is not:
///   `RefreshAction.callAsFunction` clears that state after `await action()`
///   returns, with a suspension point in between, so the end has to be read
///   from the state itself (`isRunning`) or from a frame rendered after it.
@MainActor
func settle(
    until condition: @MainActor () -> Bool, timeout: Duration = .seconds(60)
) async {
    let started = ContinuousClock.now
    let deadline = started + timeout
    var iterations = 0
    while !condition() {
        guard ContinuousClock.now < deadline else {
            // Say so. The caller's `#expect` reports what was not true; only
            // this knows whether the wait was served slowly, spun without being
            // served, or never really ran at all.
            Issue.record(
                "settle(until:) gave up after \(iterations) iterations in \(started.duration(to: .now))")
            return
        }
        iterations += 1
        if iterations.isMultiple(of: 50) {
            try? await Task.sleep(for: .milliseconds(1))
        } else {
            await Task.yield()
        }
    }
}

/// Gives work a test spawned a chance to run, for an assertion that it did NOT
/// happen — or to let work wind down when nothing is asserted after it.
///
/// A budget is sound here, and only here: the claim is that no edge is crossed,
/// so waiting too little can only make the assertion weaker — never make it
/// fail. An assertion that something DID happen needs ``settle(until:timeout:)``;
/// a budget there is the race this file exists to remove.
@MainActor
func yieldToSpawnedWork() async {
    for _ in 0..<20 { await Task.yield() }
}
