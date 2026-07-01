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
        _ = editor.handleKeyEvent(KeyEvent(key: .end))  // column 9, desired 9
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
        // The cursor cell is inverted → an SGR escape appears in the raw output.
        #expect(buffer.lines.joined().contains("\u{1B}["))
        #expect(buffer.height == 3)
    }
}
