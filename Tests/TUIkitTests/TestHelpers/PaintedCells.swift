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

    /// The foreground in force, `nil` for the terminal's own: the colour the
    /// glyph is drawn in. Only a glyph shows it — a blank cell's ink is
    /// invisible unless an underline or a strike draws it.
    var ink: SGRState.Colour? { state.foregroundColour }
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

// MARK: - What a cell shows

/// A colour as a cell SHOWS it: one of its own, or one of the terminal's two —
/// which are two colours, and which a slot left unstated shows depends on the slot.
///
/// Reverse video (SGR 7) exchanges what the two slots show, so a cell's spelled
/// ink and field say what it looks like only once the 7 is taken into account:
/// a glyph drawn in `ESC[38;2;220;220;220m` on the terminal's own field and the
/// same glyph with a 7 in front are two different pictures, and a comparison of
/// the spellings calls them one.
enum ShownColour: Equatable, CustomStringConvertible {
    case colour(SGRState.Colour)
    case terminalForeground
    case terminalBackground

    var description: String {
        switch self {
        case .colour(.rgb(let red, let green, let blue)): "rgb(\(red), \(green), \(blue))"
        case .colour(.indexed(let index)): "colour \(index) of 256"
        case .colour(.named(let code)): "SGR \(code)"
        case .terminalForeground: "the terminal's foreground"
        case .terminalBackground: "the terminal's background"
        }
    }
}

extension PaintedCell {
    /// The colour the cell is filled with: its background, or — reversed — its
    /// foreground, each the terminal's own where it is unstated.
    var shownField: ShownColour {
        state.reversesVideo
            ? state.foregroundColour.map { .colour($0) } ?? .terminalForeground
            : state.backgroundColour.map { .colour($0) } ?? .terminalBackground
    }

    /// The colour a glyph is drawn in: the field's twin.
    var shownInk: ShownColour {
        state.reversesVideo
            ? state.backgroundColour.map { .colour($0) } ?? .terminalBackground
            : state.foregroundColour.map { .colour($0) } ?? .terminalForeground
    }

    /// Every attribute in force that the cell can show, spelled as their parameters:
    /// on a glyph, all but reverse video, which the two colours above have already
    /// answered for — bold, dim, underline and the rest; on a blank, only those that
    /// draw on one (an underline, a blink, a strike), since a bold or a dim space is
    /// a space.
    var shownAttributes: String {
        var attributes = state
        attributes.setForeground(nil)
        attributes.setBackground(nil)
        attributes.apply(glyph == " " ? "\u{1B}[22;23;27;28m" : "\u{1B}[27m")
        return attributes.parameters
    }

    /// Whether the two cells look the same: the glyph, the field, the attributes
    /// the cell can show, and the ink wherever something draws in it — a glyph, or
    /// an attribute that inks a blank cell (an underline, a strike).
    func looksLike(_ other: PaintedCell) -> Bool {
        guard glyph == other.glyph, shownField == other.shownField, shownAttributes == other.shownAttributes
        else { return false }
        let inked = glyph != " " || state.paintsInkOnBlankCell
        return !inked || shownInk == other.shownInk
    }

    /// The cell as ``looksLike(_:)`` compares it, for a message.
    var shown: String {
        let ink = glyph != " " || state.paintsInkOnBlankCell ? " in \(shownInk)" : ""
        let attributes = shownAttributes.isEmpty ? "" : " [\(shownAttributes)]"
        return "'\(glyph)'\(ink) on \(shownField)\(attributes)"
    }
}
