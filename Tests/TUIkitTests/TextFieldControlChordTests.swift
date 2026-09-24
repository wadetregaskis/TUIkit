//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldControlChordTests.swift
//
//  The Control chords of the macOS text system — Ctrl-B / Ctrl-F back and
//  forward a character, Ctrl-D delete forward, Ctrl-K kill to the end, Ctrl-Y
//  yank, Ctrl-T transpose — worked in a `TextEditor` and did nothing at all in
//  a `TextField` or `SecureField` on the same page. The field kept a chord
//  table of its own, and it held only the chords somebody had remembered.
//
//  These drive every chord through the app's real input chain into every way a
//  single-line field reaches a page — plain, secure, carrying
//  `textInputSuggestions`, and the field `.searchable` puts above its content —
//  and hold each to what the editor does with the same line. The editor's
//  chords for other lines, Ctrl-O, Ctrl-P and Ctrl-N, are not a field's: it
//  declines them and they pass on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The string the control under test is bound to, read back after the keys.
@MainActor
private final class BoundText {
    var value: String
    init(_ value: String) { self.value = value }
}

/// Every way a line of text is edited on a page. The editor is the reference:
/// on a single line, a field must do what the editor does.
enum ChordHost: String, CaseIterable, Sendable {
    case textField, secureField, suggestionsField, searchField, textEditor

    /// The single-line fields — everything but the reference.
    static let fields: [Self] = [.textField, .secureField, .suggestionsField, .searchField]

    /// Whether Ctrl-K keeps what it kills for Ctrl-Y. A SecureField keeps
    /// nothing, as AppKit's `NSSecureTextField` does (see
    /// `SecureFieldClipboardTests`), so its Ctrl-Y has nothing to yank.
    var keepsAKill: Bool { self != .secureField }
}

/// One control on an otherwise empty page, so it takes the focus on the first
/// frame and every key goes to it.
private struct ChordApp: App {
    let host: ChordHost
    let text: BoundText

    init() { self.init(host: .textField, text: BoundText("")) }
    init(host: ChordHost, text: BoundText) {
        self.host = host
        self.text = text
    }

    var body: some Scene {
        WindowGroup { ChordPage(host: host, text: text) }
    }
}

private struct ChordPage: View {
    let host: ChordHost
    let text: BoundText

    var body: some View {
        let binding = Binding(get: { text.value }, set: { text.value = $0 })
        switch host {
        case .textField:
            TextField("Field", text: binding)
        case .secureField:
            SecureField("Field", text: binding)
        case .suggestionsField:
            TextField("Field", text: binding)
                .textInputSuggestions {
                    Text("abcd")
                    Text("wxyz")
                }
        case .searchField:
            Text("CONTENT").searchable(text: binding)
        case .textEditor:
            TextEditor(text: binding).frame(height: 3)
        }
    }
}

private func ctrl(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true)
}

private func typed(_ character: Character) -> KeyEvent {
    KeyEvent(key: .character(character))
}

private let shiftRight = KeyEvent(key: .right, shift: true)

/// What playing a script left behind.
private struct Played {
    /// The bound text afterwards.
    let text: String
    /// The positions in the script of keys no layer of the input chain took.
    let unconsumed: [Int]
}

/// Plays `keys` into `host`, starting from `initial`, through the app's input
/// chain — a frame between every key, the render loop's own shape, so the
/// handler each key reaches is the one the last frame registered.
@MainActor
private func play(_ keys: [KeyEvent], into host: ChordHost, from initial: String) -> Played {
    let text = BoundText(initial)
    let app = HeadlessApp(ChordApp(host: host, text: text), width: 40, height: 10)
    var now: Int64 = 0
    // The first frame registers the control and hands it the focus; the
    // second is the one a person would see before pressing anything.
    app.frame(atNanos: now)
    now += 16_666_667
    app.frame(atNanos: now)
    var unconsumed: [Int] = []
    for (index, key) in keys.enumerated() {
        if !app.send(key) { unconsumed.append(index) }
        now += 16_666_667
        app.frame(atNanos: now)
    }
    return Played(text: text.value, unconsumed: unconsumed)
}

/// A chord script over one line of text and the line it must leave. Every
/// script opens with Ctrl-A or Ctrl-E, because the editor's caret starts at
/// the beginning and a field's at the end.
struct ChordScript: Sendable, CustomTestStringConvertible {
    let name: String
    let initial: String
    let keys: [KeyEvent]
    let expected: String
    /// What a SecureField leaves instead, where it differs: it keeps no kill.
    var secureExpected: String?

    var testDescription: String { name }

    func expected(in host: ChordHost) -> String {
        host.keepsAKill ? expected : (secureExpected ?? expected)
    }

    static let all: [Self] = [
        Self(
            name: "Ctrl-B steps back a character",
            initial: "abcd", keys: [ctrl("e"), ctrl("b"), typed("X")], expected: "abcXd"),
        Self(
            name: "Ctrl-F steps forward a character",
            initial: "abcd", keys: [ctrl("a"), ctrl("f"), typed("X")], expected: "aXbcd"),
        Self(
            name: "Ctrl-D deletes forward",
            initial: "abcd", keys: [ctrl("a"), ctrl("f"), ctrl("d")], expected: "acd"),
        Self(
            name: "Ctrl-K kills to the end",
            initial: "abcd", keys: [ctrl("a"), ctrl("f"), ctrl("k")], expected: "a"),
        Self(
            name: "Ctrl-Y yanks the kill back at the caret, and the caret follows it",
            initial: "abcd",
            keys: [ctrl("a"), ctrl("f"), ctrl("k"), ctrl("a"), ctrl("y"), typed("X")],
            expected: "bcdXa", secureExpected: "Xa"),
        Self(
            name: "Ctrl-T swaps the characters around the caret and steps on",
            initial: "abcd", keys: [ctrl("a"), ctrl("f"), ctrl("t"), typed("X")], expected: "baXcd"),
        Self(
            name: "Ctrl-T at the end swaps the last two",
            initial: "abcd", keys: [ctrl("e"), ctrl("t"), typed("X")], expected: "abdcX"),
        Self(
            name: "Ctrl-K at the end kills nothing, so Ctrl-Y yanks nothing",
            initial: "abcd", keys: [ctrl("e"), ctrl("k"), ctrl("y")], expected: "abcd"),
    ]
}

@MainActor
@Suite("A field answers the editor's Control chords")
struct TextFieldControlChordTests {

    /// The editor rows are the reference: they pass on their own, and a
    /// script whose expectation the editor does not meet is a wrong script,
    /// not a field bug.
    @Test("Each chord edits one line the way the editor edits it",
          arguments: ChordHost.allCases, ChordScript.all)
    func chordEditsTheLine(host: ChordHost, script: ChordScript) {
        let played = play(script.keys, into: host, from: script.initial)
        #expect(played.text == script.expected(in: host), "\(host): \(script.name)")
        #expect(played.unconsumed.isEmpty, "\(host) let keys \(played.unconsumed) fall through the chain")
    }

    /// The editor's chords for other lines, Ctrl-O to open one and Ctrl-P and
    /// Ctrl-N to go to one, have nothing to act on in a single-line field. The
    /// field declines them, so each leaves the text and the caret alone and
    /// goes on down the input chain, which binds none of them either: the key
    /// is the app's to use.
    @Test("Ctrl-O, Ctrl-P and Ctrl-N pass on in a field", arguments: ChordHost.fields)
    func otherLineChordsPassOn(host: ChordHost) {
        for letter: Character in ["o", "p", "n"] {
            let played = play(
                [ctrl("a"), KeyEvent(key: .right), ctrl(letter), typed("X")], into: host, from: "abcd")
            #expect(played.text == "aXbcd", "\(host): Ctrl-\(letter) moved the caret or edited")
            #expect(played.unconsumed == [2], "\(host): some layer took Ctrl-\(letter)")
        }
    }

    /// The field has an undo stack, which the editor does not, so an edit made
    /// by a chord must land on it like an edit made by any other key.
    ///
    /// Each edit is checked DONE before it is checked undone: an edit that
    /// never happened is trivially "undone", and the kill and transpose rows
    /// passed on a field that ignored both chords until they were.
    @Test("Ctrl-Z undoes a kill, a transpose and a yank", arguments: ChordHost.fields)
    func chordsAreUndoable(host: ChordHost) {
        let kill = [ctrl("a"), ctrl("f"), ctrl("k")]
        #expect(play(kill, into: host, from: "abcd").text == "a", "precondition: the kill")
        #expect(
            play(kill + [ctrl("z")], into: host, from: "abcd").text == "abcd",
            "the kill was not undoable")

        let swap = [ctrl("a"), ctrl("f"), ctrl("t")]
        #expect(play(swap, into: host, from: "abcd").text == "bacd", "precondition: the transpose")
        #expect(
            play(swap + [ctrl("z")], into: host, from: "abcd").text == "abcd",
            "the transpose was not undoable")

        // A secure field keeps no kill, so it has no yank to undo.
        guard host.keepsAKill else { return }
        let yank = kill + [ctrl("y")]
        #expect(play(yank, into: host, from: "abcd").text == "abcd", "precondition: the yank")
        #expect(
            play(yank + [ctrl("z")], into: host, from: "abcd").text == "a",
            "the yank was not undoable on its own")
    }

    /// Ctrl-D is the Delete key under another name, and in a field the Delete
    /// key takes a selection with it.
    @Test("Ctrl-D deletes a selection, as the Delete key does", arguments: ChordHost.fields)
    func deleteForwardTakesTheSelection(host: ChordHost) {
        let played = play([ctrl("a"), shiftRight, shiftRight, ctrl("d")], into: host, from: "abcd")
        #expect(played.text == "cd")
    }

    /// Ctrl-K starts from the caret, as the motions do: with "ab" selected and
    /// the caret after the "b", it kills "cd" and drops the selection. The
    /// typed X lands at the caret rather than replacing "ab", and a yank at
    /// the start shows what the kill took.
    @Test(
        "Ctrl-K with a selection kills from the caret and drops the selection",
        arguments: ChordHost.fields)
    func killWithASelection(host: ChordHost) {
        let select = [ctrl("a"), shiftRight, shiftRight]
        #expect(play(select + [ctrl("k"), typed("X")], into: host, from: "abcd").text == "abX")
        #expect(
            play(select + [ctrl("k"), ctrl("a"), ctrl("y")], into: host, from: "abcd").text
                == (host.keepsAKill ? "cdab" : "ab"))
    }

    /// Ctrl-T starts from the caret too: with "ab" selected and the caret
    /// after the "b", it swaps "b" and "c" and steps on, and the typed X lands
    /// after them rather than replacing a selection.
    @Test(
        "Ctrl-T with a selection swaps at the caret and drops the selection",
        arguments: ChordHost.fields)
    func transposeWithASelection(host: ChordHost) {
        let played = play(
            [ctrl("a"), shiftRight, shiftRight, ctrl("t"), typed("X")], into: host, from: "abcd")
        #expect(played.text == "acbXd")
    }

    /// Ctrl-Y inserts, as a paste does, so it replaces a selection. The kill
    /// ring holds "bcd", and "xy" of "axyz" is selected: the yank leaves
    /// "abcdz", with the caret after the yanked text.
    @Test(
        "Ctrl-Y replaces a selection, as a paste does",
        arguments: ChordHost.fields.filter(\.keepsAKill))
    func yankReplacesTheSelection(host: ChordHost) {
        let fill = [ctrl("a"), ctrl("f"), ctrl("k"), typed("x"), typed("y"), typed("z")]
        let select = [ctrl("a"), ctrl("f"), shiftRight, shiftRight]
        let played = play(fill + select + [ctrl("y"), typed("X")], into: host, from: "abcd")
        #expect(played.text == "abcdXz")
    }

    /// With the pop-up open and a row highlighted, the chords still edit the
    /// field: the menu consumes the arrows and Return, never a Control chord.
    @Test("The chords edit a field whose suggestions are showing")
    func chordsWithTheSuggestionsOpen() {
        let played = play(
            [KeyEvent(key: .down), ctrl("a"), ctrl("f"), ctrl("k")],
            into: .suggestionsField, from: "abcd")
        #expect(played.text == "a")
        #expect(played.unconsumed.isEmpty)
    }

    /// The sweep behind the scripts: every Control chord the editor binds, a
    /// field binds too, except the three about other lines, which a field
    /// declines. Handler level, because the question is what the control
    /// claims; the chain would answer for layer 4 too, which takes an unclaimed
    /// Ctrl-Z as the shell's suspend.
    @Test("Every Control chord the editor binds, a field binds too, but the other-line ones")
    func fieldBindsWhatTheEditorBinds() {
        let otherLines: Set<Character> = ["o", "p", "n"]
        for scalar in UnicodeScalar("a").value...UnicodeScalar("z").value {
            let letter = Character(UnicodeScalar(scalar)!)
            let editor = TextEditorHandler(focusID: "editor", text: .constant("abcd"))
            let field = TextFieldHandler(focusID: "field", text: .constant("abcd"))
            // Never the real pasteboard: Ctrl-V pastes in a field.
            field.clipboard = FakeClipboard().access
            guard editor.handleKeyEvent(ctrl(letter)) else { continue }
            if otherLines.contains(letter) {
                #expect(!field.handleKeyEvent(ctrl(letter)), "a field took Ctrl-\(letter)")
            } else {
                #expect(
                    field.handleKeyEvent(ctrl(letter)), "Ctrl-\(letter) works in the editor, not in a field")
            }
        }
    }
}
