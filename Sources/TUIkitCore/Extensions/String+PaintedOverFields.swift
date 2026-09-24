//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+PaintedOverFields.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Painting a piece of a row over the fields beneath it

extension String {
    /// This frame with every cell it leaves without a field of its own drawn
    /// over the field given for THAT cell: `fields[k]` under the frame's column
    /// `k`, `nil` for the terminal's own.
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
    /// An explicit `ESC[49m` in the frame names no field here, as it names none
    /// to ``paintedOver(background:)`` — and so to compositing — and to the
    /// single-field splice this replaced. A cell after one sits on its field.
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
    /// - Parameter fields: The field under each of the frame's columns — one per
    ///   column, a wide character's second included. A column past the end has
    ///   none to restate.
    /// - Returns: The frame, each field-less cell over its own column's field.
    func paintedOver(fields: [SGRState.Colour?]) -> String {
        guard fields.contains(where: { $0 != nil }) else { return self }

        // What the frame itself states, and what the output has in force: the
        // two differ only in the background, and only by the fields put in
        // here — every sequence of the frame's goes to both, so one that
        // clears or names a background does so in each.
        var own = SGRState()
        var inForce = SGRState()
        var column = 0
        var result = ""
        // Room for four truecolour restatements, which covers a frame of
        // three coloured pieces over one field — the common shape.
        result.reserveCapacity(utf8.count + 4 * 20)

        /// Brings the field under `column` into force, when the frame leaves
        /// that cell without one of its own and it is not there already.
        func restate() {
            guard !own.namesBackground, column < fields.count else { return }
            let field = fields[column]
            guard inForce.backgroundColour != field else { return }
            result += SGRState.backgroundEscape(field)
            inForce.setBackground(field)
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
            own.apply(text)
            inForce.apply(text)
            restate()
        }
        flushVisible()
        return result
    }
}
