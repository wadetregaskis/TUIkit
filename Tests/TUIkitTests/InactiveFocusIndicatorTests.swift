//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InactiveFocusIndicatorTests.swift
//
//  A terminal that loses focus (mode 1004's `ESC [ O`) makes the scene inactive.
//  The focus does not go anywhere: it is still on the control the user left it
//  on, and the keys will reach that control again the moment the window comes
//  back. So the indicator stays where it is, drawn, and holds still — motion is
//  what says "the keys go here NOW", and right now they do not.
//
//  The report that asked for this was the Example's main menu, whose highlighted
//  row vanished on focus-out, which read as the focus having been lost rather
//  than parked. The row now takes the still tint a `List` gives a selection it
//  does not hold the keys for — the look the Lists page already had in an
//  inactive window, which is where the report pointed as the right one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// The Example's main menu in miniature: an inline `Menu` of `Button`s, whose rows
/// are page focus stops. The first row takes the focus.
private struct InlineMenuApp: App {
    /// Stated rather than left to the palette manager, so the test can name the
    /// colours it expects.
    static var palette: any Palette { PaletteRegistry.all[0] }

    init() {}

    var body: some Scene {
        WindowGroup {
            Menu("Pick") {
                Button("Alpha") {}
                Button("Bravo") {}
            }
            .menuStyle(.inline)
            .palette(Self.palette)
        }
    }
}

/// A `List` or a `Table` whose first row is selected, and so is the cursor row once the
/// control takes the focus, under one indicator style.
private struct CursorRowApp: App {
    static var palette: any Palette { PaletteRegistry.all[0] }

    var kind = ReversedCursorRowTests.Kind.list
    var style = TextCursorStyle.Animation.pulse

    init() {}

    init(kind: ReversedCursorRowTests.Kind, style: TextCursorStyle.Animation) {
        self.kind = kind
        self.style = style
    }

    var body: some Scene {
        WindowGroup {
            kind.view(selection: [0])
                .selectionIndicatorStyle(style)
                .palette(Self.palette)
        }
    }
}

@MainActor
@Suite("A focused control stays drawn, and still, while the terminal is not focused", .serialized)
struct InactiveFocusIndicatorTests {

    // MARK: - Reading a frame back

    /// The row index of the first content line that shows `word`.
    private func row(of word: String, in lines: [String]) -> Int? {
        lines.firstIndex { $0.stripped.contains(word) }
    }

    // MARK: - The report: the main menu

    /// One frame of the menu through the run loop, and what it left to animate.
    private struct Frame {
        let lines: [String]
        let runs: [AnimatedCellRun]
        let activity: RenderActivity
    }

    private func frame<A: App>(_ loop: RenderLoop<A>, _ timer: CursorTimer) throws -> Frame {
        timer.beginFrameReadTracking()
        let activity = loop.render(cursorTimer: timer)
        let frame = try #require(loop.replayable, "the loop kept no frame")
        return Frame(lines: frame.contentLines, runs: frame.runs, activity: activity)
    }

    @Test("Terminal focus-out keeps the focused menu row drawn, still; focus-in brings its breath back")
    func menuRowSurvivesFocusOut() throws {
        // The runner is the seam the terminal's report goes through; the loop draws
        // with the runner's own context, so what the report changes is what is drawn.
        let runner = AppRunner(app: InlineMenuApp(), appState: AppState())
        let harness = RenderLoopHarness(tuiContext: runner.tuiContext)
        let loop = harness.loop(InlineMenuApp())
        let timer = CursorTimer(renderNotifier: harness.appState)
        let palette = InlineMenuApp.palette

        // The first frame registers the rows and hands the first the focus; the
        // second is drawn with it.
        _ = try frame(loop, timer)
        let active = try frame(loop, timer)
        let alphaRow = try #require(row(of: "Alpha", in: active.lines))
        let page = try #require(sgrState(of: "Bravo", in: active.lines)).renderedBackground
        #expect(
            try #require(sgrState(of: "Alpha", in: active.lines)).renderedBackground != page,
            "the premise: the focused row is highlighted")
        #expect(
            active.runs.contains { $0.offsetY == alphaRow },
            "the premise: the focused row breathes while the terminal has the focus")

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        let inactive = try frame(loop, timer)
        let alpha = try #require(sgrState(of: "Alpha", in: inactive.lines)).renderedBackground
        #expect(alpha != page, "the focused row's highlight vanished when the terminal lost focus")
        #expect(
            alpha
                == renderedBackground(
                    of: palette.accent.opacity(ViewConstants.selectedBackground, over: palette.background)),
            "the row should take the still tint an unfocused List gives its selection")
        #expect(inactive.runs.isEmpty, "\(inactive.runs.count) runs left breathing in an inactive window")
        #expect(inactive.activity.animatedClocks.isEmpty)
        #expect(!inactive.activity.usesCursor, "an inactive frame read the focus clock")

        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        let back = try frame(loop, timer)
        #expect(back.runs.contains { $0.offsetY == alphaRow }, "focus-in did not bring the breath back")
    }

    /// The twins, through the run loop, out and back. A `Table` keeps its composed
    /// rows across frames (`TableRowMemoStore`), and a still cursor row was exactly
    /// the kind it kept: the inactive tint, kept while the window was inactive, was
    /// served again after it came back, and the cursor row never breathed again.
    /// Under `.none` it went wrong the other way — the bright end kept while active
    /// was served in the inactive window. The tint is spelled out rather than asked
    /// of the palette, so a row that stopped taking it cannot pass.
    @Test(
        "Focus-out stills a selected cursor row in the unfocused selection's tint; focus-in restores it",
        arguments: ReversedCursorRowTests.Kind.allCases, [TextCursorStyle.Animation.pulse, .none])
    func cursorRowRoundTrip(kind: ReversedCursorRowTests.Kind, style: TextCursorStyle.Animation) throws {
        let app = CursorRowApp(kind: kind, style: style)
        let runner = AppRunner(app: app, appState: AppState())
        let harness = RenderLoopHarness(tuiContext: runner.tuiContext)
        let loop = harness.loop(app)
        let timer = CursorTimer(renderNotifier: harness.appState)
        let palette = CursorRowApp.palette
        let breathes = style != .none

        _ = try frame(loop, timer)
        let active = try frame(loop, timer)
        let cursorRow = try #require(row(of: "row 0", in: active.lines))
        let activeFill = try #require(sgrState(of: "row 0", in: active.lines)).renderedBackground
        #expect(
            active.runs.contains { $0.offsetY == cursorRow } == breathes,
            "the premise: the cursor row breathes while active, unless the style says not to")

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        let inactive = try frame(loop, timer)
        let tint = renderedBackground(
            of: palette.accent.opacity(ViewConstants.selectedBackground, over: palette.background))
        #expect(
            try #require(sgrState(of: "row 0", in: inactive.lines)).renderedBackground == tint,
            "the cursor row should take the still tint an unfocused selection shows")
        #expect(inactive.runs.isEmpty, "\(inactive.runs.count) runs left breathing in an inactive window")

        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        let back = try frame(loop, timer)
        #expect(
            back.runs.contains { $0.offsetY == cursorRow } == breathes,
            "focus-in did not bring the cursor row's breath back")
        if !breathes {
            #expect(
                try #require(sgrState(of: "row 0", in: back.lines)).renderedBackground == activeFill,
                "focus-in left the cursor row in the inactive tint")
        }
    }

    /// A `Picker`'s drop-down (and a field's suggestions, which draw through the
    /// same renderer) is the same idiom as a `Menu` — the two share their palette
    /// and their pulse on purpose — so its highlighted row goes the same way.
    @Test("A drop-down's highlighted row stays, still, in the unfocused selection's tint")
    func dropDownRowSurvives() throws {
        func popup(appearsActive: Bool) -> FrameBuffer {
            let context = makeRenderContext(width: 30, height: 12) { environment, _ in
                environment.appearsActive = appearsActive
            }
            let config = DropdownMenu.Configuration(
                rows: [.option(" Alpha", claims: []), .option(" Bravo", claims: [])],
                highlightedRow: 0, innerWidth: 12, scroll: ScrollAxis(), followHighlight: false,
                autoRepeatToken: "inactive-drop-down")
            return DropdownMenu.popup(
                config, context: context, onHover: { _ in }, onActivate: { _ in }, onDismiss: {})
        }
        let active = popup(appearsActive: true)
        #expect(!active.animatedCells.isEmpty, "the premise: the drop-down breathes while active")

        let inactive = popup(appearsActive: false)
        #expect(inactive.animatedCells.isEmpty, "\(inactive.animatedCells.count) runs left")
        let palette = EnvironmentValues().palette
        let alpha = try #require(sgrState(of: "Alpha", in: inactive.lines)).renderedBackground
        #expect(
            alpha
                == renderedBackground(
                    of: palette.accent.opacity(ViewConstants.selectedBackground, over: palette.background)),
            "the highlighted row should take the still tint an unfocused List gives its selection")
    }

    // MARK: - Every indicator stays

    /// The whole rule, in one place: everything that says where the focus is
    /// stays on screen. A `List` with no selection binding says it with its
    /// cursor row alone, and that row used to go blank in an inactive window —
    /// the same disappearance as the menu's, on the Lists page.
    @Test("A List's cursor row stays while inactive, even with no selection to show")
    func listCursorRowSurvives() {
        func picture(appearsActive: Bool, focused: Bool) -> [String] {
            let context = makeRenderContext(width: 20, height: 6) { environment, _ in
                environment.animationScheduler = AnimationScheduler()
                environment.volatileReadTracker = VolatileReadTracker()
            }
            let list = List {
                ForEach(["alpha", "bravo"], id: \.self) { Text($0) }
            }
            .frame(width: 20, height: 4)
            .environment(\.appearsActive, appearsActive)
            let view = VStack(spacing: 0) {
                if focused {
                    list
                    Button("sibling") {}
                } else {
                    Button("sibling") {}
                    list
                }
            }
            let focus = context.environment.focusManager
            focus?.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focus?.endRenderPass()
            return buffer.lines.filter { !$0.stripped.contains("sibling") }
        }
        let unfocused = picture(appearsActive: true, focused: false)
        #expect(picture(appearsActive: true, focused: true) != unfocused, "the premise: the cursor row shows")
        #expect(
            picture(appearsActive: false, focused: true) != unfocused,
            "an inactive List drew its cursor row as if it had no focus at all")
    }
}
