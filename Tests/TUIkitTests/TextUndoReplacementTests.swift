//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextUndoReplacementTests.swift
//
//  A text control's undo history records the text before each of its own
//  edits. When the app replaces the bound text — loads another document into
//  the same control, clears a field on submit — those records describe text
//  that is no longer there, and Ctrl-Z put the old text back over the app's.
//  The history must never bring back text the control did not itself produce
//  from what is there now: a replacement from outside forgets it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The string a control is bound to, which a test can replace the way an app
/// would.
private final class TextBox: @unchecked Sendable {
    var text: String
    init(_ text: String) { self.text = text }
}

private func typed(_ character: Character) -> KeyEvent {
    KeyEvent(key: .character(character))
}

private let undo = KeyEvent(key: .character("z"), ctrl: true)

@MainActor
@Suite("Undo forgets text the control did not write")
struct TextUndoReplacementTests {

    /// A field over `initial`, its caret at the end.
    private func makeField(_ initial: String) -> (TextFieldHandler, TextBox) {
        let box = TextBox(initial)
        let field = TextFieldHandler(
            focusID: "field", text: Binding(get: { box.text }, set: { box.text = $0 }))
        return (field, box)
    }

    @Test("A field forgets its history when the app replaces the text")
    func fieldForgetsOnReplacement() {
        let (field, box) = makeField("")
        _ = field.handleKeyEvent(typed("a"))
        _ = field.handleKeyEvent(typed("b"))
        #expect(box.text == "ab", "precondition: the typing")

        box.text = "other document"
        #expect(field.handleKeyEvent(undo), "Ctrl-Z is still the field's, never the shell's suspend")
        #expect(box.text == "other document", "undo put the replaced text back")
    }

    /// The edits the field makes after the replacement are its own, and undo
    /// takes them back as far as the replacement and no further.
    @Test("After a replacement, undo takes back the field's own edits to it, and stops there")
    func fieldUndoesItsEditsSinceTheReplacement() {
        let (field, box) = makeField("")
        _ = field.handleKeyEvent(typed("a"))
        box.text = "xyz"
        field.cursorPosition = 3
        _ = field.handleKeyEvent(typed("q"))
        #expect(box.text == "xyzq", "precondition: the typing")

        _ = field.handleKeyEvent(undo)
        #expect(box.text == "xyz")
        _ = field.handleKeyEvent(undo)
        #expect(box.text == "xyz", "undo went past the replacement")
    }

    /// The app that clears its field on submit is replacing the text inside
    /// the field's own key: Return runs `onSubmit`, and `onSubmit` writes.
    @Test("A field cleared by its onSubmit does not undo back to what was submitted")
    func fieldClearedOnSubmit() {
        let (field, box) = makeField("")
        field.onSubmit = { box.text = "" }
        _ = field.handleKeyEvent(typed("h"))
        _ = field.handleKeyEvent(typed("i"))
        _ = field.handleKeyEvent(KeyEvent(key: .enter))
        #expect(box.text.isEmpty, "precondition: the submit cleared the field")

        _ = field.handleKeyEvent(undo)
        #expect(box.text.isEmpty, "undo brought the submitted text back")
    }

    /// A binding that rewrites what it is given is not a replacement: the
    /// text read back after the field's own write is what the field produced.
    @Test("A binding that rewrites the field's writes keeps the history")
    func rewritingBindingKeepsHistory() {
        let box = TextBox("")
        let field = TextFieldHandler(
            focusID: "field",
            text: Binding(get: { box.text }, set: { box.text = $0.uppercased() }))
        _ = field.handleKeyEvent(typed("a"))
        _ = field.handleKeyEvent(typed("b"))
        #expect(box.text == "AB", "precondition: the binding rewrote the typing")

        _ = field.handleKeyEvent(undo)
        #expect(box.text == "A")
    }

    /// A suggestion accepted with the mouse is the field's own edit, made
    /// outside any key, and undo takes it back.
    @Test("A suggestion accepted with the mouse is still undone")
    func acceptedSuggestionIsUndone() {
        let (field, box) = makeField("")
        field.suggestionCompletions = ["alpha", "beta"]
        _ = field.handleKeyEvent(typed("b"))
        field.acceptSuggestion(at: 1)
        #expect(box.text == "beta", "precondition: the suggestion was accepted")

        _ = field.handleKeyEvent(undo)
        #expect(box.text == "b")
    }
}
