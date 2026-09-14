//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndicatorCycleTimingTests.swift
//
//  Every focus-emphasis and caret producer builds its runs with the frame duration
//  and clock its cycle carries. Each producer renders under a forced timing that is
//  neither the cursor tick nor the cursor clock, so one that writes
//  `clock: .cursor` and leaves the frame duration to the run's default is caught
//  at the site that does it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A site that builds focus-emphasis or caret runs, by what draws through it.
enum CycleRunProducer: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// `SelectionEmphasisCycle.run`, through a bracketed button's caps.
    case bracketedButtonCaps
    /// `SelectionEmphasisCycle.run`, through a toggle's indicator.
    case toggle
    /// `SelectionEmphasisCycle.run`, through an inline menu's focused row.
    case menuRow
    /// A plain button's focus prefix beside a string label.
    case plainButtonPrefix
    /// A plain button's focus prefix beside a view label.
    case plainButtonViewLabelPrefix
    /// `BreathingLabel`, a one-line label.
    case linkLabel
    /// `BreathingLabel`, a label that is a view.
    case linkViewLabel
    case textFieldCaret
    case secureFieldCaret
    case textEditorCaret
    case listRow
    case listRowWithScrollbar
    case tableRow
    case tableRowWithScrollbar
    case tableRowMultiLine
    case color256GridCursor
    case swatchGridCursor
    case verticalScrollbar
    case horizontalScrollbar
    /// `AnimatedColor`, painted by `.border`.
    case animatedBorder
    /// `DropdownMenu`'s breathing frame and highlight.
    case contextMenuPopup

    var testDescription: String { rawValue }
}

@MainActor
@Suite("Focus and caret runs take their timing from their cycle")
struct IndicatorCycleTimingTests {
    /// Neither the cursor tick nor the cursor clock.
    static let forced = IndicatorCycleTiming(frameTicks: 5, clock: .content)

    @Test(
        "Every producer builds its runs with the frame duration and clock its cycle carries",
        arguments: CycleRunProducer.allCases)
    func producerCarriesTheTiming(_ producer: CycleRunProducer) {
        let runs = Self.runs(of: producer)
        #expect(!runs.isEmpty, "the producer left no run, so nothing was checked")
        for run in runs {
            #expect(
                run.frameTicks == Self.forced.frameTicks,
                "the run on row \(run.offsetY) steps every \(run.frameTicks) ticks")
            #expect(run.clock == Self.forced.clock, "the run on row \(run.offsetY) is on \(run.clock)")
        }
    }

    @Test("Nothing forces a cycle's timing unless a test does, and the cursor tick is 50 ms on the cursor clock")
    func nothingForcesATiming() {
        #expect(EnvironmentValues().indicatorCycleTiming == nil)
        #expect(IndicatorCycleTiming.cursorTick.frameTicks == AnimationClock.standardFrameTicks)
        #expect(IndicatorCycleTiming.cursorTick.clock == .cursor)
    }

    @Test("A cycle's step is whole frames of its own duration, counted on its own clock")
    func stepCountsItsOwnFrames() {
        #expect(IndicatorCycleTiming.cursorTick.step(on: nil) == 0, "no timer, the first frame")
        let timer = CursorTimer(renderNotifier: AppState())
        // The focus clock's zero floors to 1.000 s, a whole 50 ms of the content clock.
        timer.observe(nowNanos: 1_037_000_000)
        #expect(Self.forced.step(on: timer) == 12, "1.037 s is 12 whole 5-tick frames of 83,333,333 ns")
        #expect(
            IndicatorCycleTiming(frameTicks: 5, clock: .cursor).step(on: timer) == 0,
            "37 ms since the focus moved")
        #expect(IndicatorCycleTiming.cursorTick.step(on: timer) == timer.elapsedSteps)
    }

    @Test("An animated colour keeps its frame duration and clock through resolving, and into its run")
    func animatedColourCarriesItsTiming() throws {
        let colour = AnimatedColor(
            frames: [.palette.accent, .palette.border], step: 0, frameTicks: 5, clock: .content)
        let resolved = colour.resolved(with: SystemPalette(.green))
        #expect(resolved.frameTicks == 5)
        #expect(resolved.clock == .content)
        let run = try #require(
            resolved.run(offsetX: 0, offsetY: 0) { ANSIRenderer.colorize("x", foreground: $0) })
        #expect(run.frameTicks == 5)
        #expect(run.clock == .content)
        #expect(AnimatedColor(.red).frameTicks == AnimationClock.standardFrameTicks)
    }

    // MARK: - The producers

    private static let docs = URL(string: "https://example.com")!

    // One case per producer, and nothing else: split up, the list of what the sweep
    // renders would be in several places.
    // swiftlint:disable:next cyclomatic_complexity
    private static func runs(of producer: CycleRunProducer) -> [AnimatedCellRun] {
        switch producer {
        case .bracketedButtonCaps: focused(Button("Save") {})
        case .toggle: focused(Toggle("On", isOn: .constant(true)))
        case .menuRow:
            focused(
                Menu("Demos") {
                    Button("First") {}
                    Button("Second") {}
                }
                .menuStyle(.inline))
        case .plainButtonPrefix: focused(Button("Save") {}.buttonStyle(.plain))
        case .plainButtonViewLabelPrefix: focused(Button {} label: { Text("Save") }.buttonStyle(.plain))
        case .linkLabel: focused(Link("Docs", destination: docs))
        case .linkViewLabel: focused(Link(destination: docs) { Text("Docs") })
        case .textFieldCaret: focused(TextField("Name", text: .constant("hi")), width: 30)
        case .secureFieldCaret: focused(SecureField("Pin", text: .constant("hi")), width: 30)
        case .textEditorCaret: focused(TextEditor(text: .constant("hi")), width: 24, height: 4)
        case .listRow: focused(list(["Alpha", "Bravo", "Charlie"]), width: 30)
        case .listRowWithScrollbar:
            focused(list((0..<40).map { $0 == 0 ? "Alpha" : "Row \($0)" }), width: 30)
        case .tableRow: focused(table(rows: 3), height: 10)
        case .tableRowWithScrollbar: focused(table(rows: 40))
        case .tableRowMultiLine:
            focused(table(rows: 3, note: "a note long enough to wrap over two lines", lineLimit: 2), height: 10)
        case .color256GridCursor:
            focused(
                _Color256GridCore(selection: .constant(Color.palette(1)), focusID: "grid-timing"),
                width: 80, height: 24)
        case .swatchGridCursor: swatchGridRuns()
        case .verticalScrollbar:
            scrolled(
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<30, id: \.self) { Text("line \($0)") }
                    }
                }
                .scrollIndicators(.visible)
                .scrollIndicatorStyle(.scrollbar)
                .frame(height: 6),
                width: 20, height: 6)
        case .horizontalScrollbar:
            scrolled(
                ScrollView(.horizontal) { Text("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") }
                    .scrollIndicators(.visible)
                    .scrollIndicatorStyle(.scrollbar),
                width: 10, height: 4)
        case .animatedBorder: focused(TimingProbeBordered().focusable(), width: 20, height: 4)
        case .contextMenuPopup: contextMenuPopupRuns()
        }
    }

    /// The runs `view` leaves, rendered under the forced timing against a context
    /// whose fresh focus manager gives the first focusable the focus.
    private static func focused(_ view: some View, width: Int = 40, height: Int = 8) -> [AnimatedCellRun] {
        renderToBuffer(
            view.environment(\.indicatorCycleTiming, forced),
            context: makeRenderContext(width: width, height: height)
        ).animatedCells
    }

    private static func list(_ items: [String]) -> some View {
        List(selection: .constant("Alpha" as String?)) {
            ForEach(items, id: \.self) { Text($0) }
        }
    }

    private static func table(rows count: Int, note: String? = nil, lineLimit: Int = 1) -> some View {
        let rows = (0..<count).map { TimingRow(id: "\($0)", name: "Row \($0)", note: note ?? "note \($0)") }
        return Table(rows, selection: .constant("0" as String?)) {
            TableColumn("Name", value: \TimingRow.name)
            TableColumn("Note", value: \TimingRow.note).lineLimit(lineLimit)
        }
    }

    /// A swatch grid takes the focus on its first render and draws the mark on its
    /// second, as `SwatchGridTests` renders it.
    private static func swatchGridRuns() -> [AnimatedCellRun] {
        let entries: [Color] = (0..<4).map { Color.rgb(0, UInt8($0 * 60), 0) }
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        let context = RenderContext(
            availableWidth: 16, availableHeight: 3, environment: environment, tuiContext: TUIContext())
        let grid = _SwatchGridCore(
            entries: entries, columns: 4, selection: .constant(entries[1]), focusID: "sg-timing"
        ).environment(\.indicatorCycleTiming, forced)
        func render() -> FrameBuffer {
            focusManager.beginRenderPass()
            defer { focusManager.endRenderPass() }
            return renderToBuffer(grid, context: context)
        }
        _ = render()
        return render().animatedCells
    }

    /// A scroll view settles its extent on the first pass and draws its bar,
    /// focused, on the second, as `ScrollbarFocusPulseTests` renders it.
    private static func scrolled(_ scrollView: some View, width: Int, height: Int) -> [AnimatedCellRun] {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = scrollView.environment(\.indicatorCycleTiming, forced)
        func frame() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: width, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }
        _ = frame()
        return frame().animatedCells
    }

    /// The popup a right-click opens, as `ContextMenuTests` opens it: its frame and
    /// its highlighted row breathe.
    private static func contextMenuPopupRuns() -> [AnimatedCellRun] {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        let view = Text("Right-click me")
            .contextMenu {
                Button("Cut") {}
                Button("Copy") {}
            }
            .environment(\.indicatorCycleTiming, forced)
        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.keyEventDispatcher.clearHandlers()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }
        _ = render()
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .released, x: 3, y: 0))
        return render().overlays.first?.content.animatedCells ?? []
    }
}

private struct TimingRow: Identifiable {
    let id: String
    let name: String
    let note: String
}

/// A border painted with the focus emphasis as an `AnimatedColor`.
private struct TimingProbeBordered: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    var body: some View {
        Text("Pick me")
            .padding(.horizontal, 1)
            .border(emphasis.animatedColor(isFocused, dim: palette.border, bright: palette.accent))
    }
}
