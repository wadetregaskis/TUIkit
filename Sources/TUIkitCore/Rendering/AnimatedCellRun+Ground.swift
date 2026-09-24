//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedCellRun+Ground.swift
//
//  What a run's containers painted beneath its cells, recorded as they paint it.
//
//  A run's frames come from the view that drew them, and a view draws its cells
//  over whatever its containers paint: a frame that colours a glyph states no
//  field under it, because the `.background` around it, the tab's surface, the
//  list row's fill or the page supplies one — AFTER the view has rendered, by
//  restating its colour after every reset in the finished lines. A replayed frame
//  gets none of that, so the replay has to put back the field under each cell the
//  frame leaves bare.
//
//  The row the render drew cannot say what that field was. Where the drawn frame
//  gave a cell a field of its OWN — a block caret drawn visible, a label fading
//  through red — the row shows that field, and the one beneath it is gone. Read
//  off the row, the caret's colour came back under the blink's off frame, which
//  therefore never blinked off; and a fade's red came back under every tick that
//  should have shown the page. So the field is recorded where it is known: by each
//  painter, as it paints, on every run in the buffer it is painting.
//
//  The record is a GROUND: a styled row exactly as wide as the run, spaces on
//  each cell's field. A painter paints it with the very function it paints the
//  lines with, so the ground ends up with what the lines have beneath the run's
//  cells — the innermost painter's field winning, as it wins in the lines, where
//  its escapes are the later statement.
//
//  A pass that REWRITES the fields of lines already painted owes the ground the
//  same rewrite, for the same reason: the flatten behind a modal and under
//  `.dimmed()` washes every line, every frame and every ground, and a colour
//  effect and a transition's fade recolour them all (`FrameBuffer.restyleRuns`).
//  A pass that rewrote the lines and the frames and not the ground left the
//  replay drawing a frame's bare cells on a field the row no longer has; one
//  that rewrote the lines alone replayed the glyphs in their old ink too.
//
//  A frame can also STATE the terminal's own field, `ESC[49m` — a tab chip's
//  label and a block caret do on a `Color.default` palette, and every frame the
//  flatten washes in `Color.default` does — and the painters do not agree about
//  a stated 49. One that restates its field only after a reset (a `.background`,
//  flat or ramp, a `List` row, a menu row's bar, the page) lets it through, so
//  the cell shows the terminal's own; compositing (`String.paintedOver(background:)`)
//  reads it as no field and fills it. No one rule for a stated 49 matches all of them — measured through the run
//  loop, reading it as no field put a chip's label on a `.background`'s colour
//  where the render showed the terminal's own, and reading it as a field of its
//  own did the reverse under a `ZStack`. So a run carries a SECOND record,
//  `groundUnderStatedDefault`: painted by the same painters with the same
//  functions, from a row that states `ESC[49m` in front of its cells, so each
//  painter answers for a stated 49 as it did in the lines.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Painting the ground

extension AnimatedCellRun {

    /// A copy whose ``ground`` and ``groundUnderStatedDefault`` have been painted
    /// by `paint`.
    ///
    /// `paint` must be what the painter does to the lines under the run — the same
    /// function, over the same colour — so the ground takes exactly what those
    /// lines took beneath the run's cells. A persistent background (a colour put in
    /// front and restated after every reset) paints a bare ground outright and a
    /// painted one only where nothing inside it painted first, because the inner
    /// painter's escapes follow its restatement; a compositor's
    /// `paintedOver(background:)` fills only the cells stating no field. Either
    /// way the field the lines show is the one the ground records. The record under
    /// a stated `ESC[49m` is painted by the same function, so it takes whatever the
    /// painter did to a stated 49 in the lines: a persistent background leaves it,
    /// a compositor fills it.
    ///
    /// A run no painter has reached has no records yet, and is painted from a bare
    /// row of spaces — what its cells are over before anything paints — and from
    /// the same row stating `ESC[49m` in front of it.
    ///
    /// - Parameter paint: The painter's transformation of a line.
    /// - Returns: The run, with both records painted.
    package func paintingGround(_ paint: (String) -> String) -> Self {
        var copy = self
        (copy.ground, copy.groundUnderStatedDefault) = Self.painted(
            (ground, groundUnderStatedDefault), width: width, by: paint)
        return copy
    }

    /// A run's two records — `width` cells wide, `nil` for one nothing has painted
    /// yet — painted by `paint`: what ``paintingGround(_:)`` does, for a caller
    /// that carries a run's properties in a type of its own until it can place it.
    package static func painted(
        _ grounds: (bare: String?, underStatedDefault: String?), width: Int, by paint: (String) -> String
    ) -> (bare: String, underStatedDefault: String) {
        let cells = String(repeating: " ", count: max(0, width))
        return (paint(grounds.bare ?? cells), paint(grounds.underStatedDefault ?? statedDefault + cells))
    }

    /// `ESC[49m`: the terminal's own field, stated.
    private static let statedDefault = "\u{1B}[49m"

    /// The fields a replayed frame's cells are drawn over, read on a row's page:
    /// one list for a cell whose frame states no field, one for a cell whose frame
    /// states the terminal's own (`ESC[49m`), each one field per cell of the run,
    /// `nil` for the terminal's own.
    ///
    /// Both fixed from one render to the next, so the run loop reads them once per
    /// render (`ReplayableFrame.fields(ofRun:)`) and hands them to every tick.
    package struct GroundFields: Sendable, Equatable {
        /// Under a cell whose frame states no field: ``groundFields(onPage:)``.
        package var bare: [SGRState.Colour?]
        /// Under a cell whose frame states `ESC[49m`: ``groundUnderStatedDefault``
        /// read the same way.
        package var underStatedDefault: [SGRState.Colour?]

        package init(bare: [SGRState.Colour?], underStatedDefault: [SGRState.Colour?]) {
            self.bare = bare
            self.underStatedDefault = underStatedDefault
        }

        /// Whether no cell has a field to restate, whatever its frame states: the
        /// splice can leave the frame as it is.
        var restateNothing: Bool {
            !bare.contains { $0 != nil } && !underStatedDefault.contains { $0 != nil }
        }
    }

    /// Both lists of fields this run's cells are drawn over on a row built on
    /// `page`. See ``GroundFields``.
    ///
    /// - Parameter page: The row's own background escape, or `""`.
    /// - Returns: The fields under a bare cell and under a stated `ESC[49m`.
    package func fields(onPage page: String) -> GroundFields {
        GroundFields(
            bare: groundFields(onPage: page),
            // Nothing painted: a stated 49 is the terminal's own whatever the page
            // is, because the row builder restates the page only after a reset.
            underStatedDefault: groundUnderStatedDefault.map { Self.fields(of: $0, cells: width, onPage: page) }
                ?? Array(repeating: nil, count: max(0, width)))
    }

    /// The field under each of this run's cells, left to right, on a row built on
    /// `page` — `nil` for the terminal's own.
    ///
    /// A row reaches the terminal with the page's background in front of it and
    /// restated after every reset in it (`FrameDiffWriter.buildLine`), so a cell no
    /// painter reached sits on the page, and a painter's field after a reset sits on
    /// the page and then on the painter's own. This reads the ground the same way:
    /// from the page, with the page put back at every reset the ground contains.
    /// The restatement follows `ANSIRenderer.restating(_:afterResetsIn:)`'s rule
    /// for what a reset is — the literal `ESC[0m`, and the collapsed `ESC[0;…m`
    /// read as a reset followed by the rest — because that is the rule the row was
    /// built with.
    ///
    /// - Parameter page: The row's own background escape, or `""` where the row is
    ///   built on nothing — a buffer read before the writer has seen it.
    /// - Returns: One field per cell of the run, `width` of them.
    package func groundFields(onPage page: String) -> [SGRState.Colour?] {
        guard let ground else {
            var onPage = SGRState()
            if !page.isEmpty { onPage.apply(page) }
            return Array(repeating: onPage.backgroundColour, count: max(0, width))
        }
        return Self.fields(of: ground, cells: width, onPage: page)
    }

    /// `record` — a ground, or the record under a stated 49 — read cell by cell on
    /// a row built on `page`, as ``groundFields(onPage:)`` describes.
    private static func fields(of record: String, cells width: Int, onPage page: String) -> [SGRState.Colour?] {
        var onPage = SGRState()
        if !page.isEmpty { onPage.apply(page) }
        let cells = max(0, width)
        var fields: [SGRState.Colour?] = []
        fields.reserveCapacity(cells)
        var state = onPage
        for segment in record.ansiSegments() {
            switch segment {
            case .ansi(let sequence, isSGR: true):
                state = Self.restatingPage(onPage, after: sequence, in: state)
            case .ansi:
                continue
            case .visible(let character):
                // A wide character covers two cells, both on the one field.
                for _ in 0..<max(1, character.terminalWidth) where fields.count < cells {
                    fields.append(state.backgroundColour)
                }
            }
        }
        // A ground is always as wide as its run; this only answers for a short one.
        while fields.count < cells { fields.append(state.backgroundColour) }
        return fields
    }

    /// `state` after `sequence`, with the page put back at a reset the way the row
    /// builder puts it back.
    private static func restatingPage(
        _ page: SGRState, after sequence: String, in state: SGRState
    ) -> SGRState {
        let reset = "\u{1B}[0m"
        let collapsed = "\u{1B}[0;"
        if sequence == reset { return page }
        guard sequence.hasPrefix(collapsed) else {
            var next = state
            next.apply(sequence)
            return next
        }
        // `ESC[0;…m` is a reset, the page, then the rest as a sequence of its own.
        // A rest of `0m` is a second reset, and the builder restores after that too.
        let rest = sequence.dropFirst(collapsed.count)
        guard rest != "0m" else { return page }
        var next = page
        next.apply("\u{1B}[" + rest)
        return next
    }
}

// MARK: - Painting every run in a buffer

extension FrameBuffer {

    /// Paints the ``AnimatedCellRun/ground`` of every run this buffer carries, and
    /// its ``AnimatedCellRun/groundUnderStatedDefault``, as a painter paints the
    /// lines under them.
    ///
    /// Call it wherever lines are painted with a field that the content's own
    /// cells do not state — a background restated after every reset, a compositor
    /// filling what an overlay leaves bare — with the same function, so each run
    /// records what its cells were drawn over. Nothing to do, and nothing
    /// allocated, for a buffer that carries no runs, which is nearly every one.
    ///
    /// - Parameter paint: The painter's transformation of a line, given the run it
    ///   is painting for — for a painter whose field depends on the row or the
    ///   column the run sits at.
    package mutating func paintRunGrounds(_ paint: (AnimatedCellRun, String) -> String) {
        guard !animatedCells.isEmpty else { return }
        animatedCells = animatedCells.map { run in run.paintingGround { paint(run, $0) } }
    }

    /// Restyles every run this buffer carries as a pass restyles its lines: each
    /// frame, and both of each run's records, through the same `restyle`.
    ///
    /// For a pass that rewrites the colours of lines already painted — a colour
    /// effect, a transition's fade — and so owes the runs the same rewrite. The
    /// frames, because the replay draws them in place of the cells the pass
    /// rewrote; the records, because the replay draws a frame over them wherever
    /// the frame names no field (or states `ESC[49m`), and those fields are the
    /// ones the pass rewrote in the lines. A run's alpha rides through unchanged:
    /// such a pass leaves the lines' opacity regions standing too.
    ///
    /// - Parameter restyle: The pass's rewrite of a line.
    package mutating func restyleRuns(_ restyle: (String) -> String) {
        guard !animatedCells.isEmpty else { return }
        animatedCells = animatedCells.map { run in
            run.replacingFrames(run.frames.map(restyle), alpha: run.alpha).paintingGround(restyle)
        }
    }
}
