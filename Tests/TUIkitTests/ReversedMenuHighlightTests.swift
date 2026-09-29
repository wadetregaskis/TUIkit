//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedMenuHighlightTests.swift
//
//  A menu's highlight bar is a fill: the accent between 22% and 50% over the page,
//  breathing. Where the accent or the page has no RGB — `Color.default`, or a colour of
//  the terminal's own that it has not reported — that blend has no RGB between its ends
//  (Opacity as composition §75), so the bar was held at a solid half-strength accent
//  nobody can check the label against, or at the page itself, which says nothing at all:
//  an open menu had no cursor. Such a bar draws reverse video instead, over the
//  palette's own pair so the 7 exchanges those and not the terminal's. The row under the
//  POINTER keeps no fill of its own there — its wash is the page — and says so with its
//  ink instead (§82).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// One focused menu row under one of the shared palettes, as a whole app, for the run
/// loop — the only way to ask what the loop is woken for.
private struct ReversedMenuApp: App {
    var fixture = ReversedMenuHighlightTests.Fixture.slotAccent

    init() {}

    init(fixture: ReversedMenuHighlightTests.Fixture) {
        self.fixture = fixture
    }

    var body: some Scene {
        WindowGroup {
            Button("Open") {}.buttonStyle(_MenuItemButtonStyle()).palette(fixture.palette)
        }
    }
}

@MainActor
@Suite("A menu highlight whose colours the terminal decides")
struct ReversedMenuHighlightTests {

    /// Which colour of the highlight the terminal decides. The two fixtures
    /// `ReversedCursorRowTests` declares, shared for the reason it shares them with the
    /// text inputs: a menu bar and a cursor row are the same highlight in two controls,
    /// and the suites agreeing about what "the terminal's own colours" means is the
    /// point.
    enum Fixture: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// The accent the bar is built from is a slot, over an RGB page.
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

    /// The depths a highlight is spelled at: 24-bit, the 256-colour cube, and the sixteen.
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

    // MARK: - Reading a menu back

    /// Each visible cell of `line` with the SGR state in force on it — the twin of
    /// `ReversedCursorRowTests`'s and `ReversedTextSelectionTests`'s.
    private func cells(_ line: String) -> [(character: Character, state: SGRState)] {
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

    /// What a reversed highlight states: SGR 7 with the palette's ink and page, both
    /// opaque.
    private func reversedPair(_ palette: any Palette) -> SGRState {
        var style = TextStyle()
        style.isInverted = true
        style.foregroundColor = palette.foreground.opaqueSpelling
        style.backgroundColor = palette.background.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// A cell's state with its INK taken off, so two cells that differ only in the
    /// colour of their glyph compare equal.
    ///
    /// What a hover does where its fill cannot be measured is lift the label's ink
    /// (`Palette.hoveredLabel`, pinned by `HoverWithoutAFillTests`); what this suite asks
    /// is whether it also painted a fill, which is the other half of the same cell.
    private func field(_ state: SGRState) -> String {
        var copy = state
        copy.apply("\u{1B}[39m")
        return copy.parameters
    }

    /// The interior cells of a drop-down row: everything between its two walls.
    private func interior(_ line: String) -> [(character: Character, state: SGRState)] {
        let cells = cells(line)
        guard let first = cells.firstIndex(where: { $0.character == "│" }),
            let last = cells.lastIndex(where: { $0.character == "│" }), first < last
        else { return [] }
        return Array(cells[(first + 1)..<last])
    }

    // MARK: - The bar a menu row draws

    /// A focused menu row, rendered twice so the row has taken the keyboard.
    private func menuRow(palette: any Palette, depth: ColorDepth = .truecolor) -> FrameBuffer {
        let context = makeRenderContext(width: 24, height: 2) { environment, _ in
            environment.palette = palette
        }
        let view = Button("Open") {}.buttonStyle(_MenuItemButtonStyle())
        return ColorDepth.withCurrent(depth) {
            _ = renderToBuffer(view, context: context)
            return renderToBuffer(view, context: context)
        }
    }

    /// The row a menu draws under the POINTER, beside the same row at rest. Parked focus
    /// (`FocusSentinel`), so the keyboard's bar is not what is being read.
    private func hoveredMenuRow(palette: any Palette) -> (resting: FrameBuffer, hovered: FrameBuffer) {
        let context = makeRenderContext(width: 24, height: 2) { environment, _ in
            environment.palette = palette
        }
        context.environment.focusManager!.register(FocusSentinel())
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)
        let view = Button("Open") {}.buttonStyle(_MenuItemButtonStyle())
        return ColorDepth.withCurrent(.truecolor) {
            let resting = renderToBuffer(view, context: context)
            dispatcher.setRegions(resting.hitTestRegions)
            _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
            return (resting, renderToBuffer(view, context: context))
        }
    }

    @Test(
        "A focused menu row's bar reverses the palette's pair",
        arguments: Fixture.allCases, Depth.allCases)
    func menuRowBarReverses(_ fixture: Fixture, _ depth: Depth) {
        TerminalColors.withCurrent(.unknown) {
            let palette = fixture.palette
            let line = menuRow(palette: palette, depth: depth.depth).lines.first ?? ""
            let cells = ColorDepth.withCurrent(depth.depth) { self.cells(line) }
            let expected = ColorDepth.withCurrent(depth.depth) { reversedPair(palette) }
            #expect(!cells.isEmpty, "\(fixture), \(depth): no row: \(line.debugDescription)")
            let plain = cells.filter { !$0.state.reversesVideo }
            #expect(
                plain.isEmpty,
                "\(fixture), \(depth): \(plain.map(\.character)) not reversed in \(line.debugDescription)")
            let wrong = cells.filter { $0.state.parameters != expected.parameters }
            #expect(
                wrong.isEmpty,
                """
                \(fixture), \(depth): \(wrong.map { ($0.character, $0.state.parameters) }) \
                is not \(expected.parameters) in \(line.debugDescription)
                """)
        }
    }

    @Test("A reversed menu bar leaves no run", arguments: Fixture.allCases)
    func reversedBarLeavesNoRun(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let drawn = menuRow(palette: fixture.palette)
            #expect(drawn.animatedCells.isEmpty, "\(fixture): \(drawn.animatedCells)")
        }
    }

    @Test("The run loop is asked for no tick", arguments: Fixture.allCases)
    func loopHasNothingToWakeFor(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let harness = RenderLoopHarness()
            let loop = harness.loop(ReversedMenuApp(fixture: fixture))
            let timer = CursorTimer(renderNotifier: harness.appState)
            timer.beginFrameReadTracking()
            _ = loop.render(cursorTimer: timer)
            timer.beginFrameReadTracking()
            let activity = loop.render(cursorTimer: timer)
            #expect(activity.animatedClocks.isEmpty, "\(fixture)")
            #expect(!activity.usesPulse && !activity.usesCursor, "\(fixture)")
        }
    }

    /// The pointer's wash is 32% of the accent over the page, which below half IS the
    /// page (§75): it measures and shows nothing, so the row keeps exactly what it draws
    /// at rest and its label lifts instead (§82, pinned by `HoverWithoutAFillTests`).
    @Test("A hovered menu row states no fill of its own", arguments: Fixture.allCases)
    func hoveredRowHasNoFill(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let frames = hoveredMenuRow(palette: fixture.palette)
            let hovered = cells(frames.hovered.lines.first ?? "")
            let resting = cells(frames.resting.lines.first ?? "")
            #expect(!hovered.isEmpty, "\(fixture): \(frames.hovered.lines)")
            #expect(
                hovered.allSatisfy { !$0.state.reversesVideo },
                "\(fixture): the pointer's row is reversed: \(frames.hovered.lines)")
            #expect(
                hovered.map { field($0.state) } == resting.map { field($0.state) },
                "\(fixture): the pointer added a fill: \(frames.hovered.lines)")
        }
    }

    // MARK: - The bar a drop-down draws

    /// The open drop-down of a menu-style `Picker`, whose highlighted option is the
    /// selected one — `_PickerMenuHandler` starts its highlight there, so the first
    /// option row is both ✓-marked and highlighted. The marker is a child with a reset
    /// of its own, which is the trap a reversal has to survive.
    private func dropdown(
        palette: any Palette, depth: ColorDepth = .truecolor, options: Int = 2,
        overlayContentHeight: Int? = nil
    ) throws -> FrameBuffer {
        let context = makeRenderContext(width: 30, height: 12) { environment, _ in
            environment.palette = palette
            if let overlayContentHeight { environment.overlayContentHeight = overlayContentHeight }
        }
        var choice = AnyHashable("opt-0")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })
        let core = _PickerMenuCore(
            entries: (0..<options).map { index in
                _PickerEntry.option(
                    tag: AnyHashable("opt-\(index)"), label: AnyView(Text("Option \(index)")))
            },
            selection: binding, focusID: "reversed-menu-picker", isDisabled: false)
        return try ColorDepth.withCurrent(depth) {
            _ = renderToBuffer(core, context: context)
            let box: StateBox<_PickerMenuHandler> = context.environment.stateStorage!.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
                default: _PickerMenuHandler(
                    focusID: "reversed-menu-picker", selection: binding, itemValues: [],
                    canBeFocused: true))
            box.value.isOpen = true
            return try #require(renderToBuffer(core, context: context).overlays.first).content
        }
    }

    /// The drop-down's highlighted row: the one carrying the selected option's label.
    private func highlightedRow(_ popup: FrameBuffer) -> String {
        popup.lines.first { $0.stripped.contains("Option 0") } ?? ""
    }

    @Test(
        "An open drop-down's highlighted row reverses the palette's pair",
        arguments: Fixture.allCases, Depth.allCases)
    func dropdownHighlightReverses(_ fixture: Fixture, _ depth: Depth) throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = fixture.palette
            let line = highlightedRow(try dropdown(palette: palette, depth: depth.depth))
            let cells = ColorDepth.withCurrent(depth.depth) { interior(line) }
            let expected = ColorDepth.withCurrent(depth.depth) { reversedPair(palette) }
            #expect(!cells.isEmpty, "\(fixture), \(depth): no row: \(line.debugDescription)")
            let plain = cells.filter { !$0.state.reversesVideo }
            #expect(
                plain.isEmpty,
                "\(fixture), \(depth): \(plain.map(\.character)) not reversed in \(line.debugDescription)")
            // Every cell but the ✓, which states its own accent beside the restated
            // pair: a child that states its own colours reverses ITS pair (§86).
            let wrong = cells.filter { $0.character != "✓" && $0.state.parameters != expected.parameters }
            #expect(
                wrong.isEmpty,
                """
                \(fixture), \(depth): \(wrong.map { ($0.character, $0.state.parameters) }) \
                is not \(expected.parameters) in \(line.debugDescription)
                """)
        }
    }

    @Test("The drop-down's own frame is not reversed", arguments: Fixture.allCases)
    func dropdownChromeIsUntouched(_ fixture: Fixture) throws {
        try TerminalColors.withCurrent(.unknown) {
            let popup = try dropdown(palette: fixture.palette)
            let walls = popup.lines.flatMap { cells($0).filter { "│╭╮╰╯─".contains($0.character) } }
            #expect(!walls.isEmpty, "\(fixture): \(popup.lines.map(\.stripped))")
            #expect(
                walls.allSatisfy { !$0.state.reversesVideo },
                "\(fixture): the border is reversed: \(popup.lines.map(\.stripped))")
        }
    }

    /// The other arm of the renderer: with more options than the window shows, each row
    /// is assembled by hand around the scrollbar's cell rather than by the border helper.
    @Test("A scrolling drop-down reverses its highlighted row too", arguments: Fixture.allCases)
    func scrollingDropdownHighlightReverses(_ fixture: Fixture) throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = fixture.palette
            let popup = try dropdown(palette: palette, options: 20, overlayContentHeight: 8)
            let line = highlightedRow(popup)
            let cells = interior(line)
            #expect(!cells.isEmpty, "\(fixture): \(popup.lines.map(\.stripped))")
            // The scrollbar's own cell is the renderer's, in the bar's colours, and it
            // sits past the content the row reversed.
            let reversed = cells.prefix { $0.state.reversesVideo }
            #expect(
                reversed.count >= "Option 0".count,
                "\(fixture): only \(reversed.count) reversed in \(line.debugDescription)")
        }
    }

    @Test("A reversed drop-down leaves no run", arguments: Fixture.allCases)
    func reversedDropdownLeavesNoRun(_ fixture: Fixture) throws {
        try TerminalColors.withCurrent(.unknown) {
            let popup = try dropdown(palette: fixture.palette)
            #expect(
                !popup.animatedCells.contains { $0.isAnimating },
                "\(fixture): \(popup.animatedCells.count) runs")
        }
    }

    // MARK: - Where the colours measure

    /// Keyed on what measures: once the terminal reports its sixteen, the same slot
    /// accent tints and breathes in the bytes it always did.
    @Test("Once the terminal reports its colours, the highlight is a fill again")
    func reportedColoursFillAgain() throws {
        try TerminalColors.withCurrent(Self.reported) {
            let palette = ReversedRowSlotAccentPalette()
            let bar = menuRow(palette: palette)
            let line = bar.lines.first ?? ""
            #expect(
                cells(line).allSatisfy { !$0.state.reversesVideo && $0.state.namesBackground },
                "\(line.debugDescription)")
            #expect(bar.animatedCells.contains { $0.isAnimating }, "the bar stopped breathing")
            let row = highlightedRow(try dropdown(palette: palette))
            #expect(
                interior(row).allSatisfy { !$0.state.reversesVideo },
                "the drop-down's highlight is reversed: \(row.debugDescription)")
        }
    }

    /// The trigger is the fill's colours, not the terminal's silence.
    @Test("An RGB palette on a silent terminal keeps its tint")
    func rgbPaletteKeepsItsTint() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = SystemPalette(.green)
            let bar = menuRow(palette: palette)
            let line = bar.lines.first ?? ""
            #expect(
                cells(line).allSatisfy { !$0.state.reversesVideo && $0.state.namesBackground },
                "\(line.debugDescription)")
            #expect(bar.animatedCells.contains { $0.isAnimating }, "the bar stopped breathing")
            let row = highlightedRow(try dropdown(palette: palette))
            #expect(
                interior(row).contains { $0.state.namesBackground },
                "the drop-down lost its tint: \(row.debugDescription)")
        }
    }

    /// A reversal changes colours only: the same glyphs in the same cells.
    @Test("A reversed highlight moves no glyph", arguments: Fixture.allCases)
    func glyphsAreWhereTheyWere(_ fixture: Fixture) throws {
        let palette = fixture.palette
        let unknown = TerminalColors.withCurrent(.unknown) {
            (menuRow(palette: palette).lines.map(\.stripped), try? dropdown(palette: palette))
        }
        let reported = TerminalColors.withCurrent(Self.reported) {
            (menuRow(palette: palette).lines.map(\.stripped), try? dropdown(palette: palette))
        }
        #expect(unknown.0 == reported.0, "\(fixture): the bar's glyphs moved")
        let before = try #require(unknown.1).lines.map(\.stripped)
        let after = try #require(reported.1).lines.map(\.stripped)
        #expect(before == after, "\(fixture): the drop-down's glyphs moved")
    }

    // MARK: - A breath with reverse video in it

    /// Per frame of `run`: whether every one of its cells (or the interior's, in a
    /// drop-down) is reversed, whether any is bold, and the fills of the rest.
    private func frames(
        of run: AnimatedCellRun, depth: ColorDepth, interiorOnly: Bool = false
    ) -> (reversed: [Int], bold: [Int], fills: Set<String>) {
        ColorDepth.withCurrent(depth) {
            let states = run.frames.map { frame in (interiorOnly ? interior(frame) : cells(frame)).map(\.state) }
            let reversed = states.indices.filter { !states[$0].isEmpty && states[$0].allSatisfy(\.reversesVideo) }
            let bold = states.indices.filter { states[$0].contains(where: \.isBold) }
            let fills = Set(states.indices.filter { !reversed.contains($0) }.flatMap { states[$0].map(field) })
            return (reversed, bold, fills)
        }
    }

    /// Red Sands on xterm's sixteen: the selected cursor row's breath is (reverse
    /// video, blue), which a menu's bar and a drop-down's highlighted row share.
    private static var redSands: any Palette { PaletteRegistry.palette(withName: "Red Sands")! }

    @Test("On 16 colours a menu row's bar breathes into reverse video on its dim frames, as a list's cursor row does")
    func menuRowBreathesIntoReverseVideo() throws {
        try TerminalColors.withCurrent(.unknown) {
            let drawn = menuRow(palette: Self.redSands, depth: .basic16)
            let run = try #require(drawn.animatedCells.first, "the bar does not breathe")
            let (reversed, _, fills) = frames(of: run, depth: .basic16)
            #expect(reversed == Array(5...11))
            #expect(fills.count == 1, "the other frames fill with B's one slot: \(fills)")
        }
    }

    @Test("Without colour a menu row's bar breathes by weight, reversed throughout")
    func menuRowBreathesByWeight() throws {
        try TerminalColors.withCurrent(.unknown) {
            try TerminalClient.$drawsBoldPin.withValue(true) {
                let drawn = menuRow(palette: PaletteRegistry.all[0], depth: .noColor)
                let run = try #require(drawn.animatedCells.first, "the bar does not breathe")
                let (reversed, bold, _) = frames(of: run, depth: .noColor)
                #expect(reversed == Array(0..<16))
                #expect(bold == [0, 1, 2, 3, 4, 12, 13, 14, 15])
            }
        }
    }

    @Test("On 16 colours a drop-down's highlighted row breathes into reverse video on its dim frames")
    func dropdownBreathesIntoReverseVideo() throws {
        try TerminalColors.withCurrent(.unknown) {
            let popup = try dropdown(palette: Self.redSands, depth: .basic16)
            let row = try #require(popup.lines.firstIndex { $0.stripped.contains("Option 0") })
            let run = try #require(popup.animatedCells.first { $0.offsetY == row }, "the row does not breathe")
            let (reversed, _, fills) = frames(of: run, depth: .basic16, interiorOnly: true)
            #expect(reversed == Array(5...11))
            #expect(!fills.isEmpty)
        }
    }

    @Test("Without colour a drop-down's highlighted row breathes by weight, reversed throughout")
    func dropdownBreathesByWeight() throws {
        try TerminalColors.withCurrent(.unknown) {
            try TerminalClient.$drawsBoldPin.withValue(true) {
                let popup = try dropdown(palette: PaletteRegistry.all[0], depth: .noColor)
                let row = try #require(popup.lines.firstIndex { $0.stripped.contains("Option 0") })
                let run = try #require(popup.animatedCells.first { $0.offsetY == row }, "the row does not breathe")
                let (reversed, bold, _) = frames(of: run, depth: .noColor, interiorOnly: true)
                #expect(reversed == Array(0..<16))
                #expect(bold == [0, 1, 2, 3, 4, 12, 13, 14, 15])
            }
        }
    }
}
