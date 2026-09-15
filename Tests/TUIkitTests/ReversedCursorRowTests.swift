//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedCursorRowTests.swift
//
//  A List's or Table's cursor row draws a fill: the accent at half strength over the
//  page, breathing, or the focus wash. Where the accent, the tier or the page has no
//  RGB — `Color.default`, or a colour of the terminal's own that it has not reported —
//  that fill is the page or a solid colour under content nobody can check (Opacity as
//  composition §75), so the row said nothing about where the cursor was. Such a row
//  draws reverse video instead, over the palette's own pair so the 7 exchanges those
//  and not the terminal's. A selected row that is not the cursor, and an alternating
//  row, have the ● and the cursor row to say what they said, so they are left unfilled.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// An RGB page and ink whose accent is a terminal slot, which has no RGB until the
/// terminal reports its sixteen. The trap the reversal has to survive: the page is a
/// colour the palette paints, so a bare 7 after a child's reset would fill with the
/// terminal's own foreground instead.
struct ReversedRowSlotAccentPalette: Palette {
    let id = "reversed-row-slot-accent"
    let name = "Slot accent"
    let background = Color.rgb(20, 20, 30)
    let foreground = Color.rgb(220, 220, 220)
    let foregroundTertiary = Color.rgb(130, 130, 140)
    let accent = Color.ansi(.blue)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// The page and the ink the terminal decides, with everything else RGB.
private struct ReversedRowTerminalPairPalette: Palette {
    let id = "reversed-row-terminal-pair"
    let name = "Terminal pair"
    let background = Color(value: .terminalBackground)
    let foreground = Color(value: .terminalForeground)
    let foregroundTertiary = Color(value: .terminalForeground)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// An RGB page, ink and accent whose tertiary tier is the terminal's own foreground:
/// the focus wash is 30% of that tier over the page, which below half is the page
/// itself. The fill measures and shows nothing, so the tier it is built from decides.
private struct ReversedRowTerminalTierPalette: Palette {
    let id = "reversed-row-terminal-tier"
    let name = "Terminal tier"
    let background = Color.rgb(20, 20, 30)
    let foreground = Color.rgb(220, 220, 220)
    let foregroundTertiary = Color(value: .terminalForeground)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// A style that turns alternating rows on — no built-in style does, so this is the
/// only way to reach the code that draws them (`ListStyleTests` has the same fixture).
private struct ReversedRowZebraStyle: ListStyle {
    var alternatingRowColors: Bool { true }
    var showsBorder: Bool { true }
    var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
}

/// One control under one of the palettes above, as a whole app, for the run loop.
private struct ReversedRowApp: App {
    var kind = ReversedCursorRowTests.Kind.list
    var fixture = ReversedCursorRowTests.Fixture.slotAccent

    init() {}

    init(kind: ReversedCursorRowTests.Kind, fixture: ReversedCursorRowTests.Fixture) {
        self.kind = kind
        self.fixture = fixture
    }

    var body: some Scene {
        WindowGroup { kind.view(selection: [0, 2]).palette(fixture.palette) }
    }
}

@MainActor
@Suite("A cursor row whose highlight the terminal decides")
struct ReversedCursorRowTests {

    struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
    }

    static let rows = (0..<3).map { Row(id: $0, name: "row \($0)") }

    /// The two twins, which run the same rules about focus and selection from one
    /// place (`RowBackground`) and have drifted apart before.
    enum Kind: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case list, table

        var testDescription: String { rawValue }

        /// The control with `selection` selected. Rendered twice by the caller, so the
        /// control has taken the focus and row 0 is the cursor row.
        @MainActor @ViewBuilder
        func view(selection: Set<Int>) -> some View {
            switch self {
            case .list:
                List(selection: .constant(selection)) {
                    ForEach(0..<3, id: \.self) { Text("row \($0)") }
                }
            case .table:
                Table(ReversedCursorRowTests.rows, selection: .constant(selection)) {
                    TableColumn("Name") { $0.name }
                }
            }
        }
    }

    /// Which colour of the fill the terminal decides.
    enum Fixture: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// The accent the cursor row's breath is built from is a slot, over an RGB page.
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

    /// The depths a row is spelled at: 24-bit, the 256-colour cube, and the sixteen.
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

    // MARK: - Reading a row back

    /// `view` under `palette` at `depth`, rendered twice so the control has the focus.
    private func buffer(
        _ view: some View, palette: any Palette, depth: ColorDepth = .truecolor,
        width: Int = 24, height: Int = 8
    ) -> FrameBuffer {
        let context = makeRenderContext(width: width, height: height) { environment, _ in
            environment.palette = palette
        }
        return ColorDepth.withCurrent(depth) {
            _ = renderToBuffer(view, context: context)
            return renderToBuffer(view, context: context)
        }
    }

    /// Each visible cell of `line` with the SGR state in force on it.
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

    /// The line row `index` is drawn on.
    private func row(_ index: Int, of buffer: FrameBuffer) -> String {
        buffer.lines.first { $0.stripped.contains("row \(index)") } ?? ""
    }

    /// What a reversed row states: SGR 7 with the palette's ink and page, both opaque.
    private func reversedPair(_ palette: any Palette) -> SGRState {
        var style = TextStyle()
        style.isInverted = true
        style.foregroundColor = palette.foreground.opaqueSpelling
        style.backgroundColor = palette.background.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// The cells of a row from its text to the cell before the right border.
    ///
    /// Read from the text rather than from the fill, so the test can fail: a row that
    /// draws no fill at all has the same span, and its cells say so.
    private func rowCells(_ line: String) -> [(character: Character, state: SGRState)] {
        let cells = cells(line)
        guard let text = cells.firstIndex(where: { $0.character == "r" }),
            let border = cells.lastIndex(where: { $0.character == "│" }), text < border
        else { return [] }
        return Array(cells[text..<border])
    }

    /// ``rowCells(_:)`` without the trailing cells in no state at all — the cells the
    /// ROW itself painted.
    ///
    /// A container pads a `Table` row by a cell on each side, and the right one used to
    /// take the fill by BLEED: a persistent background is left in force at the end of a
    /// row's line, where a reversal closes itself with a reset. So the reversal covers
    /// the row's own cells and that pad cell is bare, as the left one always was.
    ///
    /// A row that paints nothing leaves nothing here at all, which is why every caller
    /// asks that the span reach past the text into the row's padding.
    private func fillCells(_ line: String) -> [(character: Character, state: SGRState)] {
        var span = rowCells(line)
        while let last = span.last, last.state.isDefault { span.removeLast() }
        return span
    }

    // MARK: - The cursor row

    @Test(
        "The cursor row of a focused control reverses the palette's pair, padding and all",
        arguments: Kind.allCases, Fixture.allCases)
    func cursorRowReverses(_ kind: Kind, _ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            for depth in Depth.allCases {
                let palette = fixture.palette
                let line = row(0, of: buffer(kind.view(selection: [0, 2]), palette: palette, depth: depth.depth))
                let cells = ColorDepth.withCurrent(depth.depth) { fillCells(line) }
                let expected = ColorDepth.withCurrent(depth.depth) { reversedPair(palette) }
                #expect(!cells.isEmpty, "\(kind), \(fixture), \(depth): no row: \(line.debugDescription)")
                #expect(
                    cells.last?.character == " ",
                    "\(kind), \(fixture), \(depth): the fill stops at the text: \(line.debugDescription)")
                let plain = cells.filter { !$0.state.reversesVideo }
                #expect(
                    plain.isEmpty,
                    "\(kind), \(fixture), \(depth): \(plain.map(\.character)) not reversed in \(line.debugDescription)")
                let wrong = cells.filter { $0.state.parameters != expected.parameters }
                #expect(
                    wrong.isEmpty,
                    """
                    \(kind), \(fixture), \(depth): \(wrong.map { ($0.character, $0.state.parameters) }) \
                    is not \(expected.parameters) in \(line.debugDescription)
                    """)
            }
        }
    }

    @Test("The cursor row keeps its ●", arguments: Kind.allCases, Fixture.allCases)
    func cursorRowKeepsItsMark(_ kind: Kind, _ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let line = row(0, of: buffer(kind.view(selection: [0, 2]), palette: fixture.palette))
            #expect(line.stripped.contains("●"), "\(kind), \(fixture): \(line.debugDescription)")
            let mark = cells(line).first { $0.character == "●" }
            #expect(mark?.state.reversesVideo == true, "\(kind), \(fixture): \(line.debugDescription)")
        }
    }

    /// The trap: a row's content states its own colours and ends in a reset, and its
    /// padding is plain spaces after that. With only the 7 restated those cells would
    /// fill with the TERMINAL's foreground on a page the palette paints.
    @Test("A child's own colours end at its reset, and the padding is the palette's pair")
    func paddingAfterAChildsResetKeepsThePalettesPair() {
        TerminalColors.withCurrent(.unknown) {
            let palette = ReversedRowSlotAccentPalette()
            let view = List(selection: .constant(Set([0]))) {
                ForEach(0..<2, id: \.self) { Text("row \($0)").foregroundStyle(Color.red) }
            }
            let line = row(0, of: buffer(view, palette: palette))
            let cells = fillCells(line)
            let expected = reversedPair(palette)
            // The row's own padding: the run of spaces after its content's last reset,
            // not every space (the one inside "row 0" is the child's, in the child's ink).
            let padding = cells.reversed().prefix { $0.character == " " }
            #expect(padding.count > 1, "\(line.debugDescription)")
            #expect(
                padding.allSatisfy { $0.state.parameters == expected.parameters },
                "padding is not \(expected.parameters): \(line.debugDescription)")
            let text = cells.filter { $0.character != " " }
            #expect(
                text.allSatisfy { $0.state.reversesVideo },
                "the child's own cells are reversed too: \(line.debugDescription)")
        }
    }

    @Test(
        "A cursor row under the cursor alone, with nothing selected, reverses too",
        arguments: Kind.allCases)
    func focusOnlyCursorRowReverses(_ kind: Kind) {
        TerminalColors.withCurrent(.unknown) {
            for palette in [ReversedRowTerminalPairPalette(), ReversedRowTerminalTierPalette()] as [any Palette] {
                let line = row(0, of: buffer(kind.view(selection: []), palette: palette))
                let cells = fillCells(line)
                #expect(!cells.isEmpty, "\(kind), \(palette.id): \(line.debugDescription)")
                #expect(
                    cells.last?.character == " ",
                    "\(kind), \(palette.id): the fill stops at the text: \(line.debugDescription)")
                #expect(
                    cells.allSatisfy { $0.state.reversesVideo },
                    "\(kind), \(palette.id): \(line.debugDescription)")
            }
        }
    }

    /// The trigger is the colours, not the terminal's silence: a wash of an RGB accent
    /// over an RGB page measures, and is drawn as it always was.
    @Test("A measurable focus wash on a silent terminal is still a fill", arguments: Kind.allCases)
    func measurableFocusWashIsUnchanged(_ kind: Kind) {
        TerminalColors.withCurrent(.unknown) {
            let line = row(0, of: buffer(kind.view(selection: []), palette: ReversedRowSlotAccentPalette()))
            let cells = rowCells(line)
            #expect(!cells.isEmpty, "\(kind): \(line.debugDescription)")
            #expect(cells.allSatisfy { !$0.state.reversesVideo }, "\(kind): \(line.debugDescription)")
            #expect(cells.allSatisfy { $0.state.namesBackground }, "\(kind): \(line.debugDescription)")
        }
    }

    // MARK: - The rows that are not the cursor

    @Test("A selected row that is not the cursor draws no fill, and keeps its ●")
    func selectedRowThatIsNotTheCursorHasNoFill() {
        TerminalColors.withCurrent(.unknown) {
            for fixture in Fixture.allCases {
                let line = row(2, of: buffer(Kind.list.view(selection: [0, 2]), palette: fixture.palette))
                let cells = rowCells(line)
                #expect(!cells.isEmpty, "\(fixture): \(line.debugDescription)")
                #expect(
                    cells.allSatisfy { !$0.state.reversesVideo && !$0.state.namesBackground },
                    "\(fixture): \(line.debugDescription)")
                #expect(line.stripped.contains("●"), "\(fixture): \(line.debugDescription)")
            }
        }
    }

    /// Under the slot accent, whose page is RGB: the tint is 15% of a colour the
    /// terminal decides, which below half is the page itself. It measures, and states
    /// the page as a fill that shows nothing — so the tint it is built from decides.
    @Test("An alternating row draws nothing")
    func alternatingRowDrawsNothing() {
        TerminalColors.withCurrent(.unknown) {
            let view = Kind.list.view(selection: []).listStyle(ReversedRowZebraStyle())
            let line = row(2, of: buffer(view, palette: ReversedRowSlotAccentPalette()))
            let cells = rowCells(line)
            #expect(!cells.isEmpty, "\(line.debugDescription)")
            #expect(
                cells.allSatisfy { !$0.state.reversesVideo && !$0.state.namesBackground },
                "\(line.debugDescription)")
        }
    }

    // MARK: - What a steady highlight costs

    @Test("A reversed cursor row leaves no run", arguments: Kind.allCases, Fixture.allCases)
    func reversedRowLeavesNoRun(_ kind: Kind, _ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let drawn = buffer(kind.view(selection: [0, 2]), palette: fixture.palette)
            #expect(drawn.animatedCells.isEmpty, "\(kind), \(fixture): \(drawn.animatedCells)")
        }
    }

    @Test("The run loop is asked for no tick", arguments: Kind.allCases, Fixture.allCases)
    func loopHasNothingToWakeFor(_ kind: Kind, _ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let harness = RenderLoopHarness()
            let loop = harness.loop(ReversedRowApp(kind: kind, fixture: fixture))
            let timer = CursorTimer(renderNotifier: harness.appState)
            timer.beginFrameReadTracking()
            _ = loop.render(cursorTimer: timer)
            timer.beginFrameReadTracking()
            let activity = loop.render(cursorTimer: timer)
            #expect(activity.animatedClocks.isEmpty, "\(kind), \(fixture)")
            #expect(!activity.usesPulse && !activity.usesCursor, "\(kind), \(fixture)")
        }
    }

    // MARK: - Where the colours measure

    /// Keyed on what measures: once the terminal reports its sixteen, the same slot
    /// accent breathes in the bytes it always did.
    @Test("Once the terminal reports its colours, the cursor row breathes again",
        arguments: Kind.allCases)
    func reportedColoursBreatheAsBefore(_ kind: Kind) {
        TerminalColors.withCurrent(Self.reported) {
            let palette = ReversedRowSlotAccentPalette()
            let drawn = buffer(kind.view(selection: [0, 2]), palette: palette)
            let line = row(0, of: drawn)
            #expect(
                fillCells(line).allSatisfy { !$0.state.reversesVideo }, "\(kind): \(line.debugDescription)")
            let runs = drawn.animatedCells.filter(\.isAnimating)
            #expect(!runs.isEmpty, "\(kind): \(drawn.animatedCells)")
            let (dim, bright) = palette.accentFillPulse()
            let frames = Set(runs.flatMap(\.frames).flatMap { cells($0).map(\.state.parameters) })
            for end in [dim, bright] {
                var state = SGRState()
                state.apply(ANSIRenderer.backgroundCode(for: end))
                #expect(
                    frames.contains { $0.hasSuffix(state.parameters) },
                    "\(kind): \(state.parameters) is not among \(frames)")
            }
        }
    }

    /// The trigger is the fill's colours, not the terminal's silence.
    @Test("An RGB palette on a silent terminal keeps its tint", arguments: Kind.allCases)
    func rgbPaletteKeepsItsTint(_ kind: Kind) {
        TerminalColors.withCurrent(.unknown) {
            let drawn = buffer(kind.view(selection: [0, 2]), palette: SystemPalette(.green))
            let line = row(0, of: drawn)
            #expect(
                fillCells(line).allSatisfy { !$0.state.reversesVideo && $0.state.namesBackground },
                "\(kind): \(line.debugDescription)")
            let runs = drawn.animatedCells.filter(\.isAnimating)
            #expect(!runs.isEmpty, "\(kind): \(drawn.animatedCells)")
        }
    }

    // MARK: - The picture

    /// A reversal changes colours only, so every glyph and every width is where it was.
    /// Recorded with `TUIKIT_RECORD_SNAPSHOTS=1`, as the corpus in `SnapshotCorpusTests`
    /// is; a moved glyph shows up as a diff against the committed grid.
    @Test("A reversed cursor row moves no glyph")
    func snapshots() {
        TerminalColors.withCurrent(.unknown) {
            for kind in Kind.allCases {
                let context = makeRenderContext(width: 24, height: 6) { environment, _ in
                    environment.palette = ReversedRowSlotAccentPalette()
                }
                let view = kind.view(selection: [0, 2])
                ColorDepth.withCurrent(.truecolor) {
                    _ = renderToBuffer(view, context: context)
                    assertSnapshot(
                        "\(kind.rawValue)-cursor-row-unmeasurable",
                        of: renderToScreen(view, context: context))
                }
            }
        }
    }
}
