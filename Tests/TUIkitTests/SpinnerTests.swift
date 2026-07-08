//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SpinnerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context for spinner testing.
private func testContext(width: Int = 40, height: Int = 24) -> RenderContext {
    makeBareRenderContext(width: width, height: height)
}

// MARK: - SpinnerStyle Tests

@MainActor
@Suite("SpinnerStyle Tests")
struct SpinnerStyleTests {

    @Test("Dots style has 10 braille frames")
    func dotsFrameCount() {
        let frames = SpinnerStyle.dots.frames
        #expect(frames.count == 10)
        #expect(frames[0] == "⠋")
        #expect(frames[9] == "⠏")
    }

    @Test("Line style has 4 ASCII frames")
    func lineFrameCount() {
        let frames = SpinnerStyle.line.frames
        #expect(frames.count == 4)
        #expect(frames[0] == "|")
        #expect(frames[1] == "/")
        #expect(frames[2] == "-")
        #expect(frames[3] == "\\")
    }

    @Test("Bouncing positions form a complete bounce cycle with edge overshoot")
    func bouncingPositions() {
        let positions = SpinnerStyle.bouncingPositions(trackLength: SpinnerStyle.trackWidth)
        let overshoot = SpinnerStyle.edgeOvershoot  // 2

        // Range: -2 → 10 (13 forward) + 10 back positions (9 → -1) = 24
        let forwardCount = SpinnerStyle.trackWidth + 2 * overshoot  // 13
        let backwardCount = forwardCount - 2  // 11
        #expect(positions.count == forwardCount + backwardCount)

        // Forward sweep starts at -overshoot
        #expect(positions[0] == -overshoot)
        // Forward sweep ends at trackWidth - 1 + overshoot
        #expect(positions[forwardCount - 1] == SpinnerStyle.trackWidth - 1 + overshoot)
    }

    @Test("Bouncing positions have no consecutive duplicates")
    func bouncingNoDuplicateEndpoints() {
        let positions = SpinnerStyle.bouncingPositions(trackLength: SpinnerStyle.trackWidth)

        for index in 1..<positions.count {
            #expect(positions[index] != positions[index - 1])
        }

        // Last and first differ (smooth looping)
        #expect(positions.last != positions.first)
    }

    @Test("Each style has a positive animation interval")
    func styleIntervals() {
        #expect(SpinnerStyle.dots.interval > 0)
        #expect(SpinnerStyle.line.interval > 0)
        #expect(SpinnerStyle.bouncing.interval > 0)
    }

    @Test("Bouncing frame renders highlight and inactive track characters")
    func bouncingFrameRendering() {
        let frame = SpinnerStyle.renderBouncingFrame(
            frameIndex: 3,
            color: .red,
            trackColor: .white
        )

        // All positions use ● with varying opacity
        #expect(frame.stripped.contains("●"))
        // Should have ANSI escape codes for coloring
        #expect(frame.contains("\u{1B}["))
    }

    @Test("Bouncing animation is left-right symmetric (both edges condense equally)")
    func bouncingMirrorSymmetry() {
        // The highlight sweeps right then left, so a horizontal mirror of the
        // animation is the same animation, just phase-shifted: reversing every
        // frame's cells must yield the same multiset of frames over a full cycle.
        // A regression here means one edge condenses differently from the other
        // — e.g. the left turnaround "resetting" a frame early (the trail flipping
        // off-screen before the dots finish condensing into the leftmost cell).
        let cycle = SpinnerStyle.bouncingPositions(trackLength: SpinnerStyle.trackWidth).count

        // Split a rendered frame into its per-cell strings (each cell ends in a reset).
        func cells(_ frame: String) -> [String] {
            frame
                .replacing("\u{1B}[0m", with: "\u{1B}[0m\u{1}")
                .split(separator: "\u{1}")
                .map(String.init)
        }

        let frames = (0..<cycle).map {
            cells(SpinnerStyle.renderBouncingFrame(frameIndex: $0, color: .red, trackColor: .white))
        }
        // Every frame has one cell per visible track position.
        #expect(frames.allSatisfy { $0.count == SpinnerStyle.trackWidth })

        let forward = frames.map { $0.joined() }.sorted()
        let mirrored = frames.map { Array($0.reversed()).joined() }.sorted()
        #expect(forward == mirrored, "Bouncing animation is not left-right symmetric")
    }
}

// MARK: - Spinner Rendering Tests

@MainActor
@Suite("Spinner Rendering Tests")
struct SpinnerRenderingTests {

    @Test("Spinner without label renders single spinner character")
    func spinnerWithoutLabel() {
        let spinner = Spinner(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(spinner, context: context)

        #expect(buffer.lines.count == 1)
        // First frame of line style is "|", colored with accent
        #expect(buffer.lines[0].stripped.contains("|"))
    }

    @Test("Spinner with label renders spinner followed by label text")
    func spinnerWithLabel() {
        let spinner = Spinner("Loading...", style: .line)
        let context = testContext()
        let buffer = renderToBuffer(spinner, context: context)

        #expect(buffer.lines.count == 1)
        let stripped = buffer.lines[0].stripped
        #expect(stripped.contains("Loading..."))
        #expect(stripped.contains("|"))
    }

    @Test("Whitespace-only label is honoured, not dropped")
    func spinnerWhitespaceLabel() {
        // The no-break-space padding label is a documented alignment
        // workaround (GitHub issue #5); U+00A0 satisfies `isWhitespace`, so a
        // blank-label check must not discard it.
        let spinner = Spinner("\u{A0}\u{A0}\u{A0}", style: .line)
        let context = testContext()
        let stripped = renderToBuffer(spinner, context: context).lines[0].stripped

        #expect(stripped.strippedLength == 5, "glyph + separator + 3 NBSP cells: '\(stripped)'")
        #expect(stripped.contains("\u{A0}"), "the NBSP label survives to the output")
    }

    @Test("Empty label renders the bare glyph with no separator")
    func spinnerEmptyLabel() {
        let spinner = Spinner("", style: .line)
        let context = testContext()
        let stripped = renderToBuffer(spinner, context: context).lines[0].stripped

        #expect(stripped.strippedLength == 1, "no trailing separator space: '\(stripped)'")
    }

    @Test("Spinner renders with custom color")
    func spinnerCustomColor() {
        let spinner = Spinner(style: .dots, color: .red)
        let context = testContext()
        let buffer = renderToBuffer(spinner, context: context)

        #expect(buffer.lines.count == 1)
        // Red foreground ANSI code
        #expect(buffer.lines[0].contains("\u{1B}[31m"))
    }

    @Test("Dots spinner first frame is braille character")
    func dotsFirstFrame() {
        let spinner = Spinner(style: .dots)
        let context = testContext()
        let buffer = renderToBuffer(spinner, context: context)

        #expect(buffer.lines[0].stripped == "⠋")
    }

    @Test("Bouncing spinner renders track with 9 visible positions")
    func bouncingRendersTrack() {
        let spinner = Spinner(style: .bouncing)
        let context = testContext()
        let buffer = renderToBuffer(spinner, context: context)

        let stripped = buffer.lines[0].stripped
        // Track is always 9 characters wide (mix of ● • and · depending on
        // highlight position — the first frame may be off-screen due to
        // edge overshoot, so we check total character count instead).
        let trackChars = stripped.filter { $0 == "●" || $0 == "•" || $0 == "·" }
        #expect(trackChars.count == SpinnerStyle.trackWidth)
    }

    @Test("Spinner frame index is derived from elapsed time")
    func spinnerTimeBasedFrames() {
        let spinner = Spinner(style: .line)
        let context = testContext()

        // Two immediate renders produce the same frame (same elapsed time bucket)
        let buffer1 = renderToBuffer(spinner, context: context)
        let buffer2 = renderToBuffer(spinner, context: context)

        #expect(buffer1.lines[0].stripped == buffer2.lines[0].stripped)
    }

    // MARK: - New styles

    @Test("Each new frame-based style has the expected frames, positive interval")
    func newStyleFrames() {
        #expect(SpinnerStyle.pie.frames == ["◴", "◷", "◶", "◵"])
        #expect(SpinnerStyle.beachball.frames == ["◐", "◓", "◑", "◒"])
        #expect(SpinnerStyle.box.frames == ["◰", "◳", "◲", "◱"])
        #expect(SpinnerStyle.bars.frames.first == "▁")
        #expect(SpinnerStyle.blockWedge.frames == ["▙", "▛", "▜", "▟"])
        #expect(SpinnerStyle.moon.frames.count == 8)
        #expect(SpinnerStyle.earth.frames.count == 3)
        #expect(SpinnerStyle.clock.frames.count == 24)
        for style: SpinnerStyle in [.pie, .beachball, .box, .bars, .blockWedge, .moon, .earth, .clock] {
            #expect(style.interval > 0)
            #expect(!style.frames.isEmpty)
        }
    }

    @Test("The emoji styles render as double-width glyphs, uniform across frames")
    func emojiStyleWidths() {
        for style: SpinnerStyle in [.moon, .earth, .clock] {
            let widths = Set(style.frames.map(\.strippedLength))
            #expect(widths == [2], "\(style) frames must all be width-2: \(widths)")
        }
    }

    @Test("A custom spinner cycles each character of its sequence")
    func customStyleFrames() {
        #expect(SpinnerStyle.custom("123432").frames == ["1", "2", "3", "4", "3", "2"])
        // An empty sequence degrades to a single blank frame (no crash).
        #expect(SpinnerStyle.custom("").frames == [" "])
        // Renders on one line like any other spinner.
        let buffer = renderToBuffer(Spinner(style: .custom("AB")), context: testContext())
        #expect(buffer.height == 1)
    }
}
