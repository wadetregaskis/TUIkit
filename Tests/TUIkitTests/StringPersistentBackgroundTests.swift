//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StringPersistentBackgroundTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Tests for `String.withPersistentBackground(_:)` — the thin wrapper
/// that applies a background that survives inner ANSI resets, or
/// returns the string unchanged when given no color.
@MainActor
@Suite("String.withPersistentBackground")
struct StringPersistentBackgroundTests {

    @Test("A nil color returns the string unchanged")
    func nilReturnsUnchanged() {
        #expect("hello".withPersistentBackground(nil) == "hello")
        #expect("".withPersistentBackground(nil).isEmpty)
    }

    @Test("A color delegates to ANSIRenderer.applyPersistentBackground")
    func appliesBackground() {
        let input = "hello"
        let result = input.withPersistentBackground(.red)

        #expect(result == ANSIRenderer.applyPersistentBackground(input, color: .red))
        // A background was actually applied (the string changed) but the
        // visible content is preserved.
        #expect(result != input)
        #expect(result.stripped == input)
    }
}
