//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// - Cursor navigation (left/right/home/end, and by word with Option/Alt)
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
/// | Option+Backspace | Delete selection or back to the previous word boundary |
/// | Option+Delete | Delete selection or forward to the next word boundary |
/// | Left | Move cursor left (clears selection) |
/// | Right | Move cursor right (clears selection) |
/// | Option+Left / Alt+b | Move to the previous word boundary (clears selection) |
/// | Option+Right / Alt+f | Move to the next word boundary (clears selection) |
/// | Home / Up | Move cursor to start (clears selection) |
/// | End / Down | Move cursor to end (clears selection) |
/// | Shift+Left | Extend selection left |
/// | Shift+Right | Extend selection right |
/// | Shift+Option+Left / Shift+Alt+b | Extend selection to the previous word boundary |
/// | Shift+Option+Right / Shift+Alt+f | Extend selection to the next word boundary |
/// | Shift+Up | Select to start of text |
/// | Shift+Down | Select to end of text |
/// | Shift+Home | Select to start of text |
/// | Shift+End | Select to end of text |
/// | Ctrl+A | Start of line (clears selection) |
/// | Ctrl+E | End of line (clears selection) |
/// | Ctrl+B / Ctrl+F | Back / forward a character, as Left / Right |
/// | Ctrl+D | Delete forward, as Delete (a selection goes with it) |
/// | Ctrl+K | Kill from the caret to the end (clears selection) |
/// | Ctrl+Y | Yank the last kill at the caret (replaces selection) |
/// | Ctrl+T | Transpose the characters around the caret (clears selection) |
/// | Ctrl+U | Erase the field — ALL of it, not just back to the caret |
/// | Option+Ctrl+A | Select all text |
/// | Ctrl+C | Copy selection to clipboard; with nothing selected the key passes on |
/// | Ctrl+X | Cut selection to clipboard; with nothing selected the key passes on |
/// | Ctrl+V | Paste from clipboard |
/// | Ctrl+Z | Undo last change |
/// | Enter | Trigger the submit action — with no `onSubmit` the field declines Return, so a dialog's default button fires |
///
/// Ctrl+A, E, B, F, D, K, Y and T, Option+Ctrl+A and Alt+b / Alt+f come from
/// ``TextEditingCommand``, the table ``TextEditorHandler`` reads too, so the
/// same chord names the same command in both. What the command does can
/// differ, because a field is one line with a keyboard selection:
///
/// - Ctrl+V is paste here, and the editor's page down. Ctrl+O, Ctrl+P and
///   Ctrl+N are the editor's open-a-line, previous line and next line; a
///   field declines them and they propagate.
/// - The editor drops its selection before any Emacs chord and acts at the
///   caret. A field's Ctrl+D deletes the selection, as its Delete key does, and
///   its Ctrl+Y replaces it, as a paste does. Ctrl+K and Ctrl+T drop it in both.
/// - A field reads Option before Control, so Option+Ctrl+B and F move by a
///   word here, and by a character in the editor.
/// - Each field keeps its own kill, apart from the editor's and from the
///   clipboard, and a field's kill, yank and transpose are undoable. A
///   ``SecureField`` keeps no kill, and its word motions go one character
///   (see ``isSecure``).
///
/// An app's keyboard shortcut on the same chord takes all of these but
/// Option+Ctrl+A from the field; Home, End, Left, Right, Delete and
/// Option+Left / Right do the same things, and a kill, yank or transpose can
/// be done by selecting and typing. See
/// ``TextEditingCommand/givesWayToKeyboardShortcuts(homeAndEndReachLineEnds:)``.
///
/// Option+Left and Alt+b are one binding, not two — likewise Option+Right and
/// Alt+f: macOS Terminal sends the readline escapes `ESC b` / `ESC f` when
/// Option is held with an arrow, in addition to the modified-arrow CSI
/// sequences, so both spellings have to mean the same thing (`e9fc5b38` and
/// `ac33ebbd`, both 2026-05-26). And a field carrying `textInputSuggestions`
/// takes Down at the caret to open its pop-up, then the arrows — and, once a
/// row is highlighted, the paging and jump keys too — plus Enter and Escape to
/// drive it, before any row above applies; that half of the map is documented
/// on the modifier.
final class TextFieldHandler: PersistedFocusable {
    /// The unique identifier for this focusable element.
    var focusID: String

    /// The binding to the text content.
    var text: Binding<String>

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool

    /// Whether the field masks its contents, i.e. is a ``SecureField``.
    ///
    /// `SecureField` reuses this handler because the key handling really is
    /// identical — except here. SwiftUI's `SecureField` documents that it
    /// "prevents anyone from cutting or copying the field's contents", which
    /// is also what AppKit's `NSSecureTextField` does, so ``copySelection()``
    /// and ``cutSelection()`` refuse while this is set. Masking alone does
    /// not do it: the bullets are drawn at render time and the handler holds
    /// the real string, so a copy would have put the password on the system
    /// pasteboard. Pasting IN stays allowed — the promise is one-directional.
    ///
    /// It changes two more things, both as `NSSecureTextField` does them
    /// (measured on macOS 15.8, through a window's key path): Ctrl-K deletes
    /// without keeping the kill, so there is nothing for Ctrl-Y to yank; and
    /// every word motion and word deletion goes one character (see
    /// ``wordBoundary(forward:)``), so none shows where the hidden text's words
    /// break. Synced by the field's render pass.
    var isSecure: Bool = false

    /// The clipboard this field reads and writes. Injectable so a test can
    /// see what would have been copied without a real pasteboard — see
    /// ``ClipboardAccess`` for why that is not a convenience.
    var clipboard: ClipboardAccess = .system

    /// The cursor position (character index where next input will be inserted).
    var cursorPosition: Int

    /// The selection anchor position (where selection started).
    /// When nil, there is no active selection.
    /// When set, the selection spans from `selectionAnchor` to `cursorPosition`.
    var selectionAnchor: Int?

    /// Callback triggered when the user presses Enter.
    var onSubmit: (() -> Void)?

    /// The last text Ctrl-K killed, for Ctrl-Y to yank back: a single-slot
    /// kill ring, as ``TextEditorHandler`` keeps. It belongs to this field
    /// alone and is never the clipboard. A ``SecureField`` keeps nothing here
    /// (see ``isSecure``).
    var killRing = ""

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

    // MARK: Input suggestions (``View/textInputSuggestions(_:)``)

    /// The completions of the field's current suggestions, in menu order
    /// (options only — dividers are not navigable). Synced by the field's
    /// render pass; empty when the field has no suggestions.
    var suggestionCompletions: [String] = []

    /// The highlighted suggestion, and every gesture that moves it — shared
    /// with the `Picker` drop-down and the pop-up `Menu`, so all three answer
    /// the same key with the same movement. See ``MenuHighlight/suggestions()``
    /// for why this one clamps and is entered by arrows alone.
    let suggestionHighlighting = MenuHighlight.suggestions()

    /// The highlighted suggestion (an index into ``suggestionCompletions``),
    /// or `nil` while the keyboard is editing the field text.
    var suggestionHighlight: Int? {
        get { suggestionHighlighting.ordinal }
        set { suggestionHighlighting.move(to: newValue) }
    }

    /// Whether the suggestions pop-up is showing. Opt-IN: the menu opens
    /// only on an explicit request — the Down key, or a click on the field's
    /// `▾` disclosure — and closes on Escape, a second disclosure click,
    /// accepting a suggestion, or focus loss. Gaining focus does NOT open
    /// it, and typing neither opens nor closes it (the combo-box field is a
    /// text field first).
    var suggestionsOpen = false

    /// Fired with `true` when the field gains focus and `false` when it
    /// loses it — the classic SwiftUI `TextField(_:text:onEditingChanged:)`
    /// signal. `false` is the "editing ended" commit point: a combo box
    /// records its recents there, not just on Enter. Re-synced by the
    /// field's render pass.
    var onEditingChanged: ((Bool) -> Void)?

    /// The suggestions menu's window scroll (see ``DropdownMenu``).
    let suggestionScroll = ScrollAxis()

    /// How many suggestion rows a Shift-accelerated Up/Down jumps in the open
    /// pop-up. Synced from `environment.shiftStepMultiplier` during the field's
    /// render (default 5), matching the Picker drop-down and radio group; a
    /// plain arrow still moves one. See ``View/shiftStepMultiplier(_:)``.
    var shiftStepMultiplier: Int = 5

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
    /// the end clamp to the text length; and a column past the content area's
    /// RIGHT edge — the closing cap, or a combo box's disclosure — clamps into
    /// its last cell.
    ///
    /// The mapping is in CELLS: `displayWidths` carries each character's
    /// display width (see ``TextFieldContentRenderer/displayCellWidths(of:displayCharacter:)``
    /// — a `SecureField` bullet is one cell however wide the hidden character
    /// is), so a click on either cell of a wide character lands on that
    /// character.
    func characterIndex(forColumn column: Int, contentWidth: Int, displayWidths: [Int]) -> Int {
        let count = displayWidths.count
        let clamped = max(0, min(cursorPosition, count))
        let cursorCellX = displayWidths[0..<clamped].reduce(0, +)
        let scrollStart = TextFieldContentRenderer.scrollCells(
            cursorCellX: cursorCellX, width: contentWidth)
        // Valid content columns are 0..<contentWidth. A column past the right
        // edge — the closing cap, or a combo box's ▾ — must clamp INTO the
        // window: without this it landed on the first OFF-SCREEN character, and
        // the caret-anchored scroll then shifted the field a column (three with
        // a disclosure) on every cap click, so holding the mouse there walked
        // the text sideways. Mirrors the TextEditor's own placeCursor clamp.
        //
        // In CELLS, so a wide character straddling the right edge still
        // resolves to that character rather than to its left neighbour.
        let targetCell = scrollStart + max(0, min(column, contentWidth - 1))
        var cellX = 0
        for (index, cellWidth) in displayWidths.enumerated() {
            if targetCell < cellX + cellWidth { return index }
            cellX += cellWidth
        }
        return count
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
    /// Puts the caret at the very start, dropping any selection.
    ///
    /// One definition, called by Home, by Up, and by Ctrl-A — the same
    /// twin-divergence lesson the list and table pair taught, in miniature: two
    /// copies of "go to the start" is two places for it to stop meaning the
    /// same thing.
    func moveToStart() {
        clearSelection()
        cursorPosition = 0
    }

    /// Puts the caret at the very end, dropping any selection.
    func moveToEnd() {
        clearSelection()
        cursorPosition = text.wrappedValue.count
    }

    func extendSelectionToEnd() {
        startOrExtendSelection()
        cursorPosition = text.wrappedValue.count
    }

    /// Steps the caret back a character, dropping any selection. One
    /// definition for plain Left and Ctrl-B, for the same reason as
    /// ``moveToStart()``.
    func moveBackward() {
        clearSelection()
        moveCursorLeft()
    }

    /// Steps the caret forward a character, dropping any selection: plain
    /// Right, and Ctrl-F.
    func moveForward() {
        clearSelection()
        moveCursorRight()
    }

    /// Moves the caret back to the previous word boundary, dropping any
    /// selection. One definition for Option-Left and Option-B, for the same
    /// reason as ``moveToStart()``.
    func moveWordBackward() {
        clearSelection()
        moveCursorToPreviousWordBoundary()
    }

    /// Moves the caret forward to the next word boundary, dropping any
    /// selection: Option-Right and Option-F.
    func moveWordForward() {
        clearSelection()
        moveCursorToNextWordBoundary()
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
        normalizeStaleState()
        if let handled = handleSuggestionKeyEvent(event) {
            return handled
        }
        switch event.key {
        case .space:
            insertCharacter(" ")
            return true

        case .character(let char):
            return handleCharacterEvent(char, event: event)

        case .backspace, .delete:
            handleDeletion(event)
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
                moveToStart()
            }
            return true

        case .down, .end:
            // Symmetric: Down / End jump to the end; Shift extends.
            if event.shift {
                extendSelectionToEnd()
            } else {
                moveToEnd()
            }
            return true

        case .enter:
            // A field with a submit action consumes Return; without one it
            // lets Return fall through — so in a dialog, Return pressed while
            // typing triggers the `.keyboardShortcut(.defaultAction)` button
            // (the macOS text-system behaviour).
            guard let onSubmit else { return false }
            onSubmit()
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

    /// Backspace and Delete: a character, or with Option a word, as in the
    /// editor. Either takes a selection instead when there is one.
    fileprivate func handleDeletion(_ event: KeyEvent) {
        switch (event.key, event.alt) {
        case (.backspace, false): deleteBackward()
        case (.backspace, true): deleteWordBackward()
        case (.delete, false): deleteForward()
        case (.delete, true): deleteWordForward()
        default: break
        }
    }

    /// Handles a `.character(c)` event: a chord (``TextFieldChord``, where
    /// the order Option and Control are read in is written down), else the
    /// character typed.
    ///
    /// Extracted from ``handleKeyEvent(_:)`` to keep the top-level switch's
    /// cyclomatic complexity manageable.
    fileprivate func handleCharacterEvent(_ char: Character, event: KeyEvent) -> Bool {
        if let chord = TextFieldChord(event) {
            return perform(chord)
        }
        // A Control chord nothing binds propagates rather than typing its
        // letter.
        if event.ctrl {
            return false
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

    /// Handles `.left` / `.right` with the four modifier combinations
    /// (Shift+Option, Option, Shift, plain).
    fileprivate func handleHorizontalArrow(direction: ArrowDirection, event: KeyEvent) {
        switch (direction, event.alt, event.shift) {
        case (.left, true, true):
            extendSelectionToPreviousWordBoundary()
        case (.left, true, false):
            moveWordBackward()
        case (.left, false, true):
            extendSelectionLeft()
        case (.left, false, false):
            moveBackward()
        case (.right, true, true):
            extendSelectionToNextWordBoundary()
        case (.right, true, false):
            moveWordForward()
        case (.right, false, true):
            extendSelectionRight()
        case (.right, false, false):
            moveForward()
        }
    }
}

// MARK: - Input Suggestions

extension TextFieldHandler {
    /// True while the suggestions menu is showing: the field has suggestions
    /// (synced by its render pass) and one of the open gestures showed the
    /// pop-up. Only consulted while focused — that's the only time key
    /// events arrive.
    var suggestionsActive: Bool {
        !suggestionCompletions.isEmpty && suggestionsOpen
    }

    /// Opens or closes the suggestions menu — the disclosure-click gesture.
    /// Opening highlights the row matching the field's current text (the ✓
    /// row), so the menu comes up "at" the field's value like NSComboBox.
    func toggleSuggestionsOpen() {
        guard !suggestionCompletions.isEmpty else { return }
        if suggestionsOpen {
            suggestionsOpen = false
            suggestionHighlight = nil
        } else {
            openSuggestions(preferFirstRow: false)
        }
    }

    /// Shows the menu, highlighting the current value's row when there is
    /// one. A keyboard open (Down) falls back to the first row — the key
    /// expresses "into the menu" — while a pointer open leaves the highlight
    /// at the caret for the mouse to take over.
    private func openSuggestions(preferFirstRow: Bool) {
        suggestionsOpen = true
        suggestionHighlighting.adopt(count: suggestionCompletions.count)
        suggestionHighlighting.move(
            to: suggestionCompletions.firstIndex(of: text.wrappedValue)
                ?? (preferFirstRow ? 0 : nil))
    }

    /// Handles the keys the suggestions menu consumes. Returns `nil` when
    /// the event is not menu interaction, so normal field handling proceeds
    /// — typing always keeps editing the field.
    private func handleSuggestionKeyEvent(_ event: KeyEvent) -> Bool? {
        guard !suggestionCompletions.isEmpty, !event.alt, !event.ctrl else { return nil }
        guard suggestionsOpen else {
            // Closed: Down is the open gesture (the NSComboBox convention);
            // every other key is ordinary field editing.
            if event.key == .down, !event.shift {
                openSuggestions(preferFirstRow: true)
                return true
            }
            return nil
        }

        // The arrows and the jump gestures, through the walk every menu in
        // TUIkit shares — Home/End, PageUp/PageDown and Shift+Up/Down included,
        // with a page being a page of the scrolling pop-up.
        //
        // The combo box's field/menu duality is CONFIGURATION on
        // `suggestionHighlighting` rather than code here: the menu clamps at
        // both ends (the field sits above the first row, so wrapping past it
        // would read as a jump — and Up used to fall back out to the caret from
        // row 0, which combined with the entry rule into a ring that only
        // turned one way), and from the caret only a plain arrow enters it, so
        // Home/End still move the caret and Shift+arrow still extends the
        // selection while nothing is highlighted.
        suggestionHighlighting.adopt(count: suggestionCompletions.count)
        if suggestionHighlighting.handle(
            event, multiplier: shiftStepMultiplier,
            pageSize: max(1, suggestionScroll.viewportHeight))
        {
            return true
        }
        // Any other shifted key is field editing (e.g. Shift+Enter), never menu
        // interaction — the plain-key switch below must not see it.
        guard !event.shift else { return nil }

        switch event.key {
        case .enter:
            guard let highlight = suggestionHighlight else {
                // Enter at the caret submits as usual; the menu closes so
                // the committed field isn't left with a dangling pop-up.
                suggestionsOpen = false
                return nil
            }
            acceptSuggestion(at: highlight)
            return true
        case .escape:
            suggestionsOpen = false
            suggestionHighlight = nil
            return true
        default:
            return nil
        }
    }

    /// Fills the field with the given completion, closes the menu, and fires
    /// the submit action — picking from the list commits a value, the
    /// combo-box (NSComboBox) convention. (SwiftUI's `textInputSuggestions`
    /// doesn't document its submit behaviour; the terminal combo-box reads
    /// better when a pick acts immediately.)
    func acceptSuggestion(at index: Int) {
        guard suggestionCompletions.indices.contains(index) else { return }
        pushUndoState()
        text.wrappedValue = suggestionCompletions[index]
        cursorPosition = text.wrappedValue.count
        clearSelection()
        suggestionHighlight = nil
        suggestionsOpen = false
        onSubmit?()
    }

    /// Any edit returns the keyboard to the caret. The menu's open state is
    /// deliberately untouched — opening and closing are explicit gestures
    /// (Down/disclosure and Escape/disclosure), not side effects of typing.
    func resetSuggestionNavigation() {
        suggestionHighlight = nil
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

        resetSuggestionNavigation()
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
        resetSuggestionNavigation()
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
        resetSuggestionNavigation()
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

    /// Option-Backspace: deletes back to where Option-Left moves
    /// (``wordBoundary(forward:)``: the word boundary the editor's
    /// Option-Backspace uses too, or one character in a ``SecureField``), as
    /// one undoable edit. A selection goes instead, as for plain Backspace.
    func deleteWordBackward() {
        guard !hasSelection else {
            deleteBackward()
            return
        }
        let target = wordBoundary(forward: false)
        guard target < cursorPosition else { return }
        resetSuggestionNavigation()
        deleteRange(target..<cursorPosition)
    }

    /// Option-Delete: deletes forward to where Option-Right moves, as one
    /// undoable edit. A selection goes instead, as for plain Delete.
    func deleteWordForward() {
        guard !hasSelection else {
            deleteForward()
            return
        }
        let target = wordBoundary(forward: true)
        guard target > cursorPosition else { return }
        resetSuggestionNavigation()
        deleteRange(cursorPosition..<target)
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
    /// underscore characters separated by anything else. See ``WordBoundary``,
    /// which `TextEditor` shares.
    func moveCursorToPreviousWordBoundary() {
        cursorPosition = wordBoundary(forward: false)
    }

    /// Moves the cursor to the end of the current word, or, if the cursor is
    /// already at the end of a word, to the end of the next word.
    func moveCursorToNextWordBoundary() {
        cursorPosition = wordBoundary(forward: true)
    }

    /// Where a word motion or a word deletion from the caret stops: the
    /// previous or next word boundary (``WordBoundary``), or, in a
    /// ``SecureField``, one character along.
    ///
    /// AppKit's `NSSecureTextField` goes one character for every word command,
    /// so a word motion cannot show where the words of the hidden text break.
    /// Measured on macOS 15.8 through an `NSWindow`'s key path, from the end of
    /// "hunter2 abc.def ghi": Option-Left stopped at 18 where a plain field
    /// stopped at 16, Option-Right from 0 at 1 not 7, Option-Backspace and
    /// Option-Delete removed one character, and `moveWordBackward:` sent to the
    /// field editor directly moved one.
    func wordBoundary(forward: Bool) -> Int {
        let count = text.wrappedValue.count
        if isSecure {
            return forward ? min(cursorPosition + 1, count) : max(cursorPosition - 1, 0)
        }
        let characters = Array(text.wrappedValue)
        return forward
            ? WordBoundary.next(in: characters, from: cursorPosition)
            : WordBoundary.previous(in: characters, from: cursorPosition)
    }

    /// Ensures the cursor position and selection anchor are within valid bounds.
    func clampCursorPosition() {
        let maxPos = text.wrappedValue.count
        cursorPosition = max(0, min(cursorPosition, maxPos))
        // A stale anchor (the bound text shrank underneath it) is DROPPED, not
        // clamped: clamping would manufacture a selection the user never made,
        // and the next edit key would then delete text they never selected. A
        // collapsed (anchor == cursor) anchor is kept - a drag in progress
        // anchors before its first movement.
        if let anchor = selectionAnchor, anchor < 0 || anchor > maxPos {
            selectionAnchor = nil
        }
    }

    /// Normalizes state that can go stale *between* key events: the bound text
    /// can change outside the handler, and an edit can leave a collapsed
    /// anchor behind whose index no longer means anything once the text has
    /// shifted. Without this, a collapsed anchor left at the old end of the
    /// text becomes a phantom selection after a backspace (anchor 11, cursor
    /// 10) and the next delete indexes past the end of the string - a crash.
    private func normalizeStaleState() {
        let maxPos = text.wrappedValue.count
        cursorPosition = max(0, min(cursorPosition, maxPos))
        if let anchor = selectionAnchor,
            anchor < 0 || anchor > maxPos || anchor == cursorPosition
        {
            selectionAnchor = nil
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
        resetSuggestionNavigation()
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
        onEditingChanged?(true)
    }

    func onFocusLost() {
        // The pop-up never outlives the focus session, and a fresh session
        // starts with the keyboard at the caret and the menu closed.
        suggestionsOpen = false
        resetSuggestionNavigation()
        // Editing has ended: the commit point for values that apply live —
        // a combo box records its recents here, not just on Enter.
        onEditingChanged?(false)
    }
}
