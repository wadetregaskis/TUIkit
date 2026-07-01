//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextEditorHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Text Editor Handler

/// The editing model behind ``TextEditor``: a two-dimensional cursor over a
/// multi-line string, persisted across renders so the cursor and scroll survive
/// re-render.
///
/// The text is stored in the bound `String` (lines joined by `\n`); this handler
/// keeps only the cursor/scroll position. Each edit reads the bound string into
/// per-line character arrays, mutates, and writes it back — simple and correct
/// for the interactive editing sizes a terminal handles.
final class TextEditorHandler: Focusable {
    let focusID: String
    var canBeFocused: Bool
    var text: Binding<String>

    /// The cursor line (0-based).
    var cursorLine = 0
    /// The cursor column, a character offset into the cursor line.
    var cursorColumn = 0
    /// The column vertical motion tries to preserve (so Up/Down through a short
    /// line don't lose the horizontal position).
    private var desiredColumn = 0

    /// Top visible line — the core advances it to follow the cursor.
    var scrollLine = 0
    /// Left visible column — advanced to follow the cursor horizontally.
    var scrollColumn = 0

    init(focusID: String, text: Binding<String>, canBeFocused: Bool = true) {
        self.focusID = focusID
        self.text = text
        self.canBeFocused = canBeFocused
    }

    // MARK: - Line access

    /// The bound text as per-line character arrays (always at least one line).
    private func readLines() -> [[Character]] {
        let parts = text.wrappedValue
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { Array($0) }
        return parts.isEmpty ? [[]] : parts
    }

    private func writeLines(_ lines: [[Character]]) {
        text.wrappedValue = lines.map { String($0) }.joined(separator: "\n")
    }

    /// The number of logical lines.
    var lineCount: Int { readLines().count }

    /// Clamps the cursor into the current text — called each render because the
    /// bound string can change outside the editor.
    func clampCursor() {
        let lines = readLines()
        cursorLine = min(max(0, cursorLine), lines.count - 1)
        cursorColumn = min(max(0, cursorColumn), lines[cursorLine].count)
    }

    // MARK: - Key handling

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .character(let character):
            guard !event.ctrl, !event.alt else { return false }
            guard character.isLetter || character.isNumber || character.isPunctuation
                || character.isSymbol || character.isWhitespace
            else { return false }
            insert(String(character))
            return true
        case .space:
            insert(" ")
            return true
        case .enter:
            insertNewline()
            return true
        case .backspace:
            deleteBackward()
            return true
        case .delete:
            deleteForward()
            return true
        case .left:
            moveLeft()
            return true
        case .right:
            moveRight()
            return true
        case .up:
            moveVertical(by: -1)
            return true
        case .down:
            moveVertical(by: 1)
            return true
        case .home:
            cursorColumn = 0
            desiredColumn = 0
            return true
        case .end:
            cursorColumn = readLines()[cursorLine].count
            desiredColumn = cursorColumn
            return true
        case .paste(let string):
            insert(string)
            return true
        default:
            return false
        }
    }

    // MARK: - Editing

    /// Inserts a string at the cursor, splitting into multiple lines on any `\n`.
    private func insert(_ string: String) {
        var lines = readLines()
        let inserted = string
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { Array($0) }

        var line = lines[cursorLine]
        let tail = Array(line[cursorColumn...])
        line.removeSubrange(cursorColumn..<line.count)

        if inserted.count == 1 {
            line.append(contentsOf: inserted[0])
            cursorColumn = line.count
            line.append(contentsOf: tail)
            lines[cursorLine] = line
        } else {
            line.append(contentsOf: inserted[0])
            lines[cursorLine] = line
            var insertAt = cursorLine + 1
            for middle in inserted[1..<(inserted.count - 1)] {
                lines.insert(middle, at: insertAt)
                insertAt += 1
            }
            var last = inserted[inserted.count - 1]
            cursorColumn = last.count
            last.append(contentsOf: tail)
            lines.insert(last, at: insertAt)
            cursorLine = insertAt
        }
        writeLines(lines)
        desiredColumn = cursorColumn
    }

    /// Splits the current line at the cursor.
    private func insertNewline() {
        var lines = readLines()
        var line = lines[cursorLine]
        let tail = Array(line[cursorColumn...])
        line.removeSubrange(cursorColumn..<line.count)
        lines[cursorLine] = line
        lines.insert(tail, at: cursorLine + 1)
        cursorLine += 1
        cursorColumn = 0
        desiredColumn = 0
        writeLines(lines)
    }

    /// Deletes the character before the cursor, joining with the previous line
    /// at column 0.
    private func deleteBackward() {
        var lines = readLines()
        if cursorColumn > 0 {
            lines[cursorLine].remove(at: cursorColumn - 1)
            cursorColumn -= 1
        } else if cursorLine > 0 {
            let previousLength = lines[cursorLine - 1].count
            lines[cursorLine - 1].append(contentsOf: lines[cursorLine])
            lines.remove(at: cursorLine)
            cursorLine -= 1
            cursorColumn = previousLength
        } else {
            return
        }
        writeLines(lines)
        desiredColumn = cursorColumn
    }

    /// Deletes the character at the cursor, joining with the next line at the
    /// line end.
    private func deleteForward() {
        var lines = readLines()
        if cursorColumn < lines[cursorLine].count {
            lines[cursorLine].remove(at: cursorColumn)
        } else if cursorLine < lines.count - 1 {
            lines[cursorLine].append(contentsOf: lines[cursorLine + 1])
            lines.remove(at: cursorLine + 1)
        } else {
            return
        }
        writeLines(lines)
        desiredColumn = cursorColumn
    }

    private func moveLeft() {
        if cursorColumn > 0 {
            cursorColumn -= 1
        } else if cursorLine > 0 {
            cursorLine -= 1
            cursorColumn = readLines()[cursorLine].count
        }
        desiredColumn = cursorColumn
    }

    private func moveRight() {
        let lines = readLines()
        if cursorColumn < lines[cursorLine].count {
            cursorColumn += 1
        } else if cursorLine < lines.count - 1 {
            cursorLine += 1
            cursorColumn = 0
        }
        desiredColumn = cursorColumn
    }

    /// Moves the cursor up/down a line, preserving the desired column where the
    /// target line is long enough.
    private func moveVertical(by delta: Int) {
        let lines = readLines()
        let target = cursorLine + delta
        guard target >= 0, target < lines.count else { return }
        cursorLine = target
        cursorColumn = min(desiredColumn, lines[cursorLine].count)
    }
}
