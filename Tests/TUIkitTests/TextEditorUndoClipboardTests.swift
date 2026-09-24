//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorUndoClipboardTests.swift
//
//  A `TextEditor` had no Ctrl-Z, Ctrl-C or Ctrl-X of its own. A field on the
//  same page had all three, standing in for ⌘Z, ⌘C and ⌘X, which a terminal
//  app never receives. In the editor Ctrl-C and Ctrl-X did nothing, and Ctrl-Z
//  fell through every layer of the input chain to the shell's meaning and
//  suspended the whole app, with the text still unsaved in it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The string an editor is bound to.
private final class TextBox: @unchecked Sendable {
    var text: String
    init(_ text: String) { self.text = text }
}

private func ctrl(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true)
}

private func typed(_ character: Character) -> KeyEvent {
    KeyEvent(key: .character(character))
}

@MainActor
@Suite("TextEditor's undo, copy and cut")
struct TextEditorUndoClipboardTests {

    /// An editor over `initial`, with its cursor at the start, and the
    /// clipboard it writes.
    private func makeEditor(_ initial: String) -> (TextEditorHandler, TextBox, FakeClipboard) {
        let box = TextBox(initial)
        let editor = TextEditorHandler(
            focusID: "editor", text: Binding(get: { box.text }, set: { box.text = $0 }))
        let board = FakeClipboard()
        editor.clipboard = board.access
        return (editor, box, board)
    }

    @Test("Ctrl-Z takes back one key's change at a time, and the cursor with it")
    func undoStepsBack() {
        let (editor, box, _) = makeEditor("ab\ncd")
        _ = editor.handleKeyEvent(typed("X"))
        _ = editor.handleKeyEvent(typed("Y"))
        #expect(box.text == "XYab\ncd", "precondition: the typing")

        #expect(editor.handleKeyEvent(ctrl("z")))
        #expect(box.text == "Xab\ncd")
        #expect(editor.cursor == TextEditorPosition(line: 0, column: 1))
        #expect(editor.handleKeyEvent(ctrl("z")))
        #expect(box.text == "ab\ncd")
        #expect(editor.cursor == TextEditorPosition(line: 0, column: 0))

        // Nothing left: the key is still the editor's, and changes nothing.
        #expect(editor.handleKeyEvent(ctrl("z")))
        #expect(box.text == "ab\ncd")
    }

    /// Keys that only move record nothing, so undo goes past them to the
    /// last edit. Each edit below is checked done before it is undone.
    @Test("Ctrl-Z takes back a line break, a kill and a transpose, and skips motions")
    func undoEdits() {
        let (editor, box, _) = makeEditor("ab\ncd")
        _ = editor.handleKeyEvent(KeyEvent(key: .right))
        _ = editor.handleKeyEvent(KeyEvent(key: .enter))
        #expect(box.text == "a\nb\ncd", "precondition: the line break")
        _ = editor.handleKeyEvent(KeyEvent(key: .down))
        _ = editor.handleKeyEvent(ctrl("k"))
        #expect(box.text == "a\nb\n", "precondition: the kill")
        _ = editor.handleKeyEvent(ctrl("a"))
        _ = editor.handleKeyEvent(ctrl("t"))
        #expect(box.text == "a\nb\n", "a transpose at the start of a line changes nothing")

        _ = editor.handleKeyEvent(ctrl("z"))
        #expect(box.text == "a\nb\ncd", "the kill came back")
        _ = editor.handleKeyEvent(ctrl("z"))
        #expect(box.text == "ab\ncd", "the line break came back")
    }

    @Test("Ctrl-C copies the selection, and leaves the text and the selection alone")
    func copyTheSelection() {
        let (editor, box, board) = makeEditor("ab\ncd")
        _ = editor.handleKeyEvent(KeyEvent(key: .character("a"), ctrl: true, alt: true))
        #expect(editor.handleKeyEvent(ctrl("c")))
        #expect(board.writes == ["ab\ncd"])
        #expect(box.text == "ab\ncd")
        #expect(editor.selectionRange != nil, "the copy dropped the selection")
    }

    /// With nothing selected there is nothing to copy or cut, so the editor
    /// passes the chord on, as a field does: an app's ⌘C or ⌘X, which arrive
    /// as these chords, or `QuitShortcut.ctrlC`, gets it
    /// (`TextInputShortcutPrecedenceTests` plays that through the chain).
    @Test("Ctrl-C and Ctrl-X with nothing selected do nothing, and pass the key on")
    func copyAndCutNothing() {
        let (editor, box, board) = makeEditor("ab\ncd")
        #expect(!editor.handleKeyEvent(ctrl("c")))
        #expect(!editor.handleKeyEvent(ctrl("x")))
        #expect(board.writes.isEmpty)
        #expect(box.text == "ab\ncd")
    }

    /// A selection across a line break, the way a drag leaves one: the cut
    /// takes the break with it, and Ctrl-Z puts all of it back.
    @Test("Ctrl-X cuts the selection, and Ctrl-Z puts it back")
    func cutAndUndo() {
        let (editor, box, board) = makeEditor("ab\ncd")
        editor.selectionAnchor = TextEditorPosition(line: 0, column: 1)
        editor.moveCursor(toLine: 1, column: 1)

        #expect(editor.handleKeyEvent(ctrl("x")))
        #expect(board.writes == ["b\nc"])
        #expect(box.text == "ad")
        #expect(editor.selectionRange == nil)

        _ = editor.handleKeyEvent(ctrl("z"))
        #expect(box.text == "ab\ncd")
    }

    /// When the app replaces the text, the editor's history describes text
    /// that is gone, and undo must not write it back: it is forgotten, as a
    /// field's is (`TextUndoReplacementTests`).
    @Test("Ctrl-Z after the app loads another document leaves the document alone")
    func undoAfterAReplacement() {
        let (editor, box, _) = makeEditor("ab\ncd")
        _ = editor.handleKeyEvent(typed("X"))
        #expect(box.text == "Xab\ncd", "precondition: the typing")
        box.text = "another\ndocument"

        #expect(editor.handleKeyEvent(ctrl("z")), "Ctrl-Z is still the editor's, never the shell's suspend")
        #expect(box.text == "another\ndocument", "undo wrote the old document back")

        // Its own edits to the new document undo as usual, as far back as the
        // replacement.
        _ = editor.handleKeyEvent(typed("Y"))
        _ = editor.handleKeyEvent(ctrl("z"))
        #expect(box.text == "another\ndocument")
    }

    /// Two editors on one binding, as the Example's two views of its notes
    /// are: an edit in one is a replacement to the other, whose undo must not
    /// take the first one's edit back.
    @Test("An editor sharing its text with another does not undo the other's edit")
    func sharedBinding() {
        let box = TextBox("ab")
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let first = TextEditorHandler(focusID: "first", text: binding)
        let second = TextEditorHandler(focusID: "second", text: binding)
        _ = second.handleKeyEvent(typed("S"))
        _ = first.handleKeyEvent(typed("F"))
        #expect(box.text == "FSab", "precondition: both edited")

        _ = second.handleKeyEvent(ctrl("z"))
        #expect(box.text == "FSab", "the second editor undid the first one's edit")
        _ = first.handleKeyEvent(ctrl("z"))
        #expect(box.text == "Sab", "the first editor's own undo")
    }

    /// The editor binds three of a field's five stand-ins. Ctrl-V is still
    /// the Emacs page down, and reads no clipboard; Ctrl-U is not bound.
    @Test("Ctrl-V still pages down, and Ctrl-U is not the editor's")
    func pasteAndEraseAreNotBound() {
        let (editor, box, board) = makeEditor("ab\ncd")
        board.contents = "PASTED"
        #expect(editor.handleKeyEvent(ctrl("v")))
        #expect(box.text == "ab\ncd", "Ctrl-V pasted")
        #expect(editor.cursor.line == 1, "Ctrl-V did not page down")
        #expect(!editor.handleKeyEvent(ctrl("u")))
        #expect(box.text == "ab\ncd")
    }
}
