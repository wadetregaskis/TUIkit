//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RefreshableMemoTests.swift
//
//  `.refreshable` inside a value-memoized subtree. Its Ctrl-R binding is a
//  per-frame registration the key dispatcher empties before every walk, so a
//  memo serving the subtree has to make it again. And the spinner it draws
//  while a refresh runs is the one thing about it that changes without its view
//  value changing, so the memo has to be told when a run starts and ends.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Counts refresh runs, from whatever thread the action runs on.
private final class RunCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var runs = 0

    var value: Int { lock.withLock { runs } }
    func increment() { lock.withLock { runs += 1 } }
}

/// Renders frames the way `RenderLoop` brackets them, and reports how many memo
/// lookups missed: a frame whose memoized subtrees were all served takes none.
@MainActor
private final class MemoHarness {
    let tuiContext = TUIContext()

    var dispatcher: KeyEventDispatcher { tuiContext.keyEventDispatcher }
    var cache: RenderCache { tuiContext.renderCache }

    func frame(
        _ view: some View, tracker: VolatileReadTracker = VolatileReadTracker()
    ) -> (buffer: FrameBuffer, misses: Int) {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        environment.installVolatileReadTracker(tracker)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 6,
            environment: environment, tuiContext: tuiContext)
        let missesBefore = cache.stats.misses
        tuiContext.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        dispatcher.clearHandlers()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        cache.removeInactive()
        return (buffer, cache.stats.misses - missesBefore)
    }

    @discardableResult
    func pressControlR() -> Bool {
        dispatcher.dispatch(KeyEvent(key: .character("r"), ctrl: true, alt: false, shift: false))
    }
}

@MainActor
@Suite("refreshable through the render memos")
struct RefreshableMemoTests {
    @Test("A memoized row with a refreshable is served, and Ctrl-R starts one refresh per keypress on every frame")
    func rowWithRefreshableIsServed() async {
        let harness = MemoHarness()
        let runs = RunCounter()
        let view = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name).refreshable { runs.increment() }
            }
        }

        for number in 1...3 {
            // The first frame of each round renders: the row is new, or the
            // last round's run started and ended, and each of those invalidates
            // it (the spinner test below is why). The second must be served.
            _ = harness.frame(view)
            let hitsBefore = harness.cache.stats.hits
            let misses = harness.frame(view).misses
            #expect(misses == 0, "round \(number): the row was rendered again, \(misses) misses")
            #expect(harness.cache.stats.hits > hitsBefore, "round \(number): nothing was served")
            #expect(harness.dispatcher.handlerCount == 1, "round \(number)")
            #expect(harness.pressControlR(), "round \(number): Ctrl-R was not taken on a served frame")
            await settle(until: { runs.value == number })
            #expect(runs.value == number, "round \(number): \(runs.value) refreshes")
        }
        #expect(!harness.cache.isEmpty, "the row was never stored")
    }

    @Test("A served refreshable shows its spinner on the frame after Ctrl-R, and loses it when the refresh ends")
    func servedRefreshableRedrawsForItsRun() async {
        let harness = MemoHarness()
        let gate = RefreshGate()
        let view = VStack {
            ForEach(["abcdefghij"], id: \.self) { name in
                Text(name).refreshable { await gate.hold() }
            }
        }

        let idle = harness.frame(view).buffer.lines
        #expect(harness.frame(view).misses == 0, "the idle row was not served")

        // Nothing about the row's value changed, so only the run starting can
        // stop the memo serving the idle picture it stored.
        harness.pressControlR()
        await settle(until: { gate.entered == 1 })
        let busy = harness.frame(view).buffer.lines
        #expect(busy != idle, "the frame after Ctrl-R still drew the row idle: \(busy)")

        // The end of a run is not the body returning — the run state is cleared
        // after it, with a suspension point in between — so the frame losing
        // the spinner is the edge to wait on.
        gate.release()
        await settle(until: { harness.frame(view).buffer.lines == idle })
        let after = harness.frame(view).buffer.lines
        #expect(after == idle, "the frame after the refresh ended still drew it running: \(after)")
    }

    @Test("An idle refreshable leaves the memoized rows inside it served on every frame")
    func idleRefreshableKeepsItsContentServed() {
        // Only a run starting or ending may invalidate: the binding every render
        // makes must not, or the rows under every `.refreshable` render again on
        // every frame.
        let harness = MemoHarness()
        let view = VStack {
            ForEach(["a", "b", "c"], id: \.self) { name in Text(name) }
        }
        .refreshable {}

        _ = harness.frame(view)
        for number in 2...4 {
            let misses = harness.frame(view).misses
            #expect(misses == 0, "frame \(number): the rows under an idle refreshable took \(misses) misses")
        }
    }

    @Test("Ctrl-R counts as a replayable effect on the frame that renders the row and the frame that serves it")
    func refreshableCountsAsReplayable() {
        let harness = MemoHarness()
        let view = VStack {
            ForEach(["row"], id: \.self) { name in Text(name).refreshable {} }
        }

        for number in 1...2 {
            let tracker = VolatileReadTracker()
            _ = harness.frame(view, tracker: tracker)
            #expect(tracker.replayableEffects == 1, "frame \(number)")
            #expect(tracker.sideEffects == 0, "frame \(number)")
        }
    }

    @Test("A dimmed refreshable row is stored, and Ctrl-R never reaches it")
    func dimmedRefreshableIsInert() async {
        let harness = MemoHarness()
        let runs = RunCounter()
        let view = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name).refreshable { runs.increment() }.dimmed()
            }
        }

        for number in 1...3 {
            let misses = harness.frame(view).misses
            if number > 1 { #expect(misses == 0, "frame \(number) rendered the dimmed row again") }
            #expect(harness.dispatcher.handlerCount == 0, "frame \(number)")
            #expect(!harness.pressControlR(), "frame \(number): a dimmed row took Ctrl-R")
        }
        // A budget: the claim is that a dimmed row starts nothing.
        await yieldToSpawnedWork()
        #expect(runs.value == 0)
        #expect(!harness.cache.isEmpty, "the dimmed row was never stored")
    }
}
