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
//  always did. The ● is what tells the two breathing rows apart: on most shipped
//  palettes the wash shares the accent's hue. A list drawn with
//  `.rowSelectionIndicator(.hidden)` has no ●, so there an unselected cursor row
//  holds the still wash, and motion says which row is selected.
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
            surfaced(kind.view(selection: selection).rowSelectionIndicator(indicator))
                .palette(palette)
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

    /// Every palette that states its own colours, by name, so a failure names the one
    /// it is about.
    nonisolated static let statedPaletteNames =
        (PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles).map(\.name)

    /// With the ● off, the highlight is all that says whether the cursor row is
    /// selected, and colour cannot say it: on most shipped palettes the neutral wash
    /// shares the accent's hue — all six phosphor presets by construction, and Basic,
    /// Man Page, Ocean, Silver Aerogel, Solid Colors and Pro — and on Green the two
    /// breaths' dim ends stand 1.03:1 apart. So motion says it: the selected cursor
    /// row breathes, and the unselected one holds the plain wash, on every palette.
    /// Asking only that the two breaths share no exact colour let both breathe alike.
    @Test(
        "Under .rowSelectionIndicator(.hidden) only a selected cursor row breathes",
        arguments: ReversedCursorRowTests.Kind.allCases, statedPaletteNames)
    func hiddenIndicatorMotionTellsSelection(kind: ReversedCursorRowTests.Kind, paletteName: String) throws {
        let palette = try #require(PaletteRegistry.palette(withName: paletteName))
        let selected = try settled(
            CursorRowBreathApp(kind: kind, selection: [0], indicator: .hidden, palette: palette)
        ).frame
        #expect(try !breath(of: selected).isEmpty, "the premise: a selected cursor row breathes")

        let unselected = try settled(
            CursorRowBreathApp(kind: kind, selection: [2], indicator: .hidden, palette: palette)
        ).frame
        let line = try #require(unselected.lines.firstIndex { $0.stripped.contains("row 0") })
        #expect(
            !unselected.runs.contains { $0.offsetY == line },
            "an unselected cursor row breathes like a selected one, with no ● to tell them apart")
        #expect(
            try #require(sgrState(of: "row 0", in: unselected.lines)).renderedBackground
                == renderedBackground(of: palette.focusBackground),
            "an unselected cursor row should hold the plain focus wash")
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
