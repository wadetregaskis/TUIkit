//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+PaintedOverFields.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Painting a piece of a row over the fields beneath it

extension String {
    /// This frame with every cell it leaves without a field of its own drawn
    /// over the field given for THAT cell: `fields.bare[k]` under the frame's
    /// column `k`, `nil` for the terminal's own — and every cell it puts on the
    /// terminal's own field by stating `ESC[49m` drawn over
    /// `fields.underStatedDefault[k]`.
    ///
    /// The per-cell twin of ``paintedOver(background:)``, for the one splice that
    /// draws a piece of a row over a row already built — an animation tick
    /// (``FrameBuffer/patchingAnimatedCells(in:with:atColumn:width:fields:compensating:)``).
    /// A run's frame comes from the view with no field under its ink, because the
    /// view drew it over whatever its containers painted; the run's ground says
    /// what that was, cell by cell (``AnimatedCellRun/groundFields(onPage:)``). One
    /// field for the whole frame is right only while one field is under the whole
    /// run, and a run need not sit on one: a whole-row fade whose row opens on a
    /// coloured label is on the label's colour for its first cells and on the page
    /// for the rest.
    ///
    /// A field is put in force at the start, again straight after every SGR
    /// sequence that leaves the frame naming none of its own — a reset, in
    /// either spelling, is one — and before any cell whose field differs from
    /// the one in force. So a reset is never followed by anything that paints
    /// before its cell's field is back, and that includes the `ECH` a host's
    /// cursor-advance compensation puts in front of a glyph it erases under
    /// (`String+CursorCompensation.swift`): an erase paints in whatever
    /// background is in force at that moment, and this runs before the
    /// compensation does.
    ///
    /// An explicit `ESC[49m` in the frame is the one statement the painters
    /// disagree about, so it has fields of its own: until the frame next resets or
    /// names a colour, its cells sit on `fields.underStatedDefault`, which records
    /// what the painters around the run made of a stated 49 — nothing, for one that
    /// restates its field only after a reset, and its field, for a compositor,
    /// which reads 49 as no field (`AnimatedCellRun.groundUnderStatedDefault`).
    /// Until 2026-09-24 it named no field here, and a tab chip's label on a
    /// `Color.default` palette, inside a `.background`, replayed on the
    /// background's colour where the render showed the terminal's own.
    ///
    /// A cell whose field is `nil` gets the terminal's own: `ESC[49m` where one
    /// of these fields would otherwise still be in force, and nothing where none
    /// is — so a frame over nothing but the terminal's own field comes back
    /// byte-identical.
    ///
    /// Where every field is the same, the cells come out as the single-field
    /// splice drew them — that background in front of the frame, after each
    /// literal `ESC[0m`, and before any cell left without one — and, for every
    /// frame `AnimatedRunPatchGoldenTests` pins, in the same bytes. It differs
    /// only in WHERE a restatement goes when other escapes sit between a reset
    /// and the next cell, and in restating nothing after the last cell.
    ///
    /// - Parameter fields: The fields under each of the frame's columns — one per
    ///   column in each list, a wide character's second included. A column past
    ///   the end has none to restate.
    /// - Returns: The frame, each field-less cell over its own column's field.
    func paintedOver(fields: AnimatedCellRun.GroundFields) -> String {
        guard !fields.restateNothing else { return self }

        // What the frame itself states, and the field the OUTPUT has in force:
        // the two differ only by the fields put in here. So the output's field
        // is the one thing tracked beside the frame's state, and each of the
        // frame's sequences is parsed once — into the frame's state, which says
        // whether it spoke about the background. One that named, cleared or
        // reset it leaves the output with exactly the frame's field; one that
        // said nothing about it leaves the output with what it had.
        var own = SGRState()
        // Whether the frame's own field, where it names none, is a stated 49
        // rather than nothing: from its last `ESC[49m` to its next reset or
        // colour.
        var statesDefault = false
        var inForce: SGRState.Colour?
        var column = 0
        var result = ""
        // Room for four truecolour restatements, which covers a frame of
        // three coloured pieces over one field — the common shape.
        result.reserveCapacity(utf8.count + 4 * 20)

        /// Brings the field under `column` into force, when the frame leaves
        /// that cell without a colour of its own and it is not there already.
        func restate() {
            guard !own.namesBackground else { return }
            let under = statesDefault ? fields.underStatedDefault : fields.bare
            guard column < under.count else { return }
            let field = under[column]
            guard inForce != field else { return }
            result += SGRState.backgroundEscape(field)
            inForce = field
        }

        let scalars = unicodeScalars
        var index = scalars.startIndex
        var pending = Self.UnicodeScalarView()

        // Visible scalars are buffered so they can be grouped into Characters:
        // a column is a per-CHARACTER count, and a grapheme may span scalars.
        func flushVisible() {
            guard !pending.isEmpty else { return }
            for character in String(pending) {
                restate()
                result.append(character)
                column += character.terminalWidth
            }
            pending = Self.UnicodeScalarView()
        }

        // The splice puts a reset in front of the frame, so it starts from the
        // terminal's default like this does.
        restate()
        while index < scalars.endIndex {
            guard scalars[index].value == 0x1B else {  // not ESC → visible
                pending.append(scalars[index])
                index = scalars.index(after: index)
                continue
            }
            flushVisible()
            let (end, isSGR) = Self.escapeSequenceEnd(startingAt: index, in: scalars)
            let text = String(scalars[index..<end])
            index = end
            result += text
            guard isSGR else { continue }
            if let statement = own.applyReportingBackground(text) {
                inForce = own.backgroundColour
                statesDefault = statement == .terminalDefault
            }
            restate()
        }
        flushVisible()
        return result
    }
}
