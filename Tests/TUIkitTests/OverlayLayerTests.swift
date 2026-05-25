//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OverlayLayerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context with a fresh FocusManager for isolated testing.
private func makeContext(width: Int = 80, height: Int = 24) -> RenderContext {
    let focusManager = FocusManager()
    var environment = EnvironmentValues()
    environment.focusManager = focusManager
    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: TUIContext()
    )
}

/// A leaf test view that renders one visible line and emits one overlay layer
/// flush against its own top-left corner.
private struct OverlayProbe: View, Renderable {
    var body: Never { fatalError("OverlayProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: ["XX"])
        buffer.overlays = [
            OverlayLayer(offsetX: 0, offsetY: 0, content: FrameBuffer(lines: ["POP"]))
        ]
        return buffer
    }
}

// MARK: - FrameBuffer Overlay Propagation

@MainActor
@Suite("Overlay Layer Propagation Tests")
struct OverlayLayerPropagationTests {

    private func layeredBuffer(_ lines: [String], overlayAt offset: (Int, Int)) -> FrameBuffer {
        var buffer = FrameBuffer(lines: lines)
        buffer.overlays = [
            OverlayLayer(offsetX: offset.0, offsetY: offset.1, content: FrameBuffer(lines: ["L"]))
        ]
        return buffer
    }

    @Test("OverlayLayer.shifted offsets both axes")
    func shiftedOffsets() {
        let layer = OverlayLayer(offsetX: 2, offsetY: 3, content: FrameBuffer(lines: ["x"]))
        let moved = layer.shifted(byX: 5, y: 7)
        #expect(moved.offsetX == 7)
        #expect(moved.offsetY == 10)
    }

    @Test("appendVertically shifts the appended buffer's overlays down")
    func appendVerticalShiftsOverlays() {
        var top = FrameBuffer(lines: ["AAA", "AAA"])
        let bottom = layeredBuffer(["BBB"], overlayAt: (1, 0))
        top.appendVertically(bottom)

        #expect(top.overlays.count == 1)
        // Bottom started two rows down, so its overlay shifts by 2.
        #expect(top.overlays[0].offsetY == 2)
        #expect(top.overlays[0].offsetX == 1)
    }

    @Test("appendVertically keeps overlays from both buffers")
    func appendVerticalKeepsBothOverlays() {
        var top = layeredBuffer(["AAA"], overlayAt: (0, 0))
        let bottom = layeredBuffer(["BBB"], overlayAt: (0, 0))
        top.appendVertically(bottom, spacing: 1)

        #expect(top.overlays.count == 2)
        #expect(top.overlays[0].offsetY == 0)
        // Bottom lands after one line of content plus one line of spacing.
        #expect(top.overlays[1].offsetY == 2)
    }

    @Test("appendHorizontally shifts the appended buffer's overlays right")
    func appendHorizontalShiftsOverlays() {
        var left = FrameBuffer(lines: ["AAAA"])
        let right = layeredBuffer(["B"], overlayAt: (0, 0))
        left.appendHorizontally(right, spacing: 2)

        #expect(left.overlays.count == 1)
        // Right starts past 4 columns of content plus 2 of spacing.
        #expect(left.overlays[0].offsetX == 6)
    }

    @Test("overlay() carries layers without shifting them")
    func overlayCarriesLayers() {
        var base = FrameBuffer(lines: ["AAA"])
        let top = layeredBuffer(["BBB"], overlayAt: (3, 4))
        base.overlay(top)

        #expect(base.overlays.count == 1)
        #expect(base.overlays[0].offsetX == 3)
        #expect(base.overlays[0].offsetY == 4)
    }

    @Test("clamped preserves overlay layers while truncating content")
    func clampedPreservesOverlays() {
        let buffer = layeredBuffer(["AAAAAAAA"], overlayAt: (0, 5))
        let clamped = buffer.clamped(toWidth: 3, height: 1)

        #expect(clamped.width == 3)
        #expect(clamped.overlays.count == 1)
        // The free-floating layer is untouched by content clamping.
        #expect(clamped.overlays[0].offsetY == 5)
    }

    @Test("composited lifts a nested overlay shifted by the paste position")
    func compositedLiftsNestedOverlays() {
        let base = FrameBuffer(lines: ["..........", ".........."])
        let pasted = layeredBuffer(["P"], overlayAt: (1, 1))
        let result = base.composited(with: pasted, at: (x: 4, y: 1))

        #expect(result.overlays.count == 1)
        // Nested overlay offset (1,1) plus paste position (4,1).
        #expect(result.overlays[0].offsetX == 5)
        #expect(result.overlays[0].offsetY == 2)
    }

    @Test("replacingLines shifts overlays by the given amount")
    func replacingLinesShiftsOverlays() {
        let buffer = layeredBuffer(["AB"], overlayAt: (0, 0))
        let replaced = buffer.replacingLines(["  AB  "], overlayShiftX: 2, overlayShiftY: 1)

        #expect(replaced.lines == ["  AB  "])
        #expect(replaced.overlays.count == 1)
        #expect(replaced.overlays[0].offsetX == 2)
        #expect(replaced.overlays[0].offsetY == 1)
    }
}

// MARK: - Container Overlay Propagation

@MainActor
@Suite("Overlay Container Propagation Tests")
struct OverlayContainerPropagationTests {

    @Test("A VStack carries a child's overlay layer, shifted past earlier siblings")
    func vStackPropagatesChildOverlay() {
        let context = makeContext()
        let stack = VStack(alignment: .leading, spacing: 0) {
            Text("AAA")
            OverlayProbe()
        }
        let buffer = renderToBuffer(stack, context: context)

        #expect(buffer.overlays.count == 1)
        // The probe sits below a single heading line, so its overlay shifts
        // down by one row; leading alignment keeps the x offset at zero.
        #expect(buffer.overlays[0].offsetY == 1)
        #expect(buffer.overlays[0].offsetX == 0)
    }

    @Test("Padding shifts a wrapped view's overlay by its insets")
    func paddingShiftsOverlay() {
        let context = makeContext()
        let padded = OverlayProbe().padding(EdgeInsets(top: 2, leading: 3, bottom: 0, trailing: 0))
        let buffer = renderToBuffer(padded, context: context)

        #expect(buffer.overlays.count == 1)
        #expect(buffer.overlays[0].offsetX == 3)
        #expect(buffer.overlays[0].offsetY == 2)
    }
}

// MARK: - Z-Index & ZStack

@MainActor
@Suite("Z-Index Tests")
struct ZIndexTests {

    @Test("zIndex renders its content transparently")
    func zIndexIsTransparent() {
        let context = makeContext()
        let withZ = renderToBuffer(Text("Hello").zIndex(3), context: context)
        let plain = renderToBuffer(Text("Hello"), context: context)
        #expect(withZ.lines.joined().stripped == plain.lines.joined().stripped)
    }

    @Test("ZStack draws a higher-zIndex child on top regardless of tree order")
    func zStackHonoursZIndex() {
        let context = makeContext()

        // "BBB" appears first in the tree but carries a higher z-index, so it
        // must be drawn last — on top of "AAA".
        let stack = ZStack {
            Text("BBB").zIndex(1)
            Text("AAA")
        }
        let buffer = renderToBuffer(stack, context: context)
        #expect(buffer.lines.joined().stripped == "BBB")
    }

    @Test("ZStack keeps tree order when z-indices are equal")
    func zStackStableForEqualZIndex() {
        let context = makeContext()
        let stack = ZStack {
            Text("AAA")
            Text("BBB")
        }
        let buffer = renderToBuffer(stack, context: context)
        // Equal (default) z-index: the later sibling wins, as before.
        #expect(buffer.lines.joined().stripped == "BBB")
    }
}
