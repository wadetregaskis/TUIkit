//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayModifierTests.swift
//
//  Tests for OverlayModifier: alignment positioning, edge cases,
//  and View extension.
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("OverlayModifier Tests")
struct OverlayModifierTests {

    /// Helper to create a RenderContext with default test settings.
    private func testContext() -> RenderContext {
        RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// Helper to render a view to a FrameBuffer.
    private func render<V: View>(_ view: V) -> FrameBuffer {
        renderToBuffer(view, context: testContext())
    }

    @Test("Overlay with empty base returns overlay")
    func emptyBaseReturnsOverlay() {
        let view = OverlayModifier(
            base: EmptyView(),
            overlay: Text("Over"),
            alignment: .center
        )
        let buffer = render(view)
        #expect(buffer.lines[0].stripped == "Over")
    }

    @Test("Overlay with empty overlay returns base")
    func emptyOverlayReturnsBase() {
        let view = OverlayModifier(
            base: Text("Base"),
            overlay: EmptyView(),
            alignment: .center
        )
        let buffer = render(view)
        #expect(buffer.lines[0].stripped == "Base")
    }

    @Test("Overlay preserves base dimensions")
    func preservesBaseDimensions() {
        let base = Text("Hello World")
        let overlay = Text("Hi")
        let view = OverlayModifier(
            base: base,
            overlay: overlay,
            alignment: .center
        )
        let baseBuffer = render(base)
        let overlayBuffer = render(view)
        #expect(overlayBuffer.width == baseBuffer.width)
        #expect(overlayBuffer.height == baseBuffer.height)
    }

    @Test("Overlay with leading alignment places overlay at start")
    func leadingAlignment() {
        let base = Text("Hello World")
        let overlay = Text("X")
        let view = OverlayModifier(base: base, overlay: overlay, alignment: .leading)
        let buffer = render(view)
        let line = buffer.lines[0].stripped
        #expect(line.hasPrefix("X"))
    }

    @Test("Overlay with trailing alignment places overlay at end")
    func trailingAlignment() {
        let base = Text("Hello World")
        let overlay = Text("X")
        let view = OverlayModifier(base: base, overlay: overlay, alignment: .trailing)
        let buffer = render(view)
        let line = buffer.lines[0].stripped
        #expect(line.hasSuffix("X"))
    }

    @Test("Overlay with topLeading alignment places overlay at top-left")
    func topLeadingAlignment() {
        let base = VStack {
            Text("Line 1")
            Text("Line 2")
            Text("Line 3")
        }
        let overlay = Text("X")
        let view = OverlayModifier(base: base, overlay: overlay, alignment: .topLeading)
        let buffer = render(view)
        #expect(buffer.height >= 3)
        let firstLine = buffer.lines[0].stripped
        #expect(firstLine.hasPrefix("X"))
    }

    @Test("Overlay with bottomTrailing alignment places overlay at bottom-right")
    func bottomTrailingAlignment() {
        let base = VStack {
            Text("Line 1")
            Text("Line 2")
            Text("Line 3")
        }
        let overlay = Text("X")
        let view = OverlayModifier(base: base, overlay: overlay, alignment: .bottomTrailing)
        let buffer = render(view)
        #expect(buffer.height >= 3)
        let lastLine = buffer.lines[buffer.height - 1].stripped
        #expect(lastLine.hasSuffix("X"))
    }

    // MARK: - A line-empty layer is not an empty layer

    /// `FrameBuffer.isEmpty` only inspects in-flow LINES. `OffsetView`'s
    /// documented output is a line-empty buffer whose entire payload is an
    /// `OverlayLayer` — so the empty-buffer shortcut used to return the other
    /// layer and throw the offset content away.
    @Test("An offset overlay survives: the layer is not lost to the empty check")
    func offsetOverlayIsNotDropped() {
        let view = Text("content").overlay(alignment: .topTrailing) {
            Text("*").offset(x: 1, y: -1)
        }
        let buffer = render(view)
        #expect(!buffer.overlays.isEmpty, "the offset badge's layer must reach the result")
        #expect(buffer.lines.first?.stripped.contains("content") == true)
    }

    /// The base side loses more: the content AND its interactivity.
    @Test("An offset BASE keeps its content and hit regions under an overlay")
    func offsetBaseIsNotDropped() {
        let view = Text("Hi").offset(x: 2).overlay { Text("!") }
        let buffer = render(view)
        #expect(!buffer.overlays.isEmpty, "the base's offset layer must survive")
        #expect(
            buffer.lines.joined().stripped.contains("!"),
            "…and the overlay still draws: \(buffer.lines.map(\.stripped))")
    }

    // MARK: - The size-taking spelling

    @Test("offset(CellSize) is offset(x:y:) under SwiftUI's other spelling")
    func offsetTakingASize() {
        // Asserted as an IDENTITY against the labelled form rather than against
        // a hand-written expectation: the two must not be able to drift, and
        // that is the whole content of the claim. A size used as a displacement
        // is SwiftUI's idiom (`offset(_ offset: CGSize)`), which is why the
        // width/height mapping onto columns/rows is worth pinning at all.
        let labelled = render(Text("Hi").offset(x: 2, y: 1).overlay { Text("!") })
        let sized = render(
            Text("Hi").offset(CellSize(width: 2, height: 1)).overlay { Text("!") })
        #expect(labelled.overlays.count == sized.overlays.count)
        #expect(sized.overlays.first?.offsetX == labelled.overlays.first?.offsetX)
        #expect(sized.overlays.first?.offsetY == labelled.overlays.first?.offsetY)
        #expect(sized.overlays.first?.offsetX == 2, "width is columns")
        #expect(sized.overlays.first?.offsetY == 1, "height is rows")
    }

    // MARK: - An overlay is laid out IN the base's frame

    /// The whole distinction between `.overlay` and a `ZStack`: a `ZStack` is
    /// sized by its largest child, an overlay is sized by its BASE and never
    /// changes it. `OverlayModifier.sizeThatFits` answered `max(base, overlay)`
    /// on each axis, so a badge wider than the thing it badges silently pushed
    /// every sibling in the enclosing stack around.
    @Test("A wide overlay does not change the size of the view it is laid over")
    func wideOverlayDoesNotResizeItsBase() {
        let context = testContext()
        let proposal = ProposedSize(width: 80, height: 24)
        let bare = measureChild(Text("Hi"), proposal: proposal, context: context)
        let overlaid = measureChild(
            Text("Hi").overlay { Text("a very much wider overlay") },
            proposal: proposal, context: context)
        #expect(
            overlaid.width == bare.width,
            "an overlay must not widen its base: \(overlaid.width) vs \(bare.width)")
        #expect(overlaid.height == bare.height)
    }

    /// …and the consequence that is actually visible: the stack around it. The
    /// sibling is measured on its own — a stack pads its rows to the widest of
    /// them, so the stack's own width is what decides where the sibling's text
    /// sits and how far the column reaches.
    @Test("A wide overlay does not widen its siblings or the stack holding them")
    func wideOverlayDoesNotWidenTheStack() {
        let context = testContext()
        let proposal = ProposedSize(width: 80, height: 24)
        let plain = measureChild(
            VStack {
                Text("Hi")
                Text("Sibling")
            }, proposal: proposal, context: context)
        let badged = measureChild(
            VStack {
                Text("Hi").overlay(alignment: .topTrailing) {
                    Text("a very much wider overlay")
                }
                Text("Sibling")
            }, proposal: proposal, context: context)
        #expect(
            badged.width == plain.width,
            "the overlay widened the stack: \(badged.width) vs \(plain.width)")
    }

    /// The render half of the same claim, so the two passes cannot drift: a
    /// buffer wider than the size reported for it is the requested-vs-drawn
    /// split every container downstream then has to guess at.
    @Test("The rendered buffer is the base's size, not the overlay's")
    func renderedBufferKeepsTheBasesSize() {
        let base = render(Text("Hi"))
        let overlaid = render(Text("Hi").overlay { Text("a very much wider overlay") })
        #expect(
            overlaid.width == base.width,
            "the composite grew: \(overlaid.width) vs \(base.width)")
        #expect(overlaid.height == base.height)
    }

    /// A layer that really is empty — no lines, no layers, no regions — still
    /// short-circuits, so nothing about the ordinary case changed.
    @Test("A genuinely empty layer still short-circuits")
    func trulyEmptyLayerShortCircuits() {
        let base = render(Text("base").overlay { EmptyView() })
        #expect(base.lines.first?.stripped == "base")
        let overlay = render(EmptyView().overlay { Text("over") })
        #expect(overlay.lines.first?.stripped == "over")
    }
}
