//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

@MainActor
private func createTestContext(width: Int = 20, height: Int = 6) -> RenderContext {
    let focusManager = FocusManager()
    var environment = EnvironmentValues()
    environment.focusManager = focusManager
    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: TUIContext()
    ).isolatingRenderCache()
}

// MARK: - Image Rendering Tests
//
// `Image` loads asynchronously. A single synchronous `renderToBuffer` starts
// the load task but cannot complete it, so the buffer it returns is always the
// *placeholder* phase. These tests therefore pin the placeholder rendering —
// the only output an isolated synchronous render can produce. (The success /
// failure ASCII-conversion paths are covered at the converter level in
// `ImageTests`.)

@MainActor
@Suite("Image rendering (placeholder phase)")
struct ImageRenderTests {

    // MARK: Default placeholder

    @Test("Default placeholder fills the frame and centres a spinner glyph")
    func defaultPlaceholderSpinner() {
        let buffer = renderToBuffer(Image(.file("/does-not-exist.png")), context: createTestContext())
        let lines = buffer.lines.map { $0.stripped }

        // Buffer occupies the full requested footprint.
        #expect(buffer.width == 20)
        #expect(buffer.height == 6)

        // Exactly one row carries the spinner; the rest are blank.
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(nonBlank.count == 1)
        #expect(nonBlank[0].contains("⠋"))

        // The spinner sits on the vertically-centred row (height 6 → row 2 or 3).
        let spinnerRow = lines.firstIndex { $0.contains("⠋") }
        #expect(spinnerRow == 2 || spinnerRow == 3)
    }

    @Test("Spinner is horizontally centred within the frame")
    func spinnerHorizontallyCentred() {
        let buffer = renderToBuffer(Image(.file("/nope.png")), context: createTestContext(width: 21, height: 5))
        let row = buffer.lines.map { $0.stripped }.first { $0.contains("⠋") }!
        let leading = row.prefix { $0 == " " }.count
        // One glyph in a 21-wide row centres at ~10 leading spaces.
        #expect(leading == 10)
    }

    // MARK: Custom text, no spinner

    @Test("Disabling the spinner with custom text shows just the text, centred")
    func customTextNoSpinner() {
        let buffer = renderToBuffer(
            Image(.file("/nope.png")).imagePlaceholder("Wait…").imagePlaceholderSpinner(false),
            context: createTestContext())
        let lines = buffer.lines.map { $0.stripped }

        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(nonBlank.count == 1)
        #expect(nonBlank[0].trimmingCharacters(in: .whitespaces) == "Wait…")
        // No spinner glyph when the spinner is disabled.
        #expect(!lines.contains { $0.contains("⠋") })
    }

    @Test("Spinner plus text renders both on separate centred rows")
    func spinnerAndText() {
        let buffer = renderToBuffer(
            Image(.file("/nope.png")).imagePlaceholder("Loading photo"),
            context: createTestContext(width: 24, height: 6))
        let lines = buffer.lines.map { $0.stripped }
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        #expect(nonBlank.count == 2)
        #expect(nonBlank.contains { $0.contains("⠋") })
        #expect(nonBlank.contains { $0.trimmingCharacters(in: .whitespaces) == "Loading photo" })
    }

    // MARK: No spinner, no text

    @Test("No spinner and no text falls back to a centred \"Loading...\"")
    func fallbackLoadingText() {
        let buffer = renderToBuffer(
            Image(.file("/nope.png")).imagePlaceholderSpinner(false),
            context: createTestContext())
        let lines = buffer.lines.map { $0.stripped }
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        #expect(nonBlank.count == 1)
        #expect(nonBlank[0].trimmingCharacters(in: .whitespaces) == "Loading...")
    }

    // MARK: Dimensions / shape

    @Test("Placeholder buffer reports the full frame width and height")
    func placeholderBufferDimensions() {
        let buffer = renderToBuffer(Image(.file("/nope.png")), context: createTestContext(width: 18, height: 5))
        // The blank rows fill the width, so the buffer's reported width is the
        // full frame; the centred content row is left-padded (never wider).
        #expect(buffer.width == 18)
        #expect(buffer.lines.count == 5)
        #expect(buffer.lines.allSatisfy { $0.stripped.count <= 18 })
        // The blank rows (no spinner) are padded out to the full width.
        let blankRows = buffer.lines.map { $0.stripped }.filter { !$0.contains("⠋") }
        #expect(blankRows.allSatisfy { $0.count == 18 })
    }

    @Test("URL-source placeholder behaves identically to a file source")
    func urlSourcePlaceholder() {
        let buffer = renderToBuffer(
            Image(.url("https://example.com/x.png")),
            context: createTestContext(width: 20, height: 6))
        let nonBlank = buffer.lines.map { $0.stripped }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(nonBlank.count == 1)
        #expect(nonBlank[0].contains("⠋"))
    }

    // MARK: Degenerate sizes

    @Test("Zero-width frame renders an empty buffer (no crash)")
    func zeroWidthEmpty() {
        let buffer = renderToBuffer(Image(.file("/nope.png")), context: createTestContext(width: 0, height: 6))
        #expect(buffer.isEmpty)
    }

    @Test("Zero-height frame renders an empty buffer (no crash)")
    func zeroHeightEmpty() {
        let buffer = renderToBuffer(Image(.file("/nope.png")), context: createTestContext(width: 20, height: 0))
        #expect(buffer.isEmpty)
    }

    @Test("Single-cell frame still renders a placeholder without overflowing")
    func singleCellFrame() {
        let buffer = renderToBuffer(Image(.file("/nope.png")), context: createTestContext(width: 1, height: 1))
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines.allSatisfy { $0.stripped.count <= 1 })
    }
}
