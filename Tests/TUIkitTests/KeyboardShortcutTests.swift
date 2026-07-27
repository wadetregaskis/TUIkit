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

@MainActor
@Suite("keyboard shortcut key equivalents")
struct KeyEquivalentShortcutTests {

    @Test("A bare key equivalent fires on that character alone")
    func bareKeyFires() {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        registry.register(KeyboardShortcut("1", modifiers: [])) { fired += 1 }

        #expect(registry.trigger(for: KeyEvent(key: .character("1"))))
        #expect(fired == 1)
        #expect(!registry.trigger(for: KeyEvent(key: .character("2"))), "a different key does nothing")
        #expect(fired == 1)
    }

    @Test("Modifiers must match exactly, not merely be present")
    func modifiersMatchExactly() {
        let registry = KeyboardShortcutRegistry()
        var bare = 0
        var ctrl = 0
        registry.register(KeyboardShortcut("q", modifiers: [])) { bare += 1 }
        registry.register(KeyboardShortcut("q", modifiers: .control)) { ctrl += 1 }

        _ = registry.trigger(for: KeyEvent(key: .character("q")))
        #expect((bare, ctrl) == (1, 0))
        _ = registry.trigger(for: KeyEvent(key: .character("q"), ctrl: true, alt: false, shift: false))
        #expect((bare, ctrl) == (1, 1), "Ctrl-Q must not fire the plain-q shortcut, or vice versa")
    }

    @Test("A Command shortcut can never fire — a terminal does not report it")
    func commandNeverFires() {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        // SwiftUI's default modifier set. Kept literal rather than quietly
        // rewritten to a bare key: an app that says ⌘Q must not quit on "q".
        registry.register(KeyboardShortcut("q")) { fired += 1 }

        #expect(!registry.trigger(for: KeyEvent(key: .character("q"))))
        #expect(
            !registry.trigger(
                for: KeyEvent(key: .character("q"), ctrl: true, alt: true, shift: true)))
        #expect(fired == 0)
    }

    /// A terminal does not report Shift for a printable key — it sends the
    /// shifted CHARACTER and no modifier bits (`KeyEvent.parse`'s printable
    /// branch builds `KeyEvent(character:)` with nothing set). So Shift has to
    /// be read off the case, or `("a", [.shift])` would be permanently dead
    /// while `("a", [])` fired for "A" as well.
    @Test("Shift on a printable key comes from the case, not the event flag")
    func shiftComesFromTheCase() {
        let registry = KeyboardShortcutRegistry()
        var lower = 0
        var upper = 0
        registry.register(KeyboardShortcut("a", modifiers: [])) { lower += 1 }
        registry.register(KeyboardShortcut("a", modifiers: .shift)) { upper += 1 }

        // Exactly what the parser produces for the two keystrokes: no flags.
        _ = registry.trigger(for: KeyEvent(key: .character("a")))
        #expect((lower, upper) == (1, 0), "lower-case a fires only the unshifted binding")
        _ = registry.trigger(for: KeyEvent(key: .character("A")))
        #expect((lower, upper) == (1, 1), "…and A fires only the shifted one")
    }

    @Test("An uppercase literal IS the shifted binding")
    func uppercaseLiteralImpliesShift() {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        // SwiftUI's reading of `keyboardShortcut("A")`.
        registry.register(KeyboardShortcut("A", modifiers: [])) { fired += 1 }

        #expect(!registry.trigger(for: KeyEvent(key: .character("a"))), "not the unshifted key")
        #expect(registry.trigger(for: KeyEvent(key: .character("A"))))
        #expect(fired == 1)
    }

    @Test("The semantic roles still work alongside key equivalents")
    func semanticsStillWork() {
        let registry = KeyboardShortcutRegistry()
        var accepted = 0
        var cancelled = 0
        registry.register(.defaultAction) { accepted += 1 }
        registry.register(.cancelAction) { cancelled += 1 }
        registry.register(KeyboardShortcut("x", modifiers: [])) { }

        #expect(registry.trigger(for: KeyEvent(key: .enter)))
        #expect(registry.trigger(for: KeyEvent(key: .escape)))
        #expect((accepted, cancelled) == (1, 1))
    }

    @Test("A shortcut reports the character a menu row should print")
    func displayCharacter() {
        #expect(KeyboardShortcut("7", modifiers: []).displayCharacter == "7")
        #expect(KeyboardShortcut.defaultAction.displayCharacter == nil)
    }
}

@MainActor
@Suite("command key substitution")
struct CommandKeySubstitutionTests {

    /// The portability point: SwiftUI source says ⌘S, and it should work here
    /// without every shared shortcut being rewritten for the terminal.
    @Test("A Command shortcut is delivered by whatever stands in for Command")
    func commandResolves() {
        let shortcut = KeyboardShortcut("s")  // SwiftUI's default: .command

        let asControl = shortcut.resolved(commandKey: .control)
        #expect(asControl != nil)
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        registry.register(asControl!) { fired += 1 }
        #expect(
            registry.trigger(
                for: KeyEvent(key: .character("s"), ctrl: true, alt: false, shift: false)))
        #expect(!registry.trigger(for: KeyEvent(key: .character("s"))), "…and not the bare key")
        #expect(fired == 1)
    }

    @Test(
        "Each binding delivers Command as the modifier it names",
        arguments: [
            (CommandKeyBinding.control, (ctrl: true, alt: false)),
            (.option, (ctrl: false, alt: true)),
            (.bare, (ctrl: false, alt: false)),
        ])
    func eachBinding(binding: CommandKeyBinding, flags: (ctrl: Bool, alt: Bool)) {
        let registry = KeyboardShortcutRegistry()
        var fired = 0
        let resolved = KeyboardShortcut("s").resolved(commandKey: binding)
        registry.register(resolved!) { fired += 1 }
        #expect(
            registry.trigger(
                for: KeyEvent(
                    key: .character("s"), ctrl: flags.ctrl, alt: flags.alt, shift: false)))
        #expect(fired == 1)
    }

    @Test("`.unavailable` binds nothing rather than guessing")
    func unavailableBindsNothing() {
        #expect(KeyboardShortcut("s").resolved(commandKey: .unavailable) == nil)
        // A shortcut that never mentioned Command is untouched either way.
        let bare = KeyboardShortcut("s", modifiers: [])
        #expect(bare.resolved(commandKey: .unavailable) == bare)
    }

    @Test("A shortcut without Command is not rewritten")
    func nonCommandUntouched() {
        let ctrl = KeyboardShortcut("s", modifiers: .control)
        #expect(ctrl.resolved(commandKey: .option) == ctrl, "only .command is substituted")
    }

    /// `KeyEvent.parse` matches Tab, Return, newline and Escape BEFORE the
    /// Ctrl-letter range, so those combinations never arrive as a modified
    /// letter — no amount of remapping can deliver ⌘I as Ctrl-I. Ctrl-C and
    /// Ctrl-Z belong to job control. Better to be able to ask than to wonder
    /// why one menu item is dead.
    @Test("The C0 collisions are reported, not silently dead")
    func c0CollisionsAreQueryable() {
        for key: KeyEquivalent in ["i", "j", "m", "c", "z", "["] {
            let resolved = KeyboardShortcut(key).resolved(commandKey: .control)
            #expect(
                resolved?.isDeliverableInTerminal == false,
                "Ctrl-\(key.character) is spoken for by the C0 range or job control")
        }
        for key: KeyEquivalent in ["s", "o", "n", "1"] {
            let resolved = KeyboardShortcut(key).resolved(commandKey: .control)
            #expect(resolved?.isDeliverableInTerminal == true)
        }
        // Under Option there is no C0 range to collide with.
        #expect(
            KeyboardShortcut("i").resolved(commandKey: .option)?.isDeliverableInTerminal == true)
        // And an unresolved Command shortcut is honestly undeliverable.
        #expect(KeyboardShortcut("s").isDeliverableInTerminal == false)
    }
}
