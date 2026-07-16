//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EmojiChromeRefresherTests.swift
//
//  The async, coalesced re-probe that keeps the emoji-chrome answer current
//  without ever blocking the render path — the receiving end of the tmux
//  client-change hooks (see TmuxClientChangeHookTests).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@Suite("probe coalescer")
struct ProbeCoalescerTests {
    @Test("Idle → request starts a probe; further requests fold into one re-run")
    func coalescesBursts() {
        var coalescer = ProbeCoalescer()
        // First request starts.
        #expect(coalescer.requestProbe() == true)
        // A burst while in flight starts nothing…
        let burst = [coalescer.requestProbe(), coalescer.requestProbe(), coalescer.requestProbe()]
        #expect(burst == [false, false, false])
        // …but completion re-runs exactly once (the running probe may have
        // sampled the world before the burst's cause happened).
        #expect(coalescer.probeCompleted() == true)
        // The re-run's completion, with no further requests, stops.
        #expect(coalescer.probeCompleted() == false)
        // And the coalescer is idle again: a new request starts a new probe.
        #expect(coalescer.isIdle)
        #expect(coalescer.requestProbe() == true)
    }

    @Test("A quiet probe completes without a re-run")
    func quietProbe() {
        var coalescer = ProbeCoalescer()
        #expect(coalescer.requestProbe() == true)
        #expect(coalescer.probeCompleted() == false)
        #expect(coalescer.requestProbe() == true)
    }
}

@Suite("emoji-chrome refresher")
@MainActor
struct EmojiChromeRefresherTests {
    /// A settled reading: no retry implied.
    nonisolated private static func settled(_ supported: Bool) -> EmojiChromeReading {
        EmojiChromeReading(supported: supported, mayImproveShortly: false)
    }

    @Test("resolve() seeds once and is a pure cache read after")
    func resolveSeedsOnce() {
        nonisolated(unsafe) var probes = 0
        let refresher = EmojiChromeRefresher(
            isRefreshable: false,
            probe: {
                probes += 1
                return Self.settled(true)
            },
            onChange: {})
        #expect(refresher.resolve())
        #expect(refresher.resolve())
        #expect(refresher.resolve())
        #expect(probes == 1, "only the first resolve may probe")
    }

    @Test("refresh() is a no-op when the answer cannot change (off tmux)")
    func refreshInertWhenNotRefreshable() async {
        nonisolated(unsafe) var probes = 0
        let refresher = EmojiChromeRefresher(
            isRefreshable: false,
            probe: {
                probes += 1
                return Self.settled(true)
            },
            onChange: {})
        _ = refresher.resolve()
        refresher.refresh()
        refresher.refresh()
        // Give any (wrongly) spawned task a chance to run before asserting.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(probes == 1, "off tmux, refresh must never probe")
    }

    @Test("A landed refresh that changes the answer fires onChange; a same answer doesn't")
    func onChangeFiresOnlyOnChange() async throws {
        nonisolated(unsafe) var answer = false
        nonisolated(unsafe) var changes = 0
        let refresher = EmojiChromeRefresher(
            isRefreshable: true,
            probe: { Self.settled(answer) },
            onChange: { changes += 1 })
        #expect(refresher.resolve() == false)  // seeded with false

        // Same answer: no onChange.
        refresher.refresh()
        try await waitUntilSettled(refresher)
        #expect(changes == 0, "an unchanged answer must not invalidate the screen")
        #expect(refresher.resolve() == false)

        // Changed answer: exactly one onChange, and resolve() serves the new value.
        answer = true
        refresher.refresh()
        try await waitUntilSettled(refresher)
        #expect(changes == 1, "a changed answer must invalidate exactly once")
        #expect(refresher.resolve() == true, "frames after the change draw the new answer")
    }

    @Test("A FAILED refresh probe keeps the previous answer — no flip, no onChange")
    func failedProbeKeepsLastAnswer() async throws {
        // The failure this guards: a transient probe failure (a slow tmux under
        // load hitting the deadline) used to read as "no clients" and flip the
        // chrome off — restyling every glyph on screen — then flip it back when
        // the next probe succeeded. nil means "could not ask", and the previous
        // answer stands.
        nonisolated(unsafe) var answer: Bool? = true
        nonisolated(unsafe) var changes = 0
        let refresher = EmojiChromeRefresher(
            isRefreshable: true,
            probe: { answer.map(Self.settled) },
            onChange: { changes += 1 })
        #expect(refresher.resolve() == true)

        answer = nil  // tmux went quiet
        refresher.refresh()
        try await waitUntilSettled(refresher)
        #expect(changes == 0, "a failed probe must not restyle the screen")
        #expect(refresher.resolve() == true, "the previous answer stands")

        answer = false  // a real answer again: now it may flip
        refresher.refresh()
        try await waitUntilSettled(refresher)
        #expect(changes == 1)
        #expect(refresher.resolve() == false)
    }

    @Test("A failed SEED probe falls to the safe glyphs")
    func failedSeedFailsClosed() {
        let refresher = EmojiChromeRefresher(
            isRefreshable: true, probe: { nil }, onChange: {})
        // At launch there is no previous answer to keep.
        #expect(refresher.resolve() == false)
    }

    @Test("An ambiguous reading retries and picks up the late XTVERSION reply")
    func ambiguousReadingRetries() async throws {
        // The measured race this covers: the client-attached hook fires before
        // the client's XTVERSION reply arrives, so the probe sees a silent,
        // unidentified client (supported: false, mayImproveShortly: true). A
        // moment later the reply lands; the bounded retry must pick it up with
        // NO further external event — there is none coming.
        nonisolated(unsafe) var reading = EmojiChromeReading(
            supported: false, mayImproveShortly: true)
        nonisolated(unsafe) var changes = 0
        let refresher = EmojiChromeRefresher(
            isRefreshable: true,
            probe: { reading },
            onChange: { changes += 1 },
            retryDelaysNanos: [5_000_000, 5_000_000, 5_000_000])
        #expect(refresher.resolve() == false)

        reading = Self.settled(true)  // the XTVERSION reply "arrives"
        try await waitUntilSettled(refresher)
        #expect(changes == 1, "the retry must land the improved answer unprompted")
        #expect(refresher.resolve() == true)
    }

    @Test("Retries are bounded: a genuinely unknown silent client stops probing")
    func retriesAreBounded() async throws {
        nonisolated(unsafe) var probes = 0
        let refresher = EmojiChromeRefresher(
            isRefreshable: true,
            probe: {
                probes += 1
                return EmojiChromeReading(supported: false, mayImproveShortly: true)
            },
            onChange: {},
            retryDelaysNanos: [5_000_000, 5_000_000, 5_000_000])
        _ = refresher.resolve()
        try await waitUntilSettled(refresher)
        // The seed plus at most the full retry budget — never a poll loop.
        #expect(probes <= 4, "retries must burn out, got \(probes) probes")
        let probesAfterSettling = probes
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(probes == probesAfterSettling, "no probes after the budget is spent")
    }

    @Test("A settled false does not retry")
    func settledFalseDoesNotRetry() async throws {
        // A detached session ([] clients) is a REAL false — no reply is coming,
        // so no retry is warranted.
        nonisolated(unsafe) var probes = 0
        let refresher = EmojiChromeRefresher(
            isRefreshable: true,
            probe: {
                probes += 1
                return Self.settled(false)
            },
            onChange: {},
            retryDelaysNanos: [5_000_000])
        _ = refresher.resolve()
        refresher.refresh()
        try await waitUntilSettled(refresher)
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(probes == 2, "seed + one refresh, no retries, got \(probes)")
    }

    /// Polls until the refresher's in-flight probe (and any coalesced re-run)
    /// has landed. The probe hops through a detached task, so tests must wait
    /// for the main-actor completion rather than assert immediately.
    private func waitUntilSettled(_ refresher: EmojiChromeRefresher) async throws {
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds: 5_000_000)
            if refresher.isIdleForTesting { return }
        }
        Issue.record("refresher never settled")
    }
}

@Suite("environment snapshot")
struct EnvironmentSnapshotTests {
    @Test("A resolved-chrome change invalidates the render cache (snapshot inequality)")
    func chromeChangeChangesSnapshot() {
        // The failure this guards, observed live: iTerm2 attached to a running
        // app, the emoji-chrome answer flipped, the full-screen repaint ran —
        // and the toggles still drew ■/□, because EquatableView/ForEach-memoized
        // subtrees served their cached buffers. RenderLoop clears that cache
        // when this snapshot differs between frames, so the resolved style MUST
        // participate: without it, rows the user touches re-render in the new
        // style while untouched rows keep the old one — a mixed-style screen.
        var environment = EnvironmentValues()
        environment.resolvedAutomaticToggleCharacterSet = .automatic(emojiChrome: false)
        let before = EnvironmentSnapshot(from: environment)
        environment.resolvedAutomaticToggleCharacterSet = .automatic(emojiChrome: true)
        let after = EnvironmentSnapshot(from: environment)
        #expect(before != after, "a chrome flip must clear the render cache")
    }

    @Test("An unchanged environment produces an equal snapshot (cache is kept)")
    func unchangedEnvironmentKeepsCache() {
        let first = EnvironmentSnapshot(from: EnvironmentValues())
        let second = EnvironmentSnapshot(from: EnvironmentValues())
        #expect(first == second)
    }
}
