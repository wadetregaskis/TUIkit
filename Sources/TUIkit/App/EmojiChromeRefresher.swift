//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EmojiChromeRefresher.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The push-refreshed cache of "do the terminal(s) in front of the user draw
/// the emoji chrome correctly?".
///
/// Off tmux the answer is a process-lifetime constant: it is resolved once and
/// never re-asked. Under tmux it can change while the app runs — a client
/// detaches, a different terminal attaches, possibly at the same size (which
/// sends no SIGWINCH of its own) — so at startup the app registers tmux hooks
/// that push a SIGWINCH on any client change
/// (``TerminalHost/installTmuxClientChangeHooks()``), and the SIGWINCH path
/// calls ``refresh()``.
///
/// ``refresh()`` is ASYNCHRONOUS: the probe (a bounded `fork`/`exec`, see
/// ``TerminalHost/probeTmuxClients()``) runs off the main actor while frames
/// keep rendering with the previous answer; when the result lands and differs,
/// `onChange` runs — the owner invalidates the whole screen and requests a
/// render, so the correction is proactive rather than waiting for the next
/// keypress. In steady state — no client changes, no resizes — no subprocess
/// runs at all, ever.
///
/// Non-generic and separate from `RenderLoop` for two reasons: the coalescing
/// logic is unit-testable with an injected probe (no tmux server, no forks),
/// and a `Task.detached` inside the generic `RenderLoop<A>` would capture
/// `A.Type`, which is not `Sendable`.
/// One probe's answer, plus whether it might improve on a short retry.
///
/// `mayImproveShortly` covers a measured race: the `client-attached` tmux hook
/// fires — and the app probes — before the new client's XTVERSION reply has
/// arrived, so the client is silent at that instant even when it is an iTerm2
/// that will name itself milliseconds later. A silent client the process walk
/// also can't identify is therefore worth a few bounded re-asks before the
/// safe answer is allowed to stand.
internal struct EmojiChromeReading: Equatable, Sendable {
    let supported: Bool
    let mayImproveShortly: Bool
}

@MainActor
internal final class EmojiChromeRefresher {
    /// The last probe's answer; `nil` only before ``resolve()`` first seeds it.
    private(set) var current: Bool?

    /// Whether ``refresh()`` does anything. Off tmux the answer cannot change,
    /// so refreshing is a no-op (`false` there).
    private let isRefreshable: Bool

    /// Produces the answer, or `nil` when the question could not be asked (a
    /// wedged tmux, the probe's deadline). `nil` is NOT "no clients" — a failed
    /// probe keeps the previous answer rather than flipping the UI, because a
    /// single slow `list-clients` under load must not restyle every glyph on
    /// screen (and flip it back when the next probe succeeds). Blocking
    /// (bounded) — always run off the main actor by ``refresh()``;
    /// ``resolve()`` runs it inline exactly once, to seed.
    private let probe: @Sendable () -> EmojiChromeReading?

    /// Backoff for re-asking after a reading that ``EmojiChromeReading/mayImproveShortly``
    /// — long enough for an XTVERSION round trip, short enough that the user
    /// never watches the wrong glyphs settle. Injectable so tests don't wait.
    private let retryDelaysNanos: [UInt64]

    /// How many retries the CURRENT burst may still spend; refilled by every
    /// external ``refresh()`` (each real event earns a fresh budget), consumed
    /// by ``scheduleRetryIfWarranted()``. Bounded so a genuinely unknown
    /// silent terminal costs a fixed handful of probes, never a poll loop.
    private var retriesRemaining = 0

    /// Retry tasks currently sleeping toward their re-ask. Tracked separately
    /// from the coalescer because a sleeping retry has not requested a probe
    /// yet — without this, ``isIdleForTesting`` reads idle mid-burst.
    private var sleepingRetries = 0

    /// Runs (on the main actor) when a refresh lands a DIFFERENT answer than
    /// the one frames have been rendering with. The owner treats this as
    /// "every glyph on screen may be wrong": full invalidate + request render.
    private let onChange: @MainActor () -> Void

    /// Coalescing: at most one probe in flight; a request arriving mid-probe
    /// re-runs ONCE at completion. A burst of SIGWINCHes (a resize drag, an
    /// attach that also resizes) therefore costs one or two probes total, and
    /// the last probe always starts after the last request, so the final
    /// client set is never missed.
    private var coalescer = ProbeCoalescer()

    init(
        isRefreshable: Bool,
        probe: @escaping @Sendable () -> EmojiChromeReading?,
        onChange: @escaping @MainActor () -> Void,
        retryDelaysNanos: [UInt64] = [250_000_000, 500_000_000, 1_000_000_000]
    ) {
        self.isRefreshable = isRefreshable
        self.probe = probe
        self.onChange = onChange
        self.retryDelaysNanos = retryDelaysNanos
    }

    /// Whether no probe is in flight, queued, or sleeping toward a retry — the
    /// moment a test can assert the refresher's state without racing a pending
    /// completion.
    var isIdleForTesting: Bool { coalescer.isIdle && sleepingRetries == 0 }

    /// The current answer, seeding it synchronously on the very first call.
    ///
    /// The one inline probe means the app never draws its first frame with a
    /// guessed answer and then visibly corrects it at launch; every later call
    /// is a pure cache read, and only ``refresh()`` — off the render path —
    /// ever probes again.
    func resolve() -> Bool {
        if let current { return current }
        // At launch there is no previous answer to keep, so a failed seed probe
        // falls to the safe glyphs (false) — the same fail-closed answer the
        // probe layer gives for an unreachable tmux.
        let reading = probe()
        let seeded = reading?.supported ?? false
        current = seeded
        if isRefreshable, reading?.mayImproveShortly == true {
            retriesRemaining = retryDelaysNanos.count
            scheduleRetryIfWarranted()
        }
        return seeded
    }

    /// Re-probes asynchronously; frames keep rendering with ``current`` while
    /// the probe is in flight, and `onChange` fires if the landed answer
    /// differs. No-op when the answer cannot change (off tmux).
    func refresh() {
        guard isRefreshable else { return }
        retriesRemaining = retryDelaysNanos.count
        guard coalescer.requestProbe() else { return }
        startProbe()
    }

    /// Launches one background probe. Only ever called with the coalescer's
    /// consent (`requestProbe()` / `probeCompleted()` returned true).
    private func startProbe() {
        let probe = self.probe
        Task.detached(priority: .utility) { [weak self] in
            // Blocking work (bounded ~250ms worst case, ~3ms typical) on a
            // cooperative-pool thread: acceptable because probes only run when
            // tmux reports an actual client change or the terminal resizes.
            let answer = probe()
            await self?.apply(answer)
        }
    }

    /// Completion of a background probe, back on the main actor. A `nil`
    /// reading (the probe failed) changes nothing: the previous answer stands.
    private func apply(_ reading: EmojiChromeReading?) {
        if let reading, reading.supported != current {
            current = reading.supported
            onChange()
        }
        if coalescer.probeCompleted() {
            startProbe()
        } else if reading?.mayImproveShortly == true {
            scheduleRetryIfWarranted()
        }
    }

    /// Re-asks after a short delay when the last reading said it might improve
    /// — the XTVERSION race — spending one unit of the bounded retry budget.
    /// The delayed re-ask goes through the coalescer like any other request, so
    /// it folds into a probe a real event started in the meantime.
    private func scheduleRetryIfWarranted() {
        guard retriesRemaining > 0 else { return }
        let delay = retryDelaysNanos[retryDelaysNanos.count - retriesRemaining]
        retriesRemaining -= 1
        sleepingRetries += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self else { return }
            self.sleepingRetries -= 1
            guard self.coalescer.requestProbe() else { return }
            self.startProbe()
        }
    }
}

/// The at-most-one-in-flight, re-run-once-if-asked-again rule, as a pure state
/// machine so it is testable without tasks or forks.
internal struct ProbeCoalescer {
    private var inFlight = false
    private var again = false

    /// Whether nothing is running or queued.
    var isIdle: Bool { !inFlight && !again }

    /// A refresh was requested. Returns whether the caller should start a
    /// probe now; if one is already running, the request is remembered instead
    /// (the running probe may have sampled the world before this request's
    /// cause happened, so it cannot satisfy it).
    mutating func requestProbe() -> Bool {
        if inFlight {
            again = true
            return false
        }
        inFlight = true
        return true
    }

    /// The in-flight probe finished. Returns whether the caller should start
    /// another (a request arrived mid-probe). When it does, the new probe is
    /// already accounted in-flight — no `requestProbe()` call needed.
    mutating func probeCompleted() -> Bool {
        if again {
            again = false
            return true  // inFlight stays true for the follow-up probe
        }
        inFlight = false
        return false
    }
}
