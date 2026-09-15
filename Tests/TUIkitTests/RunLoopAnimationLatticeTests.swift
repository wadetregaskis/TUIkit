//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RunLoopAnimationLatticeTests.swift
//
//  The renders the run loop asks for on its own behalf — a view animation in
//  flight, a drag's lift, a cancelled drag's walk home — land on the instants a
//  2-tick frame of 1/60 s begins, counted from tick zero of the frame clock:
//  where an indeterminate bar steps and a toast's fade is drawn, not on a grid
//  anchored at whichever frame first asked. Driven through `RenderLoop` itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A line of text whose opacity animates over a second when `faded` changes.
private struct FadingApp: App {
    var faded = false

    init() {}

    init(faded: Bool) {
        self.faded = faded
    }

    var body: some Scene {
        WindowGroup {
            Text("ABC").opacity(faded ? 0.2 : 1).animation(.linear(duration: 1), value: faded)
        }
    }
}

/// A still page, for the drag flights to fly over.
private struct StillApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("still")
        }
    }
}

@MainActor
@Suite("The run loop's own renders land on the 1/60 s lattice")
struct RunLoopAnimationLatticeTests {
    /// 1.037 s: 2 ms into tick 62, which is even, so the next 2-tick frame begins at tick 64.
    private static let now: Int64 = 1_037_000_000

    private func render<A: App>(_ loop: RenderLoop<A>, _ scheduler: AnimationScheduler, at nowNanos: Int64) {
        scheduler.beginFrame()
        loop.render(animationScheduler: scheduler, frameNowNanos: nowNanos)
        scheduler.endFrame()
    }

    /// Whether `instant` is exactly the instant a tick with an even index begins.
    private func beginsATwoTickFrame(_ instant: Int64) -> Bool {
        let tick = AnimationClock.tick(atNanoseconds: instant)
        return tick.isMultiple(of: 2) && AnimationClock.nanoseconds(atTick: tick) == instant
    }

    @Test("A view animation asks for its next render where a 2-tick frame begins, and every one after")
    func viewAnimationRendersOnTheLattice() throws {
        let harness = RenderLoopHarness()
        let scheduler = AnimationScheduler()
        render(harness.loop(FadingApp(faded: false)), scheduler, at: 1_000_000_000)
        let loop = harness.loop(FadingApp(faded: true))
        render(loop, scheduler, at: Self.now)
        #expect(harness.tuiContext.stateStorage.animations.hasLiveAnimations(at: Self.now), "the fixture animates")

        let first = try #require(scheduler.nextFiring(after: Self.now))
        #expect(first == AnimationClock.nanoseconds(atTick: 64))
        // The instant a 2-tick run's step ends, so one wake serves both.
        #expect(first == AnimationClock.stepEndNanos(atElapsed: 1.037, frameTicks: 2))

        // Rendered exactly when asked, until the second-long fade has finished.
        var firings: [Int64] = []
        var next: Int64? = first
        while let instant = next, firings.count < 100 {
            firings.append(instant)
            render(loop, scheduler, at: instant)
            next = scheduler.nextFiring(after: instant)
        }
        #expect(next == nil, "the loop stops asking once the fade has arrived")
        #expect(firings.count >= 29, "about thirty renders a second: \(firings.count)")
        let offLattice = firings.filter { !beginsATwoTickFrame($0) }
        #expect(offLattice.isEmpty, "renders off the lattice: \(offLattice)")
    }

    @Test("A drag's lift asks for its next render where a 2-tick frame begins")
    func dragLiftRendersOnTheLattice() {
        let harness = RenderLoopHarness()
        let scheduler = AnimationScheduler()
        let session = harness.tuiContext.dragAndDropSession
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .pressed, x: 2, y: 3)
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 20, y: 9)
        session.begin(payload: "row", preview: FrameBuffer(lines: ["ROW"]), grabX: 0, grabY: 0)

        render(harness.loop(StillApp()), scheduler, at: Self.now)
        #expect(scheduler.nextFiring(after: Self.now) == AnimationClock.nanoseconds(atTick: 64))
    }

    @Test("A cancelled drag's walk home asks for its next render where a 2-tick frame begins")
    func dragReturnRendersOnTheLattice() {
        let harness = RenderLoopHarness()
        let scheduler = AnimationScheduler()
        let session = harness.tuiContext.dragAndDropSession
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .pressed, x: 4, y: 2)
        session.begin(payload: "row", preview: FrameBuffer(text: "ROW"))
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 20, y: 8)
        session.dragMoved()
        session.cancelReturningToOrigin()

        render(harness.loop(StillApp()), scheduler, at: Self.now)
        #expect(session.returnFlightFrame != nil, "the fixture is flying home")
        #expect(scheduler.nextFiring(after: Self.now) == AnimationClock.nanoseconds(atTick: 64))
    }
}
