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
    /// `line` with `run`'s frame at `index` redrawn over the run's cells, each cell
    /// the frame leaves without a field of its own drawn over the field recorded
    /// beneath it (`AnimatedCellRun.ground`).
    ///
    /// The splice the run loop performs on an animation tick, less what only the
    /// terminal's writer knows — the row's page and the host's cursor-advance
    /// model (`FrameDiffWriter.patchingAnimatedRun`). So this is the one to replay
    /// a run with against a buffer's own lines, which have met neither: a run no
    /// container painted under sits on nothing here, as its cells do in the buffer.
    ///
    /// - Parameters:
    ///   - line: The row, as the buffer holds it.
    ///   - run: The run, sitting on that row.
    ///   - index: Which frame of its cycle to draw.
    /// - Returns: The row with the frame spliced in.
    public static func patchingAnimatedCells(
        in line: String, replaying run: AnimatedCellRun, atIndex index: Int
    ) -> String {
        patchingAnimatedCells(
            in: line, with: run.frame(atIndex: index), atColumn: run.offsetX, width: run.width,
            fields: run.fields(onPage: ""))
    }

    /// `line` with `frame` redrawn over the `width` cells starting at `column`,
    /// each cell the frame leaves without a field of its own drawn over the one
    /// given for it.
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
    /// So each cell the frame leaves bare is drawn over `fields` for THAT cell,
    /// and *only* a field — the foreground, bold and underline in force there
    /// belong to the glyph being replaced, not to the surface under it. The field
    /// is restated after every reset *inside* the frame, not only in front of it,
    /// for the same reason `applyPersistentBackground` does it: a frame is often
    /// several coloured pieces (`colorize(arrow) + colorize(label)`,
    /// `colorize("[") + mark + colorize("]")`, a glyph and the blank cell after
    /// it), and each piece ends with a reset. A leading field alone survives only
    /// to the first of them — which is why the "N more above" arrow kept its
    /// surface while its label did not, why a focused button's `●` kept it and
    /// the space beside it did not, and why an ASCII toggle kept it for `[` and
    /// nothing after. See ``String/paintedOver(fields:)``.
    ///
    /// Where the fields come from is the caller's, and the whole of what makes a
    /// replay right: the field the containers painted beneath each cell, which is
    /// what ``AnimatedCellRun/fields(onPage:)`` reads — and, under a cell the frame
    /// puts on the terminal's own field by stating `ESC[49m`, what the containers
    /// made of THAT, which differs between them. Not the field the row
    /// shows there, which is the drawn frame's own wherever that frame named one.
    /// Taken off the row, a block caret drawn visible put the caret's colour under
    /// its own hidden frame and never blinked off; and before that, when the field
    /// was the row's under the run's FIRST cell alone, a whole-row fade opening on
    /// a coloured label restated the label's colour across the row.
    ///
    /// - Parameters:
    ///   - line: The row as it is on screen.
    ///   - frame: The run's picture for this tick, as the view rendered it.
    ///   - column: The run's first visible column.
    ///   - width: How many cells the run covers.
    ///   - fields: The fields under each of the frame's columns — under a cell it
    ///     leaves bare, and under a stated `ESC[49m` — `nil` for the terminal's own.
    ///   - compensate: The host's cursor-advance compensation, applied to the
    ///     frame AFTER its fields are restated and before it is spliced in. A
    ///     host that erases under a glyph it advances too little over writes that
    ///     erase (`ECH`) in front of the glyph, and an erase paints in whatever
    ///     background is in force at that moment; compensated first, a glyph
    ///     after a reset would be erased over the terminal's default and only then
    ///     given its field, leaving a wide glyph's second cell bare on every tick.
    ///     Identity by default, for a caller with no host.
    package static func patchingAnimatedCells(
        in line: String, with frame: String, atColumn column: Int, width: Int,
        fields: AnimatedCellRun.GroundFields, compensating compensate: (String) -> String = { $0 }
    ) -> String {
        // The cells about to be replaced may carry a host's cursor-advance
        // compensation, put there by `buildLine` when the row was rendered. The
        // frame brings its own, so the old pair has to go — see
        // `String.removingCursorCompensation(coveringColumns:)`, which
        // is where the story of the extra `CUF` is written down.
        let base = line.removingCursorCompensation(
            coveringColumns: column..<(column + width))
        // One walk of the line, for where to cut it and how wide it is — which
        // used to be two more walks (`ansiSGRStateAt`, `strippedLength`) and a pad
        // that walked a third time, per run, per tick, 11% of a live frame. A line
        // shorter than the run's end is padded by the insert, not here.
        let split = base.ansiOverlaySplit(
            prefixColumns: column, suffixDropColumns: column + frame.strippedLength)
        return insertOverlay(
            split: split,
            overlay: compensate(frame.paintedOver(fields: fields)),
            atColumn: column,
            // The line used to be padded out to the run's END before the
            // split, so a frame narrower than its run left the pad's spaces
            // after it; the same spaces come from the suffix shortfall now.
            minimumTotalWidth: column + width,
            // Already over its fields, cell by cell. Painted again over the
            // field the row shows where the frame lands — the drawn frame's own,
            // as likely as not — a cell whose field is the terminal's would take
            // that one instead.
            overlayIsPainted: true)
    }

    /// `line` with `span` spliced over it starting at `column`, the line's own
    /// styling restored where the span ends.
    ///
    /// The same surgery ``patchingAnimatedCells(in:replaying:atIndex:)``
    /// performs, without the field restatement — a caller that has already
    /// decided every cell's colours (opacity resolution) wants its span taken
    /// literally, while a pre-baked animation frame was coloured against an
    /// assumed background and needs the real one restated around it.
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
}
