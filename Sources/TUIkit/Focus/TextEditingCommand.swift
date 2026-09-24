//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditingCommand.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// An editing command that an Emacs chord names in a text control: a letter
/// held with Control, or B or F held with Option.
///
/// The macOS text system handles a key in two halves. Cocoa's
/// `StandardKeyBinding.dict` maps the chord to a command (Ctrl-F to
/// `moveForward:`, Ctrl-Y to `yank:`), and each text view carries the command
/// out on its own storage. This type is the first half, kept in one place so
/// that every text control reads a chord the same way. It holds the Control
/// letters of that dictionary, and readline's two Option letters, Meta-B and
/// Meta-F, the word motions macOS Terminal sends for Option-Left and
/// Option-Right as well.
///
/// What a command *does* stays with the control, because it depends on the
/// control's shape. The previous line is one line up in a `TextEditor`, but in a
/// single-line field it can only mean the start of the text, which is where the
/// field's Up arrow goes.
///
/// Ctrl-H, Ctrl-I and Ctrl-M are missing on purpose. A terminal sends those bytes
/// for Backspace, Tab and Return, and `KeyEvent.parse` reads them that way.
enum TextEditingCommand: Equatable {
    /// Ctrl-A: to the start of the line.
    case moveToStartOfLine
    /// Ctrl-E: to the end of the line.
    case moveToEndOfLine
    /// Ctrl-B: back one character.
    case moveBackward
    /// Ctrl-F: forward one character.
    case moveForward
    /// Ctrl-P: up a line.
    case moveToPreviousLine
    /// Ctrl-N: down a line.
    case moveToNextLine
    /// Ctrl-D: delete the character after the caret.
    case deleteForward
    /// Ctrl-K: kill from the caret to the end of the line, for Ctrl-Y to yank.
    case killToEndOfLine
    /// Ctrl-Y: insert the most recent kill at the caret.
    case yank
    /// Ctrl-T: swap the characters on either side of the caret.
    case transpose
    /// Ctrl-O: break the line after the caret and leave the caret where it is.
    case openLine
    /// Ctrl-V: down a screenful.
    case pageDown
    /// Option-Ctrl-A: select everything.
    case selectAll
    /// Option-B: back to the previous word boundary.
    case moveWordBackward
    /// Option-F: forward to the next word boundary.
    case moveWordForward
    /// Option-Shift-B: back to the previous word boundary, extending the
    /// selection there.
    case moveWordBackwardAndModifySelection
    /// Option-Shift-F: forward to the next word boundary, extending the
    /// selection there.
    case moveWordForwardAndModifySelection

    /// The command a Control chord names, or `nil` when the chord has none and
    /// should propagate.
    ///
    /// - Parameters:
    ///   - character: The letter the chord arrived as. A terminal only ever
    ///     delivers lower case, but both cases are accepted, as
    ///     `TextFieldHandler` has always accepted them.
    ///   - alt: Whether Option was held as well. Only A reads it.
    init?(control character: Character, alt: Bool) {
        switch character {
        // Option-Ctrl-A selects everything. Plain Ctrl-A goes to the start of
        // the line, as it does in readline. Cmd-A cannot reach a terminal app,
        // so select-all needs some other chord, and this is the closest one
        // that does not take a motion key away.
        case "a", "A": self = alt ? .selectAll : .moveToStartOfLine
        case "e", "E": self = .moveToEndOfLine
        case "b", "B": self = .moveBackward
        case "f", "F": self = .moveForward
        case "p", "P": self = .moveToPreviousLine
        case "n", "N": self = .moveToNextLine
        case "d", "D": self = .deleteForward
        case "k", "K": self = .killToEndOfLine
        case "y", "Y": self = .yank
        case "t", "T": self = .transpose
        case "o", "O": self = .openLine
        case "v", "V": self = .pageDown
        default: return nil
        }
    }

    /// The command a letter held with Option names: readline's word motions,
    /// B and F, or `nil` for any other letter.
    ///
    /// - Parameters:
    ///   - character: The letter. A shifted letter arrives in upper case with
    ///     `shift` set, so both cases are accepted.
    ///   - shift: Whether Shift was held, which extends the selection instead
    ///     of dropping it.
    init?(option character: Character, shift: Bool) {
        switch character {
        case "b", "B": self = shift ? .moveWordBackwardAndModifySelection : .moveWordBackward
        case "f", "F": self = shift ? .moveWordForwardAndModifySelection : .moveWordForward
        default: return nil
        }
    }
}

// MARK: - Transpose

extension TextEditingCommand {
    /// Ctrl-T on one line of text: swaps the two characters on either side of
    /// `column`, and returns the column the caret moves to, which is one step
    /// on. At the end of the line there is no character after the caret, so
    /// the last two characters are swapped and the caret stays at the end.
    ///
    /// Returns `nil` and leaves `line` alone when there is nothing to swap: the
    /// line is shorter than two characters, or the caret is at its start.
    ///
    /// This is a plain function of a character array and an index, like
    /// ``WordBoundary``, so it belongs to no one control: the editor passes one
    /// line, and a single-line field's whole text is a line too.
    static func transpose(in line: inout [Character], at column: Int) -> Int? {
        guard line.count >= 2, column > 0 else { return nil }
        if column >= line.count {
            line.swapAt(line.count - 2, line.count - 1)
            return line.count
        }
        line.swapAt(column - 1, column)
        return column + 1
    }
}
