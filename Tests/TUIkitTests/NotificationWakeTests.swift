//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NotificationWakeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@Suite("Notification wake scheduling")
struct NotificationWakeTests {

    private let visible: Double = 3.0

    /// The task's wakes over one toast posted at `posted`, each taken exactly when it
    /// was planned, until the toast has faded out.
    private func wakes(postedAt posted: Int64) -> [Int64] {
        let life = NotificationTiming.fadeInDuration + visible + NotificationTiming.fadeOutDuration
        let expiry = posted + AnimationClock.nanoseconds(life)
        var now = posted
        var wakes: [Int64] = []
        while now <= expiry, wakes.count < 1000 {
            let due = NotificationTiming.timeUntilOpacityChanges(
                elapsed: Double(now - posted) / 1_000_000_000, visibleDuration: visible)
            now = NotificationTiming.nextWakeNanos(after: now, due: due)
            wakes.append(now)
        }
        return wakes
    }

    @Test("Mid-fade the value moves, so it changes now")
    func fadesChangeNow() {
        for elapsed in [0.0, 0.05, 0.19] {
            #expect(
                NotificationTiming.timeUntilOpacityChanges(elapsed: elapsed, visibleDuration: visible) == 0,
                "fade-in at \(elapsed)")
        }
        let intoFadeOut = NotificationTiming.fadeInDuration + visible + 0.1
        #expect(NotificationTiming.timeUntilOpacityChanges(elapsed: intoFadeOut, visibleDuration: visible) == 0)
    }

    /// A change due now is drawn at the next instant a 2-tick frame begins, the
    /// instants a bar or a view animation on the same screen changes at: strictly
    /// after now, so a wake on one of those instants asks for the next.
    @Test("Mid-fade the next wake is the next 2-tick instant")
    func midFadeWakesAtTheNextFrame() {
        #expect(NotificationTiming.nextWakeNanos(after: 1_037_000_000, due: 0) == AnimationClock.nanoseconds(atTick: 64))
        let onFrame = AnimationClock.nanoseconds(atTick: 64)
        #expect(NotificationTiming.nextWakeNanos(after: onFrame, due: 0) == AnimationClock.nanoseconds(atTick: 66))
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
    /// flat stretch of the one before it. The wake is the first 2-tick instant at or
    /// after the cap: 250 ms from tick 600 is tick 615, and the frame is tick 616.
    @Test("No sleep is longer than the cap and the frame it ends in, however flat the stretch")
    func theCapBoundsTheWorstCase() {
        #expect(NotificationTiming.longestSleep < 0.5)
        let due = NotificationTiming.timeUntilOpacityChanges(
            elapsed: NotificationTiming.fadeInDuration + 0.001, visibleDuration: 30)
        let now = AnimationClock.nanoseconds(atTick: 600)
        #expect(NotificationTiming.nextWakeNanos(after: now, due: due) == AnimationClock.nanoseconds(atTick: 616))
        #expect(NotificationTiming.nextWakeNanos(after: now + 1, due: due) == AnimationClock.nanoseconds(atTick: 616))
    }

    /// A toast is posted part way through a tick, as a real post is, and every wake
    /// its task plans from there is an instant a 2-tick frame begins; while a fade is
    /// drawing, the wakes are one such frame apart. They used to be 23.8 ms after
    /// wherever the last sleep ended, off every lattice another animation steps on.
    @Test("Every wake over a toast is the instant a 2-tick frame begins, and a fade's are 2 ticks apart")
    func wakesLandOnTheTwoTickLattice() {
        let posted: Int64 = 1_037_000_000
        let wakes = wakes(postedAt: posted)
        let offLattice = wakes.filter { wake in
            let tick = AnimationClock.tick(atNanoseconds: wake)
            return AnimationClock.nanoseconds(atTick: tick) != wake || !tick.isMultiple(of: 2)
        }
        #expect(offLattice.isEmpty, "wakes off the 2-tick lattice: \(offLattice.prefix(5))")
        // Each gap from a wake taken mid-fade, in ticks.
        let fadeGaps = zip(wakes, wakes.dropFirst()).compactMap { from, to -> Int64? in
            let elapsed = Double(from - posted) / 1_000_000_000
            guard NotificationTiming.timeUntilOpacityChanges(elapsed: elapsed, visibleDuration: visible) == 0
            else { return nil }
            return AnimationClock.tick(atNanoseconds: to) - AnimationClock.tick(atNanoseconds: from)
        }
        #expect(fadeGaps.count >= 10, "only \(fadeGaps.count) wakes were taken mid-fade")
        #expect(fadeGaps.allSatisfy { $0 == 2 }, "mid-fade gaps in ticks: \(fadeGaps)")
    }

    /// What this is worth, stated as a count so a regression is legible: a render for
    /// every 2-tick frame of the toast's life would be 105.
    @Test("A three-and-a-half-second toast wakes under a third as often as its frames")
    func theWakeCountCollapses() {
        let life =
            NotificationTiming.fadeInDuration + visible + NotificationTiming.fadeOutDuration
        let everyFrame = Int(life * Double(AnimationClock.ticksPerSecond) / 2)
        let wakes = wakes(postedAt: 1_037_000_000)
        #expect(everyFrame == 105)
        #expect(wakes.count < everyFrame / 3, "\(wakes.count) wakes against \(everyFrame)")
    }
}
