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

/// One `ECH` (`ESC[nX`) in a line.
struct Erasure: Equatable, CustomStringConvertible {
    /// The column the cursor is on when it runs.
    let column: Int
    /// How many cells it erases.
    let cells: Int
    /// The background it erases them in (`""` for the terminal's own).
    let background: String

    var description: String { "\(cells) at \(column) in \(background.debugDescription)" }
}

/// Every `ECH` (`ESC[nX`) in `line`, in order.
///
/// An erase paints in whatever background is in force at that moment, which is
/// the only thing that separates one from a cell that keeps the terminal's
/// default — the cursor-advance compensation writes one in front of every glyph
/// a host advances too little over (`String+CursorCompensation.swift`), and a
/// column cannot show it: ``paintedCells(_:)`` skips every escape that is not SGR.
func erasures(_ line: String) -> [Erasure] {
    var state = SGRState()
    var column = 0
    var found: [Erasure] = []
    for segment in line.ansiSegments() {
        switch segment {
        case .ansi(let sequence, true):
            state.apply(sequence)
        case .ansi(let sequence, false):
            guard sequence.hasPrefix("\u{1B}["), sequence.hasSuffix("X"),
                let cells = Int(sequence.dropFirst(2).dropLast())
            else { continue }
            found.append(Erasure(column: column, cells: cells, background: state.renderedBackground))
        case .visible(let character):
            column += character.terminalWidth
        }
    }
    return found
}

/// `field` spelled as the background escape a painted cell reports for it —
/// `""` for the terminal's own — so a run's ground and a painted line can be
/// compared in one currency.
func spelled(_ field: SGRState.Colour?) -> String {
    var state = SGRState()
    state.setBackground(field)
    return state.renderedBackground
}
