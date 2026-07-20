//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SignalManager.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

// MARK: - Signal Registration Barrier

/// Bridges libdispatch signal-source *registration* callbacks — which fire on a
/// Dispatch queue, possibly before the installer gets around to awaiting them —
/// into an async sequence the installer waits on.
///
/// Buffering is unbounded so a callback that arrives before the `await` is
/// never dropped. This lets ``SignalManager/install(wake:)`` block until every
/// source is actually armed, closing the startup race where a signal delivered
/// between `resume()` and "source armed" would be lost — preserving the old
/// synchronous `signal()`'s "Ctrl-C caught from the first instruction" guarantee.
private final class SignalRegistrationBarrier: Sendable {
    /// Registration notifications consumed by the installer.
    let events: AsyncStream<Void>

    /// Thread-safe producer used by the Dispatch registration handlers.
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .unbounded)
        self.events = pair.stream
        self.continuation = pair.continuation
    }

    /// A nonisolated Dispatch callback that records one registration.
    func callback() -> @Sendable () -> Void {
        { [continuation] in continuation.yield() }
    }

    /// Finishes the registration stream once every source is armed.
    func finish() {
        continuation.finish()
    }
}

// MARK: - Signal Manager

/// Manages POSIX signal handling for the application lifecycle via libdispatch
/// signal sources.
///
/// SIGWINCH (terminal resize) and SIGINT / SIGTERM (graceful shutdown) are
/// monitored with `DispatchSource.makeSignalSource` on the main queue. Each
/// source's handler runs on the main actor, sets an instance flag, and wakes the
/// demand-driven run loop directly. There is no async-signal-safe C handler, no
/// self-pipe, and no flag-poll layer: the loop still drains the flags each
/// iteration exactly as before (``shouldShutdown``, ``consumeResizeFlag()``),
/// but the flags are ordinary main-actor state pushed by the sources.
///
/// ## Why dispatch signal sources rather than `signal()` handlers?
///
/// A C signal handler may only call async-signal-safe functions, which is why
/// the previous design set aligned `Bool`s from the handler and woke the loop
/// through a self-pipe. A dispatch signal source moves that off the handler
/// entirely: libdispatch delivers the signal as an ordinary queued event, so the
/// handler is normal main-actor code — no torn reads, no self-pipe fd, no poll.
///
/// ## Usage
///
/// ```swift
/// let signals = SignalManager()
/// await signals.install(wake: { notifier.wake() })
/// while running {
///     if signals.shouldShutdown { break }
///     if signals.consumeResizeFlag() { invalidateAndRepaint() }
/// }
/// signals.stop()
/// ```
@MainActor
final class SignalManager {
    private typealias Disposition = @convention(c) (Int32) -> Void

    private enum Kind {
        case resize
        case shutdown
    }

    private struct Registration {
        let number: Int32
        /// The disposition to restore on teardown (Darwin only; `nil` on Linux,
        /// where the disposition must not be touched — see ``register(_:kind:barrier:)``).
        let previous: Disposition?
        let source: any DispatchSourceSignal
    }

    private var registrations: [Registration] = []

    /// Set by SIGWINCH; consumed by the loop to invalidate the frame-diff cache
    /// and repaint at the new size.
    private var terminalResized = false

    /// Set (sticky) by SIGINT / SIGTERM to request a graceful shutdown. The loop
    /// reads it and breaks so the terminal-restore teardown runs.
    private var needsShutdown = false

    /// Wakes the demand-driven run loop when a signal lands while it is
    /// idle-blocked with nothing to render.
    private var wake: (@MainActor @Sendable () -> Void)?

    /// Whether a graceful shutdown was requested (SIGINT / SIGTERM).
    var shouldShutdown: Bool { needsShutdown }

    /// Returns `true` if the terminal was resized since the last call, then
    /// resets the flag (consume-on-read).
    func consumeResizeFlag() -> Bool {
        defer { terminalResized = false }
        return terminalResized
    }

    /// Installs signal sources for SIGWINCH, SIGINT, and SIGTERM.
    ///
    /// `wake` is invoked from each source's main-actor handler so a signal that
    /// arrives while the loop is idle-blocked wakes it. This awaits each source's
    /// registration before returning, so a signal delivered *during* install is
    /// buffered by the barrier rather than dropped.
    ///
    /// - Parameter wake: Called (on the main actor) after a signal updates the
    ///   flags, to rouse the run loop.
    func install(wake: @escaping @MainActor @Sendable () -> Void) async {
        guard registrations.isEmpty else { return }
        self.wake = wake

        let barrier = SignalRegistrationBarrier()
        register(SIGINT, kind: .shutdown, barrier: barrier)
        register(SIGTERM, kind: .shutdown, barrier: barrier)
        register(SIGWINCH, kind: .resize, barrier: barrier)

        // Block until every source's registration handler has fired — i.e. all
        // sources are armed — so no early signal slips through the startup gap.
        var iterator = barrier.events.makeAsyncIterator()
        for _ in registrations { _ = await iterator.next() }
        barrier.finish()
    }

    private func register(_ number: Int32, kind: Kind, barrier: SignalRegistrationBarrier) {
        // A dispatch signal source changes NO disposition on either platform, so
        // the default action still applies unless we suppress it — but HOW we
        // suppress it differs:
        //   • Darwin (kqueue EVFILT_SIGNAL): the source fires in addition to the
        //     default action, and still fires under SIG_IGN. So SIG_IGN the
        //     signal (default=terminate for INT/TERM) and restore on teardown;
        //     SIGWINCH's default is already IGNORE, so that's a harmless no-op.
        //   • Linux (swift-corelibs-libdispatch): libdispatch installs and OWNS
        //     the signal's handler as part of source setup, which both feeds the
        //     source and displaces the terminate default. Calling SIG_IGN there
        //     would overwrite libdispatch's handler and BREAK delivery — so leave
        //     the disposition untouched.
        #if os(Linux)
            let previous: Disposition? = nil
        #else
            let previous = signal(number, SIG_IGN)
        #endif

        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { [weak self] in
            // Runs on the main thread (queue: .main), so we are already on the
            // MainActor executor — `assumeIsolated` is a static-only bridge.
            MainActor.assumeIsolated {
                guard let self else { return }
                switch kind {
                case .resize: self.terminalResized = true
                case .shutdown: self.needsShutdown = true
                }
                // Set the flag THEN wake, so the resumed loop sees it already set.
                self.wake?()
            }
        }
        source.setRegistrationHandler(handler: barrier.callback())
        source.resume()
        registrations.append(Registration(number: number, previous: previous, source: source))
    }

    /// Cancels the signal sources and restores prior dispositions (Darwin).
    /// Idempotent — safe to call more than once.
    func stop() {
        for registration in registrations {
            registration.source.cancel()
            #if !os(Linux)
                if let previous = registration.previous {
                    signal(registration.number, previous)
                }
            #endif
        }
        registrations.removeAll()
        wake = nil
    }
}
