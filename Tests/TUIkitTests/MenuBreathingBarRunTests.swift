//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuBreathingBarRunTests.swift
//
//  A menu row whose label animates on its own — a spinner beside "Busy" — under
//  the breathing bar the focused row draws. The bar leaves a run per line that
//  repaints the WHOLE row every tick, over the label as it was drawn, so a run the
//  label left on the same line is two animations claiming one cell, and the wider
//  one wins: the spinner held the glyph it was rendered with. A `List`'s breathing
//  cursor row has the same shape and answers it by dropping its row's runs and
//  asking the run loop for a render at their next step; the menu row asked for
//  nothing, so its spinner froze until something else caused a render.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// An inline menu whose first row — the one the focus lands on — has a spinner in
/// its label.
@MainActor
private func busyMenu() -> some View {
    Menu("Tasks") {
        Button(action: {}, label: { HStack(spacing: 0) { Text("Busy "); Spinner(style: .dots) } })
        Button("Idle") {}
    }
    .menuStyle(.inline)
}

private struct BusyMenuApp: App {
    init() {}
    var body: some Scene { WindowGroup { busyMenu() } }
}

@MainActor
@Suite("A menu row's breathing bar moves the label's own animation")
struct MenuBreathingBarRunTests {

    /// The focused menu rendered at `nowNanos` with a scheduler: the runs it left,
    /// how many grids it registered, and when the loop would next render.
    private func schedule(nowNanos: Int64) -> (runs: [AnimatedCellRun], grids: Int, nextRender: Int64?) {
        let scheduler = AnimationScheduler()
        let context = makeRenderContext(width: 30, height: 8) { environment, _ in
            environment.animationScheduler = scheduler
            environment.frameNowNanos = nowNanos
            environment.volatileReadTracker = VolatileReadTracker()
        }
        scheduler.beginFrame()
        let buffer = renderToBuffer(busyMenu(), context: context)
        scheduler.endFrame()
        return (buffer.animatedCells, scheduler.liveCount, scheduler.nextFiring(after: nowNanos))
    }

    @Test("A breathing bar drops its label's spinner run and wakes the loop at the spinner's next step")
    func theBarTakesOverTheSpinnersSteps() {
        let found = schedule(nowNanos: 1_000_000_000)
        let spinnerTicks = AnimationClock.frameTicks(forSeconds: SpinnerStyle.dots.interval)
        #expect(!found.runs.isEmpty, "pre-condition: the focused row's bar breathes")
        #expect(
            !found.runs.contains { $0.frameTicks == spinnerTicks },
            "the label's spinner run is still under the bar's: \(found.runs)")
        #expect(found.grids == 0, "a grid was registered for the dropped run")
        #expect(
            found.nextRender == 1_050_000_000,
            "a 7-tick spinner at 1.000 s, tick 60, is on step 8, and next steps when tick 63 begins")
    }

    /// Through the run loop: every replayed tick against a render at the same
    /// instant, with the loop rendering when a wake the menu asked for falls due.
    @Test("The spinner under a breathing bar moves on the renders the menu asks for")
    func theSpinnerMovesThroughTheLoop() {
        let found = ReplayOracle.compare({ BusyMenuApp() }, ticks: 24)
        #expect(found.compared > 0, "nothing was replayed")
        #expect(found.scheduledRenders > 0, "the menu asked for no render the loop would make")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }
}
