//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBufferTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("FrameBuffer Tests")
struct FrameBufferTests {

    @Test("Empty buffer has zero dimensions")
    func emptyBuffer() {
        let buffer = FrameBuffer()
        #expect(buffer.width == 0)
        #expect(buffer.height == 0)
        #expect(buffer.isEmpty)
    }

    @Test("Single line buffer has correct dimensions")
    func singleLine() {
        let buffer = FrameBuffer(text: "Hello")
        #expect(buffer.width == 5)
        #expect(buffer.height == 1)
        #expect(buffer.lines == ["Hello"])
    }

    @Test("Vertical append stacks lines")
    func verticalAppend() {
        var buffer = FrameBuffer(text: "Line 1")
        buffer.appendVertically(FrameBuffer(text: "Line 2"))
        #expect(buffer.height == 2)
        #expect(buffer.lines == ["Line 1", "Line 2"])
    }

    @Test("Vertical append with spacing")
    func verticalAppendWithSpacing() {
        var buffer = FrameBuffer(text: "Top")
        buffer.appendVertically(FrameBuffer(text: "Bottom"), spacing: 2)
        #expect(buffer.height == 4)
        #expect(buffer.lines == ["Top", "", "", "Bottom"])
    }

    @Test("Horizontal append places side by side")
    func horizontalAppend() {
        var buffer = FrameBuffer(text: "Left")
        buffer.appendHorizontally(FrameBuffer(text: "Right"), spacing: 1)
        #expect(buffer.height == 1)
        #expect(buffer.lines == ["Left Right"])
    }

    @Test("Horizontal append with different heights pads correctly")
    func horizontalAppendDifferentHeights() {
        var left = FrameBuffer(lines: ["AB", "CD"])
        let right = FrameBuffer(text: "X")
        left.appendHorizontally(right, spacing: 1)
        #expect(left.height == 2)
        #expect(left.lines[0] == "AB X")
        // Row 1: "CD" padded to width 2, spacing " ", no right content
        #expect(left.lines[1] == "CD ")
    }

    @Test("ANSI codes are excluded from width calculation")
    func ansiStrippedWidth() {
        let styled = "\u{1B}[1mBold\u{1B}[0m"
        let buffer = FrameBuffer(text: styled)
        #expect(buffer.width == 4)  // "Bold" is 4 chars
    }

    @Test("Horizontal append with ANSI codes pads correctly")
    func horizontalAppendWithAnsi() {
        let styled = "\u{1B}[1mHi\u{1B}[0m"
        var left = FrameBuffer(text: styled)
        left.appendHorizontally(FrameBuffer(text: "There"), spacing: 1)
        #expect(left.height == 1)
        // "Hi" (styled) + " " (spacing) + "There"
        #expect(left.lines[0].stripped == "Hi There")
    }
}

@MainActor
@Suite("Overlay Tests")
struct OverlayTests {

    @Test("Overlay modifier renders overlay on top of base")
    func overlayRendering() {
        let view = Text("Base Content")
            .overlay(alignment: .center) {
                Text("Top")
            }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        // The overlay "Top" should be centered on "Base Content"
        #expect(buffer.height >= 1)
        let allContent = buffer.lines.joined()
        #expect(allContent.contains("Top"))
    }

    @Test("Dimmed modifier strips styling and applies uniform palette colors")
    func dimmedRendering() {
        let view = Text("Dimmed text").dimmed()
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.height == 1)
        // Should not use ANSI dim — uses palette-based flat coloring now
        #expect(!buffer.lines[0].contains("\u{1B}[2m"))
        // Visible text must be preserved
        #expect(buffer.lines[0].stripped.contains("Dimmed text"))
    }

    @Test("The convenience .modal presents a centred modal over the dimmed base")
    func modalRendering() {
        let view = Text("Background")
            .modal {
                Text("Modal")
            }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        // The convenience modal now goes through the real presentation path: a
        // dimmed base with the modal centred on top (rather than a bare overlay
        // composited onto the single base line).
        let all = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        #expect(all.contains("Background"), "the dimmed base is shown")
        #expect(all.contains("Modal"), "the modal content is shown over the base")
    }

    @Test("FrameBuffer compositing places overlay at correct position")
    func frameBufferCompositing() {
        let base = FrameBuffer(lines: ["AAAA", "AAAA", "AAAA"])
        let overlay = FrameBuffer(text: "X")

        // Place overlay at position (1, 1)
        let result = base.composited(with: overlay, at: (x: 1, y: 1))

        #expect(result.height == 3)
        #expect(result.lines[0] == "AAAA")
        #expect(result.lines[1].contains("X"))
        #expect(result.lines[2] == "AAAA")
    }

    @Test("FrameBuffer compositing with offset")
    func frameBufferCompositingOffset() {
        let base = FrameBuffer(lines: ["1234567890"])
        let overlay = FrameBuffer(text: "XXX")

        // Place overlay at column 3
        let result = base.composited(with: overlay, at: (x: 3, y: 0))

        #expect(result.lines[0].stripped == "123XXX7890")
    }
}
