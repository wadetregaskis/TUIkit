//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CursorRowBreathTests.swift
//
//  Motion means "this is where the keys go". Every focused control says so by
//  breathing — except, until now, a `List` or `Table` whose cursor sat on a row
//  the selection does not include: that row wore a still wash, so a list with
//  nothing selected, or a cursor moved off the selection, was the one focused
//  control on the page that did not move. The Lists page showed it three times
//  over, each list looking different depending on where its cursor happened to be.
//
//  Now the cursor row of a list that has the keys always breathes: in the accent
//  on a selected row, as before, and in the neutral focus wash on one that is
//  not (`Palette.focusWashPulse()`). A list that does not have them — unfocused,
//  or in a window that has lost the terminal's focus — shows the still look it
//  always did. The hue is what tells the two breathing rows apart, which is all a
//  list drawn with `.rowSelectionIndicator(.hidden)` has to go on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A `List` or a `Table` with `selection` selected, whose cursor lands on row 0 once
/// it takes the focus.
private struct CursorRowBreathApp: App {
    static var palette: any Palette { PaletteRegistry.all[0] }

    var kind = ReversedCursorRowTests.Kind.list
    var selection: Set<Int> = []
    var indicator = Visibility.automatic

    init() {}

    init(kind: ReversedCursorRowTests.Kind, selection: Set<Int>, indicator: Visibility = .automatic) {
        self.kind = kind
        self.selection = selection
        self.indicator = indicator
    }

    var body: some Scene {
        WindowGroup {
            kind.view(selection: selection)
                .rowSelectionIndicator(indicator)
                .palette(Self.palette)
        }
    }
}

@MainActor
@Suite("A list that has the keys breathes its cursor row wherever it is", .serialized)
struct CursorRowBreathTests {

    /// One frame through the run loop.
    private struct Frame {
        let lines: [String]
        let runs: [AnimatedCellRun]
    }

    /// A loop over `app`, its runner (the seam a terminal focus report goes through)
    /// and a clock, rendered twice so the control has taken the focus.
    private func settled(_ app: CursorRowBreathApp) throws -> (
        runner: AppRunner<CursorRowBreathApp>, loop: RenderLoop<CursorRowBreathApp>, timer: CursorTimer,
        frame: Frame
    ) {
        let runner = AppRunner(app: app, appState: AppState())
        let harness = RenderLoopHarness(tuiContext: runner.tuiContext)
        let loop = harness.loop(app)
        let timer = CursorTimer(renderNotifier: harness.appState)
        _ = try frame(loop, timer)
        return (runner, loop, timer, try frame(loop, timer))
    }

    private func frame(_ loop: RenderLoop<CursorRowBreathApp>, _ timer: CursorTimer) throws -> Frame {
        timer.beginFrameReadTracking()
        _ = loop.render(cursorTimer: timer)
        let frame = try #require(loop.replayable, "the loop kept no frame")
        return Frame(lines: frame.contentLines, runs: frame.runs)
    }

    /// The backgrounds row 0 shows across its breath, one per frame of its run.
    private func breath(of frame: Frame) throws -> [String] {
        let line = try #require(frame.lines.firstIndex { $0.stripped.contains("row 0") })
        let run = try #require(frame.runs.first { $0.offsetY == line }, "row 0 does not breathe")
        return try run.frames.map { try #require(sgrState(of: "row 0", in: [$0])).renderedBackground }
    }

    // MARK: - The owner's rule

    /// The cursor on a row the selection does not include breathes, in the neutral
    /// wash: from ``Palette/focusBackground`` — the still look it used to have — up
    /// to the bright end of ``Palette/focusWashPulse()``.
    @Test("An unselected cursor row breathes the focus wash", arguments: ReversedCursorRowTests.Kind.allCases)
    func unselectedCursorRowBreathes(kind: ReversedCursorRowTests.Kind) throws {
        let (_, _, _, active) = try settled(CursorRowBreathApp(kind: kind, selection: [2]))
        let breath = try breath(of: active)
        let palette = CursorRowBreathApp.palette
        let ends = palette.focusWashPulse()
        #expect(
            breath.contains(renderedBackground(of: ends.dim)),
            "the breath never reached the wash: \(Set(breath))")
        #expect(
            breath.contains(renderedBackground(of: ends.bright)),
            "the breath never reached its bright end: \(Set(breath))")
    }

    /// With the ● off, the highlight is all that says whether the cursor row is
    /// selected: the two breaths share no colour.
    @Test(
        "Under .rowSelectionIndicator(.hidden) a selected cursor row and an unselected one breathe apart",
        arguments: ReversedCursorRowTests.Kind.allCases)
    func hiddenIndicatorStillReads(kind: ReversedCursorRowTests.Kind) throws {
        let selected = try breath(
            of: settled(CursorRowBreathApp(kind: kind, selection: [0], indicator: .hidden)).frame)
        let unselected = try breath(
            of: settled(CursorRowBreathApp(kind: kind, selection: [2], indicator: .hidden)).frame)
        #expect(
            Set(selected).isDisjoint(with: unselected),
            "the accent breath and the neutral one share \(Set(selected).intersection(unselected))")
    }

    /// Out and back, as `InactiveFocusIndicatorTests` takes a selected cursor row:
    /// the still wash while the window has lost the terminal's focus — the exact
    /// colour, so a row that kept breathing's bright end cannot pass — and the
    /// breath back after. A `Table` serving the still row it kept while inactive
    /// would fail the last step (`TableRowMemoStore` never keeps a cursor row).
    @Test(
        "An unselected cursor row holds the still wash while inactive, and breathes again after",
        arguments: ReversedCursorRowTests.Kind.allCases)
    func unselectedCursorRowRoundTrip(kind: ReversedCursorRowTests.Kind) throws {
        let (runner, loop, timer, active) = try settled(CursorRowBreathApp(kind: kind, selection: [2]))
        let line = try #require(active.lines.firstIndex { $0.stripped.contains("row 0") })
        #expect(active.runs.contains { $0.offsetY == line }, "the premise: the cursor row breathes")

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        let inactive = try frame(loop, timer)
        #expect(
            try #require(sgrState(of: "row 0", in: inactive.lines)).renderedBackground
                == renderedBackground(of: CursorRowBreathApp.palette.focusBackground),
            "the inactive cursor row should hold the plain focus wash")
        #expect(inactive.runs.isEmpty, "\(inactive.runs.count) runs left breathing in an inactive window")

        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        let back = try frame(loop, timer)
        #expect(back.runs.contains { $0.offsetY == line }, "focus-in did not bring the breath back")
    }
}
