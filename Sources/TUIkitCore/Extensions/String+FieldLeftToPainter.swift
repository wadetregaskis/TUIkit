//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+FieldLeftToPainter.swift
//
//  Which cells of a line — content a painter is about to fill under — leave
//  their field to the painter. A painter with a TRANSLUCENT field claims its
//  alpha for the field alone, and the field is its own only where the content
//  states none: elsewhere the content's own field is in the line in its place,
//  with the painter's beneath it (`OpacityRegion.fieldUnderContent`,
//  `Opacity as composition.md` §105).
//
//  Created by Wade Tregaskis
//  License: MIT

extension String {
    /// For each of the first `width` columns of this line, whether it leaves the
    /// cell's field to a painter that fills under it: nothing about the background
    /// said since the line's last reset — no colour, no `ESC[49m` — and not
    /// reversed, since a reversed cell shows its foreground slot as its field and
    /// the painter's colour, in the background slot, as its ink. A column past the
    /// end of the line is one the painter pads, and leaves it too; a wide glyph's
    /// second column answers as its first.
    ///
    /// Reads each sequence once, as the painters' own persistent fill restates its
    /// colour after every reset: the field it lets through is a stated 49 (the
    /// terminal's own) and every colour, and it paints the field of every cell a
    /// reset put back on none.
    ///
    /// A COMPOSITOR reads a stated 49 otherwise (`fillingStatedTerminalField`): it
    /// fills the cells of the line it lays on a base wherever they name no colour,
    /// a stated 49 among them (`String.paintedOver(background:)`), so there a 49
    /// leaves the field to what is under it as much as a cell that says nothing.
    /// Read as the content's own, a stated 49 under a translucent
    /// `.listRowBackground` — which composites its content over its fill — had a
    /// claim beneath it, and showed the fill's opaque spelling in a row of the fill
    /// at its alpha.
    ///
    /// - Parameters:
    ///   - width: How many columns to answer for.
    ///   - fillingStatedTerminalField: Whether the painter fills a stated 49, as a
    ///     compositor does.
    /// - Returns: One entry per column, `true` where the painter's field shows.
    package func columnsLeavingFieldToPainter(width: Int, fillingStatedTerminalField: Bool = false) -> [Bool] {
        columns(width: width, beyondTheEnd: true) { stated, state, _ in
            !(fillingStatedTerminalField ? state.namesBackground : stated) && !state.reversesVideo
        }
    }

    /// For each of the first `width` columns of this line, whether it shows NOTHING
    /// of its own: a blank, with nothing about the background said since the line's
    /// last reset, not reversed, and no attribute that inks a blank cell (an
    /// underline, a strike). What is behind such a cell is all it shows, so a layer
    /// composited over it is composited over whatever is behind the line, which the
    /// line cannot say. A column past the end of the line shows nothing too.
    ///
    /// - Parameter width: How many columns to answer for.
    /// - Returns: One entry per column, `true` where the cell shows nothing.
    package func columnsShowingNothing(width: Int) -> [Bool] {
        columns(width: width, beyondTheEnd: true) { stated, state, character in
            !stated && !state.reversesVideo && character == " " && !state.paintsInkOnBlankCell
        }
    }

    /// For each of the first `width` columns of this line, whether reverse video is
    /// in force on it: a cell that shows its ink as its field. A column past the end
    /// of the line is not.
    ///
    /// - Parameter width: How many columns to answer for.
    /// - Returns: One entry per column, `true` where the cell is reversed.
    package func columnsReversingVideo(width: Int) -> [Bool] {
        columns(width: width, beyondTheEnd: false) { _, state, _ in state.reversesVideo }
    }

    /// For each of the first `width` columns of this line, whether it is reversed with
    /// no colour named in its background slot: a cell a compositor fills there
    /// (`String.paintedOver(background:)`), and the reversal shows that slot as the
    /// cell's INK. So what the compositor fills it with is the colour its glyph is
    /// drawn in, and a claim on the field the cell shows cannot reach it. A column
    /// past the end of the line is not.
    ///
    /// - Parameter width: How many columns to answer for.
    /// - Returns: One entry per column, `true` where the cell's ink is left to fill.
    package func columnsReversedOverNoNamedField(width: Int) -> [Bool] {
        columns(width: width, beyondTheEnd: false) { _, state, _ in
            state.reversesVideo && !state.namesBackground
        }
    }

    /// For each of the first `width` columns of this line, whether it is reversed on
    /// the terminal's own ink (`ESC[7;39…m`): the field it shows is the terminal's
    /// foreground, which no background code spells, so a compositor draws a cell laid
    /// on it reversed itself (`String.paintedOver(fieldsReversing:)`). A column past
    /// the end of the line is not.
    ///
    /// - Parameter width: How many columns to answer for.
    /// - Returns: One entry per column, `true` where the cell shows the terminal's
    ///   foreground as its field.
    package func columnsShowingTerminalInkAsField(width: Int) -> [Bool] {
        columns(width: width, beyondTheEnd: false) { _, state, _ in
            state.reversesVideo && state.foregroundColour == nil
        }
    }

    /// For each of the first `width` columns of this line, the escape that states the
    /// background in force there, and `""` where nothing about the field was said since
    /// the last reset. A stated 49 is `ESC[49m`, the terminal's own field: not
    /// `SGRState.renderedBackground`'s `""`, which is what a cell naming no field says,
    /// and which a claim reading it takes for the field the cell shows. A column past
    /// the end of the line has none.
    ///
    /// - Parameter width: How many columns to answer for.
    /// - Returns: One escape per column.
    package func columnsBackgroundEscapes(width: Int) -> [String] {
        columns(width: width, beyondTheEnd: "") { stated, state, _ in
            stated ? SGRState.backgroundEscape(state.backgroundColour) : ""
        }
    }

    /// For each of the first `width` columns, `answer` asked of the cell there:
    /// whether anything about the background was said since the last reset, the
    /// state in force, and the character. A column past the end of the line is
    /// `beyondTheEnd`; a wide glyph's second column answers as its first.
    private func columns<Answer>(
        width: Int, beyondTheEnd: Answer,
        answering answer: (_ stated: Bool, _ state: SGRState, _ character: Character) -> Answer
    ) -> [Answer] {
        var result = [Answer](repeating: beyondTheEnd, count: max(0, width))
        guard width > 0, !isEmpty else { return result }
        var state = SGRState()
        var stated = false
        var column = 0
        forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                guard isSGR else { return true }
                if let statement = state.applyReportingBackground(sequence) {
                    stated = statement != .reset
                }
            case .visible(let character):
                guard column < width else { return false }
                let cells = character.terminalWidth
                // A zero-width scalar belongs to the cell before it.
                guard cells > 0 else { return true }
                let answered = answer(stated, state, character)
                for cell in column..<min(width, column + cells) { result[cell] = answered }
                column += cells
            }
            return true
        }
        return result
    }
}
