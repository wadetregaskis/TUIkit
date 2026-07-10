//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyboardShortcutTests.swift
//
//  `.keyboardShortcut(.defaultAction / .cancelAction)` — the default button
//  fires on Return/Enter ONLY when the focused control lets the key fall
//  through; Escape triggers the cancel button under the same rule. The
//  focused-control precedence cases here are the contract's heart: a
//  TextEditor keeps its newline, a list keeps its row activation, a focused
//  Button fires itself, and a TextField without onSubmit lets Return through.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Keyboard shortcuts (default / cancel actions)")
struct KeyboardShortcutTests {

    // MARK: - Harness

    /// Renders `view` with a full environment (focus manager + shortcut
    /// registry) and returns the pieces the dispatch chain uses.
    private func render(
        _ view: some View, width: Int = 40, height: Int = 12
    ) -> (focus: FocusManager, shortcuts: KeyboardShortcutRegistry) {
        let tui = TUIContext()
        var env = EnvironmentValues()
        let focus = FocusManager()
        env.focusManager = focus
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
        _ = renderToBuffer(view, context: context)
        return (focus, tui.keyboardShortcuts)
    }

    /// The focused-control-then-shortcut slice of InputHandler's chain: the
    /// focused control gets the key first; the semantic shortcut fires only
    /// if it fell through. (Layers 1/2/4 don't participate in these cases.)
    private func dispatch(
        _ event: KeyEvent, focus: FocusManager, shortcuts: KeyboardShortcutRegistry
    ) -> Bool {
        if focus.dispatchKeyEvent(event) { return true }
        return shortcuts.trigger(for: event)
    }

    // MARK: - Basic semantics

    @Test("Return fires the default button when nothing consumes it")
    func returnFiresDefault() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Sign in") { box.fired += 1 }
            .keyboardShortcut(.defaultAction)
        let (_, shortcuts) = render(view)

        #expect(shortcuts.trigger(for: KeyEvent(key: .enter)))
        #expect(box.fired == 1)
    }

    @Test("Escape fires the cancel button")
    func escapeFiresCancel() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Cancel") { box.fired += 1 }
            .keyboardShortcut(.cancelAction)
        let (_, shortcuts) = render(view)

        #expect(shortcuts.trigger(for: KeyEvent(key: .escape)))
        #expect(box.fired == 1)
    }

    @Test("Modified Return/Escape do not trigger the semantic actions")
    func modifiedKeysIgnored() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Go") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        let (_, shortcuts) = render(view)

        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter, ctrl: true)))
        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter, alt: true)))
        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter, shift: true)))
        #expect(box.fired == 0)
    }

    @Test("A disabled default button never registers")
    func disabledDoesNotRegister() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Go") { box.fired += 1 }
            .keyboardShortcut(.defaultAction)
            .disabled()
        let (_, shortcuts) = render(view)

        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter)))
        #expect(box.fired == 0)
    }

    @Test("The registry clears each render pass (a vanished dialog can't fire)")
    func registryClearsPerFrame() {
        final class Box { var fired = 0 }
        let box = Box()
        let view = Button("Go") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        let (_, shortcuts) = render(view)
        #expect(shortcuts.trigger(for: KeyEvent(key: .enter)))

        // Next frame renders WITHOUT the button (dialog dismissed).
        shortcuts.beginRenderPass()
        #expect(!shortcuts.trigger(for: KeyEvent(key: .enter)))
        #expect(box.fired == 1)
    }

    @Test("Overlapping registrations: the last rendered (topmost) wins")
    func lastRegistrationWins() {
        final class Box { var fired: [String] = [] }
        let box = Box()
        let view = VStack {
            Button("Page OK") { box.fired.append("page") }
                .keyboardShortcut(.defaultAction)
            Button("Dialog OK") { box.fired.append("dialog") }
                .keyboardShortcut(.defaultAction)
        }
        let (_, shortcuts) = render(view)

        #expect(shortcuts.trigger(for: KeyEvent(key: .enter)))
        #expect(box.fired == ["dialog"], "the later (topmost) registration wins")
    }

    // MARK: - Focused-control precedence (the contract's heart)

    @Test("A focused TextEditor keeps Return (newline), suppressing the default")
    func textEditorKeepsReturn() {
        final class Box { var fired = 0 }
        let box = Box()
        var text = "line"
        let view = VStack {
            TextEditor(text: Binding(get: { text }, set: { text = $0 }))
                .frame(height: 4)
            Button("Send") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        }
        let (focus, shortcuts) = render(view)

        // The editor auto-focuses (first focusable). Return → newline, consumed.
        #expect(dispatch(KeyEvent(key: .enter), focus: focus, shortcuts: shortcuts))
        #expect(text.contains("\n"), "the editor inserted a newline")
        #expect(box.fired == 0, "the default button must NOT fire")
    }

    @Test("A focused list with a row activation keeps Return, suppressing the default")
    func listActivationKeepsReturn() {
        final class Box {
            var opened: [String] = []
            var fired = 0
        }
        let box = Box()
        let view = VStack {
            List(selection: .constant(String?.none)) {
                ForEach(["a", "b"], id: \.self) { Text($0) }
            }
            .onRowActivate { box.opened.append($0) }
            .frame(height: 5)
            Button("OK") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        }
        let (focus, shortcuts) = render(view)

        #expect(dispatch(KeyEvent(key: .enter), focus: focus, shortcuts: shortcuts))
        #expect(box.opened == ["a"], "the list opened its focused row")
        #expect(box.fired == 0, "the default button must NOT fire")
    }

    @Test("A focused Button fires itself on Return, not the default")
    func focusedButtonFiresItself() {
        final class Box { var fired: [String] = [] }
        let box = Box()
        let view = VStack {
            Button("First") { box.fired.append("first") }
            Button("Default") { box.fired.append("default") }
                .keyboardShortcut(.defaultAction)
        }
        let (focus, shortcuts) = render(view)

        // Focus sits on the first button; Return activates IT.
        #expect(dispatch(KeyEvent(key: .enter), focus: focus, shortcuts: shortcuts))
        #expect(box.fired == ["first"])
    }

    @Test("A focused TextField WITHOUT onSubmit lets Return trigger the default")
    func textFieldWithoutSubmitFallsThrough() {
        final class Box { var fired = 0 }
        let box = Box()
        var text = ""
        let view = VStack {
            TextField("User", text: Binding(get: { text }, set: { text = $0 }))
            Button("Sign in") { box.fired += 1 }.keyboardShortcut(.defaultAction)
        }
        let (focus, shortcuts) = render(view)

        // Type something, then Return: the field has no submit handler, so
        // Return falls through and signs in — the macOS dialog behaviour.
        _ = dispatch(KeyEvent(character: "x"), focus: focus, shortcuts: shortcuts)
        #expect(dispatch(KeyEvent(key: .enter), focus: focus, shortcuts: shortcuts))
        #expect(box.fired == 1, "Return in a submit-less field triggers the default")
        #expect(text == "x", "typing still reached the field")
    }
}
