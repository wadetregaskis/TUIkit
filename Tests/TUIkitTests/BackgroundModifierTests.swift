//  TUIKit - Terminal UI Kit for Swift
//  BackgroundModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a default render context for testing.
private func testContext(width: Int = 40, height: Int = 24) -> RenderContext {
    makeBareRenderContext(width: width, height: height)
}

// MARK: - BackgroundModifier Tests

@MainActor
@Suite("BackgroundModifier Tests")
struct BackgroundModifierTests {

    @Test("Background modifier applies ANSI background code")
    func backgroundAppliesCode() {
        let modifier = BackgroundModifier(color: .red)
        let buffer = FrameBuffer(lines: ["Hello"])
        let context = testContext()

        let result = modifier.modify(buffer: buffer, context: context)

        #expect(result.height == 1)
        // Should contain ANSI red background code (41)
        let line = result.lines[0]
        #expect(line.contains("\u{1B}[41m"))
        #expect(line.contains("Hello"))
        // Should end with reset
        #expect(line.hasSuffix(ANSIRenderer.reset))
    }

    @Test("Background modifier preserves line count")
    func backgroundPreservesLineCount() {
        let modifier = BackgroundModifier(color: .blue)
        let buffer = FrameBuffer(lines: ["Line 1", "Line 2", "Line 3"])
        let context = testContext()

        let result = modifier.modify(buffer: buffer, context: context)

        #expect(result.height == 3)
    }

    @Test("Background modifier on empty buffer returns empty")
    func backgroundEmptyBuffer() {
        let modifier = BackgroundModifier(color: .green)
        let buffer = FrameBuffer()
        let context = testContext()

        let result = modifier.modify(buffer: buffer, context: context)

        #expect(result.isEmpty)
    }

    @Test("Background modifier pads lines to full width")
    func backgroundPadsLines() {
        let modifier = BackgroundModifier(color: .red)
        let buffer = FrameBuffer(lines: ["Short", "VeryLongLine"])
        let context = testContext()

        let result = modifier.modify(buffer: buffer, context: context)

        // Both lines should have the same visible width after padding
        #expect(result.lines[0].strippedLength == result.lines[1].strippedLength)
    }

    @Test("Background persists across a child's interior ANSI resets (no holes)")
    func backgroundPersistsAcrossResets() {
        // Child content that closes a foreground run mid-line emits an interior
        // reset; the fill must survive it (the old naive wrap left the rest of the
        // line — trailing cells, sub-views — on the terminal default).
        let inner = ANSIRenderer.colorize("AB", foreground: .blue) + "CD"  // <fg>AB<reset>CD
        let result = BackgroundModifier(color: .red).modify(
            buffer: FrameBuffer(lines: [inner]), context: testContext())
        let line = result.lines[0]
        let bg = ANSIRenderer.backgroundCode(for: .red)
        let resets = line.components(separatedBy: ANSIRenderer.reset).count - 1
        let backgrounds = line.components(separatedBy: bg).count - 1
        #expect(resets >= 2, "the inner content + the trailing reset give ≥2 resets")
        #expect(resets == backgrounds,
                "the background is re-applied after every reset (\(backgrounds) bg vs \(resets) resets)")
    }
}
