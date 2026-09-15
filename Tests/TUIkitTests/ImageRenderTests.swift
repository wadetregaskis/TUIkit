//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

// MARK: - Test Helpers

@MainActor
private func createTestContext(width: Int = 20, height: Int = 6) -> RenderContext {
    let focusManager = FocusManager()
    var environment = EnvironmentValues()
    environment.focusManager = focusManager
    // Side-effect-free (snapshot) render: the lifecycle must NOT fire `.task`
    // effects. `Image` otherwise starts an async load of the (nonexistent)
    // source on first render; for a missing file that task fails fast and
    // flips the loading phase to `.failure`, so under full-suite contention a
    // render here could land on the "Error: …" path instead of the spinner —
    // an intermittent flake that broke the `"⠋"` assertions (notably the
    // force-unwrap in `spinnerHorizontallyCentred`). Pinning the lifecycle so
    // effects don't fire keeps the phase at `.loading` — the only output an
    // isolated synchronous render is meant to pin (see suite comment below) —
    // and mirrors how `ViewRenderer` performs its snapshot renders.
    let tuiContext = TUIContext(
        lifecycle: LifecycleManager(firesEffects: false),
        keyEventDispatcher: KeyEventDispatcher(),
        preferences: PreferenceStorage()
    )
    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: tuiContext
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
    func spinnerHorizontallyCentred() throws {
        let buffer = renderToBuffer(Image(.file("/nope.png")), context: createTestContext(width: 21, height: 5))
        // `#require` rather than a force-unwrap: a missing spinner row reports a
        // clean test failure instead of trapping the whole process.
        let row = try #require(buffer.lines.map { $0.stripped }.first { $0.contains("⠋") })
        let leading = row.prefix { $0 == " " }.count
        // One glyph in a 21-wide row centres at ~10 leading spaces.
        #expect(leading == 10)
    }

    // MARK: The spinner is a Spinner

    /// Where the placeholder's `"⠋"` landed, as (column, row) in cells.
    private func spinnerCell(in buffer: FrameBuffer) -> (column: Int, row: Int)? {
        let lines = buffer.lines.map { $0.stripped }
        guard let row = lines.firstIndex(where: { $0.contains("⠋") }) else { return nil }
        return (lines[row].prefix { $0 == " " }.count, row)
    }

    /// The frame length of every run `buffer` leaves, in ticks of 1/60 s.
    private func runTicks(_ buffer: FrameBuffer) -> [Int] {
        buffer.animatedCells.map(\.frameTicks)
    }

    @Test("The loading placeholder's spinner animates, over its own cell, at the .dots interval")
    func placeholderSpinnerAnimates() throws {
        let buffer = renderToBuffer(Image(.file("/nope.png")), context: createTestContext())
        #expect(runTicks(buffer) == [AnimationClock.frameTicks(forSeconds: SpinnerStyle.dots.interval)])
        let run = try #require(buffer.animatedCells.first)
        let cell = try #require(spinnerCell(in: buffer))
        #expect(run.offsetX == cell.column && run.offsetY == cell.row, "the run sits on the glyph")
        #expect(run.width == 1)
    }

    @Test("The placeholder's spinner follows the speed set for spinners")
    func placeholderSpinnerFollowsTheSpeed() {
        let buffer = renderToBuffer(
            Image(.file("/nope.png")).indicatorAnimationSpeed(2, for: .spinners),
            context: createTestContext())
        #expect(runTicks(buffer) == [4], ".dots' 7 ticks at twice the speed are 3.5, which rounds to 4 ticks")
    }

    @Test("With the spinner off, the placeholder leaves no run")
    func noSpinnerNoRun() {
        let textOnly = renderToBuffer(
            Image(.file("/nope.png")).imagePlaceholder("Wait…").imagePlaceholderSpinner(false),
            context: createTestContext())
        #expect(textOnly.animatedCells.isEmpty)
        let fallback = renderToBuffer(
            Image(.file("/nope.png")).imagePlaceholderSpinner(false), context: createTestContext())
        #expect(fallback.animatedCells.isEmpty)
    }

    @Test("A foregroundStyle on the image tints the placeholder's spinner, and not its caption")
    func foregroundStyleTintsTheSpinner() throws {
        let buffer = renderToBuffer(
            Image(.file("/nope.png")).imagePlaceholder("Loading photo").foregroundStyle(Color.ansi(.red)),
            context: createTestContext(width: 24, height: 6))
        let red = Color.ansi(.red).foregroundCodes().joined(separator: ";")
        let spinnerRow = try #require(buffer.lines.first { $0.contains("⠋") })
        #expect(spinnerRow.contains(red), "the glyph is red: \(spinnerRow.debugDescription)")
        let captionRow = try #require(buffer.lines.first { $0.stripped.contains("Loading photo") })
        #expect(!captionRow.contains(red), "the caption keeps its own colour: \(captionRow.debugDescription)")
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

    // MARK: Over-wide content

    @Test("A placeholder wider than its box is cut to the box, not painted past it")
    func overWidePlaceholderIsClippedToTheBox() {
        // "Loading..." is 10 cells; the box is 6. Before the clip in
        // `centerContent` the content row measured 10 on a buffer declaring 6,
        // and no container could cut it: every clamp passes `availableWidth` as
        // its limit, which is the number this buffer already declares, so
        // `FrameBuffer.clamped`'s `self.width <= maxWidth` fast path returned it
        // untouched.
        let buffer = renderToBuffer(
            Image(.file("/nope.png")).imagePlaceholderSpinner(false),
            context: createTestContext(width: 6, height: 3))
        #expect(buffer.width == 6)
        // Cells, not Characters: the declared width is a promise about columns.
        #expect(
            buffer.lines.allSatisfy { $0.strippedLength <= buffer.width },
            "declared \(buffer.width) columns, rows measure \(buffer.lines.map { $0.strippedLength })")
    }

    @Test("An over-wide placeholder does not push an HStack sibling off the box edge")
    func overWidePlaceholderDoesNotShearItsSibling() {
        // The symptom the clip removes: `appendHorizontally` measures the REAL
        // width of the over-wide row, so the bar landed at column 10 on that one
        // row and at column 6 on the two blank rows of the same box — while the
        // composite went on reporting 7 columns.
        let buffer = renderToBuffer(
            HStack(spacing: 0) {
                Image(.file("/nope.png"))
                    .imagePlaceholderSpinner(false)
                    .frame(width: 6, height: 3)
                Text("|")
            },
            context: createTestContext(width: 20, height: 3))
        #expect(
            buffer.lines.allSatisfy { $0.strippedLength <= buffer.width },
            "declared \(buffer.width) columns, rows measure \(buffer.lines.map { $0.strippedLength })")
    }
}
