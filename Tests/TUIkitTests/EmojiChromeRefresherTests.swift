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
    @Test("resolve() seeds once and is a pure cache read after")
    func resolveSeedsOnce() {
        nonisolated(unsafe) var probes = 0
        let refresher = EmojiChromeRefresher(
            isRefreshable: false,
            probe: {
                probes += 1
                return true
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
                return true
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
            probe: { answer },
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
