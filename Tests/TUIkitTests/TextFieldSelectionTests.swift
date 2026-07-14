//  TUIKit - Terminal UI Kit for Swift
//  TextFieldSelectionTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - TextFieldHandler Selection Tests

@MainActor
@Suite("TextField Selection Tests")
struct TextFieldSelectionTests {

    // MARK: - Selection State

    @Test("No selection by default")
    func noSelectionByDefault() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        #expect(handler.selectionAnchor == nil)
        #expect(handler.hasSelection == false)
        #expect(handler.selectionRange == nil)
    }

    @Test("Selection range normalizes anchor and cursor")
    func selectionRangeNormalized() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 4)

        // Set anchor at position 1 (selecting "ell" from left to right)
        handler.selectionAnchor = 1
        #expect(handler.selectionRange == 1..<4)

        // Swap: anchor at 4, cursor at 1 (selecting "ell" from right to left)
        handler.selectionAnchor = 4
        handler.cursorPosition = 1
        #expect(handler.selectionRange == 1..<4)  // Still normalized
    }

    @Test("Empty selection when anchor equals cursor")
    func emptySelectionWhenAnchorEqualsCursor() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 2)

        handler.selectionAnchor = 2
        #expect(handler.hasSelection == false)
        #expect(handler.selectionRange == nil)
    }

    @Test("Clear selection removes anchor")
    func clearSelectionRemovesAnchor() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 4)
        handler.selectionAnchor = 1

        handler.clearSelection()

        #expect(handler.selectionAnchor == nil)
        #expect(handler.hasSelection == false)
    }

    @Test("Start selection sets anchor at current cursor")
    func startSelectionSetsAnchor() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 2)

        handler.startOrExtendSelection()

        #expect(handler.selectionAnchor == 2)
    }

    @Test("Extend selection keeps existing anchor")
    func extendSelectionKeepsAnchor() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 2)
        handler.selectionAnchor = 1

        handler.startOrExtendSelection()

        #expect(handler.selectionAnchor == 1)  // Unchanged
    }

    @Test("Delete range removes selected text")
    func deleteRangeRemovesSelectedText() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        handler.deleteRange(2..<8)  // Remove "llo Wo"

        #expect(text == "Herld")
        #expect(handler.cursorPosition == 2)
    }

    @Test("Clamp drops a selection anchor the text no longer contains")
    func clampDropsStaleSelectionAnchor() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 10)
        handler.selectionAnchor = 8

        // Simulate external text change. The anchor's index is meaningless in
        // the new text, so it is dropped — clamping it into bounds would
        // manufacture a selection the user never made, and the next edit key
        // would delete text they never selected.
        text = "Hi"
        handler.text = binding
        handler.clampCursorPosition()

        #expect(handler.cursorPosition == 2)
        #expect(handler.selectionAnchor == nil)
    }

    @Test("Clamp keeps an anchor the text still contains")
    func clampKeepsValidSelectionAnchor() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 10)
        handler.selectionAnchor = 3

        text = "Hello"
        handler.text = binding
        handler.clampCursorPosition()

        #expect(handler.cursorPosition == 5)
        #expect(handler.selectionAnchor == 3, "an in-bounds anchor survives the shrink")
    }

    // MARK: - Selection Keyboard Handling

    @Test(
        "A shifted movement key anchors at the start cursor and extends the selection",
        arguments: [
            // (key, startCursor, expectedCursor, expectedRange) on "Hello"
            (Key.left, 3, 2, 2..<3),  // Shift+Left extends left
            (.right, 2, 3, 2..<3),  // Shift+Right extends right
            (.up, 3, 0, 0..<3),  // Shift+Up selects to start
            (.down, 2, 5, 2..<5),  // Shift+Down selects to end
            (.home, 4, 0, 0..<4),  // Shift+Home selects to start
            (.end, 1, 5, 1..<5),  // Shift+End selects to end
        ])
    func shiftedMovementExtendsSelection(
        key: Key, startCursor: Int, expectedCursor: Int, expectedRange: Range<Int>
    ) {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: startCursor)

        let handled = handler.handleKeyEvent(KeyEvent(key: key, shift: true))

        #expect(handled == true)
        #expect(handler.selectionAnchor == startCursor)
        #expect(handler.cursorPosition == expectedCursor)
        #expect(handler.selectionRange == expectedRange)
    }

    @Test(
        "An unshifted movement key clears the selection and moves the cursor",
        arguments: [
            // (key, startCursor, expectedCursor) on "Hello" with anchor 1
            (Key.right, 3, 4),
            (.home, 3, 0),
            (.end, 2, 5),
            (.up, 3, 0),  // up moves to start
            (.down, 2, 5),  // down moves to end
        ])
    func unshiftedMovementClearsSelection(key: Key, startCursor: Int, expectedCursor: Int) {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: startCursor)
        handler.selectionAnchor = 1

        _ = handler.handleKeyEvent(KeyEvent(key: key))

        #expect(handler.selectionAnchor == nil)
        #expect(handler.hasSelection == false)
        #expect(handler.cursorPosition == expectedCursor)
    }

    @Test("Multiple Shift+Left extends selection progressively")
    func multipleShiftLeftExtendsProgressively() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 4)

        _ = handler.handleKeyEvent(KeyEvent(key: .left, shift: true))
        _ = handler.handleKeyEvent(KeyEvent(key: .left, shift: true))
        _ = handler.handleKeyEvent(KeyEvent(key: .left, shift: true))

        #expect(handler.selectionAnchor == 4)
        #expect(handler.cursorPosition == 1)
        #expect(handler.selectionRange == 1..<4)
    }

    @Test("Shift+Left at start does not move further")
    func shiftLeftAtStartDoesNotMoveFurther() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        _ = handler.handleKeyEvent(KeyEvent(key: .left, shift: true))

        #expect(handler.selectionAnchor == 0)
        #expect(handler.cursorPosition == 0)
        #expect(handler.hasSelection == false)  // Empty selection
    }

    @Test("Shift+Right at end does not move further")
    func shiftRightAtEndDoesNotMoveFurther() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)  // At end

        _ = handler.handleKeyEvent(KeyEvent(key: .right, shift: true))

        #expect(handler.selectionAnchor == 5)
        #expect(handler.cursorPosition == 5)
        #expect(handler.hasSelection == false)  // Empty selection
    }

    // MARK: - Selection Editing

    @Test("Backspace with selection deletes selected text")
    func backspaceWithSelectionDeletesSelectedText() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 8)
        handler.selectionAnchor = 2  // Select "llo Wo"

        _ = handler.handleKeyEvent(KeyEvent(key: .backspace))

        #expect(text == "Herld")
        #expect(handler.cursorPosition == 2)
        #expect(handler.hasSelection == false)
    }

    @Test("Delete with selection deletes selected text")
    func deleteWithSelectionDeletesSelectedText() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 5)
        handler.selectionAnchor = 0  // Select "Hello"

        _ = handler.handleKeyEvent(KeyEvent(key: .delete))

        #expect(text == " World")
        #expect(handler.cursorPosition == 0)
        #expect(handler.hasSelection == false)
    }

    @Test("Typing with selection replaces selected text")
    func typingWithSelectionReplacesSelectedText() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 5)
        handler.selectionAnchor = 0  // Select "Hello"

        _ = handler.handleKeyEvent(KeyEvent(key: .character("X")))

        #expect(text == "X World")
        #expect(handler.cursorPosition == 1)
        #expect(handler.hasSelection == false)
    }

    @Test("Typing multiple characters after selection replacement")
    func typingMultipleCharactersAfterSelectionReplacement() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 5)
        handler.selectionAnchor = 0  // Select "Hello"

        _ = handler.handleKeyEvent(KeyEvent(key: .character("A")))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("B")))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("C")))

        #expect(text == "ABC World")
        #expect(handler.cursorPosition == 3)
    }

    @Test("Select all and delete clears text")
    func selectAllAndDeleteClearsText() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 5)
        handler.selectionAnchor = 0  // Select all

        _ = handler.handleKeyEvent(KeyEvent(key: .backspace))

        #expect(text.isEmpty)
        #expect(handler.cursorPosition == 0)
    }

    @Test("Select all and type replaces all text")
    func selectAllAndTypeReplacesAllText() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 5)
        handler.selectionAnchor = 0  // Select all

        _ = handler.handleKeyEvent(KeyEvent(key: .character("X")))

        #expect(text == "X")
        #expect(handler.cursorPosition == 1)
    }

    // MARK: - Select All (Ctrl+A)

    @Test("Ctrl+A selects all text")
    func ctrlASelectsAllText() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 3)

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("a"), ctrl: true))

        #expect(handled == true)
        #expect(handler.selectionAnchor == 0)
        #expect(handler.cursorPosition == 11)
        #expect(handler.selectionRange == 0..<11)
    }

    @Test("Ctrl+A on empty text does nothing")
    func ctrlAOnEmptyTextDoesNothing() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("a"), ctrl: true))

        #expect(handled == true)
        #expect(handler.hasSelection == false)
    }

    // MARK: - Undo (Ctrl+Z)

    @Test("Ctrl+Z undoes character insertion")
    func ctrlZUndoesCharacterInsertion() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        // Insert a character
        _ = handler.handleKeyEvent(KeyEvent(key: .character("!")))
        #expect(text == "Hello!")

        // Undo
        let handled = handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(handled == true)
        #expect(text == "Hello")
    }

    @Test("Ctrl+Z undoes backspace")
    func ctrlZUndoesBackspace() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        // Delete last character
        _ = handler.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(text == "Hell")

        // Undo
        _ = handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(text == "Hello")
    }

    @Test("Ctrl+Z undoes selection deletion")
    func ctrlZUndoesSelectionDeletion() {
        var text = "Hello World"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 5)
        handler.selectionAnchor = 0  // Select "Hello"

        // Delete selection
        _ = handler.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(text == " World")

        // Undo
        _ = handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(text == "Hello World")
    }

    @Test("Multiple undos work correctly")
    func multipleUndosWorkCorrectly() {
        var text = "Hi"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        // Type "ABC"
        _ = handler.handleKeyEvent(KeyEvent(key: .character("A")))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("B")))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("C")))
        #expect(text == "HiABC")

        // Undo three times
        _ = handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(text == "HiAB")
        _ = handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(text == "HiA")
        _ = handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))
        #expect(text == "Hi")
    }

    @Test("Undo on empty stack does nothing")
    func undoOnEmptyStackDoesNothing() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        // Try to undo without any changes
        let handled = handler.handleKeyEvent(KeyEvent(key: .character("z"), ctrl: true))

        #expect(handled == true)
        #expect(text == "Hello")  // Unchanged
    }

    // MARK: - Copy/Cut/Paste Key Handling

    @Test("Ctrl+C is handled (copy)")
    func ctrlCIsHandled() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 3)
        handler.selectionAnchor = 0

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("c"), ctrl: true))

        #expect(handled == true)
        // Text should be unchanged (copy, not cut)
        #expect(text == "Hello")
        #expect(handler.hasSelection == true)  // Selection preserved
    }

    @Test("Ctrl+X is handled (cut)")
    func ctrlXIsHandled() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 3)
        handler.selectionAnchor = 0  // Select "Hel"

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("x"), ctrl: true))

        #expect(handled == true)
        #expect(text == "lo")  // "Hel" was cut
        #expect(handler.hasSelection == false)
    }

    @Test("Ctrl+V is handled (paste)")
    func ctrlVIsHandled() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 5)

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("v"), ctrl: true))

        #expect(handled == true)
        // Actual paste result depends on clipboard content
    }

    @Test("Ctrl+C without selection does nothing")
    func ctrlCWithoutSelectionDoesNothing() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 3)
        // No selection

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("c"), ctrl: true))

        #expect(handled == true)
        #expect(text == "Hello")  // Unchanged
    }

    @Test("Ctrl+X without selection does nothing")
    func ctrlXWithoutSelectionDoesNothing() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 3)
        // No selection

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("x"), ctrl: true))

        #expect(handled == true)
        #expect(text == "Hello")  // Unchanged
    }
}
