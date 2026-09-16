//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedDateComponentTests.swift
//
//  A focused `DatePicker` marks the component the arrow keys are on with a block: the
//  accent between 22% and 50% over the page, breathing, with the field's text punched out
//  of it. Where the accent or the page has no RGB — `Color.default`, or a colour of the
//  terminal's own that it has not reported — that blend has no RGB between its ends
//  (Opacity as composition §75), so the block was a solid half-strength accent under text
//  nobody can check for contrast, or the page itself, which marks nothing at all: you
//  could not see which component you were about to change. Such a cell reverses the
//  palette's own pair instead — STATED beside the 7, never a bare one, which would
//  exchange the terminal's defaults and collapse to dark-on-dark on a mid-tone theme.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A focused date field under one of the shared palettes, as a whole app, for the run
/// loop — the only way to ask what the loop is woken for.
private struct ReversedDateComponentApp: App {
    var fixture = ReversedDateComponentTests.Fixture.slotAccent

    init() {}

    init(fixture: ReversedDateComponentTests.Fixture) {
        self.fixture = fixture
    }

    var body: some Scene {
        WindowGroup {
            DatePicker(
                selection: .constant(ReversedDateComponentTests.instant),
                displayedComponents: .date
            ) {
                EmptyView()
            }
            .palette(fixture.palette)
        }
    }
}

@MainActor
@Suite("A date field's active component on colours the terminal decides")
struct ReversedDateComponentTests {

    /// One fixed instant, so the field's text never depends on the day the suite runs.
    /// Which digits it shows does not matter here — every case reads the field by the
    /// SHAPE of `YYYY-MM-DD`, whose first four cells are the component the arrows are on.
    static let instant = Date(timeIntervalSince1970: 1_772_000_000)

    /// Which colour of the block the terminal decides. The fixtures
    /// `ReversedCursorRowTests` declares, shared as the menu and text-input suites share
    /// them: the same highlight in another control, and one answer about what "the
    /// terminal's own colours" means.
    enum Fixture: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// A mid-tone RGB page whose accent is a slot — the case a bare SGR 7 would get
        /// wrong, by exchanging the terminal's defaults rather than this page.
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

    /// The depths a block is spelled at: 24-bit, the 256-colour cube, and the sixteen.
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

    /// How many cells the active component occupies: the year, `YYYY`.
    private static let activeCells = 4

    // MARK: - Reading the field back

    /// Each visible cell of `line` with the SGR state in force on it — the twin of
    /// `ReversedCursorRowTests`'s.
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

    /// What a reversed component states: SGR 7 with the palette's ink and page beside it,
    /// both opaque, and the underline the field draws on every editable component.
    private func reversedPair(_ palette: any Palette) -> SGRState {
        var style = TextStyle()
        style.isInverted = true
        style.isUnderlined = true
        style.foregroundColor = palette.foreground.opaqueSpelling
        style.backgroundColor = palette.background.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// A focused date field: the first focusable auto-focuses under `makeRenderContext`,
    /// so the arrows are on the year and it is drawn as the active component.
    private func field(palette: any Palette, depth: ColorDepth = .truecolor) -> String {
        let context = makeRenderContext(width: 24, height: 2) { environment, _ in
            environment.palette = palette
        }
        let view = DatePicker(selection: .constant(Self.instant), displayedComponents: .date) {
            EmptyView()
        }
        return ColorDepth.withCurrent(depth) {
            renderToBuffer(view, context: context).lines.first ?? ""
        }
    }

    /// The whole buffer, for the cases that ask what it left behind.
    private func buffer(palette: any Palette) -> FrameBuffer {
        let context = makeRenderContext(width: 24, height: 2) { environment, _ in
            environment.palette = palette
        }
        let view = DatePicker(selection: .constant(Self.instant), displayedComponents: .date) {
            EmptyView()
        }
        return ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }
    }

    // MARK: - The active component

    @Test(
        "The active component reverses the palette's pair",
        arguments: Fixture.allCases, Depth.allCases)
    func activeComponentReverses(_ fixture: Fixture, _ depth: Depth) {
        TerminalColors.withCurrent(.unknown) {
            let palette = fixture.palette
            let line = field(palette: palette, depth: depth.depth)
            let cells = ColorDepth.withCurrent(depth.depth) { self.cells(line) }
            let expected = ColorDepth.withCurrent(depth.depth) { reversedPair(palette) }
            #expect(
                cells.count >= Self.activeCells,
                "\(fixture), \(depth): no field: \(line.debugDescription)")
            let active = cells.prefix(Self.activeCells)
            let plain = active.filter { !$0.state.reversesVideo }
            #expect(
                plain.isEmpty,
                "\(fixture), \(depth): \(plain.map(\.character)) not reversed in \(line.debugDescription)")
            let wrong = active.filter { $0.state.parameters != expected.parameters }
            #expect(
                wrong.isEmpty,
                """
                \(fixture), \(depth): \(wrong.map { ($0.character, $0.state.parameters) }) \
                is not \(expected.parameters) in \(line.debugDescription)
                """)
        }
    }

    /// The trap this site has always named: a bare 7 exchanges the colours IN FORCE, which
    /// after a reset are the TERMINAL's own pair — on a mid-tone theme that collapses to
    /// dark-on-dark. Both colours are stated beside the 7, so what is exchanged is the
    /// palette's pair.
    @Test("The reversal is never a bare SGR 7", arguments: Fixture.allCases, Depth.allCases)
    func reversalStatesItsPair(_ fixture: Fixture, _ depth: Depth) {
        TerminalColors.withCurrent(.unknown) {
            let line = field(palette: fixture.palette, depth: depth.depth)
            #expect(
                !line.contains("\u{1B}[7m"),
                "\(fixture), \(depth): a bare 7 in \(line.debugDescription)")
            let active = ColorDepth.withCurrent(depth.depth) { cells(line) }.prefix(Self.activeCells)
            #expect(
                active.allSatisfy { $0.state.reversesVideo },
                "\(fixture), \(depth): not reversed in \(line.debugDescription)")
            // A page the PALETTE paints must be named beside the 7: that is the case a bare
            // 7 gets wrong, by exchanging the terminal's own pair instead of this one. Where
            // the palette's pair IS the terminal's, 39 and 49 are its correct spelling and
            // `SGRState` normalises them back to "no named colour" — so there is nothing to
            // name there, and a bare 7 would have been right by accident.
            guard fixture == .slotAccent else { return }
            #expect(
                active.allSatisfy { $0.state.namesBackground },
                "\(fixture), \(depth): the 7 states no field: \(line.debugDescription)")
        }
    }

    /// Only the component the arrows are on: the rest of the field is drawn as it always
    /// was, which is what makes the reversal say where you are.
    @Test("The other components are not reversed", arguments: Fixture.allCases)
    func onlyTheActiveComponentReverses(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let line = field(palette: fixture.palette)
            let rest = cells(line).dropFirst(Self.activeCells)
            #expect(!rest.isEmpty, "\(fixture): \(line.debugDescription)")
            #expect(
                rest.allSatisfy { !$0.state.reversesVideo },
                "\(fixture): \(line.debugDescription)")
        }
    }

    @Test("A reversed component leaves no run", arguments: Fixture.allCases)
    func reversedComponentLeavesNoRun(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let drawn = buffer(palette: fixture.palette)
            #expect(drawn.animatedCells.isEmpty, "\(fixture): \(drawn.animatedCells)")
        }
    }

    @Test("The run loop is asked for no tick", arguments: Fixture.allCases)
    func loopHasNothingToWakeFor(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let harness = RenderLoopHarness()
            let loop = harness.loop(ReversedDateComponentApp(fixture: fixture))
            let timer = CursorTimer(renderNotifier: harness.appState)
            timer.beginFrameReadTracking()
            _ = loop.render(cursorTimer: timer)
            timer.beginFrameReadTracking()
            let activity = loop.render(cursorTimer: timer)
            #expect(activity.animatedClocks.isEmpty, "\(fixture)")
            #expect(!activity.usesPulse && !activity.usesCursor, "\(fixture)")
        }
    }

    // MARK: - Where the colours measure

    /// Keyed on what measures: once the terminal reports its sixteen, the same slot accent
    /// is a block again, and it breathes.
    @Test("Once the terminal reports its colours, the block is a fill again")
    func reportedColoursFillAgain() {
        TerminalColors.withCurrent(Self.reported) {
            let palette = ReversedRowSlotAccentPalette()
            let drawn = buffer(palette: palette)
            let line = drawn.lines.first ?? ""
            let active = cells(line).prefix(Self.activeCells)
            #expect(
                active.allSatisfy { !$0.state.reversesVideo && $0.state.namesBackground },
                "\(line.debugDescription)")
            #expect(drawn.animatedCells.contains { $0.isAnimating }, "the block stopped breathing")
        }
    }

    /// The trigger is the block's colours, not the terminal's silence.
    @Test("An RGB palette on a silent terminal keeps its block")
    func rgbPaletteKeepsItsBlock() {
        TerminalColors.withCurrent(.unknown) {
            let drawn = buffer(palette: SystemPalette(.green))
            let line = drawn.lines.first ?? ""
            let active = cells(line).prefix(Self.activeCells)
            #expect(
                active.allSatisfy { !$0.state.reversesVideo && $0.state.namesBackground },
                "\(line.debugDescription)")
            #expect(drawn.animatedCells.contains { $0.isAnimating }, "the block stopped breathing")
        }
    }

    /// A reversal changes colours only: the same digits in the same cells.
    @Test("A reversed component moves no glyph", arguments: Fixture.allCases)
    func glyphsAreWhereTheyWere(_ fixture: Fixture) {
        let palette = fixture.palette
        let unknown = TerminalColors.withCurrent(.unknown) { field(palette: palette).stripped }
        let reported = TerminalColors.withCurrent(Self.reported) { field(palette: palette).stripped }
        #expect(unknown == reported, "\(fixture): \(unknown.debugDescription)")
    }
}
