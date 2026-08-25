//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextInputFocusGateTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The input dispatcher's layer-0 gate: while a text-consuming handler is
/// focused, typed keys reach it before status-bar items and `onKeyPress`
/// handlers. The gate is the marker protocol, not a type test — testing
/// `is TextFieldHandler` literally is how `TextEditor` shipped with its
/// keystrokes stealable by any lettered status item.
@MainActor
@Suite("Text-input focus gate")
struct TextInputFocusGateTests {

    @Test("Every text-consuming handler is behind the gate")
    func allTextConsumersGate() {
        let manager = FocusManager()

        let field = TextFieldHandler(focusID: "field", text: .constant(""))
        manager.register(field)
        manager.focus(id: "field")
        #expect(manager.hasTextInputFocus, "TextField lost its layer-0 priority")

        let editor = TextEditorHandler(focusID: "editor", text: .constant(""))
        manager.register(editor)
        manager.focus(id: "editor")
        #expect(manager.hasTextInputFocus, "TextEditor's typing is stealable without the gate")
    }

    @Test("With nothing focused, nothing is gated")
    func nothingFocusedNothingGated() {
        #expect(!FocusManager().hasTextInputFocus)
    }
}
