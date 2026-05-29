//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StdinArrivalStream.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch
import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

/// Lets the app's main loop wait for "stdin has data OR a
/// timeout expired", whichever fires first.
///
/// ## Why it exists
///
/// The original main-loop shape was
///
///     while !shouldShutdown {
///         drainPendingEvents()
///         try? await Task.sleep(nanoseconds: 24_000_000)
///     }
///
/// which sleeps a flat 24 ms regardless of whether stdin has
/// just received a keystroke. That sleep adds up to ~24 ms of
/// latency to every keystroke — perceptible as sluggish typing
/// in busy moments. This notifier replaces the bare
/// `Task.sleep` with a race: the loop awaits ``waitForArrival(
/// timeoutNanoseconds:)``, which wakes the moment either a
/// `DispatchSource` fires on `STDIN_FILENO` or the timeout
/// elapses.
///
/// ## How it integrates with the MainActor
///
/// The dispatch source's target queue is **`DispatchQueue.main`**,
/// not a global concurrent queue. That means the source's
/// event handler runs on the main thread — the same thread
/// the MainActor's executor lives on, on both macOS (where
/// the main actor's executor pumps the main queue via the
/// Cocoa run-loop) and Linux (where Swift's cooperative
/// executor pumps it). So when stdin has data, the handler is
/// already executing in the right place to enter MainActor
/// isolation via `MainActor.assumeIsolated`, signal the
/// pending continuation, and resume the main loop — no
/// cross-thread hop, no global-queue worker, no lock around
/// continuation state.
///
/// The earlier draft of this file ran the source on
/// `.global(qos: .userInteractive)` and protected the
/// continuation with an `NSLock`. That cost an extra
/// thread plus a continuation-resumption hop per keystroke,
/// for code whose only job was to flip a `Bool`. Targeting
/// `.main` collapses both back to "the main thread does it
/// when it gets there."
///
/// ## What the kernel does
///
/// `DispatchSource.makeReadSource` uses `kqueue` on macOS and
/// `epoll` (via swift-corelibs-libdispatch) on Linux. Both fire
/// for character devices including TTYs regardless of cooked /
/// raw mode, so this works the same whether the terminal is in
/// `ICANON` or out of it.
@MainActor
final class StdinArrivalNotifier {
    /// The continuation currently waiting to be resumed, or
    /// `nil` if nobody is waiting. At most one waiter at a
    /// time — the main loop is single-threaded.
    private var pendingContinuation: CheckedContinuation<Void, Never>?

    /// The currently-active timeout task. Cancelled if stdin
    /// arrives first; cleared when ``signal()`` consumes the
    /// continuation either way.
    private var timeoutTask: Task<Void, Never>?

    /// The active dispatch source, or `nil` if `start()`
    /// hasn't been called.
    private var source: (any DispatchSourceRead)?

    /// Installs the dispatch source on `STDIN_FILENO`. The
    /// source fires on `DispatchQueue.main` whenever the
    /// kernel has data ready to deliver — see the type-level
    /// doc for why that queue choice matters.
    func start() {
        let src = DispatchSource.makeReadSource(
            fileDescriptor: STDIN_FILENO,
            queue: .main
        )
        src.setEventHandler { [weak self] in
            // The handler executes on the main thread because
            // the source's queue is `.main`. From the main
            // thread we're already running on MainActor's
            // executor, so `assumeIsolated` is a static-only
            // bridge — no thread hop, no runtime check beyond
            // a debug assertion that we're on the right thread.
            MainActor.assumeIsolated {
                self?.signal()
            }
        }
        source = src
        src.activate()
    }

    /// Tears the dispatch source down. Safe to call multiple
    /// times.
    func stop() {
        source?.cancel()
        source = nil
        // If anyone is still waiting, resume them so the loop
        // doesn't hang on the way out.
        signal()
    }

    /// Suspends until either stdin has data or
    /// `timeoutNanoseconds` have elapsed, whichever happens
    /// first.
    func waitForArrival(timeoutNanoseconds: UInt64) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Defensive: if someone is already waiting, that's
            // a logic bug — we should be single-waiter. Resume
            // both rather than deadlock.
            if let stale = pendingContinuation {
                pendingContinuation = nil
                timeoutTask?.cancel()
                timeoutTask = nil
                stale.resume()
            }

            pendingContinuation = continuation

            // Spawn the timeout. The Task inherits MainActor
            // isolation from this enclosing method, so
            // `signal()` runs on the main actor — same place
            // the dispatch handler ends up. No locking needed
            // because all paths into `signal()` are
            // MainActor-isolated.
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self?.signal()
            }
        }
    }

    /// Resumes the pending waiter if there is one. Called
    /// from both the dispatch source's event handler (via
    /// `MainActor.assumeIsolated`) and the timeout Task
    /// (inherited MainActor isolation). The first one to
    /// grab the continuation wins; the other finds it `nil`
    /// and no-ops.
    private func signal() {
        let cont = pendingContinuation
        pendingContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        cont?.resume()
    }
}
