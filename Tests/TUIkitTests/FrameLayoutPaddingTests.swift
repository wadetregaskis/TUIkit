//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameLayoutPaddingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A view nine bytes long, so whatever follows it in a wrapper is misaligned.
private struct OddProbe: View {
    var count = 0
    var flag = false
    var body: some View { EmptyView() }
}

/// `.frame(...)` wraps its content in `FlexibleFrameView`, the most common
/// wrapper in a layout, and the one with the most padding: six `Int?` /
/// `FrameDimension?` fields of nine bytes each at eight-byte alignment left 7
/// undefined bytes after each (41 in `.frame(width:)` over a `Text`). The
/// per-pass memos key a view by its bytes, and those bytes are whatever the
/// memory held before. So they are stored as plain words, with `Int.min` for
/// "none" and `Int.min + 1` for `.infinity`; then the alignment, word-aligned
/// too; then the content, last, so nothing follows it whatever its size. The
/// `Int?` / `FrameDimension?` API is unchanged.
@Suite("The frame wrapper's layout leaves no bytes undefined, and is smaller for it")
struct FrameLayoutPaddingTests {
    @Test("No padding between the frame wrapper's fields, whatever the content's size")
    func noInteriorPadding() {
        #expect(interiorPadding(of: FlexibleFrameView<OddProbe>.self).isEmpty,
            "\(interiorPadding(of: FlexibleFrameView<OddProbe>.self))")
        #expect(interiorPadding(of: FlexibleFrameView<Text>.self).isEmpty,
            "\(interiorPadding(of: FlexibleFrameView<Text>.self))")
    }

    @Test("Six words of constraints, the alignment, then the content: 151 bytes over a Text, down from 200")
    func size() {
        #expect(
            MemoryLayout<FlexibleFrameView<Text>>.size
                == 6 * 8 + MemoryLayout<Alignment>.size + MemoryLayout<Text>.size)
        #expect(MemoryLayout<FlexibleFrameView<Text>>.size == 151)
    }
}
