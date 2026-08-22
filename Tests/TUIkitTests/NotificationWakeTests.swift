//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NotificationWakeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@Suite("Notification wake scheduling")
struct NotificationWakeTests {

    private let visible: Double = 3.0

    @Test("Mid-fade the value moves, so it is drawn every frame")
    func fadesAreDrawnEveryFrame() {
        for elapsed in [0.0, 0.05, 0.19] {
            #expect(
                NotificationTiming.timeUntilOpacityChanges(
                    elapsed: elapsed, visibleDuration: visible)
                    == NotificationTiming.frameInterval,
                "fade-in at \(elapsed)")
        }
        let intoFadeOut = NotificationTiming.fadeInDuration + visible + 0.1
        #expect(
            NotificationTiming.timeUntilOpacityChanges(
                elapsed: intoFadeOut, visibleDuration: visible)
                == NotificationTiming.frameInterval)
    }

    @Test("The flat stretch is one sleep, not a hundred and twenty-six wakes")
    func theFlatStretchIsOneSleep() {
        // The whole point. A notification is at a flat 1.0 for its visible
        // duration, and every wake in there re-renders the screen to draw what
        // is already on it.
        let justAfterFadeIn = NotificationTiming.fadeInDuration + 0.001
        let due = NotificationTiming.timeUntilOpacityChanges(
            elapsed: justAfterFadeIn, visibleDuration: visible)
        #expect(due > visible - 0.01, "asked to wake after \(due)s of a \(visible)s flat stretch")
        // Half way through, the remainder — never less than what is left.
        let halfway = NotificationTiming.fadeInDuration + visible / 2
        let rest = NotificationTiming.timeUntilOpacityChanges(
            elapsed: halfway, visibleDuration: visible)
        #expect(abs(rest - visible / 2) < 0.01)
    }

    @Test("Past the end it asks for nothing more")
    func expiredAsksForNothing() {
        let gone =
            NotificationTiming.fadeInDuration + visible + NotificationTiming.fadeOutDuration + 0.1
        #expect(
            NotificationTiming.timeUntilOpacityChanges(elapsed: gone, visibleDuration: visible)
                == .infinity)
    }

    /// The cap exists because a notification posted mid-life does not restart
    /// the animation task — the sleep already in progress decides when the new
    /// one first draws. Without it a toast could sit invisible for the whole
    /// flat stretch of the one before it.
    @Test("No sleep is longer than the cap, however flat the stretch")
    func theCapBoundsTheWorstCase() {
        #expect(NotificationTiming.longestSleep < 0.5)
        #expect(NotificationTiming.longestSleep > NotificationTiming.frameInterval)
        let due = NotificationTiming.timeUntilOpacityChanges(
            elapsed: NotificationTiming.fadeInDuration + 0.001, visibleDuration: 30)
        let slept = min(NotificationTiming.longestSleep, max(NotificationTiming.frameInterval, due))
        #expect(slept == NotificationTiming.longestSleep)
    }

    /// What this is worth, stated as a count so a regression is legible.
    @Test("A three-and-a-half-second toast wakes about a tenth as often")
    func thewakeCountCollapses() {
        var now = 0.0
        var wakes = 0
        let life =
            NotificationTiming.fadeInDuration + visible + NotificationTiming.fadeOutDuration
        while now < life, wakes < 1000 {
            let due = NotificationTiming.timeUntilOpacityChanges(
                elapsed: now, visibleDuration: visible)
            now += min(NotificationTiming.longestSleep, max(NotificationTiming.frameInterval, due))
            wakes += 1
        }
        let before = Int(life / NotificationTiming.frameInterval)
        #expect(before > 140, "the old loop woke \(before) times")
        #expect(wakes < before / 3, "\(wakes) wakes against \(before)")
    }
}
