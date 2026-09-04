//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SanitizedForTerminalRowTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

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

    /// C1 too: a pasted U+009B is an 8-bit CSI and a U+0085 a NEL on any host
    /// that decodes them. They encode as `C2 8x`/`C2 9x`, so the byte
    /// fast-reject could not even see them.
    @Test("C1 controls become spaces")
    func c1ControlsReplaced() {
        #expect("a\u{85}b".sanitizedForTerminalRow() == "a b")  // NEL
        #expect("a\u{9B}2Jb".sanitizedForTerminalRow() == "a 2Jb")  // 8-bit CSI
        #expect("a\u{80}b".sanitizedForTerminalRow() == "a b")
        #expect("a\u{9F}b".sanitizedForTerminalRow() == "a b")
        // The lead byte also begins U+00A0…U+00BF, which are content.
        #expect("a\u{A0}b©°".sanitizedForTerminalRow() == "a\u{A0}b©°")
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
