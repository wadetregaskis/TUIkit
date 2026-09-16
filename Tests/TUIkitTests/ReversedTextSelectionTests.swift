//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedTextSelectionTests.swift
//
//  A text input's selection is a tint: the accent at 60% over the field. Its block
//  caret is a fill too — the caret's own colour, with the character punched out of it
//  in the field. Where the tint, the caret's colour or the field has no RGB —
//  `Color.default`, or a colour of the terminal's own that it has not reported — every
//  share of such a blend is one end or the other (Opacity as composition §75), so the
//  selection was a solid accent under text nobody can check, or the field itself, which
//  shows nothing at all. A selection like that reverses the field's own pair instead,
//  and a block caret reverses the cell it sits on: the blink alternates, and a pulse,
//  having no phase left to breathe, holds.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A text selection and a caret whose colours the terminal decides")
struct ReversedTextSelectionTests {

    /// Which colour of the highlight the terminal decides. Both fixtures are the row
    /// tests' (`ReversedCursorRowTests`), which ask the same question of a `List`.
    enum Fixture: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// The accent the selection is a share of is a slot, over an RGB field.
        case slotAccent
        /// The page and the ink are the terminal's own, and so is the field derived
        /// from them.
        case terminalPair

        var testDescription: String { rawValue }

        var palette: any Palette {
            switch self {
            case .slotAccent: ReversedRowSlotAccentPalette()
            case .terminalPair: ReversedRowTerminalPairPalette()
            }
        }
    }

    /// The depths a cell is spelled at: 24-bit, the 256-colour cube, and the sixteen.
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

    // MARK: - Reading a field back

    /// Each visible cell of `line` with the SGR state in force on it — the twin of
    /// `ReversedCursorRowTests`'s, which reads a row's cells rather than a field's.
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

    /// What a reversed cell states: SGR 7 with the pair beside it, both opaque.
    private func reversedPair(ink: Color, field: Color) -> SGRState {
        var style = TextStyle()
        style.isInverted = true
        style.foregroundColor = ink.opaqueSpelling
        style.backgroundColor = field.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state
    }

    /// The well a field paints its content on.
    private func surface(_ palette: any Palette) -> Color {
        palette.fieldBackground.resolve(with: palette)
    }

    /// A focused field's content, through the renderer a `TextField` and a `SecureField`
    /// share: "abcdef", with `selection` selected and the caret at `cursor`.
    private func field(
        palette: any Palette, cursor: Int = 0, selection: Range<Int>? = 1..<4,
        cursorStyle: TextCursorStyle = TextCursorStyle(shape: .bar, animation: .none),
        ink: Color? = nil, depth: ColorDepth = .truecolor
    ) -> TextFieldContentRenderer.FieldContent {
        let renderer = TextFieldContentRenderer(
            prompt: nil, isDisabled: false, displayCharacter: { $0 },
            surface: surface(palette), contentForeground: ink)
        return ColorDepth.withCurrent(depth) {
            renderer.buildContent(
                text: "abcdef", cursorPosition: cursor, selectionRange: selection,
                isFocused: true, palette: palette,
                cursorStyle: cursorStyle, cursorTimer: nil, contentWidth: 12)
        }
    }

    /// A focused editor over "abcdef" with "bcd" selected by a leftward drag, as
    /// `TextEditorAlphaTests.dragLeftAcrossBCD` makes one: the caret ends on "b", which
    /// is itself selected.
    private func editorBuffer(
        palette: any Palette,
        cursorStyle: TextCursorStyle = TextCursorStyle(shape: .block, animation: .none)
    ) -> FrameBuffer {
        let context = makeRenderContext(width: 20, height: 3) { environment, _ in
            environment.palette = palette
        }
        let view = TextEditor(text: .constant("abcdef")).textCursor(cursorStyle)
            .frame(width: 20, height: 3)
        _ = renderToBuffer(view, context: context)
        if let handler = context.environment.focusManager?.activeSection?.focusables
            .compactMap({ $0 as? TextEditorHandler }).first
        {
            handler.moveCursor(toLine: 0, column: 4)
            handler.selectionAnchor = handler.cursor
            handler.startOrExtendSelection()
            handler.moveCursor(toLine: 0, column: 1)
        }
        return renderToBuffer(view, context: context)
    }

    // MARK: - The selection

    @Test(
        "A selection whose tint the terminal decides reverses the field's own pair",
        arguments: Fixture.allCases, Depth.allCases)
    func selectionReverses(_ fixture: Fixture, _ depth: Depth) {
        TerminalColors.withCurrent(.unknown) {
            let palette = fixture.palette
            let content = field(palette: palette, depth: depth.depth)
            let selected = cells(content.line).filter { "bcd".contains($0.character) }
            #expect(
                selected.count == 3,
                "\(fixture), \(depth): no selection in \(content.line.debugDescription)")
            let expected = ColorDepth.withCurrent(depth.depth) {
                reversedPair(ink: palette.foreground, field: surface(palette))
            }
            let wrong = selected.filter { $0.state.parameters != expected.parameters }
            #expect(
                wrong.isEmpty,
                """
                \(fixture), \(depth): \(wrong.map { ($0.character, $0.state.parameters) }) \
                is not \(expected.parameters) in \(content.line.debugDescription)
                """)
        }
    }

    @Test("Only the selected cells are reversed", arguments: Fixture.allCases)
    func onlyTheSelectionReverses(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let others = cells(field(palette: fixture.palette).line)
                .filter { !"bcd".contains($0.character) }
            #expect(!others.isEmpty, "\(fixture): nothing outside the selection")
            #expect(
                others.allSatisfy { !$0.state.reversesVideo },
                "\(fixture): \(others.filter { $0.state.reversesVideo }.map(\.character))")
        }
    }

    /// A reversal exchanges the CELL's own pair, so a field whose ink the style cascade
    /// overrode (`.textFieldTextStyle`) reverses that ink and not the palette's.
    @Test("A cascade's own ink is what a reversed selection exchanges")
    func cascadeInkIsReversed() {
        TerminalColors.withCurrent(.unknown) {
            let palette = ReversedRowSlotAccentPalette()
            let ink = Color.rgb(10, 200, 90)
            let selected = cells(field(palette: palette, ink: ink).line)
                .filter { "bcd".contains($0.character) }
            let expected = reversedPair(ink: ink, field: surface(palette))
            #expect(selected.count == 3, "no selection")
            #expect(
                selected.allSatisfy { $0.state.parameters == expected.parameters },
                "\(selected.map(\.state.parameters)) is not \(expected.parameters)")
        }
    }

    // MARK: - The block caret

    @Test("A block caret reverses the cell under it", arguments: Fixture.allCases)
    func blockCaretReverses(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let palette = fixture.palette
            let content = field(
                palette: palette, cursor: 0, selection: nil,
                cursorStyle: TextCursorStyle(shape: .block, animation: .none))
            let caret = cells(content.line).first { $0.character == "a" }
            let expected = reversedPair(ink: palette.foreground, field: surface(palette))
            #expect(
                caret?.state.parameters == expected.parameters,
                "\(fixture): \(caret?.state.parameters ?? "no caret cell") is not \(expected.parameters)")
        }
    }

    @Test("A blinking block caret alternates the cell's reversal", arguments: Fixture.allCases)
    func blinkingBlockCaretAlternates(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let content = field(
                palette: fixture.palette, cursor: 0, selection: nil,
                cursorStyle: TextCursorStyle(shape: .block, animation: .blink))
            let frames = content.caret?.frames ?? []
            #expect(!frames.isEmpty, "\(fixture): a blinking caret left no run")
            let reversed = frames.map { frame in
                cells(frame).allSatisfy { $0.state.reversesVideo }
            }
            #expect(
                reversed.contains(true) && reversed.contains(false),
                "\(fixture): every frame reversed \(reversed.first ?? false): \(frames.map(\.debugDescription))")
        }
    }

    /// A breath between two equal ends is still (§79), and its ends are equal exactly
    /// where the caret's colour or the field has no RGB — the same condition that makes
    /// the block reverse. So a pulsing caret holds its reversal and leaves no run.
    @Test("A pulsing block caret holds, reversed, and leaves no run", arguments: Fixture.allCases)
    func pulsingBlockCaretHolds(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let content = field(
                palette: fixture.palette, cursor: 0, selection: nil,
                cursorStyle: TextCursorStyle(shape: .block, animation: .pulse))
            #expect(content.caret == nil, "\(fixture): \(String(describing: content.caret))")
            #expect(
                cells(content.line).first { $0.character == "a" }?.state.reversesVideo == true,
                "\(fixture): \(content.line.debugDescription)")
        }
    }

    /// Two reversals read as none, and that is the point: the caret's cell stands out
    /// against its reversed neighbours exactly as a terminal's own cursor does over a
    /// selection.
    @Test("A block caret on a reversed selection un-reverses its own cell", arguments: Fixture.allCases)
    func blockCaretOnAReversedSelection(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let drawn = cells(
                field(
                    palette: fixture.palette, cursor: 1, selection: 1..<4,
                    cursorStyle: TextCursorStyle(shape: .block, animation: .none)
                ).line)
            // Every closure below is hoisted out of its `#expect` on purpose. A closure
            // inside a macro expansion and one in ordinary source, in the same enclosing
            // closure, are lowered to a SINGLE SIL function — so one of the two bodies
            // never runs. Do not fold these back into the `#expect`s; see
            // Tools/CompilerBugs/MacroClosureDiscriminatorCollision.
            let caret = drawn.first { $0.character == "b" }
            #expect(
                caret?.state.reversesVideo == false,
                "\(fixture): the caret's cell is reversed with its neighbours")
            let rest = drawn.filter { "cd".contains($0.character) }
            let restIsReversed = rest.allSatisfy { $0.state.reversesVideo }
            #expect(
                rest.count == 2 && restIsReversed,
                "\(fixture): the rest of the selection is not reversed")
        }
    }

    /// Only the block draws a fill nobody can check. A bar or an underscore draws its
    /// glyph in the caret's own colour, which a slot states perfectly well.
    @Test("A bar or underscore caret is unchanged", arguments: Fixture.allCases)
    func otherCaretShapesAreUnchanged(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            for shape in [TextCursorStyle.Shape.bar, .underscore] {
                let content = field(
                    palette: fixture.palette, cursor: 0, selection: nil,
                    cursorStyle: TextCursorStyle(shape: shape, animation: .none))
                #expect(
                    cells(content.line).allSatisfy { !$0.state.reversesVideo },
                    "\(fixture), \(shape): \(content.line.debugDescription)")
            }
        }
    }

    // MARK: - The editor

    @Test(
        "An editor's selection reverses, and its block caret un-reverses its own cell",
        arguments: Fixture.allCases)
    func editorSelectionReverses(_ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let row = ColorDepth.withCurrent(.truecolor) {
                editorBuffer(palette: fixture.palette).lines.first ?? ""
            }
            let drawn = cells(row)
            let selected = drawn.filter { "cd".contains($0.character) }
            #expect(
                selected.count == 2 && selected.allSatisfy { $0.state.reversesVideo },
                "\(fixture): the selection is not reversed in \(row.debugDescription)")
            #expect(
                drawn.first { $0.character == "b" }?.state.reversesVideo == false,
                "\(fixture): the caret's cell is reversed in \(row.debugDescription)")
            #expect(
                drawn.first { $0.character == "e" }?.state.reversesVideo == false,
                "\(fixture): an unselected cell is reversed in \(row.debugDescription)")
        }
    }

    // MARK: - Where the colours measure

    /// Keyed on what measures: once the terminal reports its sixteen and its pair, the
    /// same field paints the tint it always did.
    @Test(
        "Once the terminal reports its colours, the field is drawn as before",
        arguments: Fixture.allCases)
    func reportedColoursAreUnchanged(_ fixture: Fixture) {
        TerminalColors.withCurrent(Self.reported) {
            let content = field(
                palette: fixture.palette, cursor: 0, selection: 1..<4,
                cursorStyle: TextCursorStyle(shape: .block, animation: .none))
            let drawn = cells(content.line)
            // Hoisted out of the `#expect`s — see `blockCaretOnAReversedSelection` above
            // and Tools/CompilerBugs/MacroClosureDiscriminatorCollision.
            let noneReversed = drawn.allSatisfy { !$0.state.reversesVideo }
            #expect(noneReversed, "\(fixture): \(content.line.debugDescription)")
            let selected = drawn.filter { "bcd".contains($0.character) }
            let selectionNamesBackground = selected.allSatisfy { $0.state.namesBackground }
            #expect(
                selected.count == 3 && selectionNamesBackground,
                "\(fixture): the selection states no fill in \(content.line.debugDescription)")
        }
    }

    @Test("Once the terminal reports its colours, the editor is drawn as before")
    func editorReportedColoursAreUnchanged() {
        TerminalColors.withCurrent(Self.reported) {
            let drawn = ColorDepth.withCurrent(.truecolor) {
                editorBuffer(palette: ReversedRowSlotAccentPalette())
            }
            for line in drawn.lines {
                let reversed = cells(line).filter { $0.state.reversesVideo }
                #expect(reversed.isEmpty, "\(reversed.map(\.character)) in \(line.debugDescription)")
            }
        }
    }

    /// The trigger is the fill's colours, never the terminal's silence: an RGB palette
    /// on a host that answered nothing keeps its tint.
    @Test("An RGB palette on a silent terminal keeps its tint")
    func rgbPaletteKeepsItsTint() {
        TerminalColors.withCurrent(.unknown) {
            let content = field(
                palette: SystemPalette(.green), cursor: 0, selection: 1..<4,
                cursorStyle: TextCursorStyle(shape: .block, animation: .none))
            let drawn = cells(content.line)
            // Hoisted out of the `#expect`s — see `blockCaretOnAReversedSelection` above
            // and Tools/CompilerBugs/MacroClosureDiscriminatorCollision.
            let noneReversed = drawn.allSatisfy { !$0.state.reversesVideo }
            #expect(noneReversed, "\(content.line.debugDescription)")
            let selected = drawn.filter { "bcd".contains($0.character) }
            let selectionNamesBackground = selected.allSatisfy { $0.state.namesBackground }
            #expect(
                selected.count == 3 && selectionNamesBackground,
                "the selection states no fill in \(content.line.debugDescription)")
        }
    }
}
