//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SpinnerRenderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Buffer-level render audit for `Spinner`. Complements `SpinnerTests.swift`
//  (which covers the style frame tables and the bounce maths) by asserting
//  the rendered FrameBuffer: a single row for every style, a label rendered
//  after a single separating space, colour emitted as ANSI, and no overflow
//  past a narrow available width. The empty-string-label case (`Spinner("")`)
//  is covered by `emptyStringLabel` — it renders the bare glyph, no stray
//  trailing space.

import Testing

@testable import TUIkit

@MainActor
@Suite("Spinner rendering")
struct SpinnerRenderTests {

    private func context(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    // MARK: - Single row invariant

    @Test("Every style renders exactly one row, with or without a label")
    func singleRowAllStyles() {
        for style in [SpinnerStyle.dots, .line, .bouncing] {
            let noLabel = renderToBuffer(Spinner(style: style), context: context())
            #expect(noLabel.lines.count == 1, "\(style) without label must be one row, got \(noLabel.lines.count)")

            let withLabel = renderToBuffer(Spinner("Working", style: style), context: context())
            #expect(withLabel.lines.count == 1, "\(style) with label must be one row, got \(withLabel.lines.count)")
        }
    }

    // MARK: - No label

    @Test("Dots spinner without a label renders just the first frame glyph")
    func dotsNoLabel() {
        let buffer = renderToBuffer(Spinner(style: .dots), context: context())
        #expect(buffer.lines.count == 1)
        // First time-bucket frame of the dots style.
        #expect(buffer.lines[0].stripped == "⠋", "Expected the first braille frame, got >>\(buffer.lines[0].stripped)<<")
    }

    @Test("Line spinner without a label renders a single ASCII glyph and no trailing space")
    func lineNoLabel() {
        let buffer = renderToBuffer(Spinner(style: .line), context: context())
        let line = buffer.lines[0].stripped
        #expect(line == "|", "Unlabelled spinner must be the bare glyph with no trailing space, got >>\(line)<<")
        #expect(line.strippedLength == 1)
    }

    @Test("An empty-string label renders the bare glyph with no trailing space")
    func emptyStringLabel() {
        // Distinct from `lineNoLabel` (label == nil): here the label is an
        // empty string, which previously still emitted a separator space.
        let buffer = renderToBuffer(Spinner("", style: .line), context: context())
        let line = buffer.lines[0].stripped
        #expect(line == "|", "Empty-label spinner must be the bare glyph, got >>\(line)<<")
        #expect(line.strippedLength == 1)
    }

    // MARK: - With label

    @Test("Label is rendered after the spinner with exactly one separating space")
    func labelRendering() {
        let buffer = renderToBuffer(Spinner("Loading", style: .line), context: context())
        let line = buffer.lines[0].stripped
        #expect(line == "| Loading", "Expected glyph + single space + label, got >>\(line)<<")
    }

    @Test("Multi-word label is rendered verbatim on one row")
    func multiWordLabel() {
        let buffer = renderToBuffer(Spinner("Please wait", style: .line), context: context(width: 40))
        let line = buffer.lines[0].stripped
        #expect(line == "| Please wait", "Got >>\(line)<<")
        #expect(buffer.lines.count == 1)
    }

    // MARK: - Colour emission

    @Test("Explicit colour is emitted as an ANSI foreground code on the glyph")
    func explicitColorEmitted() {
        let buffer = renderToBuffer(Spinner(style: .dots, color: .red), context: context())
        #expect(buffer.lines[0].contains("\u{1B}[31m"), "Red foreground ANSI code must be present")
        #expect(buffer.lines[0].stripped == "⠋")
    }

    @Test("Bouncing style renders a 9-position track of dot glyphs")
    func bouncingTrack() {
        let buffer = renderToBuffer(Spinner(style: .bouncing), context: context())
        let line = buffer.lines[0].stripped
        #expect(buffer.lines.count == 1)
        // The track is a fixed 9 dot glyphs (the highlight may be off-screen
        // on the very first frame due to edge overshoot, so count glyphs).
        let dots = line.filter { $0 == "●" }
        #expect(dots.count == SpinnerStyle.trackWidth,
                "Bouncing track must be \(SpinnerStyle.trackWidth) glyphs wide, got \(dots.count) in >>\(line)<<")
        #expect(buffer.lines[0].contains("\u{1B}["), "Track must be coloured (ANSI present)")
    }

    // MARK: - Narrow width (no overflow)

    @Test("A label wider than the available width is clamped, never overflowing")
    func narrowWidthClamps() {
        let buffer = renderToBuffer(Spinner("Loading forever and ever", style: .line), context: context(width: 6))
        #expect(buffer.lines.count == 1)
        #expect(buffer.width <= 6, "Spinner must not overflow the available width, got \(buffer.width)")
        #expect(buffer.lines[0].stripped.strippedLength <= 6,
                "Visible content must fit within 6 cells, got \(buffer.lines[0].stripped.strippedLength)")
    }

    // MARK: - Determinism within a time bucket

    @Test("Two immediate renders produce identical output")
    func deterministicWithinBucket() {
        let spinner = Spinner("Sync", style: .line)
        let first = renderToBuffer(spinner, context: context())
        let second = renderToBuffer(spinner, context: context())
        #expect(first.lines[0].stripped == second.lines[0].stripped)
    }
}
