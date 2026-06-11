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

    /// An extra read source (e.g. the signal self-pipe) whose readability also
    /// wakes the loop, registered via ``watchWakeFD(_:)``. Drained on each fire.
    private var extraSource: (any DispatchSourceRead)?

    /// A wake delivered while no waiter was suspended. The next
    /// ``waitForArrival(timeoutNanoseconds:)`` returns immediately and clears
    /// it, so a render-request that lands between the loop's check and its
    /// suspension is never lost. All callers are MainActor-isolated and run to
    /// suspension, so a single flag (no lock) is sufficient.
    private var pendingWake = false

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
                self?.wake()
            }
        }
        source = src
        src.activate()
    }

    /// Also wake when `fd` becomes readable (e.g. the signal self-pipe, so
    /// SIGWINCH / SIGINT wake the demand-driven loop). The fd is drained on each
    /// fire so it doesn't keep re-triggering. Pass the read end; ownership of the
    /// fd stays with the caller (this only watches it).
    func watchWakeFD(_ fd: Int32) {
        guard fd >= 0 else { return }
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                var scratch = [UInt8](repeating: 0, count: 64)
                while read(fd, &scratch, scratch.count) > 0 {}
                self?.wake()
            }
        }
        extraSource = src
        src.activate()
    }

    /// Tears the dispatch sources down. Safe to call multiple
    /// times.
    func stop() {
        source?.cancel()
        source = nil
        extraSource?.cancel()
        extraSource = nil
        // If anyone is still waiting, resume them so the loop
        // doesn't hang on the way out.
        signal()
    }

    /// Suspends until woken — by stdin data, a ``wake()`` (render request /
    /// resize), or, if `timeoutNanoseconds` is non-nil, that timeout elapsing.
    /// Pass `nil` to block indefinitely (purely demand-driven; nothing forces a
    /// wake), which is what the run loop does when there is nothing to render.
    func waitForArrival(timeoutNanoseconds: UInt64?) async {
        // A wake that arrived before we suspended — return without blocking.
        if pendingWake {
            pendingWake = false
            return
        }
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

            // Spawn the timeout, if any. The Task inherits MainActor isolation
            // from this enclosing method, so `signal()` runs on the main actor —
            // same place the dispatch handler ends up. No locking needed because
            // all paths into `signal()` are MainActor-isolated.
            if let timeoutNanoseconds {
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    // A cancelled timeout must NOT signal. `signal()` always
                    // cancels `timeoutTask` before it resumes a waiter, so a
                    // cancelled timeout is one whose waiter was already resumed
                    // (by `wake()`, or by a newer wait superseding it). By now
                    // `pendingContinuation` may belong to a *different, later*
                    // wait — `try?` would otherwise swallow the cancellation and
                    // fall through to `signal()`, resuming that wait early, which
                    // cancels *its* timeout, which does the same on the next turn:
                    // a self-sustaining cascade of early wakes that reads as a
                    // busy spin on timer-driven (animating) screens.
                    guard !Task.isCancelled else { return }
                    self?.signal()
                }
            }
        }
    }

    /// Wakes the loop because there is work to do — stdin arrived, or a render
    /// was requested (state change, animation tick, resize). If a waiter is
    /// suspended, resume it; otherwise remember the wake (``pendingWake``) so the
    /// next ``waitForArrival`` returns at once. Crucially it does NOT set
    /// `pendingWake` when it resumes a waiter — doing so caused a spurious extra
    /// iteration per wake (a busy spin on animating screens).
    func wake() {
        if pendingContinuation != nil {
            signal()
        } else {
            pendingWake = true
        }
    }

    /// Resumes the pending waiter if there is one. Called from ``wake()`` and
    /// the timeout Task (inherited MainActor isolation). The first one to grab
    /// the continuation wins; the other finds it `nil` and no-ops.
    private func signal() {
        let cont = pendingContinuation
        pendingContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        cont?.resume()
    }
}
