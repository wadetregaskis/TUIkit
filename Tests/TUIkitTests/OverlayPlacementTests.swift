//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OverlayPlacementTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Overlay placement")
struct OverlayPlacementTests {
    /// A `height`-row popup whose rows are labelled `item0…` so the test can tell
    /// which rows survived clamping.
    private func popup(width: Int, height: Int) -> FrameBuffer {
        FrameBuffer(lines: (0..<height).map {
            "item\($0)".padding(toLength: width, withPad: " ", startingAt: 0)
        })
    }

    @Test("A popover with room below stays below its anchor")
    func staysBelow() {
        let layer = OverlayLayer(
            offsetX: 2, offsetY: 5, content: popup(width: 8, height: 4),
            level: .popover, anchorHeight: 1)
        let placed = layer.placed(maxWidth: 40, maxHeight: 24)
        #expect(placed.y == 5, "stays below at its anchor offset: \(placed.y)")
        #expect(placed.x == 2)
    }

    @Test("A popover with no room below flips above its anchor")
    func flipsAbove() {
        // Anchor's popup at y=21, height 4, screen 24 → 21+4 overflows, so flip
        // above: 21 − anchorHeight(1) − height(4) = 16.
        let layer = OverlayLayer(
            offsetX: 0, offsetY: 21, content: popup(width: 8, height: 4),
            level: .popover, anchorHeight: 1)
        let placed = layer.placed(maxWidth: 40, maxHeight: 24)
        #expect(placed.y == 16, "flips above the anchor: \(placed.y)")
    }

    @Test("A popover taller than the screen is clamped but keeps its top rows (text shown)")
    func clampedKeepsText() {
        // The case the user flagged: even when it can't be made fully visible, the
        // menu item text must still render — i.e. the top rows survive.
        let layer = OverlayLayer(
            offsetX: 0, offsetY: 2, content: popup(width: 8, height: 40),
            level: .popover, anchorHeight: 1)
        let placed = layer.placed(maxWidth: 40, maxHeight: 10)
        #expect(placed.content.height == 10, "clamped to the screen height: \(placed.content.height)")
        #expect(placed.y == 0, "kept on screen")
        #expect(
            placed.content.lines.first?.contains("item0") == true,
            "the top row's text survives the clamp: \(placed.content.lines.first ?? "")")
    }

    @Test("A popover overflowing the right edge is nudged back on screen")
    func nudgedFromRight() {
        let layer = OverlayLayer(
            offsetX: 36, offsetY: 2, content: popup(width: 8, height: 3),
            level: .popover, anchorHeight: 1)
        let placed = layer.placed(maxWidth: 40, maxHeight: 24)
        #expect(placed.x == 32, "nudged left so it fits (40 − 8): \(placed.x)")
    }

    @Test("A centred overlay with no offset is centred")
    func centredNoOffset() {
        let layer = OverlayLayer(
            offsetX: 0, offsetY: 0, content: popup(width: 10, height: 4),
            level: .modal, centered: true)
        let placed = layer.placed(maxWidth: 40, maxHeight: 20)
        #expect(placed.x == 15)  // (40 − 10) / 2
        #expect(placed.y == 8)  // (20 − 4) / 2
    }

    @Test("A centred overlay's offset shifts it, and it clamps fully on screen")
    func centredOffsetDragsAndClamps() {
        let content = popup(width: 10, height: 4)
        // A modest drag shifts the dialog by that many cells from centre.
        let dragged = OverlayLayer(
            offsetX: 4, offsetY: -2, content: content, level: .modal, centered: true)
        let placed = dragged.placed(maxWidth: 40, maxHeight: 20)
        #expect(placed.x == 19)  // 15 + 4
        #expect(placed.y == 6)  // 8 − 2

        // A large drag can never push it off screen: it clamps to the edges.
        let farRight = OverlayLayer(
            offsetX: 999, offsetY: 999, content: content, level: .modal, centered: true)
        let clamped = farRight.placed(maxWidth: 40, maxHeight: 20)
        #expect(clamped.x == 30)  // 40 − 10, right edge flush
        #expect(clamped.y == 16)  // 20 − 4, bottom edge flush

        let farUpLeft = OverlayLayer(
            offsetX: -999, offsetY: -999, content: content, level: .modal, centered: true)
        let pinned = farUpLeft.placed(maxWidth: 40, maxHeight: 20)
        #expect(pinned.x == 0)
        #expect(pinned.y == 0)
    }
}
