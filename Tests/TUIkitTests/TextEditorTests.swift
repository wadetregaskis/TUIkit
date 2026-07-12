//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextEditorTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A mutable string backing a test `Binding`.
private final class StringSink: @unchecked Sendable {
    var value: String
    init(_ value: String = "") { self.value = value }
    var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

/// Coverage for ``TextEditor``: the two-dimensional editing model
/// (``TextEditorHandler``) and the windowed, cursor-following render.
@MainActor
@Suite("TextEditor")
struct TextEditorTests {

    private func handler(_ sink: StringSink) -> TextEditorHandler {
        TextEditorHandler(focusID: "e", text: sink.binding)
    }

    // MARK: - Editing model

    @Test("Typing inserts characters and advances the cursor")
    func typing() {
        let sink = StringSink()
        let editor = handler(sink)
        for character in "hi" { _ = editor.handleKeyEvent(KeyEvent(key: .character(character))) }
        #expect(sink.value == "hi")
        #expect(editor.cursorLine == 0)
        #expect(editor.cursorColumn == 2)
    }

    @Test("Enter splits the current line")
    func enterSplits() {
        let sink = StringSink("ab")
        let editor = handler(sink)
        editor.cursorColumn = 1
        _ = editor.handleKeyEvent(KeyEvent(key: .enter))
        #expect(sink.value == "a\nb")
        #expect(editor.cursorLine == 1)
        #expect(editor.cursorColumn == 0)
    }

    @Test("Backspace at column 0 joins the previous line")
    func backspaceJoinsLines() {
        let sink = StringSink("a\nb")
        let editor = handler(sink)
        editor.cursorLine = 1
        editor.cursorColumn = 0
        _ = editor.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(sink.value == "ab")
        #expect(editor.cursorLine == 0)
        #expect(editor.cursorColumn == 1)
    }

    @Test("Delete at line end joins the next line")
    func deleteJoinsLines() {
        let sink = StringSink("a\nb")
        let editor = handler(sink)
        editor.cursorLine = 0
        editor.cursorColumn = 1
        _ = editor.handleKeyEvent(KeyEvent(key: .delete))
        #expect(sink.value == "ab")
    }

    @Test("Up/Down preserve the desired column across a short line")
    func verticalMotionKeepsColumn() {
        let sink = StringSink("long line\nx\nanother")
        let editor = handler(sink)
        // Ctrl-E moves to the end of the current line (Home/End now span the
        // whole field). "long line" is 9 characters, so this sets desired = 9.
        _ = editor.handleKeyEvent(KeyEvent(key: .character("e"), ctrl: true))  // column 9, desired 9
        _ = editor.handleKeyEvent(KeyEvent(key: .down))  // "x" (len 1) → column clamps to 1
        #expect(editor.cursorLine == 1)
        #expect(editor.cursorColumn == 1)
        _ = editor.handleKeyEvent(KeyEvent(key: .down))  // "another" (len 7) → desired 9 → column 7
        #expect(editor.cursorLine == 2)
        #expect(editor.cursorColumn == 7)
    }

    @Test("Left/Right wrap across line boundaries")
    func horizontalWrap() {
        let sink = StringSink("ab\ncd")
        let editor = handler(sink)
        editor.cursorLine = 1
        editor.cursorColumn = 0
        _ = editor.handleKeyEvent(KeyEvent(key: .left))  // wraps to end of "ab"
        #expect(editor.cursorLine == 0)
        #expect(editor.cursorColumn == 2)
        _ = editor.handleKeyEvent(KeyEvent(key: .right))  // wraps back to start of "cd"
        #expect(editor.cursorLine == 1)
        #expect(editor.cursorColumn == 0)
    }

    @Test("Multi-line paste inserts the pasted lines")
    func multilinePaste() {
        let sink = StringSink("AB")
        let editor = handler(sink)
        editor.cursorColumn = 1
        _ = editor.handleKeyEvent(KeyEvent(key: .paste("x\ny")))
        #expect(sink.value == "Ax\nyB")
        #expect(editor.cursorLine == 1)
        #expect(editor.cursorColumn == 1)
    }

    @Test("Backspace at the very start is a no-op")
    func backspaceAtStart() {
        let sink = StringSink("abc")
        let editor = handler(sink)
        editor.cursorColumn = 0
        _ = editor.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(sink.value == "abc")
    }

    // MARK: - Rendering

    @Test("Renders multiple lines within the viewport")
    func rendersLines() {
        let sink = StringSink("one\ntwo\nthree")
        let text = renderToBuffer(
            TextEditor(text: sink.binding), context: makeRenderContext(width: 12, height: 5)
        ).lines.map { $0.stripped }.joined(separator: "\n")
        #expect(text.contains("one"))
        #expect(text.contains("two"))
        #expect(text.contains("three"))
    }

    @Test("The editor paints a field background by default")
    func fieldBackground() {
        let sink = StringSink("hi")
        let raw = renderToBuffer(
            TextEditor(text: sink.binding), context: makeRenderContext(width: 12, height: 3)
        ).lines.joined()
        // A background SGR (48;…) is the field tint that makes it read as a field.
        #expect(raw.contains("48;"))
    }

    @Test("An overflowing editor shows a vertical scroll indicator")
    func overflowScrollIndicator() {
        let sink = StringSink((1...20).map { "line \($0)" }.joined(separator: "\n"))
        let buffer = renderToBuffer(
            TextEditor(text: sink.binding), context: makeRenderContext(width: 12, height: 5))
        // The scrollbar is reserved WITHIN the frame, so the size is unchanged.
        #expect(buffer.width == 12)
        #expect(buffer.height == 5)
        // The trailing column carries a scrollbar block glyph (▀▁…█) — which a
        // non-overflowing editor would not have.
        let blocks = Set("▀▁▂▃▄▅▆▇█")
        let hasBar = buffer.lines.contains { ($0.stripped.last.map(blocks.contains) ?? false) }
        #expect(hasBar, "an overflowing editor should show a scrollbar cell")
    }

    @Test("A focused editor shows a block cursor")
    func focusedShowsCursor() {
        let sink = StringSink("hi")
        let buffer = renderToBuffer(
            TextEditor(text: sink.binding), context: makeRenderContext(width: 12, height: 3))
        // The cursor cell is a coloured block → an SGR escape appears in the raw output.
        #expect(buffer.lines.joined().contains("\u{1B}["))
        #expect(buffer.height == 3)
    }

    @Test("The editor honours the .textCursor shape like TextField")
    func editorHonoursCursorStyle() {
        // A static (non-animated) thin caret draws its shape glyph at the
        // caret cell — the same `.textCursor(_:)` setting that styles
        // TextField styles the editor.
        // The editor's caret starts at the text's beginning, so the shape
        // glyph replaces the first cell.
        let sink = StringSink("hi")
        for (shape, glyph) in [
            (TextCursorStyle.Shape.underscore, "▁"), (.bar, "│"),
        ] {
            let context = makeRenderContext(width: 12, height: 3) { env, _ in
                env.textCursorStyle = TextCursorStyle(shape: shape, animation: .none)
            }
            let buffer = renderToBuffer(TextEditor(text: sink.binding), context: context)
            let firstLine = buffer.lines[0].stripped
            #expect(firstLine.hasPrefix("\(glyph)i"), "\(shape): |\(firstLine)|")
        }

        // The block shape keeps the underlying character legible (an
        // inverted cell, not a solid glyph) — no shape glyph in the text.
        let blockContext = makeRenderContext(width: 12, height: 3) { env, _ in
            env.textCursorStyle = TextCursorStyle(shape: .block, animation: .none)
        }
        let block = renderToBuffer(TextEditor(text: sink.binding), context: blockContext)
        #expect(block.lines[0].stripped.hasPrefix("hi "), "|\(block.lines[0].stripped)|")
    }

    // MARK: - Standard / Emacs key bindings

    /// A Ctrl+letter chord, as the terminal parser delivers it.
    private func ctrl(_ character: Character) -> KeyEvent {
        KeyEvent(key: .character(character), ctrl: true)
    }

    /// An Option/Alt+letter chord.
    private func alt(_ character: Character) -> KeyEvent {
        KeyEvent(key: .character(character), alt: true)
    }

    @Test("Home/End span the whole field, not the line")
    func homeEndSpanField() {
        let sink = StringSink("first\nmiddle\nlast")
        let editor = handler(sink)
        editor.cursorLine = 1
        editor.cursorColumn = 3
        _ = editor.handleKeyEvent(KeyEvent(key: .end))
        #expect(editor.cursorLine == 2)  // last line
        #expect(editor.cursorColumn == 4)  // end of "last"
        _ = editor.handleKeyEvent(KeyEvent(key: .home))
        #expect(editor.cursorLine == 0)
        #expect(editor.cursorColumn == 0)
    }

    @Test("Ctrl-A / Ctrl-E move to the line's start / end")
    func ctrlAEMoveWithinLine() {
        let sink = StringSink("one\ntwo three\nfour")
        let editor = handler(sink)
        editor.cursorLine = 1
        editor.cursorColumn = 4
        _ = editor.handleKeyEvent(ctrl("a"))
        #expect(editor.cursorLine == 1)
        #expect(editor.cursorColumn == 0)
        _ = editor.handleKeyEvent(ctrl("e"))
        #expect(editor.cursorLine == 1)
        #expect(editor.cursorColumn == 9)  // "two three"
    }

    @Test("Ctrl-B/F/P/N mirror the arrow keys")
    func ctrlBFPNMotion() {
        let sink = StringSink("ab\ncd")
        let editor = handler(sink)
        editor.cursorLine = 1
        editor.cursorColumn = 0
        _ = editor.handleKeyEvent(ctrl("b"))  // wraps to end of "ab"
        #expect(editor.cursorLine == 0)
        #expect(editor.cursorColumn == 2)
        _ = editor.handleKeyEvent(ctrl("f"))  // wraps back to start of "cd"
        #expect(editor.cursorLine == 1)
        #expect(editor.cursorColumn == 0)
        _ = editor.handleKeyEvent(ctrl("n"))  // already the last line: no-op
        #expect(editor.cursorLine == 1)
        _ = editor.handleKeyEvent(ctrl("p"))  // up to the first line
        #expect(editor.cursorLine == 0)
    }

    @Test("Ctrl-D deletes forward")
    func ctrlDDeletesForward() {
        let sink = StringSink("abc")
        let editor = handler(sink)
        editor.cursorColumn = 1
        _ = editor.handleKeyEvent(ctrl("d"))
        #expect(sink.value == "ac")
        #expect(editor.cursorColumn == 1)
    }

    @Test("Ctrl-K kills to end of line, Ctrl-Y yanks it back")
    func killAndYank() {
        let sink = StringSink("hello world")
        let editor = handler(sink)
        editor.cursorColumn = 6  // before "world"
        _ = editor.handleKeyEvent(ctrl("k"))
        #expect(sink.value == "hello ")
        _ = editor.handleKeyEvent(ctrl("y"))
        #expect(sink.value == "hello world")
        #expect(editor.cursorColumn == 11)
    }

    @Test("Ctrl-K at end of line kills the newline (joins)")
    func killNewline() {
        let sink = StringSink("a\nb")
        let editor = handler(sink)
        editor.cursorLine = 0
        editor.cursorColumn = 1  // end of "a"
        _ = editor.handleKeyEvent(ctrl("k"))
        #expect(sink.value == "ab")
    }

    @Test("Ctrl-T transposes the two characters around the cursor")
    func transpose() {
        let sink = StringSink("abcd")
        let editor = handler(sink)
        editor.cursorColumn = 2  // between b and c
        _ = editor.handleKeyEvent(ctrl("t"))
        #expect(sink.value == "acbd")
        #expect(editor.cursorColumn == 3)
    }

    @Test("Ctrl-O opens a line after the cursor without moving it")
    func openLine() {
        let sink = StringSink("abcd")
        let editor = handler(sink)
        editor.cursorColumn = 2
        _ = editor.handleKeyEvent(ctrl("o"))
        #expect(sink.value == "ab\ncd")
        #expect(editor.cursorLine == 0)
        #expect(editor.cursorColumn == 2)
    }

    @Test("Option-Left / Right move by a word")
    func optionArrowsWordMotion() {
        let sink = StringSink("alpha beta gamma")
        let editor = handler(sink)
        editor.cursorColumn = 16  // end
        _ = editor.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(editor.cursorColumn == 11)  // start of "gamma"
        _ = editor.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(editor.cursorColumn == 6)  // start of "beta"
        _ = editor.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(editor.cursorColumn == 10)  // end of "beta"
    }

    @Test("Option-B / F move by a word (Emacs)")
    func optionLettersWordMotion() {
        let sink = StringSink("alpha beta")
        let editor = handler(sink)
        editor.cursorColumn = 10  // end
        _ = editor.handleKeyEvent(alt("b"))
        #expect(editor.cursorColumn == 6)  // start of "beta"
        _ = editor.handleKeyEvent(alt("f"))
        #expect(editor.cursorColumn == 10)  // end of "beta"
    }

    @Test("Option-Tab inserts a literal tab (plain Tab moves focus)")
    func optionTabInsertsTab() {
        let sink = StringSink("ab")
        let editor = handler(sink)
        editor.cursorColumn = 1
        // Plain Tab is not handled here (the focus system consumes it).
        #expect(editor.handleKeyEvent(KeyEvent(key: .tab)) == false)
        #expect(sink.value == "ab")
        // Option-Tab types a literal tab.
        #expect(editor.handleKeyEvent(KeyEvent(key: .tab, alt: true)) == true)
        #expect(sink.value == "a\tb")
        #expect(editor.cursorColumn == 2)
    }

    @Test("Option-Backspace deletes the word before the cursor")
    func optionBackspaceDeletesWord() {
        let sink = StringSink("alpha beta")
        let editor = handler(sink)
        editor.cursorColumn = 10
        _ = editor.handleKeyEvent(KeyEvent(key: .backspace, alt: true))
        #expect(sink.value == "alpha ")
        #expect(editor.cursorColumn == 6)
    }

    @Test("Unhandled Ctrl chord is not consumed")
    func unhandledCtrlPropagates() {
        let sink = StringSink("abc")
        let editor = handler(sink)
        #expect(editor.handleKeyEvent(ctrl("g")) == false)
        #expect(sink.value == "abc")  // and it did not insert 'g'
    }

    // MARK: - Selection (mouse click / drag)

    /// Simulates a press-and-drag: anchor at `from`, cursor dragged to `to`,
    /// exactly as ``TextEditor``'s mouse handler drives the model.
    private func dragSelect(_ editor: TextEditorHandler, from: (Int, Int), to: (Int, Int)) {
        editor.moveCursor(toLine: from.0, column: from.1)
        editor.selectionAnchor = editor.cursor
        editor.startOrExtendSelection()
        editor.moveCursor(toLine: to.0, column: to.1)
    }

    @Test("Dragging within a line selects that column range")
    func dragSelectsColumns() {
        let sink = StringSink("hello world")
        let editor = handler(sink)
        dragSelect(editor, from: (0, 0), to: (0, 5))
        #expect(editor.selectedColumns(inLine: 0, lineLength: 11) == 0..<5)
        // A click with no drag (anchor == cursor) is no selection.
        editor.moveCursor(toLine: 0, column: 3)
        editor.selectionAnchor = editor.cursor
        #expect(editor.selectionRange == nil)
    }

    @Test("A backward drag normalizes the selection span")
    func backwardDragNormalizes() {
        let sink = StringSink("hello")
        let editor = handler(sink)
        dragSelect(editor, from: (0, 4), to: (0, 1))
        #expect(editor.selectedColumns(inLine: 0, lineLength: 5) == 1..<4)
    }

    @Test("A multi-line selection covers whole interior lines")
    func multiLineSelection() {
        let sink = StringSink("first\nsecond\nthird")
        let editor = handler(sink)
        dragSelect(editor, from: (0, 2), to: (2, 3))
        #expect(editor.selectedColumns(inLine: 0, lineLength: 5) == 2..<5)  // col 2 to line end
        #expect(editor.selectedColumns(inLine: 1, lineLength: 6) == 0..<6)  // whole interior line
        #expect(editor.selectedColumns(inLine: 2, lineLength: 5) == 0..<3)  // to col 3
    }

    @Test("Typing replaces the selected text")
    func typingReplacesSelection() {
        let sink = StringSink("hello world")
        let editor = handler(sink)
        dragSelect(editor, from: (0, 0), to: (0, 5))  // select "hello"
        _ = editor.handleKeyEvent(KeyEvent(key: .character("H")))
        #expect(sink.value == "H world")
        #expect(editor.selectionRange == nil)  // selection consumed
        #expect(editor.cursorColumn == 1)
    }

    @Test("Backspace deletes the selection without deleting an extra character")
    func backspaceDeletesSelection() {
        let sink = StringSink("first\nsecond")
        let editor = handler(sink)
        dragSelect(editor, from: (0, 2), to: (1, 3))  // "rst\nsec"
        _ = editor.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(sink.value == "fiond")  // "fi" + "ond"
        #expect(editor.selectionRange == nil)
        #expect(editor.cursorLine == 0)
        #expect(editor.cursorColumn == 2)
    }

    @Test("An arrow key clears the selection but is otherwise normal")
    func arrowClearsSelection() {
        let sink = StringSink("hello")
        let editor = handler(sink)
        dragSelect(editor, from: (0, 1), to: (0, 4))
        _ = editor.handleKeyEvent(KeyEvent(key: .left))
        #expect(editor.selectionRange == nil)
        #expect(sink.value == "hello")  // text unchanged
    }

    /// Regression: a plain click must not leave a collapsed anchor that the next
    /// arrow key inflates into a phantom selection (which would then be
    /// overwritten by the next keystroke). The view's mouse handler clears the
    /// selection on a plain click; simulate that here.
    @Test("A plain click then arrow then type inserts (no phantom selection)")
    func plainClickThenArrowThenTypeInserts() {
        let sink = StringSink("hello world")
        let editor = handler(sink)
        editor.moveCursor(toLine: 0, column: 3)  // plain click at column 3…
        editor.clearSelection()  // …as registerMouse now does
        _ = editor.handleKeyEvent(KeyEvent(key: .right))
        #expect(editor.selectionRange == nil, "no selection should exist after a plain click + arrow")
        _ = editor.handleKeyEvent(KeyEvent(key: .character("X")))
        #expect(sink.value == "hellXo world", "the character inserts at the caret rather than overwriting")
    }

    @Test("Vertical motion after a click keeps the clicked column")
    func verticalMotionAfterClickKeepsColumn() {
        let sink = StringSink("abcdefgh\nij\nklmnopqr")  // line lengths 8, 2, 8
        let editor = handler(sink)
        _ = editor.handleKeyEvent(KeyEvent(key: .end))  // document end (2,8): desiredColumn 8
        editor.moveCursor(toLine: 0, column: 2)  // click at column 2
        _ = editor.handleKeyEvent(KeyEvent(key: .down))
        _ = editor.handleKeyEvent(KeyEvent(key: .down))
        #expect(editor.cursorLine == 2)
        #expect(editor.cursorColumn == 2, "vertical motion keeps the clicked column, not the stale 8")
    }
}
