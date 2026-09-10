//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarAlphaTests.swift
//
//  `StatusBarState.highlightColor` and `.labelColor` are public `var`s, and each
//  paints a DIFFERENT run of every item.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A translucent status bar colour")
struct StatusBarAlphaTests {

    private func faded(_ base: Color, _ alpha: UInt8) -> Color {
        var colour = base
        colour.alpha = alpha
        return colour
    }

    private func bar(
        highlight: Color = .cyan, label: Color? = nil, width: Int = 40
    ) -> FrameBuffer {
        let view = StatusBar(
            userItems: [StatusBarItem(shortcut: "q", label: "Quit")],
            systemItems: [],
            style: .compact,
            alignment: .justified,
            highlightColor: highlight,
            labelColor: label)
        let context = RenderContext(
            availableWidth: width, availableHeight: view.height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    @Test("Opaque colours claim nothing")
    func opaqueClaimsNothing() {
        #expect(bar().opacityRegions.isEmpty)
        #expect(bar(highlight: .cyan, label: .white).opacityRegions.isEmpty)
    }

    @Test("A faded highlight claims the shortcut and not the label")
    func fadedHighlight() throws {
        let drawn = bar(highlight: faded(.cyan, 128), label: .white)
        let claim = try #require(drawn.opacityRegions.first)
        #expect(drawn.opacityRegions.count == 1, "one run, not the whole item")
        #expect(claim.width == 1, "the shortcut `q` is one cell: \(claim)")
        #expect(claim.inkOpacity == 128.0 / 255)
    }

    @Test("A faded label claims the label and not the shortcut")
    func fadedLabel() throws {
        let drawn = bar(highlight: .cyan, label: faded(.white, 64))
        let claim = try #require(drawn.opacityRegions.first)
        #expect(drawn.opacityRegions.count == 1)
        #expect(claim.offsetX >= 1, "starts after the shortcut: \(claim)")
        #expect(claim.width == 5, "` Quit` — the separating space is the label's")
        #expect(claim.inkOpacity == 64.0 / 255)
    }

    @Test("Both faded claims two runs, each at its own alpha")
    func bothFaded() {
        let drawn = bar(highlight: faded(.cyan, 128), label: faded(.white, 64))
        #expect(drawn.opacityRegions.count == 2, "\(drawn.opacityRegions)")
        // The two runs are adjacent and disjoint: together they are the item, and
        // neither the gap nor the last cell belongs to nobody. Claimed twice, the
        // overlap would resolve at the product of the two alphas.
        let sorted = drawn.opacityRegions.sorted { $0.offsetX < $1.offsetX }
        #expect(sorted[0].offsetX + sorted[0].width == sorted[1].offsetX, "\(sorted)")
        #expect(sorted[0].inkOpacity != sorted[1].inkOpacity, "each at its own alpha")
    }

    @Test("The bytes are the colours at full strength")
    func bytesAreOpaque() {
        let drawn = bar(highlight: faded(.cyan, 128))
        #expect(
            drawn.lines[0].contains(Color.cyan.foregroundCodes().joined(separator: ";")),
            "\(drawn.lines[0].debugDescription)")
    }
}
