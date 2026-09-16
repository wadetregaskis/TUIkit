//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedSplitDividerTests.swift
//
//  A `NavigationSplitView`'s divider says it holds the keyboard by filling its whole
//  column: the accent between 22% and 50% over the page, breathing. Where the accent or
//  the page has no RGB — `Color.default`, or a colour of the terminal's own that it has
//  not reported — that blend has no RGB between its ends (Opacity as composition §75), so
//  the fill was a solid half-strength accent, or the page itself, which says nothing at
//  all: a focused divider looked exactly like a resting one, and the arrow keys resized a
//  column with no sign of which. Such a divider reverses the palette's own pair instead.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A split view under one of the shared palettes, as a whole app, for the run loop.
private struct ReversedSplitDividerApp: App {
    var fixture = ReversedSplitDividerTests.Fixture.slotAccent

    init() {}

    init(fixture: ReversedSplitDividerTests.Fixture) {
        self.fixture = fixture
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
                .palette(fixture.palette)
        }
    }
}

@MainActor
@Suite("A split divider's focus fill on colours the terminal decides")
struct ReversedSplitDividerTests {

    /// Which colour of the fill the terminal decides — the fixtures
    /// `ReversedCursorRowTests` declares, shared as the menu, text-input and date-field
    /// suites share them.
    enum Fixture: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// An RGB page whose accent is a slot.
        case slotAccent
        /// The page and the ink are the terminal's own.
        case terminalPair

        var testDescription: String { rawValue }

        var palette: any Palette {
            switch self {
            case .slotAccent: ReversedRowSlotAccentPalette()
            case .terminalPair: ReversedRowTerminalPairPalette()
            }
        }
    }

    /// The depths a fill is spelled at.
    enum Depth: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case truecolor, palette256, basic16

        var testDescription: String { rawValue }

        var depth: ColorDepth {
            switch self {
            case .truecolor: .truecolor
            case .palette256: .palette256
            case .basic16: .basic16
            }
        }
    }

    /// Apple Terminal "Basic"'s sixteen, with One Dark's pair, so a slot measures.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52),
        slots: TerminalColors.Slots(UnreportedANSISlotTests.appleBasic))

    private var split: some View {
        NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
    }

    // MARK: - Reading the divider back

    private func context(palette: any Palette) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = palette
        return RenderContext(
            availableWidth: 40, availableHeight: 8, environment: environment,
            tuiContext: TUIContext())
    }

    /// One render pass, bracketed as the run loop brackets it.
    private func frame(_ view: some View, _ context: RenderContext) -> FrameBuffer {
        let states = context.environment.stateStorage!
        let focus = context.environment.focusManager!
        states.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        states.endRenderPass()
        return buffer
    }

    /// The split with its divider holding the keyboard, at `depth`.
    private func focusedSplit(palette: any Palette, depth: ColorDepth = .truecolor) throws
        -> FrameBuffer
    {
        let context = context(palette: palette)
        let focus = try #require(context.environment.focusManager)
        return try ColorDepth.withCurrent(depth) {
            _ = frame(split, context)
            let section = try #require(dividerSectionID(in: focus))
            focus.activateSection(id: section)
            return frame(split, context)
        }
    }

    private func cellStates(_ line: String) -> [(character: Character, state: SGRState)] {
        var state = SGRState()
        var result: [(character: Character, state: SGRState)] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let character): result.append((character, state))
            }
        }
        return result
    }

    /// What a reversed divider states: SGR 7 with the palette's ink and page, both opaque.
    private func reversedPair(_ palette: any Palette) -> SGRState {
        var style = TextStyle()
        style.isInverted = true
        style.foregroundColor = palette.foreground.opaqueSpelling
        style.backgroundColor = palette.background.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// The divider's column, found by the grip glyphs it draws.
    private func dividerColumn(in drawn: FrameBuffer) -> Int? {
        (cells(of: "◦", in: drawn) + cells(of: "◀", in: drawn)).first?.column
    }

    /// Every cell of the divider's column, top to bottom.
    private func column(_ drawn: FrameBuffer, at column: Int) -> [SGRState] {
        drawn.lines.compactMap { line in
            let cells = cellStates(line)
            return cells.indices.contains(column) ? cells[column].state : nil
        }
    }

    // MARK: - The focused divider

    @Test(
        "A focused divider reverses the palette's pair down its column",
        arguments: Fixture.allCases, Depth.allCases)
    func focusedDividerReverses(_ fixture: Fixture, _ depth: Depth) throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = fixture.palette
            let drawn = try focusedSplit(palette: palette, depth: depth.depth)
            let index = try #require(dividerColumn(in: drawn), "\(drawn.lines.map(\.stripped))")
            let states = ColorDepth.withCurrent(depth.depth) { column(drawn, at: index) }
            let expected = ColorDepth.withCurrent(depth.depth) { reversedPair(palette) }
            #expect(!states.isEmpty, "\(fixture), \(depth): no divider")
            let plain = states.filter { !$0.reversesVideo }
            #expect(
                plain.isEmpty,
                "\(fixture), \(depth): \(plain.count) of \(states.count) cells not reversed")
            let wrong = states.filter { $0.parameters != expected.parameters }
            #expect(
                wrong.isEmpty,
                "\(fixture), \(depth): \(wrong.map(\.parameters)) is not \(expected.parameters)")
        }
    }

    @Test("A resting divider is not reversed", arguments: Fixture.allCases)
    func restingDividerIsUntouched(_ fixture: Fixture) throws {
        try TerminalColors.withCurrent(.unknown) {
            let drawn = frame(split, context(palette: fixture.palette))
            let index = try #require(dividerColumn(in: drawn), "\(drawn.lines.map(\.stripped))")
            #expect(
                column(drawn, at: index).allSatisfy { !$0.reversesVideo },
                "\(fixture): a resting divider is reversed")
        }
    }

    @Test("A reversed divider leaves no run", arguments: Fixture.allCases)
    func reversedDividerLeavesNoRun(_ fixture: Fixture) throws {
        try TerminalColors.withCurrent(.unknown) {
            let drawn = try focusedSplit(palette: fixture.palette)
            #expect(
                !drawn.animatedCells.contains { $0.isAnimating },
                "\(fixture): \(drawn.animatedCells.count) runs")
        }
    }

    @Test("The run loop is asked for no tick", arguments: Fixture.allCases)
    func loopHasNothingToWakeFor(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let harness = RenderLoopHarness()
            let loop = harness.loop(ReversedSplitDividerApp(fixture: fixture))
            let timer = CursorTimer(renderNotifier: harness.appState)
            timer.beginFrameReadTracking()
            _ = loop.render(cursorTimer: timer)
            if let section = dividerSectionID(in: harness.focusManager) {
                harness.focusManager.activateSection(id: section)
            }
            timer.beginFrameReadTracking()
            let activity = loop.render(cursorTimer: timer)
            #expect(activity.animatedClocks.isEmpty, "\(fixture)")
            #expect(!activity.usesPulse && !activity.usesCursor, "\(fixture)")
        }
    }

    // MARK: - Where the colours measure

    @Test("Once the terminal reports its colours, the divider fills again")
    func reportedColoursFillAgain() throws {
        try TerminalColors.withCurrent(Self.reported) {
            let drawn = try focusedSplit(palette: ReversedRowSlotAccentPalette())
            let index = try #require(dividerColumn(in: drawn))
            #expect(
                column(drawn, at: index).allSatisfy { !$0.reversesVideo },
                "the divider is reversed once its colours are known")
            #expect(drawn.animatedCells.contains { $0.isAnimating }, "the divider stopped breathing")
        }
    }

    /// The trigger is the fill's colours, not the terminal's silence.
    @Test("An RGB palette on a silent terminal keeps its fill")
    func rgbPaletteKeepsItsFill() throws {
        try TerminalColors.withCurrent(.unknown) {
            let drawn = try focusedSplit(palette: SystemPalette(.green))
            let index = try #require(dividerColumn(in: drawn))
            let states = column(drawn, at: index)
            #expect(states.allSatisfy { !$0.reversesVideo }, "an RGB divider is reversed")
            #expect(states.contains { $0.namesBackground }, "an RGB divider lost its fill")
            #expect(drawn.animatedCells.contains { $0.isAnimating }, "the divider stopped breathing")
        }
    }

    /// A reversal changes colours only: the grip is where it was.
    @Test("A reversed divider moves no glyph", arguments: Fixture.allCases)
    func glyphsAreWhereTheyWere(_ fixture: Fixture) throws {
        let palette = fixture.palette
        let unknown = TerminalColors.withCurrent(.unknown) {
            (try? focusedSplit(palette: palette))?.lines.map(\.stripped)
        }
        let reported = TerminalColors.withCurrent(Self.reported) {
            (try? focusedSplit(palette: palette))?.lines.map(\.stripped)
        }
        #expect(try #require(unknown) == (try #require(reported)), "\(fixture): the grip moved")
    }
}
