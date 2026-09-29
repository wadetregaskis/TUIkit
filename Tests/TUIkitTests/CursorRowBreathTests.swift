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
//  always did. Under `.rowSelectionIndicator(.hidden)` too: the focus indicator
//  always visibly breathes, and with no ● the two breaths themselves say which
//  cursor row is selected. It used to hold the unselected one still there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A dark page whose focus wash is translucent, as the Example's faded palette makes
/// every wash (`TUIKIT_EXAMPLE_PALETTE_ALPHA`).
private struct TranslucentWashPalette: Palette {
    let id = "cursor-row-translucent-wash"
    let name = "Translucent wash"
    let background = Color.rgb(10, 10, 20)
    let foreground = Color.rgb(230, 230, 240)
    let accent = Color.rgb(0, 180, 200)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
    let focusBackground = Color.rgb(60, 60, 200).opacity(0.5)
}

/// A `List` or a `Table` with `selection` selected, whose cursor lands on row 0 once
/// it takes the focus — on the page, or on `surface` where one is given.
private struct CursorRowBreathApp: App {
    static var palette: any Palette { PaletteRegistry.all[0] }

    var kind = ReversedCursorRowTests.Kind.list
    var selection: Set<Int> = []
    var indicator = Visibility.automatic
    var palette: any Palette = Self.palette
    var surface: Color?
    /// `false` for a control with no selection binding at all.
    var bindsSelection = true

    init() {}

    init(
        kind: ReversedCursorRowTests.Kind, selection: Set<Int>, indicator: Visibility = .automatic,
        palette: any Palette = Self.palette, surface: Color? = nil
    ) {
        self.kind = kind
        self.selection = selection
        self.indicator = indicator
        self.palette = palette
        self.surface = surface
    }

    var body: some Scene {
        WindowGroup {
            surfaced(control.rowSelectionIndicator(indicator))
                .palette(palette)
        }
    }

    @ViewBuilder
    private var control: some View {
        if bindsSelection {
            kind.view(selection: selection)
        } else {
            kind.viewWithoutSelection()
        }
    }

    @ViewBuilder
    private func surfaced(_ content: some View) -> some View {
        if let surface {
            ZStack { surface; content }
        } else {
            content
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

    /// `.rowSelectionIndicator(.hidden)` is an environment value, so an app that sets
    /// it at its root reaches every list. A control with no selection binding has no
    /// selection for motion to tell its cursor row from: it breathes as everywhere.
    @Test(
        "Under .rowSelectionIndicator(.hidden), a control with no selection still breathes",
        arguments: ReversedCursorRowTests.Kind.allCases)
    func hiddenIndicatorWithoutSelectionBreathes(kind: ReversedCursorRowTests.Kind) throws {
        var app = CursorRowBreathApp(kind: kind, selection: [], indicator: .hidden)
        app.bindsSelection = false
        let (_, _, _, active) = try settled(app)
        let breath = try breath(of: active)
        let ends = CursorRowBreathApp.palette.focusWashPulse()
        #expect(
            breath.contains(renderedBackground(of: ends.bright)),
            "the cursor row stood still: \(Set(breath))")
    }

    /// Every palette that states its own colours, by name, so a failure names the one
    /// it is about.
    nonisolated static let statedPaletteNames =
        (PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles).map(\.name)

    /// The focus indicator always visibly breathes, whether or not there is a
    /// selection on the same row — with the ● off too. The unselected cursor row used
    /// to hold the plain wash still here, so motion could say which row was selected;
    /// it breathes the focus wash now, exactly as it does with the ● shown, and the
    /// selected one breathes the accent.
    @Test(
        "Under .rowSelectionIndicator(.hidden) every cursor row breathes",
        arguments: ReversedCursorRowTests.Kind.allCases, statedPaletteNames)
    func hiddenIndicatorEveryCursorRowBreathes(kind: ReversedCursorRowTests.Kind, paletteName: String) throws {
        let palette = try #require(PaletteRegistry.palette(withName: paletteName))
        let selected = try settled(
            CursorRowBreathApp(kind: kind, selection: [0], indicator: .hidden, palette: palette)
        ).frame
        #expect(try !breath(of: selected).isEmpty, "a selected cursor row stood still")

        let unselected = try settled(
            CursorRowBreathApp(kind: kind, selection: [2], indicator: .hidden, palette: palette)
        ).frame
        let breath = try breath(of: unselected)
        let ends = palette.focusWashPulse()
        #expect(
            breath.contains(renderedBackground(of: ends.dim))
                && breath.contains(renderedBackground(of: ends.bright)),
            "an unselected cursor row does not breathe the focus wash: \(Set(breath))")
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

    // MARK: - A selected row the cursor is not on

    /// A still selected row the cursor is not on (S) draws the selected-row tint in a
    /// `List` and in a `Table` alike, with the ● shown or hidden: under
    /// `.rowSelectionIndicator(.hidden)` the tint is all that says it is selected. A
    /// `Table` drew no fill there, so its selected rows under `.hidden` showed nothing.
    @Test(
        "A selected row the cursor is not on draws the selected-row tint, with the ● or without",
        arguments: ReversedCursorRowTests.Kind.allCases, [Visibility.automatic, .hidden])
    func selectedRowOffTheCursorIsTinted(kind: ReversedCursorRowTests.Kind, indicator: Visibility) throws {
        let palette = CursorRowBreathApp.palette
        let active = try settled(
            CursorRowBreathApp(kind: kind, selection: [0, 2], indicator: indicator, palette: palette)
        ).frame
        guard case .fill(let tint) = palette.selectedRowFill() else {
            Issue.record("the premise: the palette's selected-row tint is a fill")
            return
        }
        #expect(
            try #require(sgrState(of: "row 2", in: active.lines)).renderedBackground == renderedBackground(of: tint),
            "\(kind), \(indicator): row 2 is selected and not the cursor")
        #expect(
            try #require(sgrState(of: "row 1", in: active.lines)).renderedBackground != renderedBackground(of: tint),
            "\(kind), \(indicator): row 1 is not selected")
    }

    // MARK: - A translucent wash

    /// A wash the palette states translucent is spent over the page by the breath, at
    /// both ends. Held still while the window has lost the terminal's focus, the row
    /// has to stop where the breath starts — or it changes colour as the focus goes,
    /// rather than stopping — on the page and on any surface the list is drawn on.
    @Test(
        "A translucent wash holds, while inactive, the colour its breath starts from",
        arguments: ReversedCursorRowTests.Kind.allCases, [false, true])
    func translucentWashHoldsTheBreathsBottom(kind: ReversedCursorRowTests.Kind, onASurface: Bool) throws {
        let palette = TranslucentWashPalette()
        let (runner, loop, timer, active) = try settled(
            CursorRowBreathApp(
                kind: kind, selection: [2], palette: palette,
                surface: onASurface ? Color.rgb(90, 30, 30) : nil))
        let bottom = renderedBackground(of: palette.focusWashPulse().dim)
        #expect(
            try breath(of: active).contains(bottom),
            "the premise: the breath starts from the wash spent over the page")

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        let inactive = try frame(loop, timer)
        let held = try #require(sgrState(of: "row 0", in: inactive.lines)).renderedBackground
        #expect(
            held == bottom,
            "the inactive cursor row holds \(held.debugDescription), not the \(bottom.debugDescription) its breath starts from")
    }
}
