//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DeclinedRunClockTests.swift
//
//  A view that declines its run — a translucent indeterminate bar, a spinner
//  whose frames differ in width — is re-rendered by the scheduler, and must draw
//  a new frame each time. It took its frame from the cursor timer, which the run
//  loop stops, and zeroes, on a page that leaves no runs and reads nothing: so
//  alone on a page it drew frame zero forever (§66). Driven through `RenderLoop`
//  itself, with the timer as the loop leaves it there.
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

    @Test("A translucent indeterminate bar alone on a page moves from frame to frame")
    func translucentBarMoves() {
        let run = frames(of: TranslucentBarApp(), step: 0.1)
        #expect(run.idleTimer, "something else kept the timer alive, so this is not the case under test")
        #expect(run.scheduled, "nothing asked the loop to come back")
        #expect(Set(run.pictures).count > 1, "every frame drew the same picture: \(run.pictures)")
    }
}
