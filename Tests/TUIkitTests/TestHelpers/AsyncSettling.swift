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

/// Waits until `condition` holds, or gives up once `timeout` has passed and
/// ``HangBreaker/graceTurns`` more turns have not made it hold either.
///
/// Mostly by yielding, because a yield is the thing that actually helps here:
/// what these tests wait for is usually a `Task { @MainActor in … }`, and
/// yielding is how a test on that actor hands it over. Every fiftieth turn
/// naps instead — when the work is on the cooperative pool and the pool is
/// starved by other PROCESSES, no amount of yielding this actor helps and
/// briefly parking it does.
///
/// (Measured the expensive way: a first version napped for everything past
/// twenty yields, and full-suite runs went from green to failing four of five,
/// in these same assertions. Why was never established. A wait that stops
/// yielding stops handing the actor over directly; the same run also found a
/// spinning gate starving the pool (19e2ce85); and each failure was a deadline
/// running out. So the steady state here yields, and only the grace naps.)
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
/// And no deadline is long enough by itself. On 2026-09-23, with parallel
/// builds loading the machine, waits in the refresh suites gave up the moment
/// their first hop came back — "gave up after 1 iterations in 100.67 seconds"
/// — on work queued behind that hop, which had not had a turn of its own. So
/// the deadline starts a grace instead of ending the wait (``HangBreaker`` has
/// the rule): a slow main-actor turn now costs a wait time, not its verdict.
/// Every turn of the grace naps. There are few of them, and as yields they
/// could all be over before a hop to the pool had been picked up — so the
/// grace is also at least ``HangBreaker/minimumGrace`` long, which gives the
/// pool's leg of the work that long too. That is a margin, not a guarantee: a
/// pool starved for longer still reads as stuck.
///
/// Giving up is reported here, with the turn count, the elapsed time and how
/// long the grace took: the caller's `#expect` says what was not true, and only
/// this can say whether the wait was served slowly, spun without being served,
/// or never really ran.
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
    var wait = HangBreaker(timeout: timeout)
    while !condition() {
        guard !wait.hasTripped else {
            // Say so. The caller's `#expect` reports what was not true; only
            // this knows whether the wait was served slowly, spun without being
            // served, or never really ran at all.
            Issue.record("settle(until:) gave up after \(wait.report())")
            return
        }
        let turn = wait.nextTurn()
        if wait.isOverdue || turn.isMultiple(of: 50) {
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

// MARK: - The hang-breaker

/// When a wait in these tests gives up, and what it can say when it does.
///
/// ``settle(until:timeout:)`` and the registration storm's poll suspend
/// differently — one mostly yields, the other only naps, each for a reason its
/// own documentation gives — but both are waits with a hang-breaker, and when
/// to break is one rule, so it is kept in one place.
///
/// The rule is a deadline and then a grace. A wait whose deadline has passed
/// still takes ``graceTurns`` more turns, and gives up only if its condition is
/// false after every one of them. A deadline that passed DURING a turn says
/// nothing about the work: the whole turn may have been spent queued behind a
/// saturated main actor, with the work's next hop queued behind the turn. A
/// turn that BEGINS past the deadline has whatever the work queued before it
/// in front of it, so only those count towards giving up.
struct HangBreaker {
    /// How many turns a wait still takes once its deadline has passed.
    ///
    /// A margin, not a measurement. The longest chain these waits sit behind
    /// is a Ctrl-R's: the task the key press spawns starts on the main actor,
    /// `RefreshAction` hops to the pool, back to the main actor for its first
    /// `MainActor.run`, and to the pool again to run the body — two turns of
    /// each. Ten covers that with room to spare, and costs a wait that is
    /// genuinely stuck ten more turns: milliseconds on an idle main actor,
    /// longer on a saturated one.
    static let graceTurns = 10

    /// How long the grace lasts at least, from the first turn past the deadline.
    ///
    /// The turns alone cover the main actor's legs of the work and not the
    /// pool's: on an idle main actor ten naps are over in about ten
    /// milliseconds, and a body waiting for a pool thread may not have been
    /// given one by then. Half a second is a margin for that leg, no more; a
    /// genuinely stuck wait pays it once.
    static let minimumGrace: Duration = .milliseconds(500)

    private let started: ContinuousClock.Instant
    private let deadline: ContinuousClock.Instant
    /// When the first turn past the deadline began.
    private var overdueSince: ContinuousClock.Instant?
    /// When the last turn counted began.
    private var lastTurn: ContinuousClock.Instant?

    /// How many times the wait has suspended.
    private(set) var turns = 0

    /// How many of those turns began at or past the deadline.
    private(set) var overdueTurns = 0

    init(timeout: Duration, now: ContinuousClock.Instant = .now) {
        started = now
        deadline = now + timeout
    }

    /// Whether the turn last counted began past the deadline, which makes it,
    /// and every turn after it, part of the grace.
    var isOverdue: Bool { overdueTurns > 0 }

    /// Whether the wait should give up rather than suspend again: its deadline
    /// has passed, and since then it has taken every turn of its grace and
    /// begun its last one at least ``minimumGrace`` after the first.
    ///
    /// Timed by when the turns BEGAN, as the wait counted them, so the rule
    /// reads no clock of its own and its tests can inject every instant.
    var hasTripped: Bool {
        guard overdueTurns >= Self.graceTurns, let overdueSince, let lastTurn else { return false }
        return overdueSince.duration(to: lastTurn) >= Self.minimumGrace
    }

    /// Counts the suspension the wait is about to make, and returns its
    /// number, counting from 1.
    @discardableResult
    mutating func nextTurn(at now: ContinuousClock.Instant = .now) -> Int {
        turns += 1
        lastTurn = now
        if now >= deadline {
            if overdueSince == nil { overdueSince = now }
            overdueTurns += 1
        }
        return turns
    }

    /// The wait's turns and how long they took, and how long its grace took.
    ///
    /// Between them they say how the wait went. Thousands of turns and a grace
    /// over in milliseconds: the wait was served promptly, and the work still
    /// did not happen. A handful of turns and a grace that took seconds: it was
    /// served slowly throughout. A handful before a quick grace: it hardly ran
    /// before its deadline, and then the work had its turns and still did not
    /// happen.
    ///
    /// A method rather than `description`, because it reads the clock: an
    /// `#expect` that prints a breaker built at an injected instant would
    /// otherwise print durations measured against a different one.
    func report(at now: ContinuousClock.Instant = .now) -> String {
        var text = "\(turns) turns in \(started.duration(to: now))"
        if let overdueSince {
            text += ", the last \(overdueTurns) past its deadline in \(overdueSince.duration(to: now))"
        }
        return text
    }
}
