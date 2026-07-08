//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextInputStormTests.swift
//
//  Deterministic pseudo-random edit storms over the text-input handlers,
//  checking structural invariants after every step: cursor in bounds,
//  selection normalized and inside the document, text binding consistent.
//  These storms found (and now pin the fixes for) the stale-selection-anchor
//  class of bug: a collapsed anchor surviving a mutation became a phantom
//  selection whose indices lay outside the shrunken text — an
//  out-of-bounds String index crash in TextFieldHandler, and
//  never-user-selected text replacement in TextEditorHandler.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Text input edit storms", .serialized)
struct TextInputStormTests {
    /// Applies a deterministic pseudo-random storm of edit operations and
    /// checks the handler's invariants after every step: cursor in bounds,
    /// selection normalized, text binding consistent.
    @Test("Random edit storms keep the handler's invariants")
    func editStorm() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(max(1, bound)))
        }

        let keys: [KeyEvent] = [
            KeyEvent(key: .up), KeyEvent(key: .down),
            KeyEvent(key: .left), KeyEvent(key: .right),
            KeyEvent(key: .home), KeyEvent(key: .end),
            KeyEvent(key: .backspace), KeyEvent(key: .delete),
            KeyEvent(key: .enter),
            KeyEvent(key: .up, shift: true), KeyEvent(key: .down, shift: true),
            KeyEvent(key: .left, shift: true), KeyEvent(key: .right, shift: true),
            KeyEvent(character: "x"), KeyEvent(character: "é"), KeyEvent(character: "你"),
            KeyEvent(character: "🎉"), KeyEvent(character: " "),
        ]

        var violations: [String] = []
        for trial in 0..<30 {
            var text = trial.isMultiple(of: 3) ? "" : "alpha\nbravo 你好\ncharlie 🎉 delta\n\necho"
            let binding = Binding(get: { text }, set: { text = $0 })
            let handler = TextEditorHandler(focusID: "fuzz", text: binding)
            handler.viewportHeight = 4

            for step in 0..<400 {
                let key = keys[rand(keys.count)]
                _ = handler.handleKeyEvent(key)

                // Occasionally click somewhere (possibly out of bounds).
                if step.isMultiple(of: 37) {
                    handler.moveCursor(toLine: rand(10) - 2, column: rand(30) - 5)
                    if rand(2) == 0 { handler.clearSelection() } else { handler.startOrExtendSelection() }
                }

                let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
                if handler.cursorLine < 0 || handler.cursorLine >= lines.count {
                    violations.append("trial \(trial) step \(step): cursorLine \(handler.cursorLine) outside 0..<\(lines.count) after \(key)")
                    break
                }
                let lineLength = lines[handler.cursorLine].count
                if handler.cursorColumn < 0 || handler.cursorColumn > lineLength {
                    violations.append(
                        "trial \(trial) step \(step): cursorColumn \(handler.cursorColumn) "
                            + "outside 0...\(lineLength) in '\(lines[handler.cursorLine])' after \(key)")
                    break
                }
                if let span = handler.selectionRange {
                    if span.start > span.end {
                        violations.append("trial \(trial) step \(step): unnormalized selection \(span)")
                        break
                    }
                    if span.end.line >= lines.count || span.start.line < 0 {
                        violations.append("trial \(trial) step \(step): selection lines out of bounds \(span) for \(lines.count) lines")
                        break
                    }
                }
            }
        }

        if !violations.isEmpty {
            print("=== EDITOR VIOLATIONS (\(violations.count)) ===")
            for violation in violations.prefix(10) { print(violation) }
        }
        #expect(violations.isEmpty)
    }

    @Test("TextFieldHandler survives the same storm")
    func fieldStorm() {
        var seed: UInt64 = 0xDEADBEEFCAFEF00D
        func rand(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(max(1, bound)))
        }

        let keys: [KeyEvent] = [
            KeyEvent(key: .left), KeyEvent(key: .right),
            KeyEvent(key: .home), KeyEvent(key: .end),
            KeyEvent(key: .backspace), KeyEvent(key: .delete),
            KeyEvent(key: .left, shift: true), KeyEvent(key: .right, shift: true),
            KeyEvent(character: "x"), KeyEvent(character: "你"), KeyEvent(character: "🎉"),
        ]

        var violations: [String] = []
        for trial in 0..<30 {
            var text = trial.isMultiple(of: 3) ? "" : "hello 你好 🎉 world"
            let binding = Binding(get: { text }, set: { text = $0 })
            let handler = TextFieldHandler(focusID: "fuzz", text: binding)

            for step in 0..<300 {
                let key = keys[rand(keys.count)]
                _ = handler.handleKeyEvent(key)

                if handler.cursorPosition < 0 || handler.cursorPosition > text.count {
                    violations.append("trial \(trial) step \(step): cursor \(handler.cursorPosition) outside 0...\(text.count) after \(key)")
                    break
                }
            }
        }

        if !violations.isEmpty {
            print("=== FIELD VIOLATIONS (\(violations.count)) ===")
            for violation in violations.prefix(10) { print(violation) }
        }
        #expect(violations.isEmpty)
    }
}

// MARK: - Minimized regressions

/// The exact minimized sequences the storms first crashed on, plus the
/// external-binding staleness the same normalization guards against.
@MainActor
@Suite("Stale selection anchors (minimized)")
struct StaleSelectionAnchorTests {
    @Test("Field: shift+arrow at end, backspace, delete must not crash")
    func fieldPhantomSelectionAfterBackspace() {
        var text = "ab"
        let handler = TextFieldHandler(focusID: "t", text: Binding(get: { text }, set: { text = $0 }))
        // Cursor starts at the end (2). Shift+Right cannot move, but anchors.
        _ = handler.handleKeyEvent(KeyEvent(key: .right, shift: true))
        // Backspace deletes 'b'; the anchor at 2 is now past the end.
        _ = handler.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(text == "a")
        // Delete used to treat (cursor 1, stale anchor 2) as a selection and
        // index character 2 of a 1-character string: a fatal crash.
        _ = handler.handleKeyEvent(KeyEvent(key: .delete))
        #expect(text == "a", "nothing right of the cursor to delete")
    }

    @Test("Field: a shrunken binding invalidates cursor and anchor safely")
    func fieldExternalShrink() {
        var text = "a long piece of text"
        let handler = TextFieldHandler(focusID: "t", text: Binding(get: { text }, set: { text = $0 }))
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        _ = handler.handleKeyEvent(KeyEvent(key: .left, shift: true))
        // The app replaces the text underneath the handler.
        text = "hi"
        _ = handler.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(text == "h", "cursor re-clamped to the new end; stale anchor dropped")
    }

    @Test("Editor: an anchor on a merged-away line is dropped, not phantom-selected")
    func editorPhantomSelectionAfterLineMerge() {
        var text = "alpha\nb"
        let handler = TextEditorHandler(focusID: "t", text: Binding(get: { text }, set: { text = $0 }))
        // Cursor to the start of line 1, then shift+left anchors at (1, 0)…
        handler.moveCursor(toLine: 1, column: 0)
        _ = handler.handleKeyEvent(KeyEvent(key: .left, shift: true))
        // …which selects the line break; consume the selection with backspace
        // (merging the lines), then anchor again where no motion is possible.
        _ = handler.handleKeyEvent(KeyEvent(key: .backspace))
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        _ = handler.handleKeyEvent(KeyEvent(key: .right, shift: true))  // collapsed anchor at end
        _ = handler.handleKeyEvent(KeyEvent(key: .backspace))           // text shrinks under it
        let before = text
        // The next key must not treat the stale anchor as a selection.
        _ = handler.handleKeyEvent(KeyEvent(character: "z"))
        #expect(text == before + "z", "typed character inserts; no phantom selection was replaced")
    }

    @Test("Editor: a shrunken binding drops an out-of-document anchor at render")
    func editorExternalShrinkAtRender() {
        var text = "one\ntwo\nthree"
        let handler = TextEditorHandler(focusID: "t", text: Binding(get: { text }, set: { text = $0 }))
        handler.moveCursor(toLine: 2, column: 3)
        handler.startOrExtendSelection()
        handler.moveCursor(toLine: 2, column: 0)
        #expect(handler.selectionRange != nil)
        // The app replaces the text with a single line; the anchor's line is gone.
        text = "x"
        handler.clampCursor()
        #expect(handler.selectionRange == nil, "an anchor outside the document is dropped, not clamped")
        _ = handler.handleKeyEvent(KeyEvent(character: "y"))
        #expect(text.contains("y") && text.contains("x"), "the edit inserts rather than replacing a phantom span")
    }
}
