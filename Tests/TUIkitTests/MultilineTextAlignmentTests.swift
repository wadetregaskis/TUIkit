//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MultilineTextAlignmentTests.swift
//
//  Tests for SwiftUI-parity `.multilineTextAlignment(_:)`: the lines of a
//  multi-line Text align relative to the block's own width (its widest line).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("multilineTextAlignment")
struct MultilineTextAlignmentTests {
    /// The stripped (ANSI-free) lines of a view rendered at `width`.
    private func render(_ view: some View, width: Int, height: Int = 6) -> [String] {
        renderToBuffer(AnyView(view), context: makeBareRenderContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    // Two explicit lines with deterministically different widths: "alpha" (5)
    // and "hi" (2), so the short line's shift is unambiguous.
    private let twoLine = "alpha\nhi"

    @Test("Leading is the default and leaves lines ragged (unpadded)")
    func leadingRagged() {
        let rows = render(Text(twoLine), width: 12)
        #expect(rows[0] == "alpha")
        #expect(rows[1] == "hi", "the short line is flush-left with no leading pad: '\(rows[1])'")
    }

    @Test("Center pads each line to the block width, centred")
    func center() {
        let rows = render(Text(twoLine).multilineTextAlignment(.center), width: 12)
        // Block width is 5 ("alpha"); "hi" (2) centred → slack 3, leftPad 1.
        #expect(rows[0] == "alpha", "the widest line fills the block: '\(rows[0])'")
        #expect(rows[1] == " hi  ", "short line centred in a 5-wide block: '\(rows[1])'")
    }

    @Test("Trailing pushes each line flush-right within the block")
    func trailing() {
        let rows = render(Text(twoLine).multilineTextAlignment(.trailing), width: 12)
        #expect(rows[0] == "alpha")
        #expect(rows[1] == "   hi", "short line flush-right in a 5-wide block: '\(rows[1])'")
    }

    @Test("Alignment applies to wrapped (not just explicit-newline) text")
    func wrappedText() {
        // "aaaa bb" at width 4 wraps to "aaaa" (4) and "bb" (2).
        let rows = render(Text("aaaa bb").multilineTextAlignment(.trailing), width: 4)
        #expect(rows.count == 2)
        #expect(rows[0] == "aaaa")
        #expect(rows[1] == "  bb", "wrapped short line flush-right: '\(rows[1])'")
    }

    @Test("A single line is unaffected by any alignment")
    func singleLine() {
        for alignment in TextAlignment.allCases {
            let rows = render(Text("solo").multilineTextAlignment(alignment), width: 12)
            #expect(rows == ["solo"], "single line unchanged for \(alignment): \(rows)")
        }
    }

    @Test("The block width (measured size) is unchanged by alignment")
    func widthUnchanged() {
        let ctx = makeBareRenderContext(width: 12, height: 6)
        let leadingW = measureChild(Text(twoLine), proposal: .unspecified, context: ctx).width
        let centerW = measureChild(
            Text(twoLine).multilineTextAlignment(.center), proposal: .unspecified, context: ctx).width
        #expect(leadingW == centerW, "alignment redistributes within the block, not its width")
    }

    @Test("Alignment cascades to descendant Text via the environment")
    func cascades() {
        let rows = render(
            VStack(alignment: .leading) { Text(twoLine) }.multilineTextAlignment(.trailing),
            width: 12)
        #expect(rows.contains("   hi"), "the modifier on the container reaches the inner Text: \(rows)")
    }
}
