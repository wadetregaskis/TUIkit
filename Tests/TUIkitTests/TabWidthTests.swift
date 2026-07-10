//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabWidthTests.swift
//
//  Literal-tab layout in TextEditor: tabs advance to configurable stops
//  (periodic column snapping by default, like the macOS text system /
//  terminals / code editors; or a constant advance), and the caret,
//  selection, vertical motion and click mapping all agree with the
//  rendered expansion.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Layout arithmetic

@Suite("TabLayout arithmetic")
struct TabLayoutTests {

    @Test("Periodic tabs snap to the next multiple of the interval")
    func periodicSnapping() {
        let line = Array("ab\tX")
        // Tab starts at column 2 → next multiple of 4 is 4 → X at column 4.
        #expect(TabLayout.displayColumn(ofCharIndex: 3, in: line, tabWidth: .periodic(4)) == 4)
        #expect(String(TabLayout.expand(line, tabWidth: .periodic(4))) == "ab  X")
    }

    @Test("A tab starting exactly on a stop advances a full interval")
    func tabOnStopAdvancesFullInterval() {
        let line = Array("abcd\tX")
        // Tab starts at column 4 (a stop) → advances to 8, not 4.
        #expect(TabLayout.displayColumn(ofCharIndex: 5, in: line, tabWidth: .periodic(4)) == 8)
        #expect(String(TabLayout.expand(line, tabWidth: .periodic(4))) == "abcd    X")
    }

    @Test("Fixed tabs always advance the same number of cells")
    func fixedAdvance() {
        let line = Array("ab\tX\tY")
        // ab(2) + tab(2) → X at 4; X(1) + tab(2) → Y at 7.
        #expect(TabLayout.displayColumn(ofCharIndex: 3, in: line, tabWidth: .fixed(2)) == 4)
        #expect(TabLayout.displayColumn(ofCharIndex: 5, in: line, tabWidth: .fixed(2)) == 7)
        #expect(String(TabLayout.expand(line, tabWidth: .fixed(2))) == "ab  X  Y")
    }

    @Test("Any display column within a tab's span maps to the tab character")
    func clickWithinTabSpanHitsTheTab() {
        let line = Array("a\tX")  // a=col 0, tab spans 1..<4, X at 4
        for column in 1...3 {
            #expect(
                TabLayout.charIndex(forDisplayColumn: column, in: line, tabWidth: .periodic(4)) == 1,
                "column \(column) is inside the tab")
        }
        #expect(TabLayout.charIndex(forDisplayColumn: 4, in: line, tabWidth: .periodic(4)) == 2)
        // Past the end → end-of-line insertion point.
        #expect(TabLayout.charIndex(forDisplayColumn: 99, in: line, tabWidth: .periodic(4)) == 3)
    }

    @Test("Tab-free lines are the identity (fast path)")
    func tabFreeIdentity() {
        let line = Array("hello")
        #expect(TabLayout.displayColumn(ofCharIndex: 3, in: line, tabWidth: .periodic(4)) == 3)
        #expect(TabLayout.charIndex(forDisplayColumn: 3, in: line, tabWidth: .periodic(4)) == 3)
        #expect(TabLayout.expand(line, tabWidth: .periodic(4)) == line)
    }

    @Test("Degenerate widths are clamped to at least one cell")
    func degenerateWidthClamped() {
        #expect(TabWidth.periodic(0).advance(from: 5) == 6)
        #expect(TabWidth.fixed(0).advance(from: 5) == 6)
    }
}

// MARK: - Editor integration

@MainActor
@Suite("TextEditor tab rendering")
struct TextEditorTabTests {

    /// Renders an editor over `text` and returns the visible lines, stripped.
    private func render(
        _ text: String, width: Int = 24, height: Int = 3,
        tabWidth: TabWidth? = nil
    ) -> [String] {
        let editor = TextEditor(text: .constant(text))
        let view: AnyView = tabWidth.map { AnyView(editor.tabWidth($0)) } ?? AnyView(editor)
        let buffer = renderToBuffer(
            view.frame(height: height),
            context: makeRenderContext(width: width, height: height + 2))
        return buffer.lines.map(\.stripped)
    }

    @Test("Tabs render to the default 4-column stops")
    func defaultPeriodicFour() {
        let lines = render("a\tb\nno tabs")
        // a at 0, tab spans to 4 → b at column 4.
        #expect(lines[0].hasPrefix("a   b"), "expected 'a   b…', got '\(lines[0])'")
    }

    @Test(".tabWidth(.periodic(8)) uses 8-column stops")
    func periodicEight() {
        let lines = render("a\tb", tabWidth: .periodic(8))
        #expect(lines[0].hasPrefix("a       b"), "expected 'a       b…', got '\(lines[0])'")
    }

    @Test(".tabWidth(.fixed(2)) always advances two cells")
    func fixedTwo() {
        let lines = render("a\tb", tabWidth: .fixed(2))
        #expect(lines[0].hasPrefix("a  b"), "expected 'a  b…', got '\(lines[0])'")
    }

    @Test("Vertical motion preserves the VISUAL column across a tab line")
    func verticalMotionPreservesVisualColumn() {
        // Line 0: "\tX"     → X at display column 4.
        // Line 1: "abcdefg" → plain characters.
        var text = "\tX\nabcdefg"
        let handler = TextEditorHandler(
            focusID: "t", text: Binding(get: { text }, set: { text = $0 }))
        handler.tabWidth = .periodic(4)

        // Place the cursor on the X (char 1, display column 4).
        handler.moveCursor(toLine: 0, column: 1)
        // Down: the caret should land at display column 4 of the plain line —
        // character 'e' (index 4) — not at character index 1 ('b').
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.cursorLine == 1)
        #expect(handler.cursorColumn == 4, "visual column preserved through the tab")

        // And back up: display column 4 on the tab line is within the tab's
        // span... the stop itself is X. Column 4 == X's cell → char index 1.
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.cursorLine == 0)
        #expect(handler.cursorColumn == 1, "returns to the X, not mid-tab")
    }

    @Test("Option-Tab inserts a tab that renders at the next stop")
    func optionTabInsertsRealTab() {
        var text = "ab"
        let handler = TextEditorHandler(
            focusID: "t", text: Binding(get: { text }, set: { text = $0 }))
        handler.tabWidth = .periodic(4)
        handler.moveCursor(toLine: 0, column: 2)
        _ = handler.handleKeyEvent(KeyEvent(key: .tab, alt: true))
        #expect(text == "ab\t")
        // The inserted tab occupies display columns 2..<4.
        let lines = render(text)
        #expect(lines[0].hasPrefix("ab  "), "tab expanded to the stop: '\(lines[0])'")
    }
}
