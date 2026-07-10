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
    /// The selection anchor, or nil when there is no selection. A drag or
    /// Shift-click sets it; the selection then spans anchor…cursor. Set by the
    /// mouse handler and consumed/cleared by the next keystroke.
    var selectionAnchor: TextEditorPosition?
    /// The DISPLAY column vertical motion tries to preserve (so Up/Down
    /// through a short line don't lose the horizontal position). Display, not
    /// character, space: on tab-bearing lines the visual column runs ahead of
    /// the character index, and the caret should track visually — the macOS
    /// text system preserves the visual x the same way.
    private var desiredColumn = 0

    /// How tabs are laid out — synced from the environment by the rendering
    /// core each frame, so vertical motion and the renderer agree on where a
    /// tab puts the columns after it.
    var tabWidth: TabWidth = .periodic(4)

    /// Remembers the cursor's display column for vertical motion.
    private func syncDesiredColumn(_ lines: [[Character]]? = nil) {
        let lines = lines ?? readLines()
        guard cursorLine < lines.count else {
            // Out-of-bounds cursor (stale state, normalised elsewhere): fall
            // back to the raw index rather than reading a missing line.
            desiredColumn = cursorColumn
            return
        }
        desiredColumn = TabLayout.displayColumn(
            ofCharIndex: cursorColumn, in: lines[cursorLine], tabWidth: tabWidth)
    }

    /// Top visible line — the core advances it to follow the cursor.
    var scrollLine = 0
    /// Left visible column — advanced to follow the cursor horizontally.
    var scrollColumn = 0
    /// The visible row count, set by the core each render so Page Up / Page Down
    /// (and Ctrl-V) can move the cursor by a screenful.
    var viewportHeight = 1

    /// The last text removed by a kill command (Ctrl-K), replayed by yank
    /// (Ctrl-Y) — a single-slot kill ring, matching the macOS text system.
    private var killRing = ""

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

    /// Clamps the cursor into the current text — called each render because
    /// the bound string can change outside the editor. A selection anchor the
    /// text no longer contains is DROPPED, not clamped: clamping would
    /// manufacture a selection the user never made, and the next edit key
    /// would replace text they never selected. A collapsed (anchor == cursor)
    /// anchor is kept — a drag in progress anchors before its first movement.
    func clampCursor() {
        let lines = readLines()
        cursorLine = min(max(0, cursorLine), lines.count - 1)
        cursorColumn = min(max(0, cursorColumn), lines[cursorLine].count)
        if let anchor = selectionAnchor, !isInBounds(anchor, lines: lines) {
            selectionAnchor = nil
        }
    }

    /// Whether `position` denotes a real place in `lines` (column may sit at
    /// the end-of-line insertion point).
    private func isInBounds(_ position: TextEditorPosition, lines: [[Character]]) -> Bool {
        position.line >= 0 && position.line < lines.count
            && position.column >= 0 && position.column <= lines[position.line].count
    }

    /// Normalizes state that can go stale *between* key events: the bound text
    /// can change outside the editor, and an edit can leave a collapsed anchor
    /// behind whose position no longer means anything once lines have merged
    /// or split. Without this, an anchor left on a removed line becomes a
    /// phantom selection spanning past the end of the document, and the next
    /// edit key replaces text the user never selected.
    private func normalizeStaleState() {
        let lines = readLines()
        cursorLine = min(max(0, cursorLine), lines.count - 1)
        cursorColumn = min(max(0, cursorColumn), lines[cursorLine].count)
        if let anchor = selectionAnchor, !isInBounds(anchor, lines: lines) || anchor == cursor {
            selectionAnchor = nil
        }
    }

    // MARK: - Key handling

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        normalizeStaleState()
        // A drag/Shift-click selection is consumed by the next edit (delete, or
        // delete-then-insert) and cleared by any other key. This lets mouse
        // selection drive editing without the editor carrying a full
        // keyboard-selection model.
        if let span = selectionRange {
            if !event.ctrl, !event.alt, let handled = replaceSelection(span, with: event.key) {
                return handled
            }
            clearSelection()
        }

        // Ctrl-modified keys map to the macOS/Emacs text-editing bindings (the
        // Cocoa `StandardKeyBinding.dict`). Ctrl+letter arrives as
        // `.character(letter, ctrl: true)`; Ctrl-H / Ctrl-I / Ctrl-M are
        // pre-parsed to Backspace / Tab / Enter and handled below.
        if event.ctrl, case .character(let character) = event.key {
            return handleControlCharacter(character)
        }
        // Option/Alt-modified keys map to word-wise motion and deletion.
        if event.alt, handleAltKey(event) {
            return true
        }

        return handleBaseKey(event)
    }

    /// If `key` is a text edit, replaces the selection with it and returns true;
    /// returns nil for any other key so the caller clears the selection and
    /// handles the key normally.
    private func replaceSelection(_ span: SelectionSpan, with key: Key) -> Bool? {
        switch key {
        case .backspace, .delete:
            deleteSelection(span)
        case .character(let character) where isInsertable(character):
            deleteSelection(span)
            insert(String(character))
        case .space:
            deleteSelection(span)
            insert(" ")
        case .enter:
            deleteSelection(span)
            insertNewline()
        case .paste(let string):
            deleteSelection(span)
            insert(string)
        default:
            return nil
        }
        return true
    }

    // A flat key table; splitting it further would fragment the mapping
    // without simplifying it. Block form keeps the doc comment adjacent to
    // the declaration.
    // swiftlint:disable cyclomatic_complexity
    /// Handles the unmodified navigation and editing keys.
    private func handleBaseKey(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .character(let character):
            // A ctrl chord never reaches here (dispatched above); an unbound alt
            // chord must not type its letter.
            guard !event.alt, isInsertable(character) else { return false }
            insert(String(character))
        case .space:
            insert(" ")
        case .enter:
            insertNewline()
        case .backspace:
            deleteBackward()
        case .delete:
            deleteForward()
        case .left:
            moveLeft()
        case .right:
            moveRight()
        case .up:
            moveVertical(by: -1)
        case .down:
            moveVertical(by: 1)
        case .home:
            // Mac convention: Home/End move to the start/end of the whole field
            // (the document), not the current line — Ctrl-A / Ctrl-E do lines.
            moveToStartOfDocument()
        case .end:
            moveToEndOfDocument()
        case .pageUp:
            movePage(by: -1)
        case .pageDown:
            movePage(by: 1)
        case .paste(let string):
            insert(string)
        default:
            return false
        }
        return true
    }
    // swiftlint:enable cyclomatic_complexity

    /// Whether a character is one the editor inserts literally.
    private func isInsertable(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character.isPunctuation
            || character.isSymbol || character.isWhitespace
    }

    /// Handles a Ctrl+letter chord (the Emacs-style Cocoa bindings). Returns
    /// `false` for an unbound chord so it can propagate.
    private func handleControlCharacter(_ character: Character) -> Bool {
        switch character {
        case "a": moveToStartOfLine()  // beginning of line
        case "e": moveToEndOfLine()  // end of line
        case "b": moveLeft()  // back one character
        case "f": moveRight()  // forward one character
        case "p": moveVertical(by: -1)  // previous line
        case "n": moveVertical(by: 1)  // next line
        case "d": deleteForward()  // delete forward
        case "k": killToEndOfLine()  // kill to end of line
        case "y": yank()  // yank the last kill
        case "t": transpose()  // transpose characters
        case "o": openLine()  // open a line after the cursor
        case "v": movePage(by: 1)  // page down
        default: return false
        }
        return true
    }

    /// Handles an Option/Alt chord: word-wise motion and deletion. Returns
    /// `false` for an unbound chord so it can propagate.
    private func handleAltKey(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .tab:
            // Plain Tab moves focus; Option-Tab types a literal tab, since a
            // multi-line editor legitimately needs tab characters.
            // Option-Shift-Tab (shift unchecked here) does the same: the
            // modifier superset shouldn't surprise, and macOS has no
            // established binding for it in plain-text editing.
            insert("\t")
        case .left:
            moveWordLeft()
        case .right:
            moveWordRight()
        case .backspace:
            deleteWordBackward()
        case .delete:
            deleteWordForward()
        case .character(let character):
            switch Character(character.lowercased()) {
            case "b": moveWordLeft()
            case "f": moveWordRight()
            default: return false
            }
        default:
            return false
        }
        return true
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
        syncDesiredColumn()
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
        syncDesiredColumn()
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
        syncDesiredColumn()
    }

    private func moveLeft() {
        if cursorColumn > 0 {
            cursorColumn -= 1
        } else if cursorLine > 0 {
            cursorLine -= 1
            cursorColumn = readLines()[cursorLine].count
        }
        syncDesiredColumn()
    }

    private func moveRight() {
        let lines = readLines()
        if cursorColumn < lines[cursorLine].count {
            cursorColumn += 1
        } else if cursorLine < lines.count - 1 {
            cursorLine += 1
            cursorColumn = 0
        }
        syncDesiredColumn()
    }

    /// Moves the cursor up/down a line, preserving the desired column where the
    /// target line is long enough.
    private func moveVertical(by delta: Int) {
        let lines = readLines()
        let target = cursorLine + delta
        guard target >= 0, target < lines.count else { return }
        cursorLine = target
        cursorColumn = TabLayout.charIndex(
            forDisplayColumn: desiredColumn, in: lines[cursorLine], tabWidth: tabWidth)
    }

    /// Moves the cursor up/down a screenful (Page Up / Page Down, Ctrl-V).
    private func movePage(by pages: Int) {
        let lines = readLines()
        let step = max(1, viewportHeight - 1)
        let target = min(max(0, cursorLine + pages * step), lines.count - 1)
        cursorLine = target
        cursorColumn = TabLayout.charIndex(
            forDisplayColumn: desiredColumn, in: lines[cursorLine], tabWidth: tabWidth)
    }

    // MARK: - Line / document motion

    private func moveToStartOfLine() {
        cursorColumn = 0
        desiredColumn = 0
    }

    private func moveToEndOfLine() {
        cursorColumn = readLines()[cursorLine].count
        syncDesiredColumn()
    }

    private func moveToStartOfDocument() {
        cursorLine = 0
        cursorColumn = 0
        desiredColumn = 0
    }

    private func moveToEndOfDocument() {
        let lines = readLines()
        cursorLine = lines.count - 1
        cursorColumn = lines[cursorLine].count
        syncDesiredColumn()
    }

    // MARK: - Word motion

    /// A "word" character for word-wise motion: letters and digits.
    private func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// The column to the left of `column` at the previous word boundary: skip
    /// any non-word run, then the word run.
    private func wordBoundaryLeft(_ line: [Character], from column: Int) -> Int {
        var col = column
        while col > 0, !isWordCharacter(line[col - 1]) { col -= 1 }
        while col > 0, isWordCharacter(line[col - 1]) { col -= 1 }
        return col
    }

    /// The column to the right of `column` at the next word boundary: skip any
    /// non-word run, then the word run.
    private func wordBoundaryRight(_ line: [Character], from column: Int) -> Int {
        var col = column
        while col < line.count, !isWordCharacter(line[col]) { col += 1 }
        while col < line.count, isWordCharacter(line[col]) { col += 1 }
        return col
    }

    private func moveWordLeft() {
        if cursorColumn == 0 {
            moveLeft()  // cross to the end of the previous line
            return
        }
        cursorColumn = wordBoundaryLeft(readLines()[cursorLine], from: cursorColumn)
        syncDesiredColumn()
    }

    private func moveWordRight() {
        let line = readLines()[cursorLine]
        if cursorColumn >= line.count {
            moveRight()  // cross to the start of the next line
            return
        }
        cursorColumn = wordBoundaryRight(line, from: cursorColumn)
        syncDesiredColumn()
    }

    private func deleteWordBackward() {
        if cursorColumn == 0 {
            deleteBackward()  // join with the previous line
            return
        }
        var lines = readLines()
        let target = wordBoundaryLeft(lines[cursorLine], from: cursorColumn)
        lines[cursorLine].removeSubrange(target..<cursorColumn)
        cursorColumn = target
        writeLines(lines)
        syncDesiredColumn()
    }

    private func deleteWordForward() {
        var lines = readLines()
        if cursorColumn >= lines[cursorLine].count {
            deleteForward()  // pull up the next line
            return
        }
        let target = wordBoundaryRight(lines[cursorLine], from: cursorColumn)
        lines[cursorLine].removeSubrange(cursorColumn..<target)
        writeLines(lines)
        syncDesiredColumn()
    }

    // MARK: - Kill / yank / transpose / open

    /// Ctrl-K: kills from the cursor to the end of the line into the kill ring;
    /// at the end of a line it kills the newline (joining the next line).
    private func killToEndOfLine() {
        var lines = readLines()
        let line = lines[cursorLine]
        if cursorColumn < line.count {
            killRing = String(line[cursorColumn...])
            lines[cursorLine].removeSubrange(cursorColumn..<line.count)
            writeLines(lines)
        } else if cursorLine < lines.count - 1 {
            killRing = "\n"
            lines[cursorLine].append(contentsOf: lines[cursorLine + 1])
            lines.remove(at: cursorLine + 1)
            writeLines(lines)
        }
        syncDesiredColumn()
    }

    /// Ctrl-Y: inserts the most recently killed text at the cursor.
    private func yank() {
        guard !killRing.isEmpty else { return }
        insert(killRing)
    }

    /// Ctrl-T: transposes the two characters around the cursor and steps
    /// forward; at the end of a line it transposes the last two characters.
    private func transpose() {
        var lines = readLines()
        var line = lines[cursorLine]
        guard line.count >= 2, cursorColumn > 0 else { return }
        if cursorColumn >= line.count {
            line.swapAt(line.count - 2, line.count - 1)
            lines[cursorLine] = line
            cursorColumn = line.count
        } else {
            line.swapAt(cursorColumn - 1, cursorColumn)
            lines[cursorLine] = line
            cursorColumn += 1
        }
        writeLines(lines)
        syncDesiredColumn()
    }

    /// Ctrl-O: splits the line at the cursor but leaves the cursor in place, so
    /// the text after it opens onto a new line below.
    private func openLine() {
        var lines = readLines()
        var line = lines[cursorLine]
        let tail = Array(line[cursorColumn...])
        line.removeSubrange(cursorColumn..<line.count)
        lines[cursorLine] = line
        lines.insert(tail, at: cursorLine + 1)
        writeLines(lines)
    }
}

// MARK: - Selection

/// A normalized selection span: `start` is at or before `end`.
typealias SelectionSpan = (start: TextEditorPosition, end: TextEditorPosition)

extension TextEditorHandler {
    /// The cursor as a position value.
    var cursor: TextEditorPosition {
        get { TextEditorPosition(line: cursorLine, column: cursorColumn) }
        set {
            cursorLine = newValue.line
            cursorColumn = newValue.column
        }
    }

    /// The normalized selection span (start ≤ end), or nil when empty.
    var selectionRange: SelectionSpan? {
        guard let anchor = selectionAnchor, anchor != cursor else { return nil }
        return anchor < cursor ? (anchor, cursor) : (cursor, anchor)
    }

    /// Drops the selection without moving the cursor.
    func clearSelection() {
        selectionAnchor = nil
    }

    /// Anchors a selection at the current cursor if none exists (drag /
    /// Shift-click), leaving an existing anchor in place.
    func startOrExtendSelection() {
        if selectionAnchor == nil {
            selectionAnchor = cursor
        }
    }

    /// Positions the cursor at a clicked point, clamped into the text. Used by
    /// the mouse handler; leaves any selection anchor untouched (so a drag
    /// extends from it).
    func moveCursor(toLine line: Int, column: Int) {
        let lines = readLines()
        cursorLine = min(max(0, line), lines.count - 1)
        cursorColumn = min(max(0, column), lines[cursorLine].count)
        // Vertical motion after a click should keep the clicked column, so sync
        // the preferred column like the keyboard motion methods do.
        syncDesiredColumn()
    }

    /// The selected column range within `lineIndex` (whose length is
    /// `lineLength`), or nil if the line carries no selection. Interior lines of
    /// a multi-line selection return their whole width.
    func selectedColumns(inLine lineIndex: Int, lineLength: Int) -> Range<Int>? {
        guard let span = selectionRange, lineIndex >= span.start.line, lineIndex <= span.end.line
        else { return nil }
        let lo = lineIndex == span.start.line ? span.start.column : 0
        let hi = lineIndex == span.end.line ? span.end.column : lineLength
        let clampedLo = max(0, min(lo, lineLength))
        let clampedHi = max(0, min(hi, lineLength))
        return clampedLo < clampedHi ? clampedLo..<clampedHi : nil
    }

    /// Removes the selected text, placing the cursor at the span's start and
    /// clearing the selection.
    fileprivate func deleteSelection(_ span: SelectionSpan) {
        var lines = readLines()
        let startLine = min(max(0, span.start.line), lines.count - 1)
        let endLine = min(max(0, span.end.line), lines.count - 1)
        let startColumn = min(max(0, span.start.column), lines[startLine].count)
        let endColumn = min(max(0, span.end.column), lines[endLine].count)
        if startLine == endLine {
            // The per-line clamps can invert a corrupt span's columns once its
            // lines collapse together; an inverted range must not trap.
            lines[startLine].removeSubrange(min(startColumn, endColumn)..<max(startColumn, endColumn))
        } else {
            let head = Array(lines[startLine][..<startColumn])
            let tail = Array(lines[endLine][endColumn...])
            lines[startLine] = head + tail
            lines.removeSubrange((startLine + 1)...endLine)
        }
        cursorLine = startLine
        cursorColumn = startColumn
        desiredColumn = startColumn
        selectionAnchor = nil
        writeLines(lines)
    }
}

/// A position in a ``TextEditor``: a line and a character column, ordered
/// top-to-bottom then left-to-right.
struct TextEditorPosition: Comparable {
    var line: Int
    var column: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.line != rhs.line ? lhs.line < rhs.line : lhs.column < rhs.column
    }
}
