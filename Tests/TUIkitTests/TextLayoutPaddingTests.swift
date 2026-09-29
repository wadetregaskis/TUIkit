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

    /// The other half of reading a `Text` whole: no optional whose `nil` leaves
    /// bytes unwritten. Its line limit, colours and font are stored as enums of
    /// its module's own (`TextStyleStatements.swift`), so its value-hash plan
    /// is the word loop over its bytes, with no typed step to take — at the
    /// same size it had as optionals.
    @MainActor
    @Test("The value hash reads a Text whole, at the size it had")
    func readWhole() {
        let plans = ValueHashPlans()
        #expect(plans.plan(for: Text.self).pointee.shape == .dense)
        #expect(plans.plan(for: TextStyle.self).pointee.shape == .dense)
        #expect(plans.plan(for: FlexibleFrameView<Text>.self).pointee.shape == .dense)
        #expect(MemoryLayout<TextStyle>.size == 31)
        #expect(MemoryLayout<Text>.size == 55)
    }

    @Test("A style's statements read back as the optionals they stand for")
    func statementsRoundTrip() {
        var style = TextStyle()
        #expect(style.lineLimit == nil && style.foregroundColor == nil && style.font == nil)
        style.lineLimit = .lines(2)
        style.foregroundColor = .red
        style.backgroundColor = .blue
        style.font = .some(nil)
        #expect(style.lineLimit == .lines(2))
        #expect(style.foregroundColor == .red && style.backgroundColor == .blue)
        #expect(style.font == .some(nil))
        style.font = .some(.headline)
        #expect(style.font == .some(.headline))
        style.font = nil
        style.foregroundColor = nil
        #expect(style.font == nil && style.foregroundColor == nil)
        var expected = TextStyle()
        expected.lineLimit = .lines(2)
        expected.backgroundColor = .blue
        #expect(style == expected)
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
