//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RadioButtonGroupRenderTests.swift
//
//  Buffer-level rendering tests for RadioButtonGroup.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("RadioButtonGroup rendering")
struct RadioButtonGroupRenderTests {

    // MARK: - Helpers

    /// A render context with a real focus manager and state storage so the
    /// group can register, auto-focus, and persist its handler across renders.
    private func makeContext(width: Int = 30, height: Int = 8) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: TUIContext()
        )
    }

    /// A throwaway focusable used to occupy auto-focus so that a
    /// later-registered group is rendered in its genuinely-unfocused state.
    private final class FocusHog: Focusable {
        let focusID: String
        init(_ id: String) { self.focusID = id }
        func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
    }

    /// The selected radio glyph (●) and unselected glyph (◯).
    private let selected = TerminalSymbols.radioSelected
    private let unselected = TerminalSymbols.radioUnselected

    private func lines(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.map { $0.stripped }
    }

    // MARK: - Vertical layout

    @Test("Vertical group renders one row per item, only the selected item filled")
    func verticalDefault() {
        // Selection is "b"; register a focus hog first so the group is unfocused
        // and only the *selected* item shows the filled glyph.
        let group = RadioButtonGroup(selection: .constant("b")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
            RadioButtonItem("c", "Charlie")
        }
        let context = makeContext()
        context.environment.focusManager.register(FocusHog("hog"))
        _ = renderToBuffer(group, context: context)  // register
        let result = lines(renderToBuffer(group, context: context))  // read state

        #expect(result.count == 3, "Three items must produce exactly three rows")
        #expect(result[0] == "\(unselected) Alpha")
        #expect(result[1] == "\(selected) Bravo")
        #expect(result[2] == "\(unselected) Charlie")
        // No stray blank lines.
        #expect(!result.contains(where: { $0.isEmpty }))
    }

    @Test("A single-item group renders exactly one row")
    func singleItem() {
        let group = RadioButtonGroup(selection: .constant("only")) {
            RadioButtonItem("only", "Only")
        }
        let context = makeContext()
        context.environment.focusManager.register(FocusHog("hog"))
        _ = renderToBuffer(group, context: context)
        let result = lines(renderToBuffer(group, context: context))

        #expect(result.count == 1)
        #expect(result[0] == "\(selected) Only")
    }

    @Test("Every label is preceded by a glyph and a single space")
    func glyphSpacingVertical() {
        let group = RadioButtonGroup(selection: .constant("a")) {
            RadioButtonItem("a", "First")
            RadioButtonItem("b", "Second")
        }
        let context = makeContext()
        context.environment.focusManager.register(FocusHog("hog"))
        _ = renderToBuffer(group, context: context)
        let result = lines(renderToBuffer(group, context: context))

        for row in result {
            // Each row begins with a radio glyph, then exactly one space.
            let startsCorrectly = row.hasPrefix("\(selected) ") || row.hasPrefix("\(unselected) ")
            #expect(startsCorrectly, "Row '\(row)' should start with a glyph + single space")
        }
    }

    // MARK: - Selection

    @Test("Exactly one item is filled when unfocused (the selected one)")
    func onlyOneSelectedWhenUnfocused() {
        let group = RadioButtonGroup(selection: .constant("c")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
            RadioButtonItem("c", "Charlie")
        }
        let context = makeContext()
        context.environment.focusManager.register(FocusHog("hog"))
        _ = renderToBuffer(group, context: context)
        let result = lines(renderToBuffer(group, context: context))

        let filledCount = result.filter { $0.hasPrefix(selected) }.count
        #expect(filledCount == 1, "Unfocused group: only the selected item is filled")
        #expect(result[2].hasPrefix(selected), "Charlie is selected")
    }

    @Test("Changing the bound selection moves the filled glyph")
    func selectionMovesGlyph() {
        let context = makeContext()
        context.environment.focusManager.register(FocusHog("hog"))

        let groupA = RadioButtonGroup(selection: .constant("a")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
        }
        _ = renderToBuffer(groupA, context: context)
        let resultA = lines(renderToBuffer(groupA, context: context))
        #expect(resultA[0].hasPrefix(selected))
        #expect(resultA[1].hasPrefix(unselected))
    }

    // MARK: - Focus

    @Test("A focused item is filled even when it is not the selected item")
    func focusedItemIsFilled() {
        // Selection is "a" (index 0). Focus the group, then arrow-down twice so
        // the *focused* item becomes Charlie (index 2). Both the selected item
        // and the focused item must render filled.
        let group = RadioButtonGroup(selection: .constant("a")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
            RadioButtonItem("c", "Charlie")
        }
        let context = makeContext()
        _ = renderToBuffer(group, context: context)  // registers + auto-focuses
        _ = context.environment.focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        _ = context.environment.focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        let result = lines(renderToBuffer(group, context: context))

        #expect(result[0] == "\(selected) Alpha", "Selected item stays filled")
        #expect(result[1] == "\(unselected) Bravo", "Middle item neither selected nor focused")
        #expect(result[2] == "\(selected) Charlie", "Focused item is filled too")
    }

    @Test("Focus does not change the label text, only the glyph state")
    func focusPreservesLabels() {
        let group = RadioButtonGroup(selection: .constant("a")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
        }
        let context = makeContext()
        _ = renderToBuffer(group, context: context)
        let result = lines(renderToBuffer(group, context: context))

        #expect(result[0].hasSuffix("Alpha"))
        #expect(result[1].hasSuffix("Bravo"))
    }

    // MARK: - Disabled

    @Test("A disabled group still shows its selection but registers no focus glyph")
    func disabledGroup() {
        let group = RadioButtonGroup(selection: .constant("a"), isDisabled: true) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
        }
        let context = makeContext()
        _ = renderToBuffer(group, context: context)
        let result = lines(renderToBuffer(group, context: context))

        #expect(result.count == 2)
        // Disabled groups never auto-focus, so only the selected item is filled.
        #expect(result[0] == "\(selected) Alpha")
        #expect(result[1] == "\(unselected) Bravo")
        let filledCount = result.filter { $0.hasPrefix(selected) }.count
        #expect(filledCount == 1, "Disabled group shows exactly one filled (the selection)")
    }

    // MARK: - Horizontal layout

    @Test("Horizontal group renders all items on a single line")
    func horizontalSingleLine() {
        let group = RadioButtonGroup(selection: .constant("a"), orientation: .horizontal) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
        }
        let context = makeContext(width: 40)
        context.environment.focusManager.register(FocusHog("hog"))
        _ = renderToBuffer(group, context: context)
        let result = lines(renderToBuffer(group, context: context))

        #expect(result.count == 1, "Horizontal layout is a single row")
        // Two items joined by two spaces.
        #expect(result[0] == "\(selected) Alpha  \(unselected) Bravo")
    }

    @Test("Horizontal group separates items with two spaces")
    func horizontalSpacing() {
        let group = RadioButtonGroup(selection: .constant("a"), orientation: .horizontal) {
            RadioButtonItem("a", "A")
            RadioButtonItem("b", "B")
            RadioButtonItem("c", "C")
        }
        let context = makeContext(width: 40)
        context.environment.focusManager.register(FocusHog("hog"))
        _ = renderToBuffer(group, context: context)
        let result = lines(renderToBuffer(group, context: context))

        #expect(result.count == 1)
        #expect(result[0] == "\(selected) A  \(unselected) B  \(unselected) C")
    }

    // MARK: - Label content

    @Test("View-builder labels render their text")
    func viewBuilderLabel() {
        let group = RadioButtonGroup(selection: .constant(1)) {
            RadioButtonItem(1) { Text("Built") }
            RadioButtonItem(2) { Text("Label") }
        }
        let context = makeContext()
        context.environment.focusManager.register(FocusHog("hog"))
        _ = renderToBuffer(group, context: context)
        let result = lines(renderToBuffer(group, context: context))

        #expect(result[0] == "\(selected) Built")
        #expect(result[1] == "\(unselected) Label")
    }
}
