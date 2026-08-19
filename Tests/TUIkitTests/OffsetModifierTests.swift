//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OffsetModifierTests.swift
//
//  `.offset` displaces the DRAWING and leaves the layout alone — SwiftUI's
//  semantics, and what the measure pass already reported. The render pass has
//  to agree with it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("Offset modifier")
struct OffsetModifierTests {

    private func composited(_ view: some View, width: Int = 20, height: Int = 6) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .compositingOverlays(maxWidth: width, maxHeight: height, palette: SystemPalette.green)
            .lines.map { $0.stripped }
    }

    @Test("An offset view keeps its row in a stack")
    func offsetKeepsItsSlot() {
        // The bug: the render returned a buffer with NO lines, and a stack
        // reads that as "no child at all" — not as a blank one. So the row
        // collapsed, the next sibling moved up into it, and the floated
        // drawing composited on top of that sibling: one line reading "BBAAA"
        // where there should have been two.
        let out = composited(
            VStack(alignment: .leading, spacing: 0) {
                Text("AAA").offset(x: 2)
                Text("BBB")
            })
        #expect(out.count >= 2, "the offset view's row collapsed: \(out)")
        #expect(out[0].hasPrefix("  AAA"), "drawn displaced: \(out)")
        #expect(out[1].hasPrefix("BBB"), "the sibling kept its own row: \(out)")
    }

    @Test("An offset view still paints nothing where it came from")
    func offsetDoesNotEraseWhatIsBeneath() {
        // The reason the placeholder is zero-WIDTH rather than blanks: a
        // terminal has no transparency, so a blank box would erase the layer
        // under it — the opposite of SwiftUI, where the vacated region shows
        // through.
        let out = composited(
            ZStack {
                Text("under-under")
                Text("XX").offset(x: 3)
            })
        #expect(out.count == 1, "\(out)")
        #expect(out[0].contains("under"), "the layer beneath survived: \(out)")
        #expect(out[0].contains("XX"), "the offset view drew: \(out)")
    }
}
