//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListChildRunTests.swift
//
//  A row's own animation — a spinner, a blinking cursor, a pulsing badge —
//  reaches the screen only if the container carries its runs. `_ListCore` builds
//  every row's lines by hand rather than compositing the row's buffer, so
//  anything else the buffer carried is dropped unless it is threaded through
//  deliberately.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Animated runs inside a List")
struct ListChildRunTests {

    private func harness(width: Int = 40, height: Int = 20) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

    /// A two-frame run on the cell the view draws, so a container that carries
    /// it can be told apart from one that drops it.
    ///
    /// At a rate deliberately UNLIKE the clock's own, so a container that
    /// rebuilds the run with the defaults is caught rather than flattered.
    private static let childRate = 0.11

    private func blinker(_ text: String) -> some View {
        Text(text).animatedCells([
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1,
                frames: ["\u{1B}[31m*\u{1B}[0m", "\u{1B}[32m+\u{1B}[0m"],
                frameDuration: Self.childRate, clock: .cursor)
        ])
    }

    private func render(_ view: some View, tui: TUIContext, context: RenderContext) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer
    }

    @Test("A run inside a plain stack survives, which is the baseline")
    func stackCarriesRuns() {
        let (tui, context) = harness()
        let buffer = render(VStack { blinker("a"); blinker("b") }, tui: tui, context: context)
        #expect(buffer.animatedCells.count == 2, "a VStack dropped a child's runs")
    }

    @Test("A run inside a List row reaches the List's buffer")
    func listCarriesRuns() {
        let (tui, context) = harness()
        let buffer = render(
            List { blinker("one"); blinker("two"); blinker("three") },
            tui: tui, context: context)
        #expect(
            buffer.animatedCells.count == 3,
            "the List carried \(buffer.animatedCells.count) of 3 rows' runs")
    }

    /// A run rebuilt by a container must keep the rate it asked for. Dropping
    /// it retimed a `.dots` spinner in a List from 0.110 s a frame to the
    /// clock's 0.05 s — 2.2x too fast, and indistinguishable from correct in a
    /// screenshot.
    @Test("A carried run keeps its own frame rate")
    func carriedRunsKeepTheirRate() throws {
        let (tui, context) = harness()
        let buffer = render(List { blinker("one"); blinker("two") }, tui: tui, context: context)
        for run in buffer.animatedCells {
            #expect(run.frameDuration == Self.childRate, "retimed to \(run.frameDuration)")
        }
        #expect(!buffer.animatedCells.isEmpty)
    }

    @Test("A still run is not carried — it would hold the clock open forever")
    func stillRunsAreDropped() {
        let (tui, context) = harness()
        let still = Text("s").animatedCells([
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1, frames: ["=", "="], clock: .cursor)
        ])
        let buffer = render(List { still }, tui: tui, context: context)
        #expect(buffer.animatedCells.isEmpty, "a run that never changes was carried")
    }

    @Test("A carried run lands on the cell the row actually drew")
    func runsLandOnTheirCells() throws {
        let (tui, context) = harness()
        let buffer = render(List { blinker("X") }, tui: tui, context: context)
        let run = try #require(buffer.animatedCells.first)
        let line = try #require(
            buffer.lines.indices.contains(run.offsetY) ? buffer.lines[run.offsetY] : nil,
            "the run points at row \(run.offsetY) of \(buffer.lines.count)")
        // The run says "this cell animates"; the cell under it must be the one
        // the row drew there, or the replay paints over something else.
        let stripped = Array(line.stripped)
        #expect(run.offsetX < stripped.count)
        #expect(stripped[run.offsetX] == "X", "the run points at \(stripped[run.offsetX])")
    }

    @Test("A run scrolled out of the window goes with the cells it described")
    func runsClipWithTheirRows() {
        let (tui, context) = harness(height: 5)
        let buffer = render(
            List { ForEach(0..<40, id: \.self) { _ in blinker("z") } },
            tui: tui, context: context)
        #expect(buffer.animatedCells.count <= buffer.height)
        for run in buffer.animatedCells {
            #expect(run.offsetY >= 0 && run.offsetY < buffer.height, "run at row \(run.offsetY)")
        }
    }

    /// The cursor row repaints its whole line every tick, so a narrower run on
    /// it is dropped — and something has to move what the run would have moved,
    /// because a producer that left one behind has stopped asking to be
    /// re-rendered.
    @Test("A breathing row asks for the re-render its dropped run needed")
    func pulsingRowTakesOverTheAsking() {
        let (tui, context) = harness()
        var environment = context.environment
        let scheduler = AnimationScheduler()
        environment.animationScheduler = scheduler
        environment.volatileReadTracker = VolatileReadTracker()
        var focused = RenderContext(
            availableWidth: 40, availableHeight: 20, environment: environment, tuiContext: tui)
        focused.identity = context.identity

        scheduler.beginFrame()
        let buffer = render(
            List(selection: Binding<Int?>.constant(0)) {
                ForEach(0..<3, id: \.self) { _ in blinker("row") }
            },
            tui: tui, context: focused)
        scheduler.endFrame()
        // Whatever the focus state resolved to, the two must agree: a row whose
        // run was carried needs no re-render, and one whose run was dropped
        // does. What must never happen is neither — a frozen spinner.
        #expect(
            buffer.animatedCells.count == 3 || scheduler.liveCount > 0 || scheduler.liveWakeCount > 0,
            "runs dropped and nothing asked to be re-rendered")
    }

    /// A focused List with one selected row — so its row breathes and drops the
    /// row's own runs — rendered at `nowNanos` with a scheduler. Returns the runs
    /// the List left, how many grids it registered, and when the loop would next
    /// render.
    private func breathingRowSchedule(
        _ row: some View, nowNanos: Int64, cursorTimer: CursorTimer? = nil
    ) -> (runs: [AnimatedCellRun], grids: Int, nextRender: Int64?) {
        let scheduler = AnimationScheduler()
        let context = makeRenderContext(width: 30, height: 8) { environment, _ in
            environment.animationScheduler = scheduler
            environment.frameNowNanos = nowNanos
            environment.cursorTimer = cursorTimer
            environment.volatileReadTracker = VolatileReadTracker()
        }
        cursorTimer?.observe(nowNanos: UInt64(nowNanos))
        scheduler.beginFrame()
        let buffer = renderToBuffer(
            List(selection: .constant("row" as String?)) {
                ForEach(["row"], id: \.self) { _ in row }
            },
            context: context)
        scheduler.endFrame()
        return (buffer.animatedCells, scheduler.liveCount, scheduler.nextFiring(after: nowNanos))
    }

    /// The dropped run's own next step, not a 20 Hz grid. A grid re-rendered the
    /// whole screen twenty times a second for a spinner that changes nine times,
    /// and anchored wherever the first frame happened to be, off every run's
    /// boundaries.
    @Test("A breathing row wakes the loop at its dropped spinner's next step, and registers no grid")
    func droppedSpinnerWakesAtItsNextStep() {
        let schedule = breathingRowSchedule(
            HStack { Text("row"); Spinner(style: .dots) }, nowNanos: 1_000_000_000)
        #expect(
            schedule.runs.count == 1 && !schedule.runs.contains { $0.frameDuration == 0.11 },
            "pre-condition: only the row's breath is left, the spinner's run is dropped: \(schedule.runs)")
        #expect(schedule.grids == 0, "a grid was registered for the dropped run")
        #expect(schedule.nextRender == 1_100_000_000, "a 110 ms spinner at 1.000 s next steps at 1.100 s")
    }

    @Test("Several dropped runs wake the loop at the soonest of their next steps")
    func droppedRunsWakeAtTheSoonestStep() {
        let row = Text("row").animatedCells([
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1, frames: ["r", "R"], frameDuration: 0.11, clock: .content),
            AnimatedCellRun(
                offsetX: 1, offsetY: 0, width: 1, frames: ["o", "O"], frameDuration: 0.12, clock: .content),
        ])
        let schedule = breathingRowSchedule(row, nowNanos: 1_000_000_000)
        #expect(schedule.runs.count == 1, "pre-condition: both runs are dropped: \(schedule.runs)")
        #expect(schedule.grids == 0, "a grid was registered for the dropped runs")
        #expect(
            schedule.nextRender == 1_080_000_000,
            "at 1.000 s the 120 ms run steps at 1.080 s, before the 110 ms one at 1.100 s")
    }

    /// Each dropped run is asked on its own clock. The cursor clock's zero is the
    /// focus epoch, floored to 50 ms: at 1.030 s it is 1.000 s, so a 110 ms run on
    /// that clock steps at 1.110 s, where the same run on the content clock would
    /// step at 1.100 s.
    @Test("A dropped run on the cursor clock wakes the loop at that clock's next step")
    func droppedCursorRunWakesOnItsClock() {
        let row = Text("row").animatedCells([
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1, frames: ["r", "R"], frameDuration: 0.11, clock: .cursor)
        ])
        let schedule = breathingRowSchedule(
            row, nowNanos: 1_030_000_000, cursorTimer: CursorTimer(renderNotifier: AppState()))
        #expect(schedule.runs.count == 1, "pre-condition: the run is dropped: \(schedule.runs)")
        #expect(schedule.grids == 0, "a grid was registered for the dropped run")
        #expect(schedule.nextRender == 1_110_000_000, "the cursor clock is 0.030 s in, so 80 ms to go")
    }

    @Test("A measure pass leaves no runs behind")
    func measureLeavesNothing() {
        let (tui, context) = harness()
        var measuring = context
        measuring.isMeasuring = true
        let buffer = render(List { blinker("m") }, tui: tui, context: measuring)
        #expect(buffer.animatedCells.isEmpty, "a measure pass declared an animation")
    }
}
