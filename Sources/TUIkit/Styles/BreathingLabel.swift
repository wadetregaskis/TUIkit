//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BreathingLabel.swift
//
//  A label whose own text breathes to show focus, instead of a bullet growing
//  beside it — drawn from a whole emphasis cycle, so the run loop can breathe it
//  with no view involved.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Focus in the label

/// A one-line label, or a label that is a view, breathing between two ends.
///
/// Lifted out of `_ButtonStyleBody`, which is private, so that every control whose
/// focus cue is its own text builds the breath the one way: a `Link`, a plain-style
/// button, and a `NavigationStack` crumb, which had its own copy that asked for the
/// colour drawn now and the run's frames separately — the identical pulse ramp,
/// built twice.
enum BreathingLabel {
    /// A one-line label that breathes between `ends` instead of growing a bullet
    /// beside it — see `_ButtonAppearance.indicatesFocusInLabel`.
    @MainActor
    static func draw(
        _ text: String, style: TextStyle, ends: (dim: Color, bright: Color),
        cycle: SelectionEmphasisCycle, indicating: Bool, isMeasuring: Bool
    ) -> FrameBuffer {
        let resting = ends.bright
        let bright = ends.bright
        let dim = ends.dim
        func drawn(_ colour: Color) -> String {
            var style = style
            style.foregroundColor = colour
            return ANSIRenderer.render(text, with: style)
        }
        // ONE breath for both readers. The colour drawn now is just this
        // cycle's frames coloured and indexed by `step`, so asking
        // `colorNow(dim:bright:)` for it and then `run(dim:bright:…)` for the
        // frames built the identical pulse ramp twice.
        let breath = indicating ? cycle.colors(dim: dim, bright: bright) : []
        let now = breath.isEmpty ? resting : breath[cycle.step % breath.count]
        var buffer = FrameBuffer(lines: [drawn(now)])
        // The ends asked, because `run(colors:)` sees only the frames: equal ends (a
        // label whose ink or surface has no RGB) are a still label.
        if !isMeasuring, indicating, cycle.isAnimating(dim: dim, bright: bright),
            let run = cycle.run(colors: breath, offsetX: 0, offsetY: 0, draw: drawn)
        {
            buffer.animatedCells = [run]
        }
        return buffer
    }

    /// The same, for a label that is a VIEW and may therefore wrap.
    ///
    /// `render` is called once per frame of the cycle rather than the render
    /// being recoloured after the fact, because the label's cells can carry an
    /// underline (a link's do), a symbol or bold, and a string-level recolour
    /// would have to reproduce all of it. That is `frames.count` renders of a
    /// short label, for the one control holding the focus, on the passes where
    /// it re-renders.
    ///
    /// A picture in the label does not breathe. Its pixels carry the ink, so
    /// each frame would be a different picture to send, while the frames a run
    /// replays name one image. `render` draws each frame through
    /// `breathingForegroundStyle(_:holdingPicturesAt:)`, which keeps a picture
    /// at `ends.bright`. See ``PictureInkHold``.
    @MainActor
    static func draw(
        ends: (dim: Color, bright: Color), cycle: SelectionEmphasisCycle,
        indicating: Bool, isMeasuring: Bool, render: (Color) -> FrameBuffer
    ) -> FrameBuffer {
        // ONE breath for both readers — see the note in the string variant.
        let breath = indicating ? cycle.colors(dim: ends.dim, bright: ends.bright) : []
        let now = breath.isEmpty ? ends.bright : breath[cycle.step % breath.count]
        // The label's OWN buffer, payload and all — not `FrameBuffer(lines:)`
        // rebuilt from its lines. Overlays, hit regions, opacity regions and
        // the label's own runs live BESIDE the lines, and a buffer built from
        // the lines alone has none of them: that is how `.opacity` on a link's
        // label drew at full strength, and how a `.modal` presented from one
        // took the keyboard and never painted.
        var buffer = render(now)
        guard !isMeasuring, indicating, cycle.isAnimating(dim: ends.dim, bright: ends.bright) else {
            return buffer
        }
        // One run per ROW: a run names a rectangle of cells on ONE line, and a
        // label may wrap onto several. Appended after the label's own runs, so
        // both stay on the buffer: the label's keep a spinner in it alive when
        // the link is not the focus, the breath's cover the label when it is.
        let framed = breath.map { render($0).lines }
        buffer.animatedCells += buffer.lines.indices.compactMap { row in
            let rowFrames = framed.compactMap { row < $0.count ? $0[row] : nil }
            guard rowFrames.count == framed.count, let first = rowFrames.first else { return nil }
            return AnimatedCellRun(
                offsetX: 0, offsetY: row, width: first.strippedLength,
                frames: rowFrames, frameTicks: cycle.frameTicks, clock: cycle.clock)
        }
        return buffer
    }
}
