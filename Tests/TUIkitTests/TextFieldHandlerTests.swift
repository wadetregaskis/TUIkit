//  TUIKit - Terminal UI Kit for Swift
//  TextFieldHandlerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - TextFieldHandler Tests

@MainActor
@Suite("TextFieldHandler Tests")
struct TextFieldHandlerTests {

    // MARK: - Initialization

    @Test("Handler initializes with correct defaults")
    func initializationDefaults() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })

        let handler = TextFieldHandler(focusID: "test", text: binding)

        #expect(handler.focusID == "test")
        #expect(handler.canBeFocused == true)
        #expect(handler.cursorPosition == 5)  // End of "Hello"
    }

    @Test("Handler initializes with custom cursor position")
    func initializationWithCursorPosition() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })

        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 2)

        #expect(handler.cursorPosition == 2)
    }

    @Test("Handler initializes with empty text")
    func initializationEmptyText() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })

        let handler = TextFieldHandler(focusID: "test", text: binding)

        #expect(handler.cursorPosition == 0)
    }

    // MARK: - Character Insertion

    @Test("Insert character at end")
    func insertCharacterAtEnd() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        handler.insertCharacter("!")

        #expect(text == "Hello!")
        #expect(handler.cursorPosition == 6)
    }

    @Test("Insert character in middle")
    func insertCharacterInMiddle() {
        var text = "Hllo"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 1)

        handler.insertCharacter("e")

        #expect(text == "Hello")
        #expect(handler.cursorPosition == 2)
    }

    @Test("Insert character at start")
    func insertCharacterAtStart() {
        var text = "ello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        handler.insertCharacter("H")

        #expect(text == "Hello")
        #expect(handler.cursorPosition == 1)
    }

    @Test("Insert space character")
    func insertSpaceCharacter() {
        var text = "HelloWorld"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 5)

        handler.insertCharacter(" ")

        #expect(text == "Hello World")
        #expect(handler.cursorPosition == 6)
    }

    // MARK: - Delete Backward (Backspace)

    @Test("Delete backward removes character before cursor")
    func deleteBackward() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        handler.deleteBackward()

        #expect(text == "Hell")
        #expect(handler.cursorPosition == 4)
    }

    @Test("Delete backward in middle of text")
    func deleteBackwardMiddle() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 3)

        handler.deleteBackward()

        #expect(text == "Helo")
        #expect(handler.cursorPosition == 2)
    }

    @Test("Delete backward at start does nothing")
    func deleteBackwardAtStart() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        handler.deleteBackward()

        #expect(text == "Hello")
        #expect(handler.cursorPosition == 0)
    }

    // MARK: - Delete Forward (Delete Key)

    @Test("Delete forward removes character at cursor")
    func deleteForward() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        handler.deleteForward()

        #expect(text == "ello")
        #expect(handler.cursorPosition == 0)
    }

    @Test("Delete forward in middle of text")
    func deleteForwardMiddle() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 2)

        handler.deleteForward()

        #expect(text == "Helo")
        #expect(handler.cursorPosition == 2)
    }

    @Test("Delete forward at end does nothing")
    func deleteForwardAtEnd() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)  // Cursor at end

        handler.deleteForward()

        #expect(text == "Hello")
        #expect(handler.cursorPosition == 5)
    }

    // MARK: - Cursor Movement

    @Test("Move cursor left")
    func moveCursorLeft() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        handler.moveCursorLeft()

        #expect(handler.cursorPosition == 4)
    }

    @Test("Move cursor left at start stays at 0")
    func moveCursorLeftAtStart() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        handler.moveCursorLeft()

        #expect(handler.cursorPosition == 0)
    }

    @Test("Move cursor right")
    func moveCursorRight() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 2)

        handler.moveCursorRight()

        #expect(handler.cursorPosition == 3)
    }

    @Test("Move cursor right at end stays at end")
    func moveCursorRightAtEnd() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)  // Cursor at end

        handler.moveCursorRight()

        #expect(handler.cursorPosition == 5)
    }

    // MARK: - Key Event Handling

    @Test("Character key event inserts character")
    func handleCharacterKeyEvent() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("A")))

        #expect(handled == true)
        #expect(text == "A")
    }

    @Test("Backspace key event deletes backward")
    func handleBackspaceKeyEvent() {
        var text = "AB"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .backspace))

        #expect(handled == true)
        #expect(text == "A")
    }

    @Test("Delete key event deletes forward")
    func handleDeleteKeyEvent() {
        var text = "AB"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        let handled = handler.handleKeyEvent(KeyEvent(key: .delete))

        #expect(handled == true)
        #expect(text == "B")
    }

    @Test("Left arrow key event moves cursor left")
    func handleLeftArrowKeyEvent() {
        var text = "AB"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .left))

        #expect(handled == true)
        #expect(handler.cursorPosition == 1)
    }

    @Test("Right arrow key event moves cursor right")
    func handleRightArrowKeyEvent() {
        var text = "AB"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        let handled = handler.handleKeyEvent(KeyEvent(key: .right))

        #expect(handled == true)
        #expect(handler.cursorPosition == 1)
    }

    @Test("Home key event moves cursor to start")
    func handleHomeKeyEvent() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .home))

        #expect(handled == true)
        #expect(handler.cursorPosition == 0)
    }

    @Test("End key event moves cursor to end")
    func handleEndKeyEvent() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        let handled = handler.handleKeyEvent(KeyEvent(key: .end))

        #expect(handled == true)
        #expect(handler.cursorPosition == 5)
    }

    @Test("Enter key event triggers onSubmit")
    func handleEnterKeyEvent() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        var submitCalled = false
        handler.onSubmit = { submitCalled = true }

        let handled = handler.handleKeyEvent(KeyEvent(key: .enter))

        #expect(handled == true)
        #expect(submitCalled == true)
    }

    @Test("Unhandled key event returns false")
    func handleUnhandledKeyEvent() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .f1))

        #expect(handled == false)
    }

    // MARK: - Cursor Clamping

    @Test("Clamp cursor position when text shrinks")
    func clampCursorPosition() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        // Simulate external text change
        text = "Hi"
        handler.text = binding
        handler.clampCursorPosition()

        #expect(handler.cursorPosition == 2)  // Clamped to "Hi".count
    }

    // MARK: - Ctrl-U: erase contents

    @Test("Ctrl-U erases the text field contents and resets the cursor")
    func ctrlUErasesContents() {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 10)

        let consumed = handler.handleKeyEvent(
            KeyEvent(key: .character("u"), ctrl: true))
        #expect(consumed)
        #expect(text.isEmpty)
        #expect(handler.cursorPosition == 0)
    }

    // MARK: - Option / Alt + arrow: word navigation

    @Test("Option-Left moves to the start of the previous word")
    func optionLeftMovesToPreviousWord() {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(
            focusID: "test", text: binding, cursorPosition: text.count)

        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 16, "Cursor moved to start of 'fox'")
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 10, "Cursor moved to start of 'brown'")
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 4, "Cursor moved to start of 'quick'")
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 0, "Cursor moved to start of 'the'")
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 0, "At start: Option-Left is a no-op")
    }

    @Test("Option-Right moves to the end of the next word")
    func optionRightMovesToNextWord() {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 3, "End of 'the'")
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 9, "End of 'quick'")
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 15, "End of 'brown'")
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 19, "End of 'fox'")
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 19, "At end: Option-Right is a no-op")
    }

    @Test("Option-b is a synonym for Option-Left (readline word-back)")
    func optionBSynonymForOptionLeft() {
        var text = "hello world"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(
            focusID: "test", text: binding, cursorPosition: text.count)

        let consumed = handler.handleKeyEvent(
            KeyEvent(key: .character("b"), alt: true))
        #expect(consumed)
        #expect(handler.cursorPosition == 6, "Cursor at start of 'world'")
        #expect(text == "hello world", "No 'b' was inserted")
    }

    @Test("Option-f is a synonym for Option-Right (readline word-forward)")
    func optionFSynonymForOptionRight() {
        var text = "hello world"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        let consumed = handler.handleKeyEvent(
            KeyEvent(key: .character("f"), alt: true))
        #expect(consumed)
        #expect(handler.cursorPosition == 5, "Cursor at end of 'hello'")
        #expect(text == "hello world", "No 'f' was inserted")
    }

    @Test("Shift+Option+Left extends selection to the previous word boundary")
    func shiftOptionLeftExtendsSelectionToPreviousWord() throws {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(
            focusID: "test", text: binding, cursorPosition: text.count)

        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true, shift: true))
        #expect(handler.cursorPosition == 16, "Cursor at start of 'fox'")
        #expect(handler.selectionAnchor == 19, "Anchor at original end")
        let range1 = try #require(handler.selectionRange)
        #expect(range1 == 16..<19, "Selection spans 'fox'")

        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true, shift: true))
        #expect(handler.cursorPosition == 10, "Cursor at start of 'brown'")
        let range2 = try #require(handler.selectionRange)
        #expect(range2 == 10..<19, "Selection now spans 'brown fox'")
    }

    @Test("Shift+Option+Right extends selection to the next word boundary")
    func shiftOptionRightExtendsSelectionToNextWord() throws {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true, shift: true))
        #expect(handler.cursorPosition == 3, "Cursor at end of 'the'")
        let range1 = try #require(handler.selectionRange)
        #expect(range1 == 0..<3, "Selection spans 'the'")

        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true, shift: true))
        #expect(handler.cursorPosition == 9, "Cursor at end of 'quick'")
        let range2 = try #require(handler.selectionRange)
        #expect(range2 == 0..<9, "Selection now spans 'the quick'")
    }

    @Test("Shift+Option+Right shrinks an existing leftward selection")
    func shiftOptionRightShrinksLeftwardSelection() throws {
        // Start with cursor in the middle, extend leftward, then shrink
        // back by stepping right one word at a time.
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 15)

        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true, shift: true))
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true, shift: true))
        // Anchor stays at 15, cursor now at 4 (start of 'quick').
        #expect(handler.cursorPosition == 4)
        #expect(handler.selectionAnchor == 15)

        // Stepping right with Shift+Option moves the cursor end without
        // touching the anchor, so the selection contracts.
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true, shift: true))
        #expect(handler.cursorPosition == 9, "Cursor at end of 'quick'")
        #expect(handler.selectionAnchor == 15, "Anchor unchanged")
        let range = try #require(handler.selectionRange)
        #expect(range == 9..<15)
    }

    @Test("Shift+Option+b/f mirror Shift+Option+Left/Right")
    func shiftOptionLetterSynonyms() throws {
        var text = "hello world"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(
            focusID: "test", text: binding, cursorPosition: text.count)

        _ = handler.handleKeyEvent(KeyEvent(key: .character("b"), alt: true, shift: true))
        #expect(handler.cursorPosition == 6)
        let range = try #require(handler.selectionRange)
        #expect(range == 6..<11, "Selection spans 'world'")
        #expect(text == "hello world", "No 'b' was inserted")
    }

    // MARK: - Click column → character index

    @Test("A click column maps to a character index (unscrolled field)")
    func clickColumnMapsToIndex() {
        var text = "hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        // With the whole word visible, the click column is the character index.
        #expect(handler.characterIndex(forColumn: 0, contentWidth: 20) == 0)
        #expect(handler.characterIndex(forColumn: 3, contentWidth: 20) == 3)
        // Past the end clamps to the text length; negatives clamp to the start.
        #expect(handler.characterIndex(forColumn: 40, contentWidth: 20) == 5)
        #expect(handler.characterIndex(forColumn: -2, contentWidth: 20) == 0)
    }

    @Test("A click column maps through the horizontal scroll offset")
    func clickColumnMapsThroughScroll() {
        var text = "abcdefghij"  // 10 chars
        let binding = Binding(get: { text }, set: { text = $0 })
        // Cursor at the end scrolls the field: contentWidth 5 → visibleTextWidth 4,
        // so scrollOffset = 10 - 4 = 6; visible window starts at index 6.
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 10)
        #expect(handler.characterIndex(forColumn: 0, contentWidth: 5) == 6)
        #expect(handler.characterIndex(forColumn: 2, contentWidth: 5) == 8)
    }
}
