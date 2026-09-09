//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    @Test("The bounce never goes dark, so the dots never appear to reset")
    func bouncingNeverGoesDark() {
        // The trail used to be derived from the CURRENT direction — "the cells
        // behind me". That is right mid-sweep and wrong at each turnaround,
        // where the direction flips while the glow is still on the far side: the
        // trail jumped across the highlight, and on the two frames where the
        // highlight itself is off-track it left nothing behind at all. Both
        // ends went blank for a frame, which reads as the animation resetting
        // early rather than the dots condensing into the end.
        let cycle = SpinnerStyle.bouncingPositions(trackLength: SpinnerStyle.trackWidth).count
        let track = Color.brightBlack
        for index in 0..<cycle {
            let frame = SpinnerStyle.renderBouncingFrame(
                frameIndex: index, color: .red, trackColor: track)
            let lit = frame.contains(ANSIRenderer.colorize("●", foreground: .red))
                || frame != String(
                    repeating: ANSIRenderer.colorize("●", foreground: track),
                    count: SpinnerStyle.trackWidth)
            #expect(lit, "frame \(index) of \(cycle) is entirely track colour")
        }
    }

    @Test("The glow follows where the dot has been, not where it is going")
    func bouncingTrailFollowsHistory() {
        // Frame 2 is the dot's first frame ON the track (positions -2, -1 then
        // 0), reached from the left after the wrap. Cell 0 holds the highlight;
        // the cells to its RIGHT were where the dot was a few frames ago, coming
        // in leftward, so they must still be glowing. Under the old
        // direction-derived trail they were dark, because "behind" had just
        // flipped to mean the (off-track) left.
        let plain = ANSIRenderer.colorize("●", foreground: Color.brightBlack)
        let frame = SpinnerStyle.renderBouncingFrame(
            frameIndex: 2, color: .red, trackColor: .brightBlack)
        let cells =
            frame
            .replacing("\u{1B}[0m", with: "\u{1B}[0m\u{1}")
            .split(separator: "\u{1}")
            .map(String.init)
        #expect(cells.count == SpinnerStyle.trackWidth)
        #expect(cells[0] == ANSIRenderer.colorize("●", foreground: .red), "the highlight")
        #expect(cells[1] != plain, "the cell the dot passed through is still warm")
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

    @Test("Each frame-based style has the expected frames, positive interval")
    func newStyleFrames() {
        #expect(SpinnerStyle.pie.frames == ["◴", "◷", "◶", "◵"])
        #expect(SpinnerStyle.beachball.frames == ["◐", "◓", "◑", "◒"])
        #expect(SpinnerStyle.box.frames == ["◰", "◳", "◲", "◱"])
        #expect(SpinnerStyle.curve.frames == ["◜", "◝", "◞", "◟"])
        #expect(SpinnerStyle.column.frames.first == "▁")
        #expect(SpinnerStyle.bar.frames.first == "█")
        #expect(SpinnerStyle.blockWedge.frames == ["▙", "▛", "▜", "▟"])
        #expect(SpinnerStyle.spinningTriangle.frames == ["▶", "▼", "◀", "▲"])
        #expect(SpinnerStyle.dancingLine.frames == ["⎛", "⎜", "⎞", "⎜", "⎝", "⎜", "⎠", "⎜"])
        #expect(SpinnerStyle.moon.frames.count == 8)
        #expect(SpinnerStyle.earth.frames.count == 3)
        #expect(SpinnerStyle.clock.frames.count == 24)
        for style in Self.frameBasedStyles {
            #expect(style.interval > 0)
            #expect(!style.frames.isEmpty)
        }
    }

    /// `.shade`'s cycle passes through EMPTY, which is what makes it a pulse
    /// rather than a flicker between three shades — so the leading space is part
    /// of the style, not a typo waiting to be tidied away.
    @Test("The shade style's first frame is a space")
    func shadeStartsEmpty() {
        #expect(SpinnerStyle.shade.frames == [" ", "░", "▒", "▓", "▒", "░"])
    }

    /// `column` and `bar` are the same animation on the two axes, so they have
    /// the same number of frames and each begins at the opposite extreme: the
    /// column starts nearly empty and fills, the bar starts full and empties.
    @Test("column and bar are the same cycle on different axes")
    func columnAndBarAreTwins() {
        #expect(SpinnerStyle.column.frames.count == SpinnerStyle.bar.frames.count)
        #expect(SpinnerStyle.column.frames.contains("█"))
        #expect(SpinnerStyle.bar.frames.contains("▏"))
    }

    /// Every style's frames are one width, or the spinner jitters as it cycles —
    /// which is the whole reason the built-in catalogue exists rather than
    /// leaving people to `.custom(_:)`. The emoji ones are two cells, the rest
    /// one; what matters is that no style mixes.
    @Test("Every built-in style's frames share one width")
    func everyStyleHasUniformWidth() {
        for style in Self.frameBasedStyles {
            let widths = Set(style.frames.map(\.strippedLength))
            #expect(widths.count == 1, "\(style) frames differ in width: \(widths)")
        }
        for style: SpinnerStyle in [.moon, .earth, .clock] {
            let widths = Set(style.frames.map(\.strippedLength))
            #expect(widths == [2], "\(style) frames must all be width-2: \(widths)")
        }
    }

    /// Every built-in style except `.bouncing`, whose frames are positions on a
    /// track rather than glyphs, and `.custom(_:)`, which has no fixed frames.
    private static let frameBasedStyles: [SpinnerStyle] = [
        .dots, .line, .dancingLine, .pie, .beachball, .box, .curve,
        .column, .bar, .shade, .blockWedge, .spinningTriangle, .moon, .earth, .clock,
    ]

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
