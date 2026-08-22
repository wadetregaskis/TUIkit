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
    private func blinker(_ text: String) -> some View {
        Text(text).animatedCells([
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1,
                frames: ["\u{1B}[31m*\u{1B}[0m", "\u{1B}[32m+\u{1B}[0m"], clock: .cursor)
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
            buffer.animatedCells.count == 3 || scheduler.liveCount > 0,
            "runs dropped and nothing asked to be re-rendered")
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
