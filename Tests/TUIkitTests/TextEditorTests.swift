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

    @Test("A focused editor shows a block cursor")
    func focusedShowsCursor() {
        let sink = StringSink("hi")
        let buffer = renderToBuffer(
            TextEditor(text: sink.binding), context: makeRenderContext(width: 12, height: 3))
        // The cursor cell is a coloured block → an SGR escape appears in the raw output.
        #expect(buffer.lines.joined().contains("\u{1B}["))
        #expect(buffer.height == 3)
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
}
