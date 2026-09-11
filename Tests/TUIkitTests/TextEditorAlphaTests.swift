//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorAlphaTests.swift
//
//  A `TextEditor` under a faded palette: its rows, its blank rows and its caret
//  state their colours' alpha as claims beside opaque bytes, as a focused
//  `TextField`'s content does (§61). Before, its first frame trapped in a debug
//  build.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A text editor under a faded palette")
struct TextEditorAlphaTests {

    /// A context under `palette`, with a focus manager of its own when `focused` — so
    /// the editor, the only thing registering, takes the focus — and none otherwise.
    private func context(
        palette: any Palette, width: Int, height: Int, focused: Bool
    ) -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = palette
        environment.applyRuntimeServices(from: tuiContext)
        if focused { environment.focusManager = FocusManager() }
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
    }

    /// An unfocused editor over `text`.
    private func unfocused(
        _ text: String, palette: any Palette = FadedAll(), width: Int = 20, height: Int = 6,
        disabled: Bool = false
    ) -> FrameBuffer {
        renderToBuffer(
            TextEditor(text: .constant(text)).disabled(disabled).frame(width: width, height: height),
            context: context(palette: palette, width: width, height: height, focused: false))
    }

    /// A focused editor over `text`, drawn after `place` has put its caret and any
    /// selection: rendered once to register it, which focuses it, then again.
    private func focused(
        _ text: String, palette: any Palette = FadedAll(), cursor: TextCursorStyle = TextCursorStyle(),
        width: Int = 20, height: Int = 4, place: (TextEditorHandler) -> Void = { _ in }
    ) throws -> FrameBuffer {
        let context = context(palette: palette, width: width, height: height, focused: true)
        let view = TextEditor(text: .constant(text)).textCursor(cursor).frame(width: width, height: height)
        _ = renderToBuffer(view, context: context)
        let handler = try #require(
            context.environment.focusManager?.activeSection?.focusables
                .compactMap { $0 as? TextEditorHandler }.first,
            "no editor handler registered")
        place(handler)
        return renderToBuffer(view, context: context)
    }

    /// The well an editor paints its rows on.
    private func well(_ palette: any Palette) -> Color {
        palette.fieldBackground.resolve(with: palette)
    }

    /// A leftward drag across "bcd", as `TextEditorTests.dragSelect` makes one: the
    /// caret ends on "b", and "b" through "d" are selected.
    private func dragLeftAcrossBCD(_ handler: TextEditorHandler) {
        handler.moveCursor(toLine: 0, column: 4)
        handler.selectionAnchor = handler.cursor
        handler.startOrExtendSelection()
        handler.moveCursor(toLine: 0, column: 1)
    }

    // MARK: - Unfocused

    /// The probe that trapped: an overflowing editor. Every cell left of the bar owes
    /// the text as ink and the well as field — text and padding alike — and no row's
    /// claim reaches the bar's column.
    @Test("An overflowing editor's rows owe the text and the well")
    func rowsClaim() throws {
        let palette = FadedAll()
        try #require(!palette.foreground.isOpaque && !well(palette).isOpaque, "the premise")
        let drawn = unfocused((0..<30).map { "line \($0)" }.joined(separator: "\n"))
        let bar = drawn.width - 1
        var wrong: [String] = []
        for row in 0..<drawn.height {
            for column in 0..<bar {
                let owes = owed(atColumn: column, row: row, in: drawn)
                if owes.ink != owed(palette.foreground) || owes.field != owed(well(palette)) {
                    wrong.append("(\(column), \(row)): \(owes)")
                }
            }
        }
        #expect(wrong.isEmpty, "cells owing the wrong alphas: \(wrong.prefix(8))")
        let onTheBar = drawn.opacityRegions.filter { $0.offsetX < bar && $0.offsetX + $0.width > bar }
        #expect(onTheBar.isEmpty, "a row's claim reaches the bar: \(onTheBar)")
    }

    /// Rows past the text are blank, painted in the well: they owe its alpha as a
    /// field, and no ink, since nothing is drawn in them.
    @Test("An editor's blank rows owe the well and no ink")
    func blankRowsClaimTheWell() {
        let palette = FadedAll()
        let drawn = unfocused("one", height: 4)
        for row in 1..<4 {
            for column in [0, 10, 19] {
                let owes = owed(atColumn: column, row: row, in: drawn)
                #expect(owes.ink == 1 && owes.field == owed(well(palette)), "(\(column), \(row)) owes \(owes)")
            }
        }
    }

    /// The bytes state the opaque spelling; the claims carry the alpha.
    @Test("An editor's bytes spell its colours opaque")
    func bytesAreOpaque() {
        withColorDepth(.truecolor) {
            let palette = FadedAll()
            let drawn = unfocused("one", height: 4)
            #expect(
                drawn.lines[0].contains(code(palette.foreground.opaqueSpelling, palette)),
                "\(drawn.lines[0].debugDescription)")
        }
    }

    /// Disabled, the editor paints no well: its text claims its tint's alpha as ink and
    /// no field, and the blank rows below it claim nothing.
    @Test("A disabled editor claims its text's alpha and nothing else")
    func disabledClaimsItsText() throws {
        let palette = FadedAll()
        try #require(!palette.foregroundTertiary.isOpaque, "the premise")
        let drawn = unfocused("alpha", height: 3, disabled: true)
        for column in [0, 4, 10, 19] {
            let owes = owed(atColumn: column, row: 0, in: drawn)
            #expect(owes.ink == owed(palette.foregroundTertiary) && owes.field == 1, "(\(column), 0) owes \(owes)")
        }
        for row in 1..<3 {
            let owes = owed(atColumn: 5, row: row, in: drawn)
            #expect(owes.ink == 1 && owes.field == 1, "(5, \(row)) owes \(owes)")
        }
    }

    // MARK: - Focused

    /// The caret on a character, on a tab of two cells and of four, on a wide glyph and
    /// past the end, in every shape and animation. Nothing traps; every run replays
    /// onto the drawn cells; every row is the editor's width; the caret's cell owes no
    /// ink; the cell after it owes the text and the well. The caret's own FIELD is not
    /// asserted: it is open (§61.2).
    @Test("A focused editor's caret draws, and claims only around itself")
    func caretsClaimAroundThemselves() throws {
        let palette = FadedAll()
        // The caret's column, as a character index and as a cell, and its own width.
        let cases: [(text: String, column: Int, cell: Int, cells: Int)] = [
            ("ab\tcd\nend", 2, 2, 1),  // a two-cell tab: the caret takes its first cell
            ("\tab", 0, 0, 1),  // a four-cell tab
            ("a中b", 1, 1, 2),  // a wide glyph
            ("end", 3, 3, 1),  // past the end
        ]
        for shape in TextCursorStyle.Shape.allCases {
            for animation in TextCursorStyle.Animation.allCases {
                for (text, column, cell, cells) in cases {
                    let label = "\(shape) \(animation) \(text.debugDescription)"
                    let drawn = try focused(
                        text, palette: palette, cursor: TextCursorStyle(shape: shape, animation: animation)
                    ) { $0.moveCursor(toLine: 0, column: column) }
                    #expect(
                        drawn.lines.allSatisfy { $0.strippedLength == 20 },
                        "\(label): row widths \(drawn.lines.map(\.strippedLength))")
                    expectReplayIsIdentity(drawn, "\(label): a run moved the cells")
                    #expect(owed(atColumn: cell, row: 0, in: drawn).ink == 1, "\(label): the caret owes ink")
                    let after = owed(atColumn: cell + cells, row: 0, in: drawn)
                    #expect(
                        after.ink == owed(palette.foreground) && after.field == owed(well(palette)),
                        "\(label): the cell after the caret owes \(after)")
                }
            }
        }
    }

    /// A selection's cells owe its text's alpha over the highlight's opaque field; the
    /// caret on the selection owes no ink; the cell before it owes the text and the well.
    @Test("An editor's selection claims its text over an opaque highlight")
    func selectionClaims() throws {
        let palette = FadedAll()
        let selection = TextFieldContentRenderer.selectionColors(palette: palette, background: well(palette))
        try #require(selection.background.isOpaque && !selection.foreground.isOpaque, "the premise")
        let drawn = try focused("abcdef\nsecond", palette: palette, place: dragLeftAcrossBCD)
        for column in [2, 3] {
            let owes = owed(atColumn: column, row: 0, in: drawn)
            #expect(owes.ink == owed(selection.foreground) && owes.field == 1, "selected (\(column), 0) owes \(owes)")
        }
        #expect(owed(atColumn: 1, row: 0, in: drawn).ink == 1, "the caret owes ink")
        let before = owed(atColumn: 0, row: 0, in: drawn)
        #expect(before.ink == owed(palette.foreground) && before.field == owed(well(palette)), "(0, 0) owes \(before)")
    }

    /// Scrolled sideways past a tab, with a wide glyph straddling the window's left
    /// edge: the glyph's visible cell is drawn as a space in its colours and claimed,
    /// and every cell but the caret's owes the text and the well.
    @Test("A scrolled editor claims what it drew")
    func scrolledClaimsWhatItDrew() throws {
        let palette = FadedAll()
        // Cells: the tab 0..<4, the x's 4..<24, 😀 24..<26, the tab 26..<28, the y's
        // 28..<44, and the caret at 44. Twenty cells wide, the window is 25..<45.
        let long = "\t" + String(repeating: "x", count: 20) + "😀\t" + String(repeating: "y", count: 16)
        let drawn = try focused(long + "\nshort", palette: palette, height: 2) {
            $0.moveCursor(toLine: 0, column: long.count)
        }
        #expect(drawn.lines[0].stripped.first == " ", "row 0: '\(drawn.lines[0].stripped)'")
        let caret = 19
        for row in 0..<2 {
            for column in 0..<20 where !(row == 0 && column == caret) {
                let owes = owed(atColumn: column, row: row, in: drawn)
                #expect(
                    owes.ink == owed(palette.foreground) && owes.field == owed(well(palette)),
                    "(\(column), \(row)) owes \(owes)")
            }
        }
    }

    // MARK: - The control

    /// Under an opaque palette nothing is claimed — focused, overflowing, with a
    /// selection — so a claim at full strength, or a fixture that failed to fade,
    /// cannot pass the tests above for the wrong reason.
    @Test("An opaque palette's editor claims nothing")
    func opaqueClaimsNothing() throws {
        let palette = SystemPalette.default
        let selection = TextFieldContentRenderer.selectionColors(palette: palette, background: well(palette))
        try #require(
            palette.foreground.isOpaque && well(palette).isOpaque && palette.accent.isOpaque
                && selection.foreground.isOpaque && selection.background.isOpaque,
            "the premise")
        let drawn = try focused(
            (0..<30).map { "line \($0)" }.joined(separator: "\n"), palette: palette, height: 6,
            place: dragLeftAcrossBCD)
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }
}
