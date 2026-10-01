//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StdinArrivalStream.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// A readiness source is the POSIX half of this file. WebAssembly's wasip1 has
// no libdispatch to hold one — but it does have `poll`, which answers the very
// question this type exists to ask ("stdin, or the timeout, whichever is
// first") in a single call. The arm at the bottom is that call.
#if !canImport(WASILibc)

import Dispatch

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
/// not a global concurrent queue. The main queue IS the main
/// actor's executor — pumped by the Cocoa run-loop on macOS,
/// by Swift's cooperative executor on Linux — so the source's
/// event handler is already running in the main actor's
/// context. Note the claim is about the EXECUTOR, not a
/// thread: which OS thread drains the main actor is not
/// fixed, and on Linux it is a cooperative pool thread rather
/// than the process main thread from the first suspension
/// point onward (measured — see the "Thread correctness" note
/// on TUIkitCore's `StackGuard`). So when stdin has data, the
/// handler is already in the right place to enter MainActor
/// isolation via `MainActor.assumeIsolated`, signal the
/// pending continuation, and resume the main loop — no
/// executor hop, no global-queue worker, no lock around
/// continuation state.
///
/// The earlier draft of this file ran the source on
/// `.global(qos: .userInteractive)` and protected the
/// continuation with an `NSLock`. That cost an extra
/// thread plus a continuation-resumption hop per keystroke,
/// for code whose only job was to flip a `Bool`. Targeting
/// `.main` collapses both back to "the main actor does it
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

    /// The descriptor ``source`` watches: stdin, except under test.
    private var descriptor: Int32 = STDIN_FILENO

    /// Whether a source is watching the descriptor — false before ``start(descriptor:)``,
    /// after ``stop()``, and once the descriptor reached end of file.
    var isWatching: Bool { source != nil }

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
    ///
    /// - Parameter descriptor: The descriptor to watch. Only the tests pass
    ///   anything but stdin, and they have to: a read source cannot be driven
    ///   without a descriptor to close, and the EOF behaviour below is
    ///   otherwise unobservable without a live TTY. The same seam, for the same
    ///   reason, as `Terminal.readSource`.
    func start(descriptor: Int32 = STDIN_FILENO) {
        self.descriptor = descriptor
        let src = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: .main
        )
        src.setEventHandler { [weak self] in
            // The source's queue is `.main`, and the main queue
            // is the main actor's executor — so this handler is
            // already running in the main actor's context and
            // `assumeIsolated` is a static-only bridge, with no
            // thread hop.
            //
            // Deliberately says nothing about *threads*: which
            // OS thread drains the main actor is not fixed. On
            // Linux it is a cooperative pool thread, not the
            // process main thread, from the first suspension
            // point onward (measured — see the "Thread
            // correctness" note in TUIkitCore's StackGuard).
            // The executor is what serialises this against the
            // run loop; the thread is incidental.
            MainActor.assumeIsolated {
                self?.handleReadable()
            }
        }
        source = src
        src.activate()
    }

    /// One firing of the read source: wake the loop, unless the descriptor has
    /// reached end of file, in which case take the source down.
    ///
    /// A read source is level-triggered, and EOF reads as permanently readable:
    /// the handler is re-armed the moment it returns, fires again on a
    /// descriptor that will never have another byte, and does so as fast as the
    /// main queue can dispatch it. Each firing woke the loop, so the
    /// demand-driven wait stopped waiting — the process sat at 100% of a core,
    /// rendering nothing, for as long as it ran. Nothing downstream could catch
    /// it either: `Terminal`'s reader returns 0 at EOF and `appendDrain` only
    /// acts on `n > 0`, so EOF was indistinguishable from "no data yet" all the
    /// way up.
    ///
    /// It is not a hypothetical descriptor. Stdin is at EOF whenever the app is
    /// run with its input closed or redirected from `/dev/null` — a CI step, a
    /// process supervisor, anything launching it non-interactively.
    ///
    /// The source is cancelled rather than left armed, and deliberately WITHOUT
    /// signalling: a `wake()` here would set `pendingWake` and make the next
    /// wait return at once, which is a smaller version of the same spin. Any
    /// waiter suspended at that moment is bounded by its own timeout. A TTY does
    /// not reach this — in raw mode Ctrl-D is the byte 0x04, not end of file —
    /// so nothing cancels the source out from under a live terminal.
    ///
    /// The source's own count of ready bytes cannot say which it is. On Linux
    /// that count is an `ioctl` libdispatch makes on its own thread after
    /// `epoll` wakes it, while the run loop reads the same descriptor on the
    /// main actor — and a hang-up reaches the handler as 0 too. A keystroke the
    /// loop has already read by the time of the `ioctl` comes to the handler
    /// as "0 bytes ready", which this used to take for end of file: the source
    /// was cancelled, and from then on the app heard a key only when something
    /// else woke the loop. On a screen with nothing animating that is never —
    /// every Linux CI lane's PTY walk went deaf on such a page, a different
    /// page from run to run, and no macOS lane ever did (2026-09-29 to
    /// 10-01). So a 0 is a question for ``isAtEndOfInput(_:)``, which asks the
    /// descriptor itself.
    private func handleReadable() {
        guard let source else { return }
        handleReadable(reportedBytes: source.data)
    }

    /// The decision ``handleReadable()`` makes for a count of `reportedBytes`
    /// ready. Internal so a test can hand it the 0 a race produces, which no
    /// test can make libdispatch produce on cue.
    func handleReadable(reportedBytes: UInt) {
        if reportedBytes == 0, Self.isAtEndOfInput(descriptor) {
            source?.cancel()
            source = nil
            return
        }
        // Waking when the bytes were in fact already read costs one pass of the
        // loop that finds nothing to do, against missing a keystroke.
        wake()
    }

    /// Whether `descriptor` is at end of file: readable, with nothing to read.
    ///
    /// A descriptor that is not readable at all is not at end of file — its
    /// bytes were taken by someone else (the race ``handleReadable()``
    /// describes), and more may come. One that is readable but cannot say
    /// how much it holds (`/dev/null`, which answers no `FIONREAD`) is taken
    /// to be at the end, since a descriptor stdin can sensibly be that never
    /// counts its bytes is not one a person types into.
    nonisolated static func isAtEndOfInput(_ descriptor: Int32) -> Bool {
        var probe = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&probe, 1, 0) == 1 else { return false }
        var available: Int32 = 0
        #if canImport(Glibc) || canImport(Musl)
            let result = ioctl(descriptor, UInt(FIONREAD), &available)
        #else
            // Darwin's `FIONREAD` is `_IOR('f', 127, int)`, a function-like
            // macro Swift does not import; this is its value.
            let result = ioctl(descriptor, 0x4004_667F, &available)
        #endif
        return result != 0 || available == 0
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

#else  // canImport(WASILibc)

import WASILibc

// MARK: - WebAssembly

/// The same waiter, built on `poll` instead of a dispatch source.
///
/// The POSIX arm above races a readiness source against a `Task.sleep`, because
/// that is how you ask two questions at once when the answer arrives on another
/// thread. wasip1 has one thread and one call — `poll_oneoff`, which wasi-libc
/// spells `poll` — that takes both subscriptions and returns on whichever fires.
/// So the race collapses into the wait itself, and the timeout task, the
/// continuation and the source all go with it.
///
/// ## Blocking, on purpose
///
/// This blocks the only thread there is, which on any other platform would be a
/// bug and here is the point: while the loop is waiting for input there is, by
/// construction, nothing else to run — no other thread, no timer that is not
/// already this call's timeout. In a browser the same call is what hands the
/// tab back (the host's `poll_oneoff` sleeps the worker), so blocking here is
/// how the page stays responsive rather than how it stops being.
///
/// The one real difference from the POSIX arm: a `wake()` cannot interrupt a
/// wait in progress. It does not need to. Every caller of `wake()` is main-actor
/// isolated, and the main actor is inside this call for the duration — so a wake
/// can only land before the wait (caught by ``pendingWake``) or after it.
@MainActor
final class StdinArrivalNotifier {

    /// A wake delivered while nobody was waiting, so the next wait returns at
    /// once. Same contract as the POSIX arm's flag of the same name.
    private var pendingWake = false

    /// Nothing to install: `poll` is asked per wait, not armed in advance.
    func start() {}

    /// Nothing to tear down.
    func stop() {}

    /// Records a wake for the next wait. There is no waiter to resume — see the
    /// type's doc for why that is sound here and not elsewhere.
    func wake() {
        pendingWake = true
    }

    /// Waits until stdin has bytes or the timeout elapses, whichever is first.
    ///
    /// - Parameter timeoutNanoseconds: The longest to wait, or `nil` to wait
    ///   until stdin speaks. `poll` counts milliseconds, so a timeout shorter
    ///   than one is rounded UP to one rather than down to zero: a zero would
    ///   turn a demand-driven loop into a spin.
    func waitForArrival(timeoutNanoseconds: UInt64?) async {
        if pendingWake {
            pendingWake = false
            return
        }
        let milliseconds: Int32
        if let timeoutNanoseconds {
            let rounded = (timeoutNanoseconds + 999_999) / 1_000_000
            milliseconds = Int32(clamping: rounded)
        } else {
            milliseconds = -1
        }
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        _ = withUnsafeMutablePointer(to: &descriptor) { poll($0, 1, milliseconds) }
        // The wait above is synchronous, and this is what keeps that from
        // eating the stack. On the single-threaded executor a resumption is a
        // direct call rather than a return to a scheduler — so an `async`
        // function with no suspension point inside it leaves the caller's frame
        // in place, and a run loop awaiting one grows the stack by a few frames
        // per frame drawn until wasm traps. (Measured: the Example ran for a
        // few hundred frames, then `call stack exhausted`.) Yielding is a real
        // suspension: the continuation is enqueued and the stack unwinds to the
        // executor before it runs.
        await Task.yield()
    }
}

#endif
