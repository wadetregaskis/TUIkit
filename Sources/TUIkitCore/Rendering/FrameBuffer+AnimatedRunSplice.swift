//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+AnimatedRunSplice.swift
//
//  The animation tick's splice: a run's frame drawn over the row already on
//  screen. Split from `FrameBuffer.swift`, which had reached the file-length
//  limit, along the seam between assembling a frame and patching a finished one.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Replaying a run over a finished row

extension FrameBuffer {
    /// `line` with `frame` redrawn over the `width` cells starting at `column`.
    ///
    /// This is the animation tick — the one splice that happens *after* a frame
    /// is finished, rather than while one is being assembled, and the difference
    /// matters for exactly one reason: **the background**.
    ///
    /// ``composited(with:at:)`` resets before an overlay, so an overlay stating
    /// no background of its own lands on the terminal's default. During assembly
    /// that is harmless, because a container paints its background across the
    /// whole finished row afterwards (`ANSIRenderer.applyPersistentBackground`
    /// re-injects it after every reset). Nothing does that here — the row is
    /// already on screen — so a foreground-only frame, which is what colouring a
    /// glyph produces and therefore what most focus indicators leave behind,
    /// punched a hole through to the terminal background on every tick: a white
    /// box around a breathing checkbox on a light-background terminal.
    ///
    /// So the frame is drawn over the background the line already had at that
    /// column, and *only* the background — the foreground, bold and underline in
    /// force there belong to the glyph being replaced, not to the surface under
    /// it.
    ///
    /// The background is re-stated after every reset *inside* the frame, not
    /// only in front of it, for the same reason `applyPersistentBackground`
    /// does it: a frame is often several coloured pieces (`colorize(arrow) +
    /// colorize(label)`, `colorize("[") + mark + colorize("]")`, a glyph and
    /// the blank cell after it), and each piece ends with a reset. A leading
    /// background alone survives only to the first of them — which is why the
    /// "N more above" arrow kept its surface while its label did not, why a
    /// focused button's `●` kept it and the space beside it did not, and why an
    /// ASCII toggle kept it for `[` and nothing after.
    public static func patchingAnimatedCells(
        in line: String, with frame: String, atColumn column: Int, width: Int
    ) -> String {
        // The cells about to be replaced may carry a host's cursor-advance
        // compensation, put there by `buildLine` when the row was rendered. The
        // frame brings its own, so the old pair has to go — see
        // `String.removingCursorCompensation(coveringColumns:)`, which
        // is where the story of the extra `CUF` is written down.
        let base = line.removingCursorCompensation(
            coveringColumns: column..<(column + width))
        // One walk of the line. The split already knows the background in
        // force where the run starts and the line's width, which used to be
        // two more walks (`ansiSGRStateAt`, `strippedLength`) and a pad that
        // walked a third time — per run, per tick, 11% of a live frame. A line
        // shorter than the run's end is padded by the insert, not here.
        let split = base.ansiOverlaySplit(
            prefixColumns: column, suffixDropColumns: column + frame.strippedLength)
        let background = split.backgroundUnderOverlay
        return insertOverlay(
            split: split,
            overlay: background + restating(background, afterResetsIn: frame),
            atColumn: column,
            // The line used to be padded out to the run's END before the
            // split, so a frame narrower than its run left the pad's spaces
            // after it; the same spaces come from the suffix shortfall now.
            minimumTotalWidth: column + width)
    }

    /// `line` with `span` spliced over it starting at `column`, the line's own
    /// styling restored where the span ends.
    ///
    /// The same surgery ``patchingAnimatedCells(in:with:atColumn:width:)``
    /// performs, without the background re-statement — a caller that has
    /// already decided every cell's colours (opacity resolution) wants its span
    /// taken literally, while a pre-baked animation frame was coloured against
    /// an assumed background and needs the real one restated around it.
    public static func splicing(_ span: String, into line: String, atColumn column: Int) -> String {
        let width = span.strippedLength
        guard width > 0 else { return line }
        // As above: the split is the one walk; a short line is padded by the
        // insert.
        return insertOverlay(
            split: line.ansiOverlaySplit(prefixColumns: column, suffixDropColumns: column + width),
            overlay: span,
            atColumn: column)
    }

    /// `frame` with `background` re-stated after every reset that has cells
    /// after it.
    ///
    /// A trailing reset is left bare deliberately: nothing follows it inside the
    /// run, and `insertOverlay` restores the line's own styling where the suffix
    /// begins — so a background there would be bytes emitted per tick, per run,
    /// to change nothing.
    private static func restating(_ background: String, afterResetsIn frame: String) -> String {
        guard !background.isEmpty, frame.contains(ansiReset) else { return frame }
        var rebuilt = ""
        var remainder = Substring(frame)
        while let reset = remainder.range(of: ansiReset) {
            rebuilt += remainder[..<reset.upperBound]
            remainder = remainder[reset.upperBound...]
            if !remainder.isEmpty { rebuilt += background }
        }
        return rebuilt + remainder
    }
}
