//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldHandler+Chords.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Chords

/// A letter held with Control or Option, as a text field reads it.
///
/// A chord is read in this order: Option's word motions first, then the
/// Command-key stand-ins (``StandInEditingCommand``), then the rest of the
/// table the field shares with ``TextEditor`` (``TextEditingCommand``). That
/// order is the whole of what makes a chord mean one thing rather than
/// another, so it is written down once, here, and the field's key handling is
/// only a switch over the result.
enum TextFieldChord: Equatable {
    /// Ctrl-C, X, V, Z and U: copy, cut, paste, undo and erase, the chords that
    /// stand in for the Command-key ones. Ctrl-V is read here before the shared
    /// table, where it is the editor's page down, which a single line has no
    /// use for.
    case standIn(StandInEditingCommand)
    /// A command from ``TextEditingCommand``, the table the field shares with
    /// ``TextEditorHandler``.
    ///
    /// Option is read before Control, so Option-Ctrl-B and Option-Ctrl-F are
    /// the word motions here. ``TextEditorHandler`` reads Control first, and
    /// moves one character for the same chords.
    case shared(TextEditingCommand)

    /// The chord `event` is, or `nil` when it is not one: not a character,
    /// held with neither modifier, or a chord nothing binds.
    init?(_ event: KeyEvent) {
        guard case .character(let character) = event.key else { return nil }
        if event.alt, let command = TextEditingCommand(option: character, shift: event.shift) {
            self = .shared(command)
            return
        }
        guard event.ctrl else { return nil }
        if let command = StandInEditingCommand(control: character) {
            self = .standIn(command)
        } else if let command = TextEditingCommand(control: character, alt: event.alt) {
            self = .shared(command)
        } else {
            return nil
        }
    }
}

// MARK: - Carrying Chords Out

extension TextFieldHandler {
    /// The ``TextEditingCommand`` `event` reaches in this field, read by
    /// ``TextFieldChord`` as the field's key handling reads it, whether or not
    /// the field carries it out. So Ctrl-V is not the editor's page down here,
    /// because paste takes it first, and Option-Ctrl-B is the word motion,
    /// because Option is read first. `nil` for any other key.
    func editingCommand(for event: KeyEvent) -> TextEditingCommand? {
        guard case .shared(let command) = TextFieldChord(event) else { return nil }
        return command
    }

    /// Carries out `chord`, and returns whether the field took the key.
    ///
    /// Every stand-in is taken, whether or not it had anything to act on:
    /// Ctrl-C with nothing selected still does not type a "c". A shared command
    /// can be declined, and then its chord propagates.
    func perform(_ chord: TextFieldChord) -> Bool {
        switch chord {
        case .standIn(let command):
            perform(command)
            return true
        case .shared(let command):
            return perform(command)
        }
    }

    /// Carries out one of the chords that stand in for the Command-key ones.
    private func perform(_ command: StandInEditingCommand) {
        switch command {
        case .copy: copySelection()
        case .cut: cutSelection()
        case .paste: paste()
        case .undo: undo()
        case .erase: eraseAll()
        }
    }

    /// Carries out a command from ``TextEditingCommand`` on the field's one
    /// line, and returns whether it did.
    ///
    /// The field carries out the commands for the two ends of its line,
    /// select-all and the word motions. It declines the rest, so each of those
    /// chords propagates as a chord nothing binds would.
    ///
    /// The two ends go together. With Ctrl-A moving and Ctrl-E typing an "e",
    /// a field would have half of readline's pair, which is the asymmetry that
    /// made Ctrl-A mean the same in the field as in the editor.
    func perform(_ command: TextEditingCommand) -> Bool {
        switch command {
        case .moveToStartOfLine:
            moveToStart()
        case .moveToEndOfLine:
            moveToEnd()
        case .selectAll:
            selectAll()
        case .moveWordBackward:
            moveWordBackward()
        case .moveWordForward:
            moveWordForward()
        case .moveWordBackwardAndModifySelection:
            extendSelectionToPreviousWordBoundary()
        case .moveWordForwardAndModifySelection:
            extendSelectionToNextWordBoundary()
        case .moveBackward, .moveForward, .moveToPreviousLine, .moveToNextLine, .deleteForward,
            .killToEndOfLine, .yank, .transpose, .openLine, .pageDown:
            return false
        }
        return true
    }

    /// Ctrl-U: erases the field, all of it, as one undoable edit, and leaves
    /// the caret at the start with nothing selected.
    private func eraseAll() {
        let length = text.wrappedValue.count
        if length > 0 {
            deleteRange(0..<length)
        }
        clearSelection()
        cursorPosition = 0
    }
}
