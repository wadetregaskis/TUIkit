//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextLayoutPaddingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling
@testable import TUIkitView

/// The per-pass memos key a view by its raw bytes (`viewValueHash`), and a
/// padding byte is whatever the memory held before — so two equal values can
/// differ there, and one misses the other's entry. Swift lays out stored
/// properties in declaration order, so the order is what decides whether a
/// type has any. On Linux a standard button's two cap `Text`s missed the memo
/// on every probe through exactly these bytes: 7 between `Text.style` and
/// `Text.runs`, and 2 before `TextStyle.lineLimit`.
@Suite("Text's layout leaves no bytes for the memos' raw-byte key to read undefined")
struct TextLayoutPaddingTests {
    @Test("Text, TextStyle and Color have no padding between their fields")
    func noInteriorPadding() {
        #expect(interiorPadding(of: Text.self).isEmpty, "Text: \(interiorPadding(of: Text.self))")
        #expect(interiorPadding(of: TextStyle.self).isEmpty, "TextStyle: \(interiorPadding(of: TextStyle.self))")
        #expect(interiorPadding(of: Color.self).isEmpty, "Color: \(interiorPadding(of: Color.self))")
    }

    @Test("The padding finder sees padding where there is some")
    func finderSeesPadding() {
        struct Padded {
            var flag: Bool
            var count: Int
        }
        struct Nested {
            var count: Int
            var inner: Padded
        }
        #expect(interiorPadding(of: Padded.self) == [1..<8])
        #expect(interiorPadding(of: Nested.self) == [9..<16])
    }
}
