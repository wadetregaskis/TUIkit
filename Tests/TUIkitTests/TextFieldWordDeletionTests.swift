//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldWordDeletionTests.swift
//
//  Option-Backspace and Option-Delete delete a word in a `TextEditor`, the
//  macOS text system's `deleteWordBackward:` and `deleteWordForward:`. In a
//  `TextField` on the same page they deleted one character, as if Option were
//  not held, while Option-Left and Option-Right beside them already moved by a
//  word. These hold the field to the word the arrows move by, and to what the
//  editor does with the same line.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The string a control is bound to.
private final class TextBox: @unchecked Sendable {
    var text: String
    init(_ text: String) { self.text = text }
}

private let optionBackspace = KeyEvent(key: .backspace, alt: true)
private let optionDelete = KeyEvent(key: .delete, alt: true)

@MainActor
@Suite("Option-Backspace and Option-Delete delete a word in a field")
struct TextFieldWordDeletionTests {

    /// A field over `initial` with its caret at `caret`.
    private func makeField(_ initial: String, caret: Int) -> (TextFieldHandler, TextBox) {
        let box = TextBox(initial)
        let field = TextFieldHandler(
            focusID: "field", text: Binding(get: { box.text }, set: { box.text = $0 }),
            cursorPosition: caret)
        return (field, box)
    }

    @Test("Option-Backspace deletes back to the word boundary Option-Left moves to")
    func deleteWordBackward() {
        let (field, box) = makeField("foo bar", caret: 7)
        #expect(field.handleKeyEvent(optionBackspace))
        #expect(box.text == "foo ")
        #expect(field.cursorPosition == 4)
        #expect(field.handleKeyEvent(optionBackspace))
        #expect(box.text.isEmpty, "the space goes with the word before it, as Option-Left goes past it")
    }

    @Test("Option-Delete deletes forward to the word boundary Option-Right moves to")
    func deleteWordForward() {
        let (field, box) = makeField("foo bar", caret: 0)
        #expect(field.handleKeyEvent(optionDelete))
        #expect(box.text == " bar")
        #expect(field.cursorPosition == 0)
        #expect(field.handleKeyEvent(optionDelete))
        #expect(box.text.isEmpty)
    }

    /// At the start there is nothing to delete backward, and at the end
    /// nothing forward; a single line has no line break to join across.
    @Test("At the ends there is nothing to delete, and the key is still the field's")
    func nothingAtTheEnds() {
        let (atStart, startBox) = makeField("foo", caret: 0)
        #expect(atStart.handleKeyEvent(optionBackspace))
        #expect(startBox.text == "foo")
        let (atEnd, endBox) = makeField("foo", caret: 3)
        #expect(atEnd.handleKeyEvent(optionDelete))
        #expect(endBox.text == "foo")
    }

    /// A selection goes instead, as it does for plain Backspace and Delete.
    @Test("With a selection, Option-Backspace and Option-Delete delete the selection")
    func selectionGoesInstead() {
        let (backward, backwardBox) = makeField("foo bar", caret: 5)
        backward.selectionAnchor = 3
        #expect(backward.handleKeyEvent(optionBackspace))
        #expect(backwardBox.text == "fooar")

        let (forward, forwardBox) = makeField("foo bar", caret: 5)
        forward.selectionAnchor = 3
        #expect(forward.handleKeyEvent(optionDelete))
        #expect(forwardBox.text == "fooar")
    }

    @Test("A word deletion is one step for Ctrl-Z")
    func undoable() {
        let (field, box) = makeField("foo bar", caret: 7)
        _ = field.handleKeyEvent(optionBackspace)
        #expect(box.text == "foo ", "precondition: the deletion")
        _ = field.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(box.text == "foo bar")
    }

    /// The editor is the reference: on one line, the field deletes the word
    /// the editor deletes.
    @Test("The field deletes the word the editor deletes on the same line")
    func matchesTheEditor() {
        for (key, caret) in [(optionBackspace, 5), (optionDelete, 5), (optionBackspace, 7), (optionDelete, 1)] {
            let (field, fieldBox) = makeField("foo_1 bar.baz", caret: caret)
            _ = field.handleKeyEvent(key)

            let editorBox = TextBox("foo_1 bar.baz")
            let editor = TextEditorHandler(
                focusID: "editor",
                text: Binding(get: { editorBox.text }, set: { editorBox.text = $0 }))
            editor.moveCursor(toLine: 0, column: caret)
            _ = editor.handleKeyEvent(key)

            #expect(fieldBox.text == editorBox.text, "\(key.key) at \(caret)")
        }
    }
}
