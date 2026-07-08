//  🖥️ TUIKit — Terminal UI Kit for Swift
//  VolatileReadTrackerTests.swift
//
//  Pins the tracker's two-counter design: `reads` drives the run loop's
//  pulse-timer demand (`usesPulse: reads > 0`), while `animationRequests`
//  only feeds `cacheUnsafeCount` for the value memos. Folding animation
//  requests into `reads` would spin the pulse clock whenever any
//  scheduler-driven animation (a Spinner, say) is on screen — the reason
//  `requestAnimation` records on a separate counter.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("VolatileReadTracker counters")
struct VolatileReadTrackerTests {
    @Test("requestAnimation marks the subtree cache-unsafe without demanding the pulse clock")
    func animationRequestDoesNotDemandPulse() {
        let tracker = VolatileReadTracker()
        var environment = EnvironmentValues()
        environment.volatileReadTracker = tracker
        environment.animationScheduler = AnimationScheduler()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: TUIContext())

        context.requestAnimation(token: "test", frequency: 10)

        #expect(tracker.reads == 0, "no pulse demand: the pulse timer keys off `reads` alone")
        #expect(tracker.animationRequests == 1)
        #expect(tracker.cacheUnsafeCount == 1, "the memos see the request")
    }

    @Test("The request records even with no scheduler wired in")
    func recordsWithoutScheduler() {
        // A one-off render (ViewRenderer snapshot) has no scheduler; the
        // subtree is still time-varying and must classify consistently.
        let tracker = VolatileReadTracker()
        var environment = EnvironmentValues()
        environment.volatileReadTracker = tracker
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: TUIContext())

        context.requestAnimation(token: "test", frequency: 10)

        #expect(tracker.animationRequests == 1)
    }

    @Test("No side effects during a measure pass")
    func measurePassIsSideEffectFree() {
        let tracker = VolatileReadTracker()
        var environment = EnvironmentValues()
        environment.volatileReadTracker = tracker
        environment.animationScheduler = AnimationScheduler()
        var context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: TUIContext())
        context.isMeasuring = true

        context.requestAnimation(token: "test", frequency: 10)

        #expect(tracker.cacheUnsafeCount == 0)
    }

    @Test("Volatile reads and animation requests tally independently")
    func countersAreIndependent() {
        let tracker = VolatileReadTracker()
        tracker.recordVolatileRead()
        tracker.recordVolatileRead()
        tracker.recordAnimationRequest()

        #expect(tracker.reads == 2)
        #expect(tracker.animationRequests == 1)
        #expect(tracker.cacheUnsafeCount == 3)
    }
}
