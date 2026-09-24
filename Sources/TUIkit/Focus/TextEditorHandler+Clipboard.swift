//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+Clipboard.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Command-Key Stand-Ins

extension TextEditorHandler {
    /// The Command-key stand-in `event` is, among the three the editor binds:
    /// copy, cut and undo. Read before anything else, and in particular before
    /// a selection is dropped, because copy and cut act on it.
    ///
    /// The editor binds only those three of a field's five. Ctrl-V stays the
    /// Emacs page down it has always been here, and a paste reaches the editor
    /// through the terminal's own paste. Ctrl-U, which erases a whole field,
    /// is not bound: one chord erasing a whole document is a different thing.
    func standInCommand(for event: KeyEvent) -> StandInEditingCommand? {
        guard event.ctrl, case .character(let character) = event.key,
            let command = StandInEditingCommand(control: character)
        else { return nil }
        switch command {
        case .copy, .cut, .undo: return command
        case .paste, .erase: return nil
        }
    }

    /// Carries out copy or cut, and returns whether the editor took the key.
    ///
    /// Both act on the selection, and with nothing selected they decline, as a
    /// field's do, so the chord goes on to the app: to its ⌘C or ⌘X, which
    /// arrive as these chords, or to `QuitShortcut.ctrlC`. Undo never gets
    /// here: it is not an edit to record, so the key handling takes it first,
    /// and it always takes the key, since an unclaimed Ctrl-Z reaches layer 4,
    /// which suspends the app.
    func perform(_ command: StandInEditingCommand) -> Bool {
        switch command {
        case .copy, .cut:
            guard let span = selectionRange else { return false }
            clipboard.write(selectedText(span))
            if command == .cut {
                deleteSelection(span)
            }
            return true
        case .undo, .paste, .erase:
            return false
        }
    }

    /// Ctrl-Z: puts the text back as it was before the newest edit, with the
    /// cursor where it was, and drops the selection. With nothing to undo it
    /// does nothing, and the key is still the editor's.
    func undo() {
        guard let previous = undoHistory.popLast() else { return }
        write(previous.text)
        selectionAnchor = nil
        cursor = previous.caret
        clampCursor()
        syncDesiredColumn()
    }

    /// The text `span` covers, its lines joined by line breaks.
    func selectedText(_ span: SelectionSpan) -> String {
        let lines = readLines()
        let (start, end) = clamped(span, in: lines)
        if start.line == end.line {
            let line = lines[start.line]
            return String(line[min(start.column, end.column)..<max(start.column, end.column)])
        }
        var parts = [String(lines[start.line][start.column...])]
        parts += lines[(start.line + 1)..<end.line].map { String($0) }
        parts.append(String(lines[end.line][..<end.column]))
        return parts.joined(separator: "\n")
    }
}
