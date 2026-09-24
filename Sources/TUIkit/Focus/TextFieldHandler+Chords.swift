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

    /// Carries out `chord`, and returns whether the field took the key. A
    /// chord the field declines propagates, as one nothing binds would.
    func perform(_ chord: TextFieldChord) -> Bool {
        switch chord {
        case .standIn(let command):
            return perform(command)
        case .shared(let command):
            return perform(command)
        }
    }

    /// Carries out one of the chords that stand in for the Command-key ones,
    /// and returns whether the field took the key.
    ///
    /// Copy and cut act on the selection, and with nothing selected they
    /// decline, so the chord goes on to the app: to its ⌘C or ⌘X, which
    /// arrive as these chords, or to `QuitShortcut.ctrlC`. With a selection
    /// they take the key, a ``SecureField``'s too, although it refuses to copy
    /// or cut its contents. Paste, undo and erase always take it. Undo with
    /// nothing to undo must not decline: an unclaimed Ctrl-Z reaches layer 4,
    /// which suspends the app.
    private func perform(_ command: StandInEditingCommand) -> Bool {
        switch command {
        case .copy:
            guard hasSelection else { return false }
            copySelection()
        case .cut:
            guard hasSelection else { return false }
            cutSelection()
        case .paste: paste()
        case .undo: undo()
        case .erase: eraseAll()
        }
        return true
    }

    /// Carries out a command from ``TextEditingCommand`` on the field's one
    /// line, and returns whether it did.
    ///
    /// The field declines the commands about other lines: the previous and
    /// next line, opening a line, and paging down. A field has one line, and
    /// strips line breaks from anything pasted into it. Each of those chords
    /// propagates as a chord nothing binds would. (Ctrl-V never gets here,
    /// because the field reads it as paste first.)
    ///
    /// The field has a keyboard selection, and the commands follow the field's
    /// own keys in how they treat it. Ctrl-D is the Delete key, so it deletes a
    /// selection. Ctrl-Y inserts, as a paste does, so it replaces one. Ctrl-K
    /// and Ctrl-T start from the caret, as the motions do, so they drop the
    /// selection first. ``TextEditorHandler`` drops its selection before any
    /// Emacs chord, so there Ctrl-D and Ctrl-Y act at the caret.
    ///
    /// The two ends of the line go together. With Ctrl-A moving and Ctrl-E
    /// typing an "e", a field would have half of readline's pair, which is the
    /// asymmetry that made Ctrl-A mean the same in the field as in the editor.
    func perform(_ command: TextEditingCommand) -> Bool {
        switch command {
        case .moveToStartOfLine:
            moveToStart()
        case .moveToEndOfLine:
            moveToEnd()
        case .moveBackward:
            moveBackward()
        case .moveForward:
            moveForward()
        case .deleteForward:
            deleteForward()
        case .killToEndOfLine:
            killToEnd()
        case .yank:
            yank()
        case .transpose:
            transpose()
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
        case .moveToPreviousLine, .moveToNextLine, .openLine, .pageDown:
            return false
        }
        return true
    }

    /// Ctrl-K: kills from the caret to the end of the field into
    /// ``killRing``, as one undoable edit. At the end there is nothing to
    /// kill, and the ring keeps what it had.
    private func killToEnd() {
        clearSelection()
        let length = text.wrappedValue.count
        guard cursorPosition < length else { return }
        resetSuggestionNavigation()
        let current = text.wrappedValue
        let start = current.index(current.startIndex, offsetBy: cursorPosition)
        killRing = String(current[start...])
        deleteRange(cursorPosition..<length)
    }

    /// Ctrl-Y: inserts the last kill at the caret. It goes the way a paste
    /// goes, so it replaces a selection, respects the field's content type,
    /// and is one undoable edit.
    private func yank() {
        guard !killRing.isEmpty else { return }
        insertText(killRing)
    }

    /// Ctrl-T: swaps the characters on either side of the caret and steps the
    /// caret on, or swaps the last two at the end of the field. The swap is
    /// the one the editor makes, ``TextEditingCommand/transpose(in:at:)``.
    private func transpose() {
        clearSelection()
        var characters = Array(text.wrappedValue)
        guard let caret = TextEditingCommand.transpose(in: &characters, at: cursorPosition)
        else { return }
        resetSuggestionNavigation()
        pushUndoState()
        text.wrappedValue = String(characters)
        cursorPosition = caret
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
