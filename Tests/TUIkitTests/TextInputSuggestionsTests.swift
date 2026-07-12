//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextInputSuggestionsTests.swift
//
//  The combo-box surface: `.textInputSuggestions` menus on TextField
//  (extraction, keyboard navigation, rendering, mouse), plus divider support
//  in the shared drop-down machinery — Divider inside Picker content and
//  MenuItem.divider in Menu.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Extraction

@MainActor
@Suite("Text-input suggestion extraction")
struct TextSuggestionExtractionTests {

    private func kinds(_ entries: [_TextSuggestionEntry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .option: "option"
            case .divider: "divider"
            }
        }
    }

    @Test("Texts, dividers, and explicit completions extract in order")
    func basicExtraction() {
        @ViewBuilder func content() -> some View {
            Text("alpha")
            Divider()
            Text("labelled").textInputCompletion("expanded value")
        }
        let entries = extractTextSuggestions(content())
        #expect(kinds(entries) == ["option", "divider", "option"])
        guard case .option(let completion, _) = entries[2] else {
            Issue.record("expected an option entry")
            return
        }
        #expect(completion == "expanded value")
        guard case .option(let derived, _) = entries[0] else {
            Issue.record("expected an option entry")
            return
        }
        #expect(derived == nil, "a plain Text derives its completion at render time")
    }

    @Test("Edge and adjacent dividers are collapsed")
    func dividerNormalization() {
        @ViewBuilder func content() -> some View {
            Divider()
            Text("a")
            Divider()
            Divider()
            Text("b")
            Divider()
        }
        let entries = extractTextSuggestions(content())
        #expect(kinds(entries) == ["option", "divider", "option"])
    }

    @Test("ForEach and conditional groups contribute entries")
    func structuredExtraction() {
        @MainActor
        @ViewBuilder func suggestions(withRecents: Bool) -> some View {
            ForEach(["x", "y"], id: \.self) { Text($0) }
            if withRecents {
                Divider()
                Text("recent")
            }
        }
        #expect(kinds(extractTextSuggestions(suggestions(withRecents: true)))
            == ["option", "option", "divider", "option"])
        #expect(kinds(extractTextSuggestions(suggestions(withRecents: false)))
            == ["option", "option"])
    }
}

// MARK: - Keyboard

@MainActor
@Suite("Text-input suggestion keyboard navigation")
struct TextSuggestionKeyboardTests {

    private final class TextBox {
        var value = ""
        var submitted = 0
        var binding: Binding<String> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    private func makeHandler(_ box: TextBox, completions: [String]) -> TextFieldHandler {
        let handler = TextFieldHandler(focusID: "combo", text: box.binding)
        handler.suggestionCompletions = completions
        handler.onSubmit = { box.submitted += 1 }
        return handler
    }

    @Test("Down enters the menu and walks it, stopping at the last row")
    func downNavigation() {
        let box = TextBox()
        let handler = makeHandler(box, completions: ["alpha", "beta"])

        #expect(handler.handleKeyEvent(KeyEvent(key: .down)))
        #expect(handler.suggestionHighlight == 0)
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)))
        #expect(handler.suggestionHighlight == 1)
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)))
        #expect(handler.suggestionHighlight == 1, "Down stops at the last suggestion")
    }

    @Test("Up from the first row returns the keyboard to the caret")
    func upReturnsToCaret() {
        let box = TextBox()
        box.value = "abc"
        let handler = makeHandler(box, completions: ["alpha"])
        handler.cursorPosition = 3

        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.suggestionHighlight == 0)
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.suggestionHighlight == nil)
        // A further Up is the field's normal behaviour (caret to start).
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.cursorPosition == 0)
    }

    @Test("Enter accepts the highlighted suggestion and submits")
    func enterAccepts() {
        let box = TextBox()
        box.value = "al"
        let handler = makeHandler(box, completions: ["alpha", "beta"])

        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)))
        #expect(box.value == "alpha")
        #expect(box.submitted == 1, "picking a suggestion fires onSubmit")
        #expect(handler.suggestionHighlight == nil)
        #expect(handler.suggestionsDismissed, "the menu closes after a pick")
        #expect(handler.cursorPosition == 5, "caret lands at the end of the completion")
    }

    @Test("Enter with no highlight submits the typed text as usual")
    func enterWithoutHighlightSubmits() {
        let box = TextBox()
        box.value = "custom"
        let handler = makeHandler(box, completions: ["alpha"])

        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)))
        #expect(box.value == "custom")
        #expect(box.submitted == 1)
        #expect(!handler.suggestionsDismissed)
    }

    @Test("Escape dismisses the menu; typing re-opens it")
    func escapeThenTyping() {
        let box = TextBox()
        let handler = makeHandler(box, completions: ["alpha"])

        #expect(handler.handleKeyEvent(KeyEvent(key: .escape)))
        #expect(handler.suggestionsDismissed)
        #expect(!handler.suggestionsActive)

        // While dismissed, Down is the field's normal caret-to-end.
        box.value = "ab"
        handler.cursorPosition = 0
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.suggestionHighlight == nil)
        #expect(handler.cursorPosition == 2)

        // An edit re-opens the menu.
        _ = handler.handleKeyEvent(KeyEvent(key: .character("c")))
        #expect(!handler.suggestionsDismissed)
        #expect(handler.suggestionsActive)
    }

    @Test("Shift+Down keeps its select-to-end meaning while the menu shows")
    func shiftDownStillSelects() {
        let box = TextBox()
        box.value = "abc"
        let handler = makeHandler(box, completions: ["alpha"])
        handler.cursorPosition = 0

        _ = handler.handleKeyEvent(KeyEvent(key: .down, shift: true))
        #expect(handler.suggestionHighlight == nil)
        #expect(handler.selectionRange == 0..<3)
    }
}

// MARK: - Rendering + Mouse

@MainActor
@Suite("Text-input suggestions menu", .serialized)
struct TextSuggestionMenuTests {

    private final class TextBox {
        var value = ""
        var binding: Binding<String> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    private func makeEnvironment(tui: TUIContext, focus: FocusManager) -> EnvironmentValues {
        var env = EnvironmentValues()
        env.focusManager = focus
        env.stateStorage = tui.stateStorage
        env.lifecycle = tui.lifecycle
        env.keyEventDispatcher = tui.keyEventDispatcher
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        env.renderCache = tui.renderCache
        env.preferenceStorage = tui.preferences
        env.terminalWidth = 60
        env.terminalHeight = 20
        return env
    }

    private func makeField(_ box: TextBox) -> some View {
        TextField("Value", text: box.binding)
            .focusID("combo")
            .textInputSuggestions {
                Text("alpha")
                Text("beta")
                Divider()
                Text("recent one")
            }
            .frame(width: 24)
    }

    private func render(
        _ view: some View, tui: TUIContext, focus: FocusManager, env: EnvironmentValues
    ) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: 60, availableHeight: 20, environment: env, tuiContext: tui)
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        return buffer
    }

    @Test("An unfocused field shows the ▾ affordance and no menu")
    func unfocusedAffordance() {
        let tui = TUIContext()
        let focus = FocusManager()
        let env = makeEnvironment(tui: tui, focus: focus)
        let box = TextBox()

        // A second focusable holds the focus — a lone field would auto-focus
        // and legitimately open its menu.
        let view = VStack {
            Button("Other") {}.focusID("other")
            makeField(box)
        }
        _ = render(view, tui: tui, focus: focus, env: env)
        focus.focus(id: "other")
        let buffer = render(view, tui: tui, focus: focus, env: env)
        let composited = buffer.compositingOverlays(
            maxWidth: 60, maxHeight: 20, palette: env.palette)
        let screen = composited.lines.map(\.stripped).joined(separator: "\n")
        #expect(screen.contains(DropdownMenu.closedCaret), "the combo affordance shows: \(screen)")
        #expect(!screen.contains("alpha"), "no menu while unfocused: \(screen)")
    }

    @Test("Focusing the field opens the menu with dividers between groups")
    func focusedMenu() {
        let tui = TUIContext()
        let focus = FocusManager()
        let env = makeEnvironment(tui: tui, focus: focus)
        let box = TextBox()
        let field = makeField(box)

        _ = render(field, tui: tui, focus: focus, env: env)  // register
        focus.focus(id: "combo")
        let buffer = render(field, tui: tui, focus: focus, env: env)
        let composited = buffer.compositingOverlays(
            maxWidth: 60, maxHeight: 20, palette: env.palette)
        let lines = composited.lines.map(\.stripped)
        let screen = lines.joined(separator: "\n")

        #expect(screen.contains("alpha") && screen.contains("recent one"), "menu open: \(screen)")
        #expect(screen.contains(DropdownMenu.openCaret), "the affordance flips to ▴")
        // The divider renders as a rule row between "beta" and "recent one".
        let betaRow = lines.firstIndex { $0.contains("beta") }
        let recentRow = lines.firstIndex { $0.contains("recent one") }
        if let betaRow, let recentRow {
            #expect(recentRow == betaRow + 2, "one rule row sits between the groups")
            #expect(lines[betaRow + 1].contains("──"), "the divider is a horizontal rule")
        } else {
            Issue.record("could not locate menu rows in: \(screen)")
        }
    }

    @Test("Clicking a suggestion row fills the field")
    func clickPicksSuggestion() {
        let tui = TUIContext()
        let focus = FocusManager()
        let env = makeEnvironment(tui: tui, focus: focus)
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        let box = TextBox()
        let field = makeField(box)

        _ = render(field, tui: tui, focus: focus, env: env)
        focus.focus(id: "combo")
        let buffer = render(field, tui: tui, focus: focus, env: env)
        let composited = buffer.compositingOverlays(
            maxWidth: 60, maxHeight: 20, palette: env.palette)

        guard let (row, column) = locate("beta", in: composited) else {
            Issue.record(
                "could not find beta row in:\n\(composited.lines.map(\.stripped).joined(separator: "\n"))"
            )
            return
        }
        dispatcher.setRegions(composited.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        let consumed = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: column, y: row))
        #expect(consumed, "the row click lands on a hit region")
        #expect(box.value == "beta", "clicking the row fills the field")
    }

    @Test("The current value's row carries the ✓ marker")
    func currentValueMarker() {
        let tui = TUIContext()
        let focus = FocusManager()
        let env = makeEnvironment(tui: tui, focus: focus)
        let box = TextBox()
        box.value = "beta"
        let field = makeField(box)

        _ = render(field, tui: tui, focus: focus, env: env)
        focus.focus(id: "combo")
        let buffer = render(field, tui: tui, focus: focus, env: env)
        let composited = buffer.compositingOverlays(
            maxWidth: 60, maxHeight: 20, palette: env.palette)
        // Skip the field's own line (it shows "beta" too); the menu rows
        // start beneath it.
        let betaLine = composited.lines.dropFirst().map(\.stripped).first { $0.contains("beta") }
        #expect(betaLine?.contains(DropdownMenu.selectedMarker) == true, "\(betaLine ?? "nil")")
    }

    /// The (y, x) of `needle`'s first character in the buffer, or nil.
    private func locate(_ needle: String, in buffer: FrameBuffer) -> (row: Int, column: Int)? {
        for (row, line) in buffer.lines.enumerated() {
            let stripped = line.stripped
            if let range = stripped.range(of: needle) {
                return (row, stripped.distance(from: stripped.startIndex, to: range.lowerBound))
            }
        }
        return nil
    }
}

// MARK: - Dividers in Picker + Menu

@MainActor
@Suite("Menu dividers")
struct MenuDividerTests {

    @Test("A Divider in Picker content becomes a rule row in the drop-down")
    func pickerDivider() throws {
        let context = makeRenderContext()
        var choice = AnyHashable("a")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })

        let entries: [_PickerEntry<AnyHashable>] = [
            .option(tag: AnyHashable("a"), label: AnyView(Text("Apple"))),
            .divider,
            .option(tag: AnyHashable("b"), label: AnyView(Text("Banana"))),
        ]
        let core = _PickerMenuCore(
            entries: entries, selection: binding, focusID: "menu-picker", isDisabled: false)

        _ = renderToBuffer(core, context: context)
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let box: StateBox<_PickerMenuHandler> = context.environment.stateStorage!.storage(
            for: key,
            default: _PickerMenuHandler(
                focusID: "menu-picker",
                selection: binding,
                itemValues: [],
                canBeFocused: true))
        box.value.isOpen = true

        let open = renderToBuffer(core, context: context)
        let layer = try #require(open.overlays.first)
        let lines = layer.content.lines.map(\.stripped)
        // Top border, Apple, rule, Banana, bottom border.
        #expect(lines.count == 5)
        #expect(lines[1].contains("Apple"))
        #expect(lines[2].contains("──"), "the divider renders as a rule: \(lines[2])")
        #expect(lines[3].contains("Banana"))
        // Only the two options are keyboard-navigable.
        #expect(box.value.itemValues.count == 2)
    }

    @Test("The Picker extracts Divider entries from its content")
    func pickerExtraction() {
        @ViewBuilder func content() -> some View {
            Text("A").tag("a")
            Divider()
            Text("B").tag("b")
        }
        let options = (content() as? PickerOptionProvider)?.pickerOptions() ?? []
        #expect(options.count == 3)
        guard case .divider = options[1] else {
            Issue.record("expected a divider entry")
            return
        }
    }

    @Test("MenuItem.divider renders as a rule and navigation skips it")
    func menuControlDivider() {
        let context = makeRenderContext { env, tui in
            env.keyEventDispatcher = tui.keyEventDispatcher
        }
        var selection = 0
        let menu = Menu(
            items: [
                MenuItem(label: "First"),
                .divider,
                MenuItem(label: "Second"),
            ],
            selection: Binding(get: { selection }, set: { selection = $0 })
        )

        let buffer = renderToBuffer(menu, context: context)
        let lines = buffer.lines.map(\.stripped)
        // Top border, First, rule, Second, bottom border.
        #expect(lines.count == 5)
        #expect(lines[2].contains("──"), "the divider renders as a rule: \(lines[2])")

        // Down from First skips the divider straight to Second (index 2),
        // and Down again wraps past it back to First.
        let dispatcher = context.environment.keyEventDispatcher!
        #expect(dispatcher.dispatch(KeyEvent(key: .down)))
        #expect(selection == 2)
        #expect(dispatcher.dispatch(KeyEvent(key: .down)))
        #expect(selection == 0)
    }
}
