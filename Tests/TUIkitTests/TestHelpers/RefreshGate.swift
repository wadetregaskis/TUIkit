//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RefreshGate.swift
//
//  The gate a refresh body waits at, so a test decides when the refresh
//  finishes — and the count of bodies that have reached it, so a test can wait
//  for a run to have STARTED rather than for a number of yields to have gone
//  by. Shared rather than copied: `RefreshableTests`, `RefreshableMemoTests`
//  and `TerminalFocusPhaseTests` each had their own.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A gate a refresh body waits at until the test opens it.
///
/// A refresh action is `@Sendable` and runs off the test's own actor, so a
/// captured `nonisolated(unsafe) var` opened afterwards is precisely the
/// mutation-after-capture the compiler warns about. Reference semantics behind
/// a lock are what these tests always meant — `RefreshAction.RunState` is the
/// same shape for the same reason.
final class RefreshGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var entries = 0

    /// How many refresh bodies have reached the gate.
    ///
    /// The sound edge to wait on for "a run has started": `RefreshAction`
    /// claims its run state *before* calling the body, so a body that has
    /// arrived here is a run already marked running — the spinner is up and a
    /// second request will coalesce. The END of a run is deliberately not
    /// observable here: the state is cleared after the body returns, with a
    /// suspension point in between, so that edge has to be read from
    /// `isRunning` or from a frame rendered after it.
    var entered: Int { lock.withLock { entries } }

    /// Holds the calling refresh body until ``release()``.
    ///
    /// It PARKS rather than spinning on `Task.yield()`, which is what the three
    /// copies of this gate did. A held body waits on the test, not on other
    /// tasks, so yielding buys nothing and costs a cooperative-pool slot for as
    /// long as the gate is shut — and that pool is where the work these tests
    /// wait for runs (`RefreshAction` hops off the main actor to call the
    /// body). With waits of twenty yields the gates were shut for microseconds
    /// and it never showed; with waits that actually wait, several bodies spun
    /// at once and starved the pool, failing five tests together in three full
    /// runs out of five. Parked, a held body occupies nothing.
    func hold() async {
        lock.withLock { entries += 1 }
        while lock.withLock({ !open }) {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Lets every waiting body finish.
    func release() { lock.withLock { open = true } }

    /// Shuts the gate again, for a test that runs a second body through it.
    func reset() { lock.withLock { open = false } }
}
