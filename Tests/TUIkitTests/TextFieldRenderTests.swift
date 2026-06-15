//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextFieldRenderTests.swift
//
//  Buffer-level rendering tests for TextField.
//  These assert the actual stripped output of TextField across the
//  states that matter visually: default, empty, prompt, focused vs
//  unfocused, disabled, narrow truncation, wide, and multi-field
//  composition.

import Testing

@testable import TUIkit

// MARK: - Helpers

/// The half-block caps that wrap the field content (U+2590 / U+258C).
private let openCap = "▐"
private let closeCap = "▌"
/// The default block cursor shape (U+2588), shown when a field is focused.
private let cursor = "█"

/// Builds a render context backed by a fresh `FocusManager`.
///
/// A fresh `FocusManager` matters: the manager auto-focuses the first
/// focusable that registers, so each test starts from a known focus state
/// instead of inheriting the process-wide default manager.
@MainActor
private func fieldContext(
    width: Int,
    focusManager: FocusManager,
    identityPath: String = ""
) -> RenderContext {
    var env = EnvironmentValues()
    env.focusManager = focusManager
    return RenderContext(
        availableWidth: width,
        availableHeight: 1,
        environment: env,
        tuiContext: TUIContext(),
        identity: ViewIdentity(path: identityPath)
    ).isolatingRenderCache()
}

/// Renders a view twice through the same context (the first pass registers
/// the focus handler; the second pass observes the resolved focus state) and
/// returns the stripped lines.
@MainActor
private func strippedLines(_ view: some View, context: RenderContext) -> [String] {
    _ = renderToBuffer(view, context: context)
    let buffer = renderToBuffer(view, context: context)
    return buffer.lines.map { $0.stripped }
}

// MARK: - Tests

@MainActor
@Suite("TextField rendering")
struct TextFieldRenderTests {

    // MARK: Focused (default first-field auto-focus)

    @Test("Focused field shows text followed by the block cursor")
    func focusedWithText() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 30, focusManager: fm)
        let lines = strippedLines(
            TextField("Name", text: .constant("hello")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        #expect(fm.currentFocusedID == "tf")  // first focusable auto-focuses
        let line = lines[0]
        #expect(line.count == 30)
        #expect(line.hasPrefix(openCap))
        #expect(line.hasSuffix(closeCap))
        // Content between the caps: "hello" + cursor + padding.
        let content = String(line.dropFirst().dropLast())
        #expect(content.hasPrefix("hello\(cursor)"))
        #expect(content.count == 28)
        // The remainder is padding spaces only.
        #expect(content.dropFirst("hello\(cursor)".count).allSatisfy { $0 == " " })
    }

    @Test("Focused empty field shows only the cursor")
    func focusedEmpty() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 30, focusManager: fm)
        let lines = strippedLines(
            TextField("Name", text: .constant("")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 30)
        #expect(line == "\(openCap)\(cursor)" + String(repeating: " ", count: 27) + closeCap)
    }

    // MARK: Unfocused

    @Test("Unfocused field with text shows the text, no cursor")
    func unfocusedWithText() {
        let fm = FocusManager()
        // A decoy field registers first and grabs the auto-focus, so the
        // field under test renders in its unfocused state.
        let decoyCtx = fieldContext(width: 30, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(TextField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 30, focusManager: fm, identityPath: "real")
        let lines = strippedLines(
            TextField("Name", text: .constant("hello")).focusID("tf"),
            context: ctx
        )

        #expect(fm.currentFocusedID == "decoy")  // not our field
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 30)
        // No cursor when unfocused.
        #expect(!line.contains(cursor))
        let content = String(line.dropFirst().dropLast())
        #expect(content.hasPrefix("hello"))
        #expect(content == "hello" + String(repeating: " ", count: 23))
    }

    @Test("Empty unfocused field with a prompt shows the prompt text")
    func unfocusedEmptyWithPrompt() {
        let fm = FocusManager()
        let decoyCtx = fieldContext(width: 30, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(TextField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 30, focusManager: fm, identityPath: "real")
        let lines = strippedLines(
            TextField("Email", text: .constant(""), prompt: Text("you@example.com")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 30)
        #expect(!line.contains(cursor))
        let content = String(line.dropFirst().dropLast())
        #expect(content == "you@example.com" + String(repeating: " ", count: 13))
    }

    @Test("Empty unfocused field without a prompt is blank between the caps")
    func unfocusedEmptyNoPrompt() {
        let fm = FocusManager()
        let decoyCtx = fieldContext(width: 30, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(TextField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 30, focusManager: fm, identityPath: "real")
        let lines = strippedLines(
            TextField("Email", text: .constant("")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        // Exactly: open cap, 28 spaces, close cap. No stray cursor, no gap.
        #expect(line == openCap + String(repeating: " ", count: 28) + closeCap)
    }

    // MARK: Empty label

    @Test("Empty label does not add a blank line or alter the field")
    func emptyLabel() {
        // The label is metadata for the field; it is never rendered inside
        // the field itself, so an empty label must not introduce a blank
        // line or change the single-line layout.
        let fm = FocusManager()
        let ctx = fieldContext(width: 20, focusManager: fm)
        let lines = strippedLines(
            TextField("", text: .constant("hi")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 20)
        #expect(line == "\(openCap)hi\(cursor)" + String(repeating: " ", count: 15) + closeCap)
    }

    // MARK: Disabled

    @Test("Disabled field renders its text but cannot take focus")
    func disabled() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 30, focusManager: fm)
        let lines = strippedLines(
            TextField("Name", text: .constant("hello")).disabled(),
            context: ctx
        )

        // Disabled views never register, so nothing is focused.
        #expect(fm.currentFocusedID == nil)
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 30)
        #expect(!line.contains(cursor))  // no cursor when unfocusable
        let content = String(line.dropFirst().dropLast())
        #expect(content == "hello" + String(repeating: " ", count: 23))
    }

    // MARK: Narrow width / truncation

    @Test("Unfocused narrow field clips overflowing text to the content width")
    func unfocusedNarrowTruncates() {
        let fm = FocusManager()
        let decoyCtx = fieldContext(width: 14, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(TextField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 14, focusManager: fm, identityPath: "real")
        let lines = strippedLines(
            TextField("N", text: .constant("abcdefghijklmnopqrstuvwxyz")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 14)
        // width 14 => content width 12; first 12 characters are shown.
        #expect(line == "\(openCap)abcdefghijkl\(closeCap)")
    }

    @Test("Focused narrow field scrolls to keep the cursor visible")
    func focusedNarrowScrolls() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 14, focusManager: fm)
        let lines = strippedLines(
            TextField("N", text: .constant("abcdefghijklmnopqrstuvwxyz")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 14)
        // Cursor sits at the end (position 26); the field scrolls so the
        // tail of the text plus the cursor are visible: "pqrstuvwxyz" + cursor.
        #expect(line == "\(openCap)pqrstuvwxyz\(cursor)\(closeCap)")
        #expect(line.hasSuffix("\(cursor)\(closeCap)"))
    }

    @Test("Narrow field at its minimum total width keeps both caps")
    func minimumWidthKeepsBothCaps() {
        // The field's minimum total width is minContentWidth (10) + 2 caps = 12.
        let fm = FocusManager()
        let ctx = fieldContext(width: 12, focusManager: fm)
        let lines = strippedLines(
            TextField("N", text: .constant("abcdefghijklmno")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 12)
        #expect(line.hasPrefix(openCap))
        #expect(line.hasSuffix(closeCap))
        // 10-wide content: 9 trailing chars + cursor.
        #expect(line == "\(openCap)ghijklmno\(cursor)\(closeCap)")
    }

    // MARK: Wide

    @Test("Wide field expands to fill the available width")
    func wide() {
        let fm = FocusManager()
        let decoyCtx = fieldContext(width: 50, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(TextField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 50, focusManager: fm, identityPath: "real")
        let lines = strippedLines(
            TextField("N", text: .constant("hi")).focusID("tf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 50)
        #expect(line == "\(openCap)hi" + String(repeating: " ", count: 46) + closeCap)
    }

    // MARK: Multi-field composition

    @Test("A VStack of fields renders one continuous line each, only first focused")
    func multipleFieldsInVStack() {
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        let ctx = RenderContext(
            availableWidth: 24,
            availableHeight: 5,
            environment: env,
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        let view = VStack {
            TextField("A", text: .constant("one")).focusID("a")
            TextField("B", text: .constant("two")).focusID("b")
            TextField("C", text: .constant("three")).focusID("c")
        }

        _ = renderToBuffer(view, context: ctx)
        let buffer = renderToBuffer(view, context: ctx)
        let lines = buffer.lines.map { $0.stripped }

        #expect(lines.count == 3)
        // Every line is a full-width, cap-wrapped field with no blank lines.
        for line in lines {
            #expect(line.count == 24)
            #expect(line.hasPrefix(openCap))
            #expect(line.hasSuffix(closeCap))
        }
        // Only the first field is focused, so only line 0 shows a cursor.
        #expect(fm.currentFocusedID == "a")
        #expect(lines[0].contains(cursor))
        #expect(!lines[1].contains(cursor))
        #expect(!lines[2].contains(cursor))
        #expect(lines[0] == "\(openCap)one\(cursor)" + String(repeating: " ", count: 18) + closeCap)
        #expect(lines[1] == "\(openCap)two" + String(repeating: " ", count: 19) + closeCap)
        #expect(lines[2] == "\(openCap)three" + String(repeating: " ", count: 17) + closeCap)
    }
}
