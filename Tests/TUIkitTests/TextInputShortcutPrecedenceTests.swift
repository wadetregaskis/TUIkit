//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextInputShortcutPrecedenceTests.swift
//
//  Under the default `.commandKey(.control)` a SwiftUI ⌘ shortcut arrives as a
//  Control chord: an app's Find, `.keyboardShortcut("f")`, is Ctrl-F, and its
//  Duplicate, `("d")`, is Ctrl-D. Under `.commandKey(.option)` ⌘B and ⌘F
//  arrive as Option-B and Option-F. Those are also the text controls' Emacs
//  chords — forward a character, delete forward, back and forward a word — and
//  a focused text control is offered a key before the app's shortcuts are. So a
//  focused `TextEditor` swallowed the app's Find and moved its caret instead.
//
//  The app's shortcut wins. The Emacs chords are a bonus: whatever one does can
//  be done some other way. These put every kind of focused text control beside
//  a button carrying the shortcut and press the chord through the real input
//  chain: the button fires and the control does nothing. Without the shortcut
//  the chord edits. And the chords that are the only way to do what they do
//  keep the key: select-all, the editor's ends of the line (its Home and End go
//  to the ends of the document), and the Command-key stand-ins.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

/// The string the control under test is bound to.
private final class BoundText: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}

/// The shortcut actions that ran, in order.
private final class FireLog: @unchecked Sendable {
    var fired: [String] = []
}

/// How many times the input chain asked the app to quit.
private final class QuitCount: @unchecked Sendable {
    var count = 0
}

/// Every way text is edited on a page.
enum PrecedenceHost: String, CaseIterable, Sendable {
    case textField, secureField, suggestionsField, searchField, textEditor

    /// The single-line fields.
    static let fields: [Self] = [.textField, .secureField, .suggestionsField, .searchField]

    var isSecure: Bool { self == .secureField }
    var isEditor: Bool { self == .textEditor }
}

/// A shortcut an app registers, and the key that stands in for ⌘ on its page.
struct AppShortcut: Sendable, CustomTestStringConvertible {
    let key: Character
    let modifiers: EventModifiers
    var commandKey: CommandKeyBinding = .control

    /// SwiftUI's form, `.keyboardShortcut("f")`: ⌘, which is Control here.
    static func command(_ key: Character) -> Self { Self(key: key, modifiers: .command) }

    var testDescription: String {
        (modifiers.contains(.option) ? "⌥" : "") + (modifiers.contains(.command) ? "⌘" : "")
            + String(key) + (commandKey == .control ? "" : " under .\(commandKey)")
    }
}

/// The text control under test, first on the page so it takes the focus, and
/// a button carrying the shortcut, if there is one, after it.
private struct PrecedencePage: View {
    let host: PrecedenceHost
    let text: BoundText
    let log: FireLog
    let shortcut: AppShortcut?

    var body: some View {
        content.commandKey(shortcut?.commandKey ?? .control)
    }

    @ViewBuilder private var content: some View {
        let binding = Binding(get: { text.value }, set: { text.value = $0 })
        switch host {
        case .textField:
            VStack {
                TextField("Field", text: binding)
                buttons
            }
        case .secureField:
            VStack {
                SecureField("Field", text: binding)
                buttons
            }
        case .suggestionsField:
            VStack {
                TextField("Field", text: binding)
                    .textInputSuggestions {
                        Text("abcd")
                        Text("wxyz")
                    }
                buttons
            }
        case .searchField:
            VStack {
                Text("CONTENT")
                buttons
            }
            .searchable(text: binding)
        case .textEditor:
            VStack {
                TextEditor(text: binding).frame(height: 3)
                buttons
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        if let shortcut {
            Button("Shortcut") { [log] in log.fired.append(String(shortcut.key)) }
                .keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: shortcut.modifiers)
        }
    }
}

/// Renders frames the way the run loop brackets them and hands keys to a real
/// `InputHandler` over the same services.
@MainActor
private final class Harness {
    let tui = TUIContext()
    let focusManager = FocusManager()
    let statusBar = StatusBarState()
    let quits = QuitCount()
    let context: RenderContext
    let handler: InputHandler

    init() {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        statusBar.focusManager = focusManager
        environment.statusBar = statusBar
        context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        handler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tui.keyEventDispatcher,
            focusManager: focusManager,
            paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
            appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
            keyboardShortcuts: tui.keyboardShortcuts,
            dragAndDropSession: tui.dragAndDropSession,
            onQuit: { [quits] in quits.count += 1 }, onSuspend: {})
    }

    func frame(_ view: some View) {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.keyboardShortcuts.beginRenderPass()
        tui.preferences.beginRenderPass()
        statusBar.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
    }
}

/// What playing a script left behind.
private struct Played {
    /// The bound text afterwards.
    let text: String
    /// The shortcuts that fired, by key.
    let fired: [String]
    /// What the control wrote to its clipboard.
    let clipboardWrites: [String]
    /// The positions in the script of keys no layer of the input chain took.
    let unconsumed: [Int]
    /// How many times the chain quit the app.
    let quits: Int
}

/// Plays `keys` into `host`, starting from `initial`, with a button carrying
/// `shortcut` on the page: a frame before the first key and after every one,
/// so each key reaches what the last frame registered.
@MainActor
private func play(
    _ keys: [KeyEvent], into host: PrecedenceHost, from initial: String,
    shortcut: AppShortcut?, clipboard: String? = nil, quitShortcut: QuitShortcut = .q
) -> Played {
    let text = BoundText(initial)
    let log = FireLog()
    let board = FakeClipboard(contents: clipboard)
    let harness = Harness()
    harness.statusBar.quitShortcut = quitShortcut
    let page = PrecedencePage(host: host, text: text, log: log, shortcut: shortcut)
    harness.frame(page)
    // Never the real pasteboard: a field's Ctrl-C, X and V reach it.
    if let field = harness.focusManager.currentFocused as? TextFieldHandler {
        field.clipboard = board.access
    }
    harness.frame(page)
    var unconsumed: [Int] = []
    for (index, key) in keys.enumerated() {
        if !harness.handler.handle(key) { unconsumed.append(index) }
        harness.frame(page)
    }
    return Played(
        text: text.value, fired: log.fired, clipboardWrites: board.writes, unconsumed: unconsumed,
        quits: harness.quits.count)
}

private func ctrl(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true)
}

private func option(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), alt: true, shift: letter.isUppercase)
}

private func optionCtrl(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true, alt: true)
}

private func typed(_ character: Character) -> KeyEvent {
    KeyEvent(key: .character(character))
}

private let home = KeyEvent(key: .home)
private let right = KeyEvent(key: .right)
private let down = KeyEvent(key: .down)

/// A chord that gives way, the shortcut on it, and the two texts a script
/// around it can leave: the one where the chord did nothing and the one where
/// it edited.
///
/// Every script puts the caret after the first character with keys no
/// shortcut is on (Home, Right), presses the chord, and types an "X", so a
/// motion the chord made shows up as where the X lands. A field starts from
/// "abcd", the editor from two lines, "ab" and "cd".
struct GivingWayCase: Sendable, CustomTestStringConvertible {
    let name: String
    let chord: KeyEvent
    let shortcut: AppShortcut
    let hosts: [PrecedenceHost]
    var keys: [KeyEvent] { prefix + [chord, typed("X")] }
    var prefix: [KeyEvent] = [home, right]
    /// The text when the chord did nothing.
    var untouched: (field: String, editor: String) = (field: "aXbcd", editor: "aXb\ncd")
    /// The text when the chord edited.
    let edited: (field: String, editor: String)

    var testDescription: String { name }

    static func initial(_ host: PrecedenceHost) -> String {
        host.isEditor ? "ab\ncd" : "abcd"
    }

    /// The Control chord on `letter`, under an app's plain ⌘ shortcut on it.
    private static func control(
        _ letter: Character, hosts: [PrecedenceHost], edited: (field: String, editor: String)
    ) -> Self {
        Self(
            name: "Ctrl-\(letter.uppercased())", chord: ctrl(letter), shortcut: .command(letter),
            hosts: hosts, edited: edited)
    }

    static let all: [Self] = [
        // The ends of the line give way in a field, where Home and End go to
        // them too. The editor keeps them (see `KeepingCase`).
        control("a", hosts: PrecedenceHost.fields, edited: (field: "Xabcd", editor: "")),
        control("e", hosts: PrecedenceHost.fields, edited: (field: "abcdX", editor: "")),
        // The editor's single-character and line chords.
        control("b", hosts: [.textEditor], edited: (field: "", editor: "Xab\ncd")),
        control("f", hosts: [.textEditor], edited: (field: "", editor: "abX\ncd")),
        control("d", hosts: [.textEditor], edited: (field: "", editor: "aX\ncd")),
        control("k", hosts: [.textEditor], edited: (field: "", editor: "aX\ncd")),
        control("t", hosts: [.textEditor], edited: (field: "", editor: "baX\ncd")),
        control("n", hosts: [.textEditor], edited: (field: "", editor: "ab\ncXd")),
        control("o", hosts: [.textEditor], edited: (field: "", editor: "aX\nb\ncd")),
        control("v", hosts: [.textEditor], edited: (field: "", editor: "ab\ncXd")),
        // Ctrl-K fills the kill ring first, so a yank that happened shows.
        Self(
            name: "Ctrl-Y", chord: ctrl("y"), shortcut: .command("y"), hosts: [.textEditor],
            prefix: [home, right, ctrl("k")], untouched: (field: "", editor: "aX\ncd"),
            edited: (field: "", editor: "abX\ncd")),
        Self(
            name: "Ctrl-P", chord: ctrl("p"), shortcut: .command("p"), hosts: [.textEditor],
            prefix: [down, right], untouched: (field: "", editor: "ab\ncXd"),
            edited: (field: "", editor: "aXb\ncd")),
        // The word motions, readline's Meta-B and Meta-F. Under
        // `.commandKey(.option)` they are where an app's ⌘B and ⌘F arrive.
        Self(
            name: "Option-B", chord: option("b"),
            shortcut: AppShortcut(key: "b", modifiers: .command, commandKey: .option),
            hosts: PrecedenceHost.allCases, edited: (field: "Xabcd", editor: "Xab\ncd")),
        Self(
            name: "Option-F", chord: option("f"),
            shortcut: AppShortcut(key: "f", modifiers: .command, commandKey: .option),
            hosts: PrecedenceHost.allCases, edited: (field: "abcdX", editor: "abX\ncd")),
        // With Shift they extend a field's selection, so the X replaces it.
        Self(
            name: "Option-Shift-F", chord: option("F"),
            shortcut: AppShortcut(key: "F", modifiers: .option),
            hosts: PrecedenceHost.allCases, edited: (field: "aX", editor: "abX\ncd")),
        // A field reads Option first, so these are its word motions, and the
        // editor reads Control first, so they are its character motions. Both
        // give way: they used to disagree about that too.
        Self(
            name: "Option-Ctrl-B", chord: optionCtrl("b"),
            shortcut: AppShortcut(key: "b", modifiers: [.command, .option]),
            hosts: PrecedenceHost.allCases, edited: (field: "Xabcd", editor: "Xab\ncd")),
        Self(
            name: "Option-Ctrl-F", chord: optionCtrl("f"),
            shortcut: AppShortcut(key: "f", modifiers: [.command, .option]),
            hosts: PrecedenceHost.allCases, edited: (field: "abcdX", editor: "abX\ncd")),
    ]

    func untouched(in host: PrecedenceHost) -> String {
        host.isEditor ? untouched.editor : untouched.field
    }

    func edited(in host: PrecedenceHost) -> String {
        host.isEditor ? edited.editor : edited.field
    }

    /// Every host each chord applies to, paired with it.
    static let rows: [(PrecedenceHost, Self)] = all.flatMap { chord in
        chord.hosts.map { ($0, chord) }
    }
}

/// A chord that keeps the key, the script that shows it did its work, and
/// what that work leaves behind.
struct KeepingCase: Sendable, CustomTestStringConvertible {
    let name: String
    let shortcut: AppShortcut
    let keys: [KeyEvent]
    /// The text afterwards, in a plain field and in a secure one, which
    /// refuses to copy or cut.
    let text: (plain: String, secure: String)
    /// What reached the clipboard, in a plain field.
    var clipboardWrites: [String] = []
    /// What the clipboard held beforehand.
    var clipboard: String?

    var testDescription: String { name }

    static let fieldCases: [Self] = [
        Self(
            name: "Option-Ctrl-A selects all",
            shortcut: AppShortcut(key: "a", modifiers: [.command, .option]),
            keys: [optionCtrl("a"), typed("X")], text: ("X", "X")),
        Self(
            name: "Ctrl-C copies the selection", shortcut: .command("c"),
            keys: [optionCtrl("a"), ctrl("c")], text: ("abcd", "abcd"), clipboardWrites: ["abcd"]),
        Self(
            name: "Ctrl-X cuts the selection", shortcut: .command("x"),
            keys: [optionCtrl("a"), ctrl("x")], text: ("", "abcd"), clipboardWrites: ["abcd"]),
        Self(
            name: "Ctrl-V pastes", shortcut: .command("v"),
            keys: [home, ctrl("v")], text: ("PASTEDabcd", "PASTEDabcd"), clipboard: "PASTED"),
        Self(
            name: "Ctrl-Z undoes", shortcut: .command("z"),
            keys: [typed("X"), ctrl("z")], text: ("abcd", "abcd")),
        Self(
            name: "Ctrl-U erases", shortcut: .command("u"),
            keys: [ctrl("u")], text: ("", "")),
    ]

    /// Every field, paired with every case.
    static let rows: [(PrecedenceHost, Self)] = fieldCases.flatMap { keeping in
        PrecedenceHost.fields.map { ($0, keeping) }
    }
}

@MainActor
@Suite("An app's shortcut takes an editing chord from a focused text control")
struct TextInputShortcutPrecedenceTests {

    @Test("The shortcut fires and the control does nothing", arguments: GivingWayCase.rows)
    func shortcutTakesTheChord(host: PrecedenceHost, chord: GivingWayCase) {
        let played = play(
            chord.keys, into: host, from: GivingWayCase.initial(host), shortcut: chord.shortcut)
        #expect(played.fired == [String(chord.shortcut.key)], "\(host): the shortcut did not fire")
        #expect(played.text == chord.untouched(in: host), "\(host): the chord edited as well")
        #expect(played.unconsumed.isEmpty, "\(host) let keys \(played.unconsumed) fall through")
    }

    /// The same scripts with no shortcut on the page. The chord is the
    /// control's, so what the test above sees is the shortcut's doing, not a
    /// chord that does nothing anyway.
    @Test("Without the shortcut the chord edits", arguments: GivingWayCase.rows)
    func chordEditsWithoutAShortcut(host: PrecedenceHost, chord: GivingWayCase) {
        let played = play(chord.keys, into: host, from: GivingWayCase.initial(host), shortcut: nil)
        #expect(played.text == chord.edited(in: host), "\(host)")
    }

    /// A shortcut on some other chord leaves this one alone: the question is
    /// about the key pressed, not about whether the page has shortcuts.
    @Test("A shortcut on another chord does not take this one", arguments: PrecedenceHost.allCases)
    func unrelatedShortcutLeavesTheChord(host: PrecedenceHost) {
        let played = play(
            [home, right, option("f"), typed("X")], into: host,
            from: GivingWayCase.initial(host), shortcut: .command("g"))
        #expect(played.fired.isEmpty)
        #expect(played.text == (host.isEditor ? "abX\ncd" : "abcdX"))
    }

    /// A disabled button registers no shortcut, so it takes nothing.
    @Test("A disabled button's shortcut does not take the chord")
    func disabledShortcutLeavesTheChord() {
        let text = BoundText("ab\ncd")
        let log = FireLog()
        let harness = Harness()
        let binding = Binding(get: { text.value }, set: { text.value = $0 })
        let page = VStack {
            TextEditor(text: binding).frame(height: 3)
            Button("Find") { [log] in log.fired.append("f") }
                .keyboardShortcut("f")
                .disabled(true)
        }
        harness.frame(page)
        harness.frame(page)
        for key in [ctrl("f"), typed("X")] {
            harness.handler.handle(key)
            harness.frame(page)
        }
        #expect(log.fired.isEmpty)
        #expect(text.value == "aXb\ncd")
    }

    // MARK: - The chords that keep the key

    /// Each script is checked for its effect as well as for the silent button,
    /// so a chord that did nothing cannot pass as a chord that kept the key.
    @Test(
        "A field keeps select-all and its clipboard, undo and erase chords",
        arguments: KeepingCase.rows)
    func fieldKeepsItsChords(host: PrecedenceHost, keeping: KeepingCase) {
        let played = play(
            keeping.keys, into: host, from: "abcd", shortcut: keeping.shortcut,
            clipboard: keeping.clipboard)
        #expect(played.fired.isEmpty, "\(host): \(keeping.name) went to the shortcut")
        #expect(played.text == (host.isSecure ? keeping.text.secure : keeping.text.plain), "\(host)")
        #expect(played.clipboardWrites == (host.isSecure ? [] : keeping.clipboardWrites), "\(host)")
    }

    /// The editor's Home and End go to the ends of the document, so Ctrl-A and
    /// Ctrl-E are the only keys for the ends of its lines, and they keep the
    /// key there. Select-all has no other key anywhere.
    @Test("The editor keeps the ends of the line and select-all")
    func editorKeepsItsChords() {
        let start = play(
            [down, KeyEvent(key: .end), ctrl("a"), typed("X")], into: .textEditor, from: "ab\ncd",
            shortcut: .command("a"))
        #expect(start.fired.isEmpty)
        #expect(start.text == "ab\nXcd")

        let end = play(
            [ctrl("e"), typed("X")], into: .textEditor, from: "ab\ncd", shortcut: .command("e"))
        #expect(end.fired.isEmpty)
        #expect(end.text == "abX\ncd")

        let all = play(
            [optionCtrl("a"), typed("X")], into: .textEditor, from: "ab\ncd",
            shortcut: AppShortcut(key: "a", modifiers: [.command, .option]))
        #expect(all.fired.isEmpty)
        #expect(all.text == "X")
    }

    // MARK: - Copy and cut with nothing selected

    /// With nothing selected there is nothing for Ctrl-C or Ctrl-X to copy or
    /// cut, so a field passes the chord on, and the app's ⌘C or ⌘X, which
    /// arrive as those chords, fire. With a selection the field keeps them
    /// (see ``fieldKeepsItsChords(host:keeping:)``).
    @Test(
        "With nothing selected, Ctrl-C and Ctrl-X reach the app's ⌘C and ⌘X",
        arguments: PrecedenceHost.fields)
    func copyAndCutWithNothingSelectedPassOn(host: PrecedenceHost) {
        for letter: Character in ["c", "x"] {
            let played = play(
                [home, right, ctrl(letter), typed("X")], into: host, from: "abcd",
                shortcut: .command(letter), clipboard: "BOARD")
            #expect(played.fired == [String(letter)], "\(host): Ctrl-\(letter) did not reach ⌘\(letter)")
            #expect(played.text == "aXbcd", "\(host): Ctrl-\(letter) edited")
            #expect(played.clipboardWrites.isEmpty, "\(host): Ctrl-\(letter) wrote the clipboard")
        }
    }

    /// `QuitShortcut.ctrlC` is layer 4. A field that took Ctrl-C with nothing
    /// selected kept the app from quitting for as long as it had the focus,
    /// and a field has the focus from the first frame of many an app.
    @Test("With nothing selected, Ctrl-C quits under quitShortcut .ctrlC", arguments: PrecedenceHost.fields)
    func ctrlCQuitsFromAField(host: PrecedenceHost) {
        let idle = play([ctrl("c")], into: host, from: "abcd", shortcut: nil, quitShortcut: .ctrlC)
        #expect(idle.quits == 1, "\(host): Ctrl-C did not quit")
        #expect(idle.text == "abcd")

        // With a selection Ctrl-C is the field's copy, and the app stays.
        let copying = play(
            [optionCtrl("a"), ctrl("c")], into: host, from: "abcd", shortcut: nil,
            quitShortcut: .ctrlC)
        #expect(copying.quits == 0, "\(host): Ctrl-C quit while text was selected")
        #expect(copying.clipboardWrites == (host.isSecure ? [] : ["abcd"]), "\(host)")
    }

    // MARK: - The registry's question

    /// The question asks for what `trigger(for:)` would fire, by the same
    /// match, and fires nothing. A framework default is left out: it never
    /// takes a key from the control holding the focus.
    @Test("hasAppShortcut matches what trigger fires, for app shortcuts only, and runs nothing")
    func registryQuestion() {
        let registry = KeyboardShortcutRegistry()
        var runs = 0
        registry.register(KeyboardShortcut("f", modifiers: .control)) { runs += 1 }
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { runs += 1 }

        #expect(registry.hasAppShortcut(for: ctrl("f")))
        #expect(!registry.hasAppShortcut(for: typed("f")), "modifiers match exactly")
        #expect(!registry.hasAppShortcut(for: optionCtrl("f")), "modifiers match exactly")
        #expect(!registry.hasAppShortcut(for: ctrl("s")), "a framework default is not an app's")
        #expect(runs == 0, "the question fired a shortcut")

        #expect(registry.trigger(for: ctrl("f")))
        #expect(registry.trigger(for: ctrl("s")))
        #expect(runs == 2)
    }
}
