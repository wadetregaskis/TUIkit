//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OffScreenAnimationDemandTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A view that builds its appearance from the pulse phase WHILE rendering, so
/// nothing can replay it and it must ask for a render every tick.
///
/// The shape a multi-row `Button`'s caps already take (`ButtonStyle.swift`,
/// `recordVolatileRead`), reduced to the one line that matters.
private struct TickHungryProbe: View, Renderable {
    var body: Never { fatalError("TickHungryProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.environment.volatileReadTracker?.recordVolatileRead()
        return FrameBuffer(text: "tick")
    }
}

/// A view whose animation is driven by the scheduler alone — no volatile read,
/// no ``AnimatedCellRun``. The `Spinner` fallback's shape, and the one the
/// indeterminate bar takes when its colours are translucent.
private struct SchedulerDrivenProbe: View, Renderable {
    var body: Never { fatalError("SchedulerDrivenProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.requestAnimation(token: "probe", frameTicks: 3)
        return FrameBuffer(text: "spin")
    }
}

private struct VisibleProbeApp: App {
    init() {}
    var body: some Scene { WindowGroup { TickHungryProbe() } }
}

private struct HiddenProbeApp: App {
    init() {}
    var body: some Scene { WindowGroup { TickHungryProbe().hidden() } }
}

/// The probe is the stack's ROOT, and a screen is pushed over it. The root
/// still renders — that is how its `@State` survives being covered — and its
/// buffer is thrown away.
private struct CoveredRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: .constant([1])) {
                TickHungryProbe()
                    .navigationDestination(for: Int.self) { _ in Text("detail") }
            }
        }
    }
}

/// The control for the one above: the same stack, with a root that wants
/// nothing. Without it, `usesPulse` being set would not be evidence about the
/// ROOT — a navigation bar or a focused control on the pushed screen would do
/// just as well.
private struct CoveredPlainRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: .constant([1])) {
                Text("root")
                    .navigationDestination(for: Int.self) { _ in Text("detail") }
            }
        }
    }
}

private struct SchedulerDrivenApp: App {
    init() {}
    var body: some Scene { WindowGroup { SchedulerDrivenProbe() } }
}

/// Every way a view has of saying "render me again" is PASS-wide, and a pass
/// does not know which of its renders reached the screen. An animation that is
/// hidden or covered therefore goes on costing a full render twenty times a
/// second while showing nobody anything.
///
/// Pinned as known issues rather than asserted as they are: the fix is a
/// request that rides on the `FrameBuffer` the way an ``AnimatedCellRun``
/// does, which reaches every site that builds one, and that is the owner's
/// call. What these tests do is make the day it lands the day they start
/// passing.
///
/// The last test is the standing condition rather than a defect, and is here
/// because it is the same fact seen from the other side.
@MainActor
@Suite("An animation nobody can see still asks for frames", .serialized)
struct OffScreenAnimationDemandTests {

    /// The control, and the reason the two below are about visibility rather
    /// than about the probe: on screen it asks for every tick, which is right.
    @Test("A visible tick-hungry view keeps the clock live")
    func visibleKeepsTheClockLive() {
        let harness = RenderLoopHarness()
        let activity = harness.loop(VisibleProbeApp()).render()

        #expect(harness.terminal.allOutput.contains("tick"))
        #expect(activity.usesPulse)
    }

    /// `.hidden()` renders its content and returns an empty buffer, so the read
    /// is made and counted against a frame that shows none of it.
    @Test("A hidden one draws nothing and asks for frames anyway")
    func hiddenLeaksTheDemand() {
        let harness = RenderLoopHarness()
        let activity = harness.loop(HiddenProbeApp()).render()

        #expect(!harness.terminal.allOutput.contains("tick"), "nothing is on screen")
        withKnownIssue("the demand outlives the buffer it was made in") {
            #expect(!activity.usesPulse)
        }
    }

    /// `NavigationStack` renders a covered root to keep its `@State` alive and
    /// drops the buffer (`NavigationStack.swift`, `isolatedForBackground`).
    /// That isolation covers the focus ring, the key channels and the status
    /// bar — every channel by which the invisible root could reach the user —
    /// and not the volatile-read tracker, which is the channel by which it
    /// reaches the CLOCK.
    @Test("A covered NavigationStack root asks for frames from behind a screen")
    func coveredRootLeaksTheDemand() {
        let harness = RenderLoopHarness()
        let activity = harness.loop(CoveredRootApp()).render()

        #expect(harness.terminal.allOutput.contains("detail"), "the pushed screen is showing")
        #expect(!harness.terminal.allOutput.contains("tick"), "and the root is not")
        withKnownIssue("a covered root drives the loop at 20 Hz") {
            #expect(!activity.usesPulse)
        }
    }

    /// The control: the same stack with an ordinary root reads no phase, so
    /// the flag above is the covered root's and nothing else's.
    @Test("A covered ordinary root asks for nothing")
    func coveredPlainRootIsQuiet() {
        let harness = RenderLoopHarness()
        #expect(!harness.loop(CoveredPlainRootApp()).render().usesPulse)
    }

    /// The other half of the same fact, and NOT a defect: `requestAnimation`
    /// records a render SIDE EFFECT, a different counter from a volatile READ,
    /// deliberately — folding the two would spin the pulse clock whenever any
    /// scheduler-driven animation was on screen. So a page whose only
    /// animation is scheduler-driven leaves all three inputs to
    /// `App.renderFrame`'s `clockLive` clear, and the loop stops the cursor
    /// timer, zeroing it.
    ///
    /// That froze the translucent indeterminate bar and the mixed-width
    /// `Spinner` until §66 of `Opacity as composition.md` moved a declined
    /// run's frame onto `frameNowNanos`; `DeclinedRunClockTests` pins the
    /// four frames that now differ. What is pinned HERE is the standing
    /// condition that made it possible, so that the next animation to ask the
    /// scheduler for its frames meets the rule before it meets the symptom:
    /// asking the scheduler does not keep a clock running, so nothing that
    /// asks may read one.
    @Test("A scheduler-driven animation keeps no clock running")
    func schedulerDrivenKeepsNoClock() {
        let harness = RenderLoopHarness()
        let scheduler = AnimationScheduler()
        let activity = harness.loop(SchedulerDrivenApp())
            .render(animationScheduler: scheduler)

        #expect(harness.terminal.allOutput.contains("spin"), "it is on screen")
        #expect(!activity.usesPulse)
        #expect(!activity.usesCursor)
        #expect(activity.animatedClocks.isEmpty)
    }
}
