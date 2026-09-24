//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaintedCells.swift
//
//  Reads a styled line back as the terminal would paint it, column by column:
//  the character drawn there and the SGR state it is drawn in. For the suites
//  about a run's ground and its replay, which ask one question of every cell —
//  which field is it on — and need it asked of columns, not of escapes: two
//  spellings of one background are one answer.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkitCore

/// One terminal column of a styled line.
struct PaintedCell {
    /// The character drawn there. A wide character covers two columns, and
    /// its second column repeats it.
    let glyph: Character
    /// The netted SGR state it is drawn in.
    let state: SGRState

    /// The background escape in force (`""` for the terminal's own) — two
    /// spellings of one background read the same.
    var background: String { state.renderedBackground }
}

/// `line` as the columns it paints, left to right.
///
/// Escapes that are not SGR — an erase, a cursor step — are skipped: they
/// move no column here, which is what every width measure in the framework
/// assumes of them too.
func paintedCells(_ line: String) -> [PaintedCell] {
    var state = SGRState()
    var cells: [PaintedCell] = []
    for segment in line.ansiSegments() {
        switch segment {
        case .ansi(let sequence, true): state.apply(sequence)
        case .ansi: continue
        case .visible(let character):
            let cell = PaintedCell(glyph: character, state: state)
            cells += Array(repeating: cell, count: max(1, character.terminalWidth))
        }
    }
    return cells
}

/// `field` spelled as the background escape a painted cell reports for it —
/// `""` for the terminal's own — so a run's ground and a painted line can be
/// compared in one currency.
func spelled(_ field: SGRState.Colour?) -> String {
    var state = SGRState()
    state.setBackground(field)
    return state.renderedBackground
}
