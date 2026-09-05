//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AutoRepeatTimerTests.swift
//
//  The auto-repeat timer decides whether a press was a tap or a hold, and the
//  only evidence it has is that no release has been read yet. That evidence is
//  worthless while the main actor is busy, because the run loop reads stdin
//  between frames and a busy main actor is a loop that is not reading: a frame
//  slower than the initial delay turned one click on a Slider / Stepper arrow
//  into two steps. These tests wait by the wall on purpose — main-actor
//  starvation is the thing under test, and it cannot be faked with a clock —
//  so the cadences here are shrunk to tens of milliseconds.
//
//  Created by Wade Tregaskis
//  License: MIT

import Dispatch
import Testing

@testable import TUIkit

@MainActor
/// `.serialized` because the whole point of one of these is to occupy the
/// main actor: run in parallel, the blocking test starves its siblings'
/// timers and the hold below never gets to repeat.
@Suite("AutoRepeatTimer tap versus hold", .serialized)
struct AutoRepeatTimerTests {
    /// Shrunk cadence: the shipping 400 ms / 80 ms would make every case here
    /// a wall-clock second or more.
    private static let delayMs = 40
    private static let intervalMs = 10

    private static func timer() -> AutoRepeatTimer {
        AutoRepeatTimer(initialDelayMs: delayMs, repeatIntervalMs: intervalMs)
    }

    /// Yields long enough for the timer's task to reach its next suspension.
    private static func settle(ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    /// Occupies the main actor for `ms`, the way a long render does: no
    /// suspension point, so nothing else queued on it can run. A spin rather
    /// than a sleep because `Thread.sleep` is unavailable from an async
    /// context — and because a render burns the actor rather than parking it,
    /// which is exactly the state being reproduced.
    private static func blockMainActor(ms: Int) {
        let until = DispatchTime.now().uptimeNanoseconds + UInt64(ms) * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < until {
            // Spin.
        }
    }

    /// A scrollbar arrow and a slider arrow are the same gesture, and the two
    /// auto-repeats are separate implementations — the scrollbar's is driven
    /// from the render pass, this one from a task. They must still agree about
    /// where a click ends, or the same press means different things one control
    /// apart.
    @Test("The two auto-repeats agree on how long a click may be")
    func initialDelayMatchesTheScrollbar() {
        #expect(
            AutoRepeatTimer().initialDelayMs * 1_000_000
                == Int(ScrollbarRenderer.autoRepeatInitialDelayNanos))
    }

    @Test("A tap fires exactly once")
    func tapFiresOnce() async {
        var fires = 0
        let timer = Self.timer()
        timer.start { fires += 1 }
        // The press acts on the next main-actor turn and the release is read
        // on the one after — a yield, not a sleep, for the reason given in
        // `slowFrameDoesNotDoubleATap`: a timed wake can lose to the timer's.
        await Task.yield()
        timer.stop()
        await Self.settle(ms: Self.delayMs * 3)
        #expect(fires == 1, "the press acted, the release ended it before any repeat")
    }

    @Test("A hold still repeats")
    func holdRepeats() async {
        var fires = 0
        let timer = Self.timer()
        timer.start { fires += 1 }
        // Polled rather than waited out in one go: another main-actor test
        // running alongside this one can starve the timer through a window,
        // and the gate's whole job is then to wait for the next one. That
        // delays the first repeat; it does not prevent it.
        for _ in 0..<20 where fires <= 1 {
            await Self.settle(ms: Self.delayMs)
        }
        timer.stop()
        #expect(fires > 1, "past the initial delay the repeat loop runs (\(fires) fires)")
    }

    /// The regression. The main actor is blocked right through the initial
    /// delay — the app rendering a frame that outlasts it — and only then does
    /// the loop get to read the release. Without the awake-time gate the timer
    /// wakes first and fires a repeat that the user never asked for.
    @Test("A frame longer than the initial delay does not turn a tap into two")
    func slowFrameDoesNotDoubleATap() async {
        var fires = 0
        let timer = Self.timer()
        timer.start { fires += 1 }
        await Self.settle(ms: 5)
        #expect(fires == 1, "the press acted")

        // Block the main actor the way a long render does: synchronously, with
        // no suspension point for the timer's task to be resumed at.
        Self.blockMainActor(ms: Self.delayMs * 3)

        // The first await after the frame — the run loop's own, where it waits
        // for stdin. Queued main-actor work runs here, the timer's included.
        //
        // A yield, not a sleep. The timer's wake has been queued on the main
        // actor since the delay elapsed, so a yield re-queues this test BEHIND
        // it and the actor runs the two in that order: the timer re-arms, then
        // the test reads the release below. Whichever order they run in, the
        // outcome is one fire — the timer either waits again or is cancelled
        // mid-sleep — so nothing here depends on timing any more.
        //
        // It did. A `settle(intervalMs)` here read the release 10 ms into the
        // timer's 40 ms re-arm, and that 30 ms was a race: a sleep's wake
        // crosses the global pool before it reaches the main actor, so two
        // wakes 30 ms apart can arrive in either order once the process is
        // oversubscribed. The only way to a second fire is the timer's wake
        // arriving first — its sleep then returns on time, passes the gate, and
        // fires before the release is read — and on a CI runner saturated by
        // the rest of the suite that is what one run in eight showed:
        // `(fires → 2) == 1`. The gate was right; the test had entered a race
        // it had no reason to enter.
        await Task.yield()
        #expect(fires == 1, "the timer woke late and waited again, rather than firing (\(fires) fires)")

        // Only NOW does the loop reach the release that has been sitting in the
        // input buffer since the click.
        timer.stop()
        await Self.settle(ms: Self.delayMs * 2)
        #expect(fires == 1, "still one step, not two (\(fires) fires)")
    }
}
