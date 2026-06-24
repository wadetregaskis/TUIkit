//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SanitizedForTerminalRowTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - sanitizedForTerminalRow

@Suite("String.sanitizedForTerminalRow")
struct SanitizedForTerminalRowTests {

    @Test("Clean text is returned unchanged")
    func cleanUnchanged() {
        #expect("Hello, World!".sanitizedForTerminalRow() == "Hello, World!")
        #expect("".sanitizedForTerminalRow().isEmpty)
    }

    @Test("Newlines, carriage returns, and tabs become spaces")
    func cursorMoversReplaced() {
        #expect("a\nb".sanitizedForTerminalRow() == "a b")
        #expect("a\rb".sanitizedForTerminalRow() == "a b")
        #expect("a\tb".sanitizedForTerminalRow() == "a b")
        // CR + LF → two spaces (each is replaced independently).
        #expect("a\r\nb".sanitizedForTerminalRow() == "a  b")
    }

    @Test("Other C0 controls and DEL become spaces")
    func otherControlsReplaced() {
        #expect("a\u{07}b".sanitizedForTerminalRow() == "a b")  // bell
        #expect("a\u{08}b".sanitizedForTerminalRow() == "a b")  // backspace
        #expect("a\u{0C}b".sanitizedForTerminalRow() == "a b")  // form feed
        #expect("a\u{7F}b".sanitizedForTerminalRow() == "a b")  // DEL
    }

    @Test("The ESC that introduces an ANSI sequence is preserved")
    func ansiPreserved() {
        let styled = "\u{1B}[31mred\u{1B}[0m"
        #expect(styled.sanitizedForTerminalRow() == styled, "ANSI colour codes must survive intact")
        // A stray newline inside a styled line is still neutralised; the ESCs stay.
        let mixed = "\u{1B}[31mred\ntext\u{1B}[0m"
        #expect(mixed.sanitizedForTerminalRow() == "\u{1B}[31mred text\u{1B}[0m")
    }
}
