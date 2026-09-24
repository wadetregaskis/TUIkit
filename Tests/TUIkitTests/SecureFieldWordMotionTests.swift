//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SecureFieldWordMotionTests.swift
//
//  Word motion and word deletion stop at the word boundaries of the text, so in
//  a SecureField they showed where the words of a hidden password break:
//  Option-Left from the end of "hunter2 abc" landed after the space. AppKit's
//  NSSecureTextField does not do that. Measured on macOS 15.8 through an
//  NSWindow's key path, every word command in a secure field goes one
//  character: Option-Left from the end of "hunter2 abc.def ghi" stopped at
//  18, not 16; Option-Right from 0 at 1, not 7; Option-Backspace and
//  Option-Delete removed one character; and `moveWordBackward:` sent straight
//  to its field editor moved one. A SecureField does the same.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The string a field is bound to.
private final class TextBox: @unchecked Sendable {
    var text: String
    init(_ text: String) { self.text = text }
}

/// A word command, where the caret starts, and what a TextField and a
/// SecureField leave: the text, and the caret.
struct WordCommandCase: Sendable, CustomTestStringConvertible {
    let name: String
    let key: KeyEvent
    let caret: Int
    let plain: (text: String, caret: Int)
    let secure: (text: String, caret: Int)
    /// Where the selection is anchored afterwards, when the command extends it.
    var secureAnchor: Int?

    var testDescription: String { name }

    static let text = "hunter2 abc"

    static let all: [Self] = [
        Self(
            name: "Option-Left", key: KeyEvent(key: .left, alt: true), caret: 11,
            plain: (text, 8), secure: (text, 10)),
        Self(
            name: "Option-Right", key: KeyEvent(key: .right, alt: true), caret: 0,
            plain: (text, 7), secure: (text, 1)),
        Self(
            name: "Option-B", key: KeyEvent(key: .character("b"), alt: true), caret: 11,
            plain: (text, 8), secure: (text, 10)),
        Self(
            name: "Option-F", key: KeyEvent(key: .character("f"), alt: true), caret: 0,
            plain: (text, 7), secure: (text, 1)),
        Self(
            name: "Option-Ctrl-F", key: KeyEvent(key: .character("f"), ctrl: true, alt: true),
            caret: 0, plain: (text, 7), secure: (text, 1)),
        Self(
            name: "Shift-Option-Right", key: KeyEvent(key: .right, alt: true, shift: true), caret: 0,
            plain: (text, 7), secure: (text, 1), secureAnchor: 0),
        Self(
            name: "Option-Backspace", key: KeyEvent(key: .backspace, alt: true), caret: 11,
            plain: ("hunter2 ", 8), secure: ("hunter2 ab", 10)),
        Self(
            name: "Option-Delete", key: KeyEvent(key: .delete, alt: true), caret: 0,
            plain: (" abc", 0), secure: ("unter2 abc", 0)),
    ]
}

@MainActor
@Suite("A SecureField moves and deletes a character where a TextField goes a word")
struct SecureFieldWordMotionTests {

    private func makeField(secure: Bool, caret: Int) -> (TextFieldHandler, TextBox) {
        let box = TextBox(WordCommandCase.text)
        let field = TextFieldHandler(
            focusID: "field", text: Binding(get: { box.text }, set: { box.text = $0 }),
            cursorPosition: caret)
        field.isSecure = secure
        return (field, box)
    }

    @Test("Each word command goes one character in a secure field", arguments: WordCommandCase.all)
    func secureGoesACharacter(command: WordCommandCase) {
        let (field, box) = makeField(secure: true, caret: command.caret)
        #expect(field.handleKeyEvent(command.key))
        #expect(box.text == command.secure.text)
        #expect(field.cursorPosition == command.secure.caret)
        #expect(field.selectionAnchor == command.secureAnchor)
    }

    /// The control case: the same keys at the same places go a word in a
    /// TextField, so the secure rows are about `isSecure`.
    @Test("The same command goes a word in a TextField", arguments: WordCommandCase.all)
    func plainGoesAWord(command: WordCommandCase) {
        let (field, box) = makeField(secure: false, caret: command.caret)
        #expect(field.handleKeyEvent(command.key))
        #expect(box.text == command.plain.text)
        #expect(field.cursorPosition == command.plain.caret)
    }
}
