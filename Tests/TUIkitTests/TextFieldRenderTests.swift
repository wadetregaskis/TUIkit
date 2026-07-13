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

/// Whether `rawLine` paints any cell on the palette's caret colour.
///
/// The block caret inverts its cell — the character rendered on a
/// caret-coloured background — rather than stamping a `█` glyph, so in raw
/// output the caret is a background-colour run, not a character. Backgrounds
/// are emitted last in a style sequence, so the caret background's SGR
/// fragment terminates its escape (`…;48;…m`), making it an unambiguous
/// marker.
@MainActor
private func hasCaretCell(_ rawLine: String, palette: (any Palette)? = nil) -> Bool {
    let cursorColor = (palette ?? EnvironmentValues().palette).cursorColor
    let fragment = ANSIRenderer.backgroundCodes(for: cursorColor).joined(separator: ";") + "m"
    return rawLine.contains(fragment)
}

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
/// returns the raw (ANSI-bearing) lines.
@MainActor
private func rawLines(_ view: some View, context: RenderContext) -> [String] {
    _ = renderToBuffer(view, context: context)
    return renderToBuffer(view, context: context).lines
}

/// `rawLines`, stripped of ANSI escapes.
@MainActor
private func strippedLines(_ view: some View, context: RenderContext) -> [String] {
    rawLines(view, context: context).map { $0.stripped }
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
        let raw = rawLines(
            TextField("Name", text: .constant("hello")).focusID("tf"),
            context: ctx
        )

        #expect(raw.count == 1)
        #expect(fm.currentFocusedID == "tf")  // first focusable auto-focuses
        let line = raw[0].stripped
        #expect(line.count == 30)
        #expect(line.hasPrefix(openCap))
        #expect(line.hasSuffix(closeCap))
        // Content between the caps: "hello", then the caret cell (an
        // inverted space, invisible when stripped) and padding.
        let content = String(line.dropFirst().dropLast())
        #expect(content == "hello" + String(repeating: " ", count: 23))
        #expect(hasCaretCell(raw[0]))
    }

    @Test("Focused empty field shows only the cursor")
    func focusedEmpty() {
        let fm = FocusManager()
        let ctx = fieldContext(width: 30, focusManager: fm)
        let raw = rawLines(
            TextField("Name", text: .constant("")).focusID("tf"),
            context: ctx
        )

        #expect(raw.count == 1)
        let line = raw[0].stripped
        #expect(line.count == 30)
        // The caret is a caret-coloured cell, not a glyph — the stripped
        // line is all padding.
        #expect(line == openCap + String(repeating: " ", count: 28) + closeCap)
        #expect(hasCaretCell(raw[0]))
    }

    // MARK: Wide characters (cell-exact layout)

    @Test("Emoji content renders the field at exactly the available width, focused or not")
    func emojiContentIsCellExact() {
        // The field's contract is CELLS, not characters: an emoji is one
        // Character but two cells, and the char-counting renderer used to
        // emit one extra cell per visible emoji — the combo disclosure and
        // its hit region drifted apart, and focusing (which scrolls) moved
        // the field's right edge.
        let text = "😃😃😃ab"

        let focusedFM = FocusManager()
        let focused = strippedLines(
            TextField("Fill", text: .constant(text)).focusID("tf"),
            context: fieldContext(width: 20, focusManager: focusedFM))[0]
        #expect(focusedFM.currentFocusedID == "tf")
        #expect(focused.strippedLength == 20, "focused: |\(focused)|")
        #expect(focused.hasSuffix(closeCap))

        let unfocusedFM = FocusManager()
        let decoyCtx = fieldContext(width: 20, focusManager: unfocusedFM, identityPath: "decoy")
        _ = renderToBuffer(TextField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)
        let unfocused = strippedLines(
            TextField("Fill", text: .constant(text)).focusID("tf"),
            context: fieldContext(width: 20, focusManager: unfocusedFM, identityPath: "real"))[0]
        #expect(unfocused.strippedLength == 20, "unfocused: |\(unfocused)|")
        #expect(unfocused.hasSuffix(closeCap))
    }

    @Test("A combo box's ▾ stays on the same cell column focused and unfocused, emoji included")
    func comboDisclosureStaysPut() {
        // The disclosure's hit region is computed from the content width; the
        // rendered arrow must sit exactly there in both states, or clicks
        // land one cell off (the reported must-click-left-of-the-arrow bug).
        let text = "😃😃😃😃"
        func arrowCell(focused: Bool) -> Int {
            let fm = FocusManager()
            if !focused {
                let decoyCtx = fieldContext(width: 24, focusManager: fm, identityPath: "decoy")
                _ = renderToBuffer(
                    TextField("Decoy", text: .constant("x")).focusID("decoy"), context: decoyCtx)
            }
            let line = strippedLines(
                TextField("Fill", text: .constant(text))
                    .focusID("tf")
                    .textInputSuggestions { Text("😃😃😃😃") },
                context: fieldContext(
                    width: 24, focusManager: fm, identityPath: focused ? "" : "real"))[0]
            #expect(line.strippedLength == 24, "field is cell-exact: |\(line)|")
            guard let index = line.firstIndex(of: "▾") else {
                Issue.record("no disclosure in |\(line)|")
                return -1
            }
            return String(line[line.startIndex..<index]).strippedLength
        }
        let focusedCell = arrowCell(focused: true)
        let unfocusedCell = arrowCell(focused: false)
        #expect(focusedCell == unfocusedCell, "▾ must not move on focus")
        // …and exactly where the hit region is registered: the second cell of
        // the two-cell disclosure, flush against the trailing cap.
        #expect(focusedCell == 24 - 2, "▾ against the trailing cap")
    }

    @Test("The block caret over a wide character keeps the field's width")
    func caretOverWideCharacter() {
        // Caret ON the emoji (index 0): the caret inverts the WHOLE wide
        // character (both cells) — the emoji stays legible on the caret
        // colour, and nothing after it may shift.
        let palette = SystemPalette(.green)
        let renderer = TextFieldContentRenderer(
            prompt: nil,
            isDisabled: false,
            displayCharacter: { index, text in text[text.index(text.startIndex, offsetBy: index)] },
            contentForeground: nil
        )
        let raw = renderer.buildContent(
            text: "😃ab",
            cursorPosition: 0,
            selectionRange: nil,
            isFocused: true,
            palette: palette,
            cursorStyle: TextCursorStyle(),
            cursorTimer: nil,
            contentWidth: 10
        )
        let content = raw.stripped
        #expect(content.strippedLength == 10, "|\(content)|")
        #expect(content.hasPrefix("😃ab"), "caret keeps the wide char legible: |\(content)|")
        #expect(hasCaretCell(raw, palette: palette))
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
        let raw = rawLines(
            TextField("Name", text: .constant("hello")).focusID("tf"),
            context: ctx
        )

        #expect(fm.currentFocusedID == "decoy")  // not our field
        #expect(raw.count == 1)
        let line = raw[0].stripped
        #expect(line.count == 30)
        // No cursor when unfocused: no cell carries the caret colour.
        #expect(!hasCaretCell(raw[0]))
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
        let raw = rawLines(
            TextField("Email", text: .constant(""), prompt: Text("you@example.com")).focusID("tf"),
            context: ctx
        )

        #expect(raw.count == 1)
        let line = raw[0].stripped
        #expect(line.count == 30)
        #expect(!hasCaretCell(raw[0]))
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
        #expect(line == "\(openCap)hi" + String(repeating: " ", count: 16) + closeCap)
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
        let raw = rawLines(
            TextField("N", text: .constant("abcdefghijklmnopqrstuvwxyz")).focusID("tf"),
            context: ctx
        )

        #expect(raw.count == 1)
        let line = raw[0].stripped
        #expect(line.count == 14)
        // Cursor sits at the end (position 26); the field scrolls so the
        // tail of the text plus the caret cell (an inverted space) are
        // visible: "pqrstuvwxyz" + one cell.
        #expect(line == "\(openCap)pqrstuvwxyz \(closeCap)")
        #expect(hasCaretCell(raw[0]))
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
        // 10-wide content: 9 trailing chars + the caret cell.
        #expect(line == "\(openCap)ghijklmno \(closeCap)")
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
        // Only the first field is focused, so only line 0 shows a caret.
        #expect(fm.currentFocusedID == "a")
        #expect(hasCaretCell(buffer.lines[0]))
        #expect(!hasCaretCell(buffer.lines[1]))
        #expect(!hasCaretCell(buffer.lines[2]))
        #expect(lines[0] == "\(openCap)one" + String(repeating: " ", count: 19) + closeCap)
        #expect(lines[1] == "\(openCap)two" + String(repeating: " ", count: 19) + closeCap)
        #expect(lines[2] == "\(openCap)three" + String(repeating: " ", count: 17) + closeCap)
    }
}
