//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextEditorCellWidthTests.swift
//
//  TextEditor's display model must be measured in terminal CELLS, not
//  characters — the cells-not-characters bug class. An emoji or CJK character
//  occupies two cells, so caret placement, click mapping, vertical motion's
//  column preservation, the horizontal scroll window, and the row width all
//  desynchronise from the screen if the model counts characters. TextField
//  was fixed with per-character display widths; these pin the TextEditor
//  sibling. `TabLayout` is the shared charIndex ↔ displayColumn seam, so most
//  of the surface is pinned there, with render-level tests for the row walk.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A mutable string backing a test `Binding`.
private final class StringSink: @unchecked Sendable {
    var value: String
    init(_ value: String = "") { self.value = value }
    var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("TextEditor cell-width (emoji/CJK) display model")
struct TextEditorCellWidthTests {

    // MARK: - TabLayout: the charIndex ↔ displayColumn seam

    @Test(
        "displayColumn advances by each character's cell width",
        arguments: [
            // (line, charIndex, tabInterval, expectedDisplayColumn)
            ("中文abc", 0, 4, 0),
            ("中文abc", 1, 4, 2),  // after 中 (2 cells)
            ("中文abc", 2, 4, 4),  // after 中文
            ("中文abc", 5, 4, 7),  // end of line
            ("🍎b", 1, 4, 2),  // after the apple
            ("a🍎b", 3, 4, 4),  // 1 + 2 + 1
            // A wide char before a tab shifts the stop the tab lands on:
            // 🍎 (2 cells) → tab advances 2→4 → x at 4.
            ("🍎\tx", 2, 4, 4),
            ("🍎\tx", 3, 4, 5),
        ])
    func displayColumnCountsCells(line: String, charIndex: Int, interval: Int, expected: Int) {
        #expect(
            TabLayout.displayColumn(
                ofCharIndex: charIndex, in: Array(line), tabWidth: .periodic(interval)) == expected)
    }

    @Test(
        "charIndex maps any cell within a wide character's span to that character",
        arguments: [
            // (line, displayColumn, expectedCharIndex)
            ("中文ab", 0, 0),
            ("中文ab", 1, 0),  // second cell of 中 → still 中
            ("中文ab", 2, 1),
            ("中文ab", 3, 1),  // second cell of 文 → still 文
            ("中文ab", 4, 2),  // 'a'
            ("中文ab", 5, 3),  // 'b'
            ("中文ab", 6, 4),  // past the end → insertion point
            ("中文ab", 99, 4),
        ])
    func charIndexMapsCellSpans(line: String, displayColumn: Int, expected: Int) {
        #expect(
            TabLayout.charIndex(
                forDisplayColumn: displayColumn, in: Array(line), tabWidth: .periodic(4)) == expected)
    }

    // MARK: - Render: row geometry

    @Test("Rows containing wide characters are exactly the content width")
    func rowsAreExactlyContentWidth() {
        let sink = StringSink("🍎🍎🍎 pie\nplain line")
        let buffer = renderToBuffer(
            TextEditor(text: sink.binding), context: makeRenderContext(width: 14, height: 3))
        #expect(buffer.width == 14)
        for (index, line) in buffer.lines.enumerated() {
            #expect(
                line.strippedLength == 14,
                "row \(index) is \(line.strippedLength) cells: '\(line.stripped)'")
        }
    }

    @Test("Wide-char rows stay exact when the scrollbar column is present")
    func wideRowsWithScrollbarStayExact() {
        let sink = StringSink((1...9).map { _ in "中文 line" }.joined(separator: "\n"))
        let buffer = renderToBuffer(
            TextEditor(text: sink.binding), context: makeRenderContext(width: 12, height: 4))
        #expect(buffer.width == 12)
        for (index, line) in buffer.lines.enumerated() {
            #expect(
                line.strippedLength == 12,
                "row \(index) is \(line.strippedLength) cells: '\(line.stripped)'")
        }
    }

    // MARK: - Render: caret placement

    @Test("A bar caret on a wide character replaces its first cell and pads the rest")
    func barCaretOnWideChar() {
        // Caret on 中 (char 1 of "a中b"): the bar glyph takes 中's first cell,
        // the second pads with a space so 'b' stays at cell 3 — exactly
        // TextField's rule. A character-counted model draws "a▎b" and shifts
        // everything after the caret one cell left.
        let sink = StringSink("a中b")
        let context = makeRenderContext(width: 10, height: 1) { env, _ in
            env.textCursorStyle = TextCursorStyle(shape: .bar, animation: .none)
        }
        _ = renderToBuffer(TextEditor(text: sink.binding), context: context)
        guard let handler = context.environment.focusManager?.currentFocused as? TextEditorHandler
        else {
            Issue.record("editor did not take focus")
            return
        }
        handler.moveCursor(toLine: 0, column: 1)
        let buffer = renderToBuffer(TextEditor(text: sink.binding), context: context)
        #expect(
            buffer.lines[0].stripped.hasPrefix("a▎ b"),
            "caret covers the wide char's span: '\(buffer.lines[0].stripped)'")
        #expect(buffer.lines[0].strippedLength == 10)
    }

    @Test("The caret after CJK text sits at the cell column, not the character index")
    func caretAfterCJKAtCellColumn() {
        let sink = StringSink("中文")
        let context = makeRenderContext(width: 10, height: 1) { env, _ in
            env.textCursorStyle = TextCursorStyle(shape: .bar, animation: .none)
        }
        _ = renderToBuffer(TextEditor(text: sink.binding), context: context)
        guard let handler = context.environment.focusManager?.currentFocused as? TextEditorHandler
        else {
            Issue.record("editor did not take focus")
            return
        }
        handler.moveCursor(toLine: 0, column: 2)  // end of line
        let buffer = renderToBuffer(TextEditor(text: sink.binding), context: context)
        let stripped = buffer.lines[0].stripped
        #expect(stripped.hasPrefix("中文▎"), "'\(stripped)'")
        #expect(buffer.lines[0].strippedLength == 10, "row stays exactly 10 cells")
    }

    // MARK: - Vertical motion

    @Test("Up/Down preserve the VISUAL column across wide-character lines")
    func verticalMotionPreservesVisualColumn() {
        // End of "中文中文" is char 4 = display column 8. Moving down into an
        // ASCII line must land at char 8 (the same screen column), not char 4.
        let sink = StringSink("中文中文\nabcdefghij")
        let context = makeRenderContext(width: 14, height: 3)
        _ = renderToBuffer(TextEditor(text: sink.binding), context: context)
        guard let handler = context.environment.focusManager?.currentFocused as? TextEditorHandler
        else {
            Issue.record("editor did not take focus")
            return
        }
        handler.moveCursor(toLine: 0, column: 4)
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.cursorLine == 1)
        #expect(handler.cursorColumn == 8, "same visual column, got char \(handler.cursorColumn)")

        // And back up: char 8 of the ASCII line is display column 8, which is
        // char 4 of the CJK line again.
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.cursorLine == 0)
        #expect(handler.cursorColumn == 4, "round-trips, got char \(handler.cursorColumn)")
    }

    // MARK: - Click mapping

    @Test(
        "A click maps screen cells to the character whose span contains them",
        arguments: [
            // (clickX, expectedCursorColumn) on "中文ab"
            (0, 0),
            (1, 0),  // second cell of 中
            (2, 1),
            (3, 1),  // second cell of 文
            (4, 2),  // 'a'
            (5, 3),  // 'b'
        ])
    func clickMapsCellsToChar(clickX: Int, expected: Int) {
        let sink = StringSink("中文ab")
        // The context's OWN dispatcher (RenderContext(tuiContext:) wires the
        // services from its backing TUIContext — a foreign one would never
        // see the editor's region handler).
        let context = makeRenderContext(width: 12, height: 1)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        let buffer = renderToBuffer(TextEditor(text: sink.binding), context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: clickX, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: clickX, y: 0))
        guard let handler = context.environment.focusManager?.currentFocused as? TextEditorHandler
        else {
            Issue.record("click did not focus the editor")
            return
        }
        #expect(
            handler.cursorColumn == expected,
            "click at cell \(clickX) → char \(handler.cursorColumn)")
    }

    // MARK: - Horizontal scroll window

    @Test("A scroll window edge straddling a wide character keeps the row exact")
    func scrollWindowClipsStraddledWideChar() {
        // A long CJK line with the caret at its end: the window starts
        // mid-line; whatever character straddles the left edge must render as
        // a pad cell (it can't be shown half), and every row stays exactly
        // the content width.
        let sink = StringSink(String(repeating: "中", count: 12))
        let context = makeRenderContext(width: 9, height: 1)
        _ = renderToBuffer(TextEditor(text: sink.binding), context: context)
        guard let handler = context.environment.focusManager?.currentFocused as? TextEditorHandler
        else {
            Issue.record("editor did not take focus")
            return
        }
        handler.moveCursor(toLine: 0, column: 12)  // end: display column 24
        let buffer = renderToBuffer(TextEditor(text: sink.binding), context: context)
        #expect(
            buffer.lines[0].strippedLength == 9,
            "scrolled row is exactly 9 cells: '\(buffer.lines[0].stripped)' (\(buffer.lines[0].strippedLength))")
        #expect(buffer.lines[0].stripped.contains("中"), "the visible tail shows content")
    }
}
