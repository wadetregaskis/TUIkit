//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WordBoundaryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Word-wise motion")
struct WordBoundaryTests {

    private func characters(_ text: String) -> [Character] { Array(text) }

    @Test("An underscore is part of a word, not a break in one")
    func underscoreIsAWordCharacter() {
        // The whole reason this type exists: a TextField said yes and a
        // TextEditor said no, so the same Option-Left landed in two places.
        let line = characters("foo_bar baz")
        #expect(WordBoundary.previous(in: line, from: 7) == 0, "stopped inside foo_bar")
        #expect(WordBoundary.next(in: line, from: 0) == 7)
    }

    @Test("Motion skips the separator run, then the word run")
    func skipsSeparatorsThenWord() {
        let line = characters("one   two")
        #expect(WordBoundary.next(in: line, from: 3) == 9, "should land past `two`")
        #expect(WordBoundary.previous(in: line, from: 9) == 6, "should land at `two`'s start")
    }

    @Test("Repeating the motion walks a word at a time")
    func repeatedMotionWalks() {
        let line = characters("alpha beta gamma")
        var position = line.count
        var stops: [Int] = []
        for _ in 0..<3 {
            position = WordBoundary.previous(in: line, from: position)
            stops.append(position)
        }
        #expect(stops == [11, 6, 0], "stops: \(stops)")
    }

    @Test("The ends of the text are fixed points")
    func endsAreStable() {
        let line = characters("word")
        #expect(WordBoundary.previous(in: line, from: 0) == 0)
        #expect(WordBoundary.next(in: line, from: line.count) == line.count)
        #expect(WordBoundary.previous(in: [], from: 0) == 0)
        #expect(WordBoundary.next(in: [], from: 0) == 0)
    }

    @Test("An index past the end is clamped rather than trapping")
    func outOfRangeIsClamped() {
        let line = characters("abc")
        #expect(WordBoundary.previous(in: line, from: 99) == 0)
        #expect(WordBoundary.next(in: line, from: -5) == 3)
    }

    @Test("The two text controls now agree, character for character")
    func fieldAndEditorAgree() {
        // Driven through the real handlers, because agreeing in the helper and
        // disagreeing in the callers is exactly what happened before.
        let text = "let some_value = other_value"
        let fieldSink = Sink(text)
        let field = TextFieldHandler(focusID: "f", text: fieldSink.binding)
        let editorSink = Sink(text)
        let editor = TextEditorHandler(focusID: "e", text: editorSink.binding)

        field.cursorPosition = text.count
        editor.cursorLine = 0
        editor.cursorColumn = text.count

        var fieldStops: [Int] = []
        var editorStops: [Int] = []
        for _ in 0..<4 {
            _ = field.handleKeyEvent(KeyEvent(key: .left, alt: true))
            _ = editor.handleKeyEvent(KeyEvent(key: .left, alt: true))
            fieldStops.append(field.cursorPosition)
            editorStops.append(editor.cursorColumn)
        }
        #expect(fieldStops == editorStops, "field \(fieldStops) vs editor \(editorStops)")
        withExtendedLifetime((fieldSink, editorSink)) {}
    }

    private final class Sink: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
        var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }
}
