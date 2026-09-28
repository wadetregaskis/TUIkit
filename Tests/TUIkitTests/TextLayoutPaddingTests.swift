//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextLayoutPaddingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling
@testable import TUIkitView

/// The byte ranges inside a type's `MemoryLayout.size` that no stored field
/// covers, found from the runtime's field metadata and recursing into struct
/// and tuple fields. Enum and optional fields are taken whole: their payloads
/// come out of the compiler zeroed, and their spare bytes are theirs.
func interiorPadding(of type: Any.Type) -> [Range<Int>] {
    func size(_ type: Any.Type) -> Int {
        func measure<T>(_: T.Type) -> Int { MemoryLayout<T>.size }
        return _openExistential(type, do: measure)
    }
    func gaps(of type: Any.Type, at base: Int) -> [Range<Int>] {
        var fields: [(offset: Int, type: Any.Type, kind: RuntimeFields.Kind)] = []
        RuntimeFields.forEach(of: type) { _, offset, field, kind in
            fields.append((offset, field, kind))
            return true
        }
        var found: [Range<Int>] = []
        var covered = 0
        for field in fields.sorted(by: { $0.offset < $1.offset }) {
            if field.offset > covered { found.append(base + covered..<base + field.offset) }
            if field.kind == .struct || field.kind == .tuple {
                found += gaps(of: field.type, at: base + field.offset)
            }
            covered = max(covered, field.offset + size(field.type))
        }
        if !fields.isEmpty, covered < size(type) { found.append(base + covered..<base + size(type)) }
        return found
    }
    return gaps(of: type, at: 0)
}

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
