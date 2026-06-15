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
/// The default block cursor shape (U+2588), shown when focused.
private let cursor = "█"
/// The mask character SecureField substitutes for every input character (U+25CF).
private let bullet = "●"

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
private func strippedLines(_ view: some View, context: RenderContext) -> [String] {
    _ = renderToBuffer(view, context: context)
    let buffer = renderToBuffer(view, context: context)
    return buffer.lines.map { $0.stripped }
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
        let lines = strippedLines(
            SecureField("Password", text: .constant("secret")).focusID("sf"),
            context: ctx
        )

        #expect(lines.count == 1)
        #expect(fm.currentFocusedID == "sf")
        let line = lines[0]
        #expect(line.count == 30)
        #expect(line.hasPrefix(openCap))
        #expect(line.hasSuffix(closeCap))
        // The plaintext must never appear; "secret" -> six bullets + cursor.
        #expect(!line.contains("secret"))
        let content = String(line.dropFirst().dropLast())
        #expect(content.hasPrefix("\(bullet)\(bullet)\(bullet)\(bullet)\(bullet)\(bullet)\(cursor)"))
        #expect(content.count == 28)
        #expect(content == String(repeating: bullet, count: 6) + cursor + String(repeating: " ", count: 21))
    }

    @Test("Focused empty field shows only the cursor")
    func focusedEmpty() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 30, focusManager: fm)
        let lines = strippedLines(
            SecureField("Password", text: .constant("")).focusID("sf"),
            context: ctx
        )

        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 30)
        #expect(!line.contains(bullet))
        #expect(line == "\(openCap)\(cursor)" + String(repeating: " ", count: 27) + closeCap)
    }

    // MARK: Unfocused

    @Test("Unfocused field with text shows bullets, no cursor and no plaintext")
    func unfocusedWithText() {
        let fm = FocusManager()
        let decoyCtx = fieldContext(width: 30, focusManager: fm, identityPath: "decoy")
        _ = renderToBuffer(SecureField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)

        let ctx = fieldContext(width: 30, focusManager: fm, identityPath: "real")
        let lines = strippedLines(
            SecureField("Password", text: .constant("secret")).focusID("sf"),
            context: ctx
        )

        #expect(fm.currentFocusedID == "decoy")
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count == 30)
        #expect(!line.contains(cursor))
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
        #expect(!line.contains(cursor))
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
        #expect(line == "\(openCap)\(bullet)\(bullet)\(cursor)" + String(repeating: " ", count: 15) + closeCap)
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
        #expect(!line.contains(cursor))
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
        // 16 bullets scroll so the tail + cursor are visible: 11 bullets + cursor.
        #expect(line == openCap + String(repeating: bullet, count: 11) + cursor + closeCap)
        #expect(line.hasSuffix("\(cursor)\(closeCap)"))
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
        #expect(!line.contains(cursor))
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
        // Focused: two bullets + cursor + padding.
        #expect(line == openCap + String(repeating: bullet, count: 2) + cursor + String(repeating: " ", count: 45) + closeCap)
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
        #expect(lines[0].contains(cursor))
        #expect(!lines[1].contains(cursor))
        #expect(lines[0] == openCap + String(repeating: bullet, count: 2) + cursor + String(repeating: " ", count: 19) + closeCap)
        #expect(lines[1] == openCap + String(repeating: bullet, count: 3) + String(repeating: " ", count: 19) + closeCap)
    }
}
