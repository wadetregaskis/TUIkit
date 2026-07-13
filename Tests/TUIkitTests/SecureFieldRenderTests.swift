//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SecureFieldRenderTests.swift
//
//  Buffer-level rendering tests for SecureField.
//  SecureField shares TextField's content renderer but masks every
//  character with a bullet (●). These assert the masked output across the
//  states that matter visually: default, empty, prompt, focused vs
//  unfocused, disabled, narrow truncation, wide, and multi-field
//  composition.

import Testing

@testable import TUIkit

// MARK: - Helpers

/// The half-block caps that wrap the field content (U+2590 / U+258C).
private let openCap = "▐"
private let closeCap = "▌"
/// The mask character SecureField substitutes for every input character (U+25CF).
private let bullet = "●"

/// Whether `rawLine` paints any cell on the palette's caret colour.
///
/// The block caret inverts its cell (character on a caret-coloured
/// background) rather than stamping a `█` glyph, so in raw output the caret
/// is a background-colour run, not a character.
@MainActor
private func hasCaretCell(_ rawLine: String) -> Bool {
    let fragment = ANSIRenderer.backgroundCodes(for: EnvironmentValues().palette.cursorColor)
        .joined(separator: ";") + "m"
    return rawLine.contains(fragment)
}

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

@MainActor
private func rawLines(_ view: some View, context: RenderContext) -> [String] {
    _ = renderToBuffer(view, context: context)
    return renderToBuffer(view, context: context).lines
}

@MainActor
private func strippedLines(_ view: some View, context: RenderContext) -> [String] {
    rawLines(view, context: context).map { $0.stripped }
}

// MARK: - Tests

@MainActor
@Suite("SecureField rendering")
struct SecureFieldRenderTests {

    // MARK: Focused

    @Test("Focused field masks text with bullets followed by the cursor")
    func focusedWithText() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 30, focusManager: fm)
        let raw = rawLines(
            SecureField("Password", text: .constant("secret")).focusID("sf"),
            context: ctx
        )

        #expect(raw.count == 1)
        #expect(fm.currentFocusedID == "sf")
        let line = raw[0].stripped
        #expect(line.count == 30)
        #expect(line.hasPrefix(openCap))
        #expect(line.hasSuffix(closeCap))
        // The plaintext must never appear; "secret" -> six bullets, then the
        // caret cell (an inverted space, invisible when stripped).
        #expect(!line.contains("secret"))
        let content = String(line.dropFirst().dropLast())
        #expect(content == String(repeating: bullet, count: 6) + String(repeating: " ", count: 22))
        #expect(hasCaretCell(raw[0]))
    }

    @Test("Focused empty field shows only the cursor")
    func focusedEmpty() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 30, focusManager: fm)
        let raw = rawLines(
            SecureField("Password", text: .constant("")).focusID("sf"),
            context: ctx
        )

        #expect(raw.count == 1)
        let line = raw[0].stripped
        #expect(line.count == 30)
        #expect(!line.contains(bullet))
        #expect(line == openCap + String(repeating: " ", count: 28) + closeCap)
        #expect(hasCaretCell(raw[0]))
    }

    // MARK: Unfocused

    @Test("Unfocused field with text shows bullets, no cursor and no plaintext")
    func unfocusedWithText() {
        let fm = FocusManager()
        let decoyCtx = fieldContext(width: 30, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(SecureField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 30, focusManager: fm, identityPath: "real")
        let raw = rawLines(
            SecureField("Password", text: .constant("secret")).focusID("sf"),
            context: ctx
        )

        #expect(fm.currentFocusedID == "decoy")
        #expect(raw.count == 1)
        let line = raw[0].stripped
        #expect(line.count == 30)
        #expect(!hasCaretCell(raw[0]))  // no caret when unfocused
        #expect(!line.contains("secret"))
        let content = String(line.dropFirst().dropLast())
        #expect(content == String(repeating: bullet, count: 6) + String(repeating: " ", count: 22))
    }

    @Test("Empty unfocused field with a prompt shows the prompt text")
    func unfocusedEmptyWithPrompt() {
        let fm = FocusManager()
        let decoyCtx = fieldContext(width: 30, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(SecureField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 30, focusManager: fm, identityPath: "real")
        let lines = strippedLines(
            SecureField("Password", text: .constant(""), prompt: Text("Required")).focusID("sf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 30)
        #expect(!line.contains(bullet))  // empty field has nothing to mask
        let content = String(line.dropFirst().dropLast())
        #expect(content == "Required" + String(repeating: " ", count: 20))
    }

    // MARK: Empty label

    @Test("Empty label does not add a blank line or alter the field")
    func emptyLabel() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 20, focusManager: fm)
        let lines = strippedLines(
            SecureField("", text: .constant("pw")).focusID("sf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 20)
        #expect(line == "\(openCap)\(bullet)\(bullet)" + String(repeating: " ", count: 16) + closeCap)
    }

    // MARK: Disabled

    @Test("Disabled field masks its text but cannot take focus")
    func disabled() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 30, focusManager: fm)
        let lines = strippedLines(
            SecureField("Password", text: .constant("pw")).disabled(),
            context: ctx
        )

        #expect(fm.currentFocusedID == nil)
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 30)
        #expect(!line.contains("pw"))
        let content = String(line.dropFirst().dropLast())
        #expect(content == String(repeating: bullet, count: 2) + String(repeating: " ", count: 26))
    }

    // MARK: Narrow width / truncation

    @Test("Focused narrow field scrolls bullets to keep the cursor visible")
    func focusedNarrowScrolls() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 14, focusManager: fm)
        let lines = strippedLines(
            SecureField("P", text: .constant("abcdefghijklmnop")).focusID("sf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 14)
        #expect(!line.contains("abc"))  // never reveal plaintext
        // 16 bullets scroll so the tail + the caret cell are visible:
        // 11 bullets + the caret (an inverted space).
        #expect(line == openCap + String(repeating: bullet, count: 11) + " " + closeCap)
    }

    @Test("Unfocused narrow field clips bullets to the content width")
    func unfocusedNarrowTruncates() {
        let fm = FocusManager()
        let decoyCtx = fieldContext(width: 14, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(SecureField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 14, focusManager: fm, identityPath: "real")
        let lines = strippedLines(
            SecureField("P", text: .constant("abcdefghijklmnop")).focusID("sf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 14)
        // width 14 => content width 12; first 12 bullets shown, no cursor.
        #expect(line == openCap + String(repeating: bullet, count: 12) + closeCap)
    }

    // MARK: Wide

    @Test("Wide field expands to fill the available width")
    func wide() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 50, focusManager: fm)
        let lines = strippedLines(
            SecureField("P", text: .constant("pw")).focusID("sf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 50)
        // Focused: two bullets + the caret cell (an inverted space) + padding.
        #expect(line == openCap + String(repeating: bullet, count: 2) + String(repeating: " ", count: 46) + closeCap)
    }

    // MARK: Multi-field composition

    @Test("A VStack of secure fields renders one continuous line each, only first focused")
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
            SecureField("A", text: .constant("aa")).focusID("a")
            SecureField("B", text: .constant("bbb")).focusID("b")
        }

        _ = renderToBuffer(view, context: ctx)
        let buffer = renderToBuffer(view, context: ctx)
        let lines = buffer.lines.map { $0.stripped }

        #expect(lines.count == 2)
        for line in lines {
            #expect(line.count == 24)
            #expect(line.hasPrefix(openCap))
            #expect(line.hasSuffix(closeCap))
        }
        #expect(fm.currentFocusedID == "a")
        #expect(hasCaretCell(buffer.lines[0]))
        #expect(!hasCaretCell(buffer.lines[1]))
        #expect(lines[0] == openCap + String(repeating: bullet, count: 2) + String(repeating: " ", count: 20) + closeCap)
        #expect(lines[1] == openCap + String(repeating: bullet, count: 3) + String(repeating: " ", count: 19) + closeCap)
    }
}
