//  TUIKit - Terminal UI Kit for Swift
//  TextFieldHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A focus handler for text field components.
///
/// `TextFieldHandler` manages text editing state and keyboard input for
/// `TextField`. It handles:
/// - Character insertion at cursor position
/// - Backspace/delete for removing characters
/// - Cursor navigation (left/right/home/end)
/// - Text selection with Shift+Arrow keys
/// - Copy/Cut/Paste via system clipboard
/// - Submit action on Enter
///
/// ## Usage
///
/// ```swift
/// // In TextField's renderToBuffer:
/// let handler = TextFieldHandler(
///     focusID: focusID,
///     text: textBinding,
///     canBeFocused: !isDisabled
/// )
/// handler.onSubmit = submitAction
/// focusManager.register(handler, inSection: sectionID)
/// ```
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | Any printable | Insert character at cursor (replaces selection) |
/// | Backspace | Delete selection or character before cursor |
/// | Delete | Delete selection or character at cursor |
/// | Left | Move cursor left (clears selection) |
/// | Right | Move cursor right (clears selection) |
/// | Home | Move cursor to start (clears selection) |
/// | End | Move cursor to end (clears selection) |
/// | Shift+Left | Extend selection left |
/// | Shift+Right | Extend selection right |
/// | Shift+Up | Select to start of text |
/// | Shift+Down | Select to end of text |
/// | Shift+Home | Select to start of text |
/// | Shift+End | Select to end of text |
/// | Ctrl+A | Select all text |
/// | Ctrl+C | Copy selection to clipboard |
/// | Ctrl+X | Cut selection to clipboard |
/// | Ctrl+V | Paste from clipboard |
/// | Ctrl+Z | Undo last change |
/// | Enter | Trigger submit action |
final class TextFieldHandler: Focusable {
    /// The unique identifier for this focusable element.
    let focusID: String

    /// The binding to the text content.
    var text: Binding<String>

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool

    /// The cursor position (character index where next input will be inserted).
    var cursorPosition: Int

    /// The selection anchor position (where selection started).
    /// When nil, there is no active selection.
    /// When set, the selection spans from `selectionAnchor` to `cursorPosition`.
    var selectionAnchor: Int?

    /// Callback triggered when the user presses Enter.
    var onSubmit: (() -> Void)?

    /// The text content type used for input character filtering.
    ///
    /// When set, both typed characters and pasted text are filtered against
    /// the allowed character set of the content type. Synced from the
    /// environment during each render pass.
    var textContentType: TextContentType?

    /// Undo history stack storing previous text states and cursor positions.
    private var undoStack: [(text: String, cursor: Int)] = []

    /// Maximum number of undo states to keep.
    private let maxUndoStates = 50

    /// Creates a text field handler.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - text: The binding to the text content.
    ///   - canBeFocused: Whether this element can receive focus. Defaults to `true`.
    ///   - cursorPosition: The initial cursor position. Defaults to end of text.
    init(
        focusID: String,
        text: Binding<String>,
        canBeFocused: Bool = true,
        cursorPosition: Int? = nil
    ) {
        self.focusID = focusID
        self.text = text
        self.canBeFocused = canBeFocused
        self.cursorPosition = cursorPosition ?? text.wrappedValue.count
        self.selectionAnchor = nil
    }
}

// MARK: - Selection

extension TextFieldHandler {
    /// Returns the current selection range, or nil if no selection.
    ///
    /// The range is always normalized (start < end) regardless of
    /// whether the user selected left-to-right or right-to-left.
    var selectionRange: Range<Int>? {
        guard let anchor = selectionAnchor else { return nil }
        guard anchor != cursorPosition else { return nil }  // Empty selection
        let start = min(anchor, cursorPosition)
        let end = max(anchor, cursorPosition)
        return start..<end
    }

    /// Returns true if there is an active text selection.
    var hasSelection: Bool {
        selectionRange != nil
    }

    /// Clears the current selection without moving the cursor.
    func clearSelection() {
        selectionAnchor = nil
    }

    /// Starts or extends a selection from the current cursor position.
    ///
    /// If no selection exists, sets the anchor at the current cursor position.
    /// If a selection exists, the anchor stays where it is.
    func startOrExtendSelection() {
        if selectionAnchor == nil {
            selectionAnchor = cursorPosition
        }
    }

    /// Maps a click column — measured from the content area's left edge, 0-based
    /// — to a character index, inverting the horizontal-scroll math in
    /// ``TextFieldContentRenderer`` `buildTextWithCursor`. The scroll offset is
    /// derived from the *current* cursor position, exactly as the renderer
    /// derives it, so a click lands where the user sees the caret land. Columns
    /// left of the text clamp to the start of the visible window; columns past
    /// the end clamp to the text length.
    ///
    /// The field renders one cell per character (wide characters are not given
    /// extra cells), so this inverse is a straight column-to-index mapping,
    /// matching what is on screen.
    func characterIndex(forColumn column: Int, contentWidth: Int) -> Int {
        let count = text.wrappedValue.count
        let clamped = max(0, min(cursorPosition, count))
        let visibleTextWidth = max(1, contentWidth - 1)  // renderer reserves 1 for the cursor
        let scrollOffset = clamped <= visibleTextWidth ? 0 : clamped - visibleTextWidth
        return max(0, min(scrollOffset + max(0, column), count))
    }

    /// Deletes the text in the given range and positions cursor at start.
    ///
    /// Pushes the current state to the undo stack before deleting.
    ///
    /// - Parameter range: The range of characters to delete.
    func deleteRange(_ range: Range<Int>) {
        pushUndoState()
        deleteRangeWithoutUndo(range)
    }

    /// Deletes the text in the given range without pushing to undo stack.
    ///
    /// Used internally when undo state has already been pushed.
    ///
    /// - Parameter range: The range of characters to delete.
    func deleteRangeWithoutUndo(_ range: Range<Int>) {
        var current = text.wrappedValue
        let startIndex = current.index(current.startIndex, offsetBy: range.lowerBound)
        let endIndex = current.index(current.startIndex, offsetBy: range.upperBound)
        current.removeSubrange(startIndex..<endIndex)
        text.wrappedValue = current
        cursorPosition = range.lowerBound
    }

    /// Extends selection one character to the left.
    func extendSelectionLeft() {
        startOrExtendSelection()
        if cursorPosition > 0 {
            cursorPosition -= 1
        }
    }

    /// Extends selection one character to the right.
    func extendSelectionRight() {
        startOrExtendSelection()
        if cursorPosition < text.wrappedValue.count {
            cursorPosition += 1
        }
    }

    /// Extends selection to the start of the text.
    func extendSelectionToStart() {
        startOrExtendSelection()
        cursorPosition = 0
    }

    /// Extends selection to the end of the text.
    func extendSelectionToEnd() {
        startOrExtendSelection()
        cursorPosition = text.wrappedValue.count
    }

    /// Extends selection to the start of the current (or previous) word.
    ///
    /// Same boundary semantics as ``moveCursorToPreviousWordBoundary()`` —
    /// the cursor moves to the start of the word it's inside, or, if it's
    /// already at the start of a word, to the start of the word before.
    func extendSelectionToPreviousWordBoundary() {
        startOrExtendSelection()
        moveCursorToPreviousWordBoundary()
    }

    /// Extends selection to the end of the current (or next) word.
    ///
    /// Same boundary semantics as ``moveCursorToNextWordBoundary()``.
    func extendSelectionToNextWordBoundary() {
        startOrExtendSelection()
        moveCursorToNextWordBoundary()
    }
}

// MARK: - Key Event Handling

extension TextFieldHandler {
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .space:
            insertCharacter(" ")
            return true

        case .character(let char):
            return handleCharacterEvent(char, event: event)

        case .backspace:
            deleteBackward()
            return true

        case .delete:
            deleteForward()
            return true

        case .left:
            handleHorizontalArrow(direction: .left, event: event)
            return true

        case .right:
            handleHorizontalArrow(direction: .right, event: event)
            return true

        case .up, .home:
            // A single-line text field has nowhere "up" to go, so Up and
            // Home both jump to the start; Shift+Up / Shift+Home extend the
            // selection there instead.
            if event.shift {
                extendSelectionToStart()
            } else {
                clearSelection()
                cursorPosition = 0
            }
            return true

        case .down, .end:
            // Symmetric: Down / End jump to the end; Shift extends.
            if event.shift {
                extendSelectionToEnd()
            } else {
                clearSelection()
                cursorPosition = text.wrappedValue.count
            }
            return true

        case .enter:
            onSubmit?()
            return true

        case .paste(let text):
            insertText(text)
            return true

        default:
            return false
        }
    }

    /// Direction enum for `handleHorizontalArrow`.
    fileprivate enum ArrowDirection {
        case left, right
    }

    /// Routes a `.character(c)` event through the Option- and Ctrl-modifier
    /// shortcut tables before falling through to insertion.
    ///
    /// Extracted from ``handleKeyEvent(_:)`` to keep the top-level switch's
    /// cyclomatic complexity manageable — the modifier shortcuts have their
    /// own nested switches and pushed the parent function over the linter
    /// threshold.
    fileprivate func handleCharacterEvent(_ char: Character, event: KeyEvent) -> Bool {
        // Option/Alt + b / f are the historical readline word-navigation
        // bindings, and macOS Terminal sends them as `ESC b` / `ESC f` when
        // the user holds Option with the arrow keys (in addition to the
        // modified-arrow CSI sequences). Handle them up-front so the letter
        // does not fall through to `insertCharacter`.
        if event.alt, let handled = handleAltCharacter(char, shift: event.shift) {
            return handled
        }
        if event.ctrl {
            return handleCtrlCharacter(char)
        }
        // Ignore control characters except printable ones.
        if char.isLetter || char.isNumber || char.isPunctuation
            || char.isSymbol || char.isWhitespace
        {
            insertCharacter(char)
            return true
        }
        return false
    }

    /// Handles Option/Alt + character shortcuts. Returns `nil` when the
    /// character is not a recognised Alt shortcut so the caller can fall
    /// through to Ctrl-handling / insertion.
    fileprivate func handleAltCharacter(_ char: Character, shift: Bool) -> Bool? {
        switch char {
        case "b", "B":
            if shift {
                extendSelectionToPreviousWordBoundary()
            } else {
                clearSelection()
                moveCursorToPreviousWordBoundary()
            }
            return true
        case "f", "F":
            if shift {
                extendSelectionToNextWordBoundary()
            } else {
                clearSelection()
                moveCursorToNextWordBoundary()
            }
            return true
        default:
            return nil
        }
    }

    /// Handles Ctrl + character shortcuts. Always returns a `Bool` — `false`
    /// when the character has no Ctrl binding, so the event is dropped.
    fileprivate func handleCtrlCharacter(_ char: Character) -> Bool {
        switch char {
        case "a", "A":
            selectAll()
            return true
        case "c", "C":
            copySelection()
            return true
        case "x", "X":
            cutSelection()
            return true
        case "v", "V":
            paste()
            return true
        case "z", "Z":
            undo()
            return true
        case "u", "U":
            let length = text.wrappedValue.count
            if length > 0 {
                deleteRange(0..<length)
            }
            clearSelection()
            cursorPosition = 0
            return true
        default:
            return false
        }
    }

    /// Handles `.left` / `.right` with the four modifier combinations
    /// (Shift+Option, Option, Shift, plain).
    fileprivate func handleHorizontalArrow(direction: ArrowDirection, event: KeyEvent) {
        switch (direction, event.alt, event.shift) {
        case (.left, true, true):
            extendSelectionToPreviousWordBoundary()
        case (.left, true, false):
            clearSelection()
            moveCursorToPreviousWordBoundary()
        case (.left, false, true):
            extendSelectionLeft()
        case (.left, false, false):
            clearSelection()
            moveCursorLeft()
        case (.right, true, true):
            extendSelectionToNextWordBoundary()
        case (.right, true, false):
            clearSelection()
            moveCursorToNextWordBoundary()
        case (.right, false, true):
            extendSelectionRight()
        case (.right, false, false):
            clearSelection()
            moveCursorRight()
        }
    }
}

// MARK: - Text Editing

extension TextFieldHandler {
    /// Inserts a character at the current cursor position.
    ///
    /// If text is selected, the selection is replaced with the character.
    ///
    /// - Parameter char: The character to insert.
    func insertCharacter(_ char: Character) {
        guard textContentType?.isAllowed(char) ?? true else { return }

        pushUndoState()

        // Replace selection if present
        if let range = selectionRange {
            deleteRangeWithoutUndo(range)
            clearSelection()
        }

        // Note: `current` retains the pre-write value via copy-on-
        // write; we only mutate `updated`. Diagnostic logging below
        // takes advantage of that to report the before/after pair
        // without an extra capture.
        let current = text.wrappedValue
        var updated = current
        let index = updated.index(updated.startIndex, offsetBy: min(cursorPosition, updated.count))
        updated.insert(char, at: index)
        text.wrappedValue = updated
        cursorPosition += 1

        // Diagnostic (TUIKIT_DEBUG_FOCUS=1): identify which @State
        // we actually wrote through. Bindings don't carry identity,
        // but the wrappedValue pair is enough to spot the wrong-
        // field-receiving-input class of bug.
        debugFocusLog("""
            insertCharacter '\(char)' into handler \(focusID)
              pre wrappedValue: \(current.debugDescription)
              post wrappedValue: \(updated.debugDescription)
            """)
    }

    /// Deletes the character before the cursor (backspace).
    ///
    /// If text is selected, the entire selection is deleted.
    func deleteBackward() {
        // Delete selection if present
        if let range = selectionRange {
            pushUndoState()
            deleteRangeWithoutUndo(range)
            clearSelection()
            return
        }

        guard cursorPosition > 0 else { return }
        pushUndoState()
        var current = text.wrappedValue
        let index = current.index(current.startIndex, offsetBy: cursorPosition - 1)
        current.remove(at: index)
        text.wrappedValue = current
        cursorPosition -= 1
    }

    /// Deletes the character at the cursor position (delete key).
    ///
    /// If text is selected, the entire selection is deleted.
    func deleteForward() {
        // Delete selection if present
        if let range = selectionRange {
            pushUndoState()
            deleteRangeWithoutUndo(range)
            clearSelection()
            return
        }

        var current = text.wrappedValue
        guard cursorPosition < current.count else { return }
        pushUndoState()
        let index = current.index(current.startIndex, offsetBy: cursorPosition)
        current.remove(at: index)
        text.wrappedValue = current
    }
}

// MARK: - Cursor Navigation

extension TextFieldHandler {
    /// Moves the cursor one position to the left.
    func moveCursorLeft() {
        if cursorPosition > 0 {
            cursorPosition -= 1
        }
    }

    /// Moves the cursor one position to the right.
    func moveCursorRight() {
        if cursorPosition < text.wrappedValue.count {
            cursorPosition += 1
        }
    }

    /// Moves the cursor to the start of the current word, or, if the cursor is
    /// already at the start of a word, to the start of the previous word.
    ///
    /// "Word" here matches the readline convention — runs of alphanumeric or
    /// underscore characters separated by anything else.
    func moveCursorToPreviousWordBoundary() {
        let chars = Array(text.wrappedValue)
        var pos = cursorPosition
        // Skip back over inter-word (non-word) characters.
        while pos > 0 && !TextFieldHandler.isWordCharacter(chars[pos - 1]) {
            pos -= 1
        }
        // Skip back over the word itself.
        while pos > 0 && TextFieldHandler.isWordCharacter(chars[pos - 1]) {
            pos -= 1
        }
        cursorPosition = pos
    }

    /// Moves the cursor to the end of the current word, or, if the cursor is
    /// already at the end of a word, to the end of the next word.
    func moveCursorToNextWordBoundary() {
        let chars = Array(text.wrappedValue)
        var pos = cursorPosition
        // Skip forward over inter-word (non-word) characters.
        while pos < chars.count && !TextFieldHandler.isWordCharacter(chars[pos]) {
            pos += 1
        }
        // Skip forward over the word itself.
        while pos < chars.count && TextFieldHandler.isWordCharacter(chars[pos]) {
            pos += 1
        }
        cursorPosition = pos
    }

    /// A "word" character for the purposes of Option+arrow navigation —
    /// letters, digits, and underscore. Everything else is treated as a word
    /// separator.
    fileprivate static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// Ensures the cursor position and selection anchor are within valid bounds.
    func clampCursorPosition() {
        let maxPos = text.wrappedValue.count
        cursorPosition = max(0, min(cursorPosition, maxPos))
        if let anchor = selectionAnchor {
            selectionAnchor = max(0, min(anchor, maxPos))
        }
    }
}

// MARK: - Undo

extension TextFieldHandler {
    /// Pushes the current state onto the undo stack.
    func pushUndoState() {
        let state = (text: text.wrappedValue, cursor: cursorPosition)

        // Avoid duplicate states
        if let last = undoStack.last, last.text == state.text {
            return
        }

        undoStack.append(state)

        // Limit stack size
        if undoStack.count > maxUndoStates {
            undoStack.removeFirst()
        }
    }

    /// Restores the previous text state from the undo stack.
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        text.wrappedValue = previous.text
        cursorPosition = min(previous.cursor, previous.text.count)
        clearSelection()
    }
}

// MARK: - Focus Lifecycle

extension TextFieldHandler {
    func onFocusReceived() {
        // Ensure cursor is at a valid position
        clampCursorPosition()
    }

    func onFocusLost() {
        // Nothing special needed when losing focus
    }
}
