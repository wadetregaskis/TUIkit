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
/// Why it exists: the original main-loop shape was
///
///     while !shouldShutdown {
///         drainPendingEvents()
///         try? await Task.sleep(nanoseconds: 24_000_000)
///     }
///
/// which sleeps a flat 24 ms regardless of whether stdin had
/// just received a keystroke. That sleep adds up to ~24 ms of
/// latency to every key press — perceptible as sluggish
/// typing in busy moments. This notifier replaces the bare
/// `Task.sleep` with a race: the loop awaits ``waitForArrival(
/// timeoutNanoseconds:)``, which wakes the moment a
/// `DispatchSource` fires on `STDIN_FILENO` (kqueue on macOS,
/// epoll on Linux) or the timeout expires, whichever comes
/// first. Animations still advance at the same cadence, but
/// keystrokes get drained immediately.
///
/// The class is `nonisolated` because the dispatch source's
/// event handler runs on a background queue and must be able
/// to resume the continuation. Internal state is protected by
/// an `NSLock`.
final class StdinArrivalNotifier: @unchecked Sendable {
    /// The continuation currently waiting to be resumed, or
    /// `nil` if nobody is waiting. At most one waiter at a
    /// time — the app's main loop is single-threaded.
    private var pendingContinuation: CheckedContinuation<Void, Never>?

    /// Protects ``pendingContinuation`` and ``isTimeoutScheduled``.
    /// The dispatch source's event handler resumes the
    /// continuation from a background queue, and the main
    /// loop sets it from the main thread — both need
    /// synchronisation.
    private let lock = NSLock()

    /// True while a timeout Task is scheduled. Lets us
    /// no-op when stdin arrives before the timeout (we don't
    /// need to cancel the Task explicitly — it will fire
    /// after and find no waiter to resume).
    private var isTimeoutScheduled = false

    /// The active dispatch source, or `nil` if `start()`
    /// hasn't been called.
    private var source: (any DispatchSourceRead)?

    /// Installs the dispatch source on `STDIN_FILENO`. The
    /// source fires on a background `userInteractive` queue
    /// whenever the kernel has data ready to deliver.
    func start() {
        let src = DispatchSource.makeReadSource(
            fileDescriptor: STDIN_FILENO,
            queue: .global(qos: .userInteractive)
        )
        src.setEventHandler { [weak self] in
            self?.signal()
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
        // doesn't hang on its way out.
        signal()
    }

    /// Suspends until either stdin has data or
    /// `timeoutNanoseconds` have elapsed, whichever happens
    /// first.
    ///
    /// Implementation: stash the suspending continuation, then
    /// spawn a Task that calls ``signal()`` after the timeout.
    /// Whichever path (stdin or timeout) signals first wins;
    /// the other becomes a no-op because the continuation has
    /// been consumed.
    func waitForArrival(timeoutNanoseconds: UInt64) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()

            // Defensive: if someone is already waiting, that's
            // a logic bug — we should be single-waiter. Resume
            // both rather than deadlock.
            if let stale = pendingContinuation {
                pendingContinuation = nil
                lock.unlock()
                stale.resume()
                continuation.resume()
                return
            }

            pendingContinuation = continuation
            isTimeoutScheduled = true
            lock.unlock()

            // Spawn the timeout. It fires on whatever executor
            // — we don't need MainActor for the signal()
            // method, which is nonisolated.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self?.signal()
            }
        }
    }

    /// Resumes the pending waiter if there is one. Called from
    /// both the dispatch source's event handler (when stdin
    /// has data) and the timeout Task. The first one to grab
    /// the continuation wins; the other finds it `nil` and
    /// no-ops.
    private func signal() {
        lock.lock()
        let cont = pendingContinuation
        pendingContinuation = nil
        isTimeoutScheduled = false
        lock.unlock()
        cont?.resume()
    }
}
