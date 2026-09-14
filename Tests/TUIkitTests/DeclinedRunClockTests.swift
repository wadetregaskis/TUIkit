//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DeclinedRunClockTests.swift
//
//  A view that declines its run — a translucent indeterminate bar, a spinner
//  whose frames differ in width — is re-rendered by the scheduler, and must draw
//  a new frame each time. It took its frame from the cursor timer, which the run
//  loop stopped, and then zeroed, on a page that leaves no runs and reads nothing:
//  so alone on a page it drew frame zero forever (§66). Driven through `RenderLoop`
//  itself, with the timer as the loop leaves it there. And the run path and the
//  declined path must agree on the step at any one frame (§74).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A spinner whose two frames are one cell and two wide, so no run can hold it.
private struct MixedWidthSpinnerApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Spinner(style: .custom("-你"))
        }
    }
}

/// An indeterminate bar under a faded tint, which no run can carry (§36.7).
private struct TranslucentBarApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ProgressView().tint(Color.red.opacity(0.5))
        }
    }
}

@MainActor
@Suite("A declined run keeps moving")
struct DeclinedRunClockTests {

    /// Four frames of `app` at frame times `step` seconds apart. The cursor timer is
    /// never started, which is where the loop leaves it on a page like these — so
    /// alongside the pictures, whether every frame left nothing to keep the timer
    /// alive, and whether the scheduler would still come back after each.
    private func frames<A: App>(
        of app: A, step: Double
    ) -> (pictures: [[String]], idleTimer: Bool, scheduled: Bool) {
        let harness = RenderLoopHarness()
        let loop = harness.loop(app)
        let timer = CursorTimer(renderNotifier: harness.appState)
        let scheduler = AnimationScheduler()
        var pictures: [[String]] = []
        var idleTimer = true
        var scheduled = true
        for frame in 0..<4 {
            let now = Int64(1_000_000_000) + Int64((Double(frame) * step * 1e9).rounded())
            scheduler.beginFrame()
            let activity = loop.render(cursorTimer: timer, animationScheduler: scheduler, frameNowNanos: now)
            scheduler.endFrame()
            idleTimer = idleTimer && activity.animatedClocks.isEmpty && !activity.usesPulse && !activity.usesCursor
            scheduled = scheduled && scheduler.nextFiring(after: now) != nil
            pictures.append(loop.replayable?.contentLines ?? [])
        }
        return (pictures, idleTimer, scheduled)
    }

    @Test("A mixed-width spinner alone on a page moves from frame to frame")
    func mixedWidthSpinnerMoves() {
        let run = frames(of: MixedWidthSpinnerApp(), step: 0.120)
        #expect(run.idleTimer, "something else kept the timer alive, so this is not the case under test")
        #expect(run.scheduled, "nothing asked the loop to come back")
        #expect(Set(run.pictures).count > 1, "every frame drew the same picture: \(run.pictures)")
    }

    /// A same-width spinner, which leaves a run, beside a mixed-width one, which
    /// declines it: two `.custom` sequences of two frames at the one interval every
    /// `.custom` runs at, so at any instant both are due the same frame index.
    private struct RunBesideDeclinedApp: App {
        init() {}

        var body: some Scene {
            WindowGroup {
                HStack(spacing: 1) {
                    Spinner(style: .custom("ab"))
                    Spinner(style: .custom("-你"))
                }
            }
        }
    }

    /// The run path reads the cursor timer and the declined path the frame clock, and
    /// they have to be one instant: a render shows the timer its frame time first.
    ///
    /// Before, the timer counted its own wakes from wherever it had last been zeroed —
    /// here, never started, it stood at zero — so the run-backed spinner drew frame 0 at
    /// every frame while the declined one, beside it, stepped.
    @Test("A spinner that leaves a run and one that declines it draw the same step in one frame")
    func runAndDeclinedRunReadOneInstant() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(RunBesideDeclinedApp())
        let timer = CursorTimer(renderNotifier: harness.appState)
        let scheduler = AnimationScheduler()
        // 90,090 s, a whole number of 120 ms steps, and past any real clock reading.
        let base: Int64 = 90_090 * 1_000_000_000
        var mismatches: [(frame: Int, picture: String)] = []
        for frame in 0..<6 {
            // 1 ms into each step, so both spinners are due frame index `frame % 2`.
            let now = base + Int64(frame) * 120_000_000 + 1_000_000
            scheduler.beginFrame()
            loop.render(cursorTimer: timer, animationScheduler: scheduler, frameNowNanos: now)
            scheduler.endFrame()
            #expect(timer.elapsed(for: .content) == Double(now) / 1_000_000_000)
            let picture = (loop.replayable?.contentLines ?? []).map(\.stripped).joined()
            let runIndex = picture.contains("b") ? 1 : 0
            let declinedIndex = picture.contains("你") ? 1 : 0
            if runIndex != frame % 2 || declinedIndex != frame % 2 {
                mismatches.append((frame, picture))
            }
        }
        #expect(mismatches.isEmpty, "frames where the two spinners disagreed: \(mismatches)")
    }

    @Test("A translucent indeterminate bar alone on a page moves from frame to frame")
    func translucentBarMoves() {
        let run = frames(of: TranslucentBarApp(), step: 0.1)
        #expect(run.idleTimer, "something else kept the timer alive, so this is not the case under test")
        #expect(run.scheduled, "nothing asked the loop to come back")
        #expect(Set(run.pictures).count > 1, "every frame drew the same picture: \(run.pictures)")
    }
}
