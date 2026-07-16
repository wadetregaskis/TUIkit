//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EmojiChromeCachePolicyTests.swift
//
//  The rule that decides when RenderLoop's cached emoji-chrome answer must be
//  re-probed. Off tmux the answer is a process-lifetime constant; under tmux it
//  can change on a client re-attach that need not resize the terminal, so it
//  expires on a TTL. Resize-only invalidation (the old behaviour) left a
//  same-size re-attach — `tmux new-session -d app; tmux attach` — showing the
//  previous client's glyphs forever.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@Suite("emoji-chrome cache freshness")
struct EmojiChromeCachePolicyTests {
    private let ttl = EmojiChromeCachePolicy.ttlNanos

    @Test("Off tmux the answer never expires — the host can't change mid-process")
    func offTmuxNeverExpires() {
        // Even an absurd elapsed time keeps the cache: there is no client to swap.
        #expect(
            EmojiChromeCachePolicy.isFresh(underTmux: false, cachedAtNanos: 0, nowNanos: ttl * 1000))
        #expect(
            EmojiChromeCachePolicy.isFresh(
                underTmux: false, cachedAtNanos: 5, nowNanos: 5))
    }

    @Test("Under tmux the answer is fresh only within the TTL")
    func underTmuxExpiresOnTTL() {
        let base: Int64 = 1_000_000_000
        // Just-taken, and anywhere inside the window: fresh.
        #expect(EmojiChromeCachePolicy.isFresh(underTmux: true, cachedAtNanos: base, nowNanos: base))
        #expect(
            EmojiChromeCachePolicy.isFresh(
                underTmux: true, cachedAtNanos: base, nowNanos: base + ttl - 1))
        // At and beyond the TTL: stale — re-probe. This is the case a resize-only
        // cache never reached, so an Apple Terminal that attached at the same
        // size stayed on the safe glyphs indefinitely.
        #expect(
            !EmojiChromeCachePolicy.isFresh(
                underTmux: true, cachedAtNanos: base, nowNanos: base + ttl))
        #expect(
            !EmojiChromeCachePolicy.isFresh(
                underTmux: true, cachedAtNanos: base, nowNanos: base + ttl * 2))
    }

    @Test("The TTL is short enough to feel immediate, long enough to not thrash")
    func ttlIsAboutTwoSeconds() {
        // A couple of seconds: a client swap self-heals almost at once, yet a
        // rendering app probes at most once per window (nothing while idle).
        #expect(ttl == 2_000_000_000)
    }
}
