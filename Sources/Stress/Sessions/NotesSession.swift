//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NotesSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The notebook

/// Notes, and where the person is among them: which tab, which note is open,
/// and whether a note is being written or a deletion confirmed.
@Observable
@MainActor
final class Notebook {
    struct Note: Identifiable, Equatable {
        let id: Int
        var title: String
        var text: String
        var archived = false
    }

    var notes: [Note]
    var tab = 0
    /// The open notes, by id: the navigation path.
    var path: [Int] = []
    var composing = false
    var draftTitle = ""
    /// The note a deletion is waiting to be confirmed for.
    var deleting: Int?
    private(set) var nextID: Int

    init(notes: [Note]) {
        self.notes = notes
        nextID = notes.count
    }

    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    var active: [Note] { notes.filter { !$0.archived } }
    var archived: [Note] { notes.filter(\.archived) }

    func index(of id: Int) -> Int? { notes.firstIndex { $0.id == id } }

    /// Files the note being written, if it has a title.
    func compose() {
        if !draftTitle.isEmpty {
            notes.insert(Note(id: makeID(), title: draftTitle, text: ""), at: 0)
        }
        draftTitle = ""
        composing = false
    }

    /// Deletes the note the deletion was confirmed for.
    func delete() {
        if let id = deleting, let index = index(of: id) {
            notes.remove(at: index)
            path.removeAll { $0 == id }
        }
        deleting = nil
    }
}

// MARK: - The page

/// Two tabs: notes in a navigation stack, each opening into an editor, and the
/// archive in a list. Over them, a sheet to write a new note and an alert to
/// confirm a deletion.
struct NotesPage: View {
    let book: Notebook

    var body: some View {
        TabView(selection: bind(\.tab)) {
            Tab("Notes", value: 0) {
                NavigationStack(path: bind(\.path)) {
                    NoteList(book: book)
                        .navigationDestination(for: Int.self) { id in NoteDetail(book: book, id: id) }
                }
            }
            Tab("Archive", value: 1) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(book.archived.count) archived")
                    List {
                        ForEach(book.archived) { note in NoteRow(note: note) }
                    }
                }
            }
        }
        .sheet(isPresented: bind(\.composing)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "New note")
                TextField("Title", text: bind(\.draftTitle)).onSubmit { book.compose() }
            }
            .padding(1)
        }
        .alert(
            "Delete note?",
            isPresented: Binding(get: { book.deleting != nil }, set: { if !$0 { book.deleting = nil } })
        ) {
            Button("Delete", role: .destructive) { book.delete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<Notebook, Value>) -> Binding<Value> {
        Binding(get: { book[keyPath: keyPath] }, set: { book[keyPath: keyPath] = $0 })
    }
}

/// The notes not archived, each a link that opens it.
private struct NoteList: View {
    let book: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(book.active.count) notes")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(book.active) { note in
                        NavigationLink(value: note.id) { NoteRow(note: note) }
                    }
                }
            }
        }
        .navigationTitle("Notes")
    }
}

/// A note's title, and its number at the trailing edge — how the session tells
/// which notes are on the screen.
private struct NoteRow: View {
    let note: Notebook.Note

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: note.title)
            Spacer()
            Text(verbatim: "#\(note.id)").foregroundStyle(Color.gray)
        }
    }
}

/// One note, open: its title and number over an editor of its text — or word
/// that it is gone, when it was deleted or archived while open.
private struct NoteDetail: View {
    let book: Notebook
    let id: Int

    var body: some View {
        if let index = book.index(of: id) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(book.notes[index].title)  #\(id)").bold()
                TextEditor(
                    text: Binding(
                        get: { book.notes[index].text },
                        set: { value in
                            if let index = book.index(of: id) { book.notes[index].text = value }
                        }))
            }
            .navigationTitle(book.notes[index].title)
        } else {
            Text(verbatim: "Note #\(id) is gone")
        }
    }
}

// MARK: - The script

/// Someone keeping notes: opening one and writing in it, going back, writing
/// a new one in a sheet, deleting one with a confirmation, looking in the
/// archive with a click on its tab, wheeling through the list — while notes
/// sync in, change and get archived from another device.
@MainActor
final class NotesSession: StressSession {
    private let book: Notebook
    private var random: SessionRandom
    /// The steps still to come of an activity under way.
    private var pending: [SessionStep] = []
    /// The screen as it stood before this step.
    private var screen: [String] = []

    init(config: StressConfig) {
        let seed = config.seed
        book = Notebook(
            notes: (0..<config.sized(60)).map { index in
                let h = mix(seed, index)
                return Notebook.Note(
                    id: index, title: Synth.sentence(h, words: 2 + Int(h % 4)),
                    text: Synth.sentence(h >> 8, words: 10 + Int(h % 40)), archived: h.isMultiple(of: 5))
            })
        random = SessionRandom(seed: seed ^ 0x9073)
    }

    var page: NotesPage { NotesPage(book: book) }

    var looksBeforeEachStep: Bool { true }

    func look(at screen: [String]) { self.screen = screen }

    func step(_ index: Int) -> SessionStep {
        if !pending.isEmpty { return pending.removeFirst() }
        if book.composing || book.deleting != nil {
            // A modal left up by a script that ran out: close it.
            return SessionStep(action: "dismiss", keys: [KeyEvent(key: .escape)])
        }
        if book.tab == 1 {
            return archiveStep()
        }
        return book.path.isEmpty ? listStep() : detailStep()
    }

    /// On the list of notes.
    private func listStep() -> SessionStep {
        switch random.pick([
            ("walk", 20), ("open", 12), ("deeplink", 5), ("compose", 6), ("delete", 5),
            ("wheel", 10), ("archive-tab", 6), ("sync", 16), ("quiet", 10),
        ]) {
        case "walk":
            // Tab from link to link, as a person reading down the list does.
            return SessionStep(action: "walk", keys: Array(repeating: KeyEvent(key: .tab), count: random.within(1...4)))
        case "open":
            return SessionStep(action: "open", keys: [KeyEvent(key: .enter)])
        case "deeplink":
            // A note opened from outside: a notification, a search result.
            let active = book.active
            guard !active.isEmpty else { return SessionStep(action: "quiet") }
            book.path = [active[random.below(active.count)].id]
            return SessionStep(action: "open")
        case "compose":
            book.composing = true
            let title = Synth.sentence(random.next(), words: random.within(1...4))
            pending = title.map { SessionStep(action: "type", keys: [$0 == " " ? KeyEvent(key: .space) : KeyEvent(key: .character($0))]) }
            pending.append(SessionStep(action: "compose", keys: [KeyEvent(key: random.below(5) == 0 ? .escape : .enter)]))
            return SessionStep(action: "compose")
        case "delete":
            let active = book.active
            guard !active.isEmpty else { return SessionStep(action: "quiet") }
            // A delete command on a note; the alert asks, and the person says
            // yes with Return or thinks better of it with Escape.
            book.deleting = active[random.below(active.count)].id
            pending = [SessionStep(action: "delete", keys: [KeyEvent(key: random.below(3) == 0 ? .escape : .enter)])]
            return SessionStep(action: "delete")
        case "wheel":
            return wheel()
        case "archive-tab":
            return click("Archive", action: "tab")
        case "sync":
            return sync()
        default:
            return SessionStep(action: "quiet")
        }
    }

    /// In an open note.
    private func detailStep() -> SessionStep {
        switch random.pick([("type", 50), ("back", 12), ("sync", 12), ("quiet", 8), ("newline", 6)]) {
        case "type":
            let text = Synth.sentence(random.next(), words: random.within(1...3)) + " "
            return SessionStep(
                action: "type", keys: text.map { $0 == " " ? KeyEvent(key: .space) : KeyEvent(key: .character($0)) })
        case "newline":
            return SessionStep(action: "type", keys: [KeyEvent(key: .enter)])
        case "back":
            return SessionStep(action: "back", keys: [KeyEvent(key: .escape)])
        case "sync":
            return sync()
        default:
            return SessionStep(action: "quiet")
        }
    }

    /// On the archive.
    private func archiveStep() -> SessionStep {
        switch random.pick([("notes-tab", 30), ("wheel", 20), ("sync", 25), ("quiet", 25)]) {
        case "notes-tab":
            return click("Notes", action: "tab")
        case "wheel":
            return wheel()
        case "sync":
            return sync()
        default:
            return SessionStep(action: "quiet")
        }
    }

    /// A change from another device: a note arrives, is retitled, archived or
    /// brought back.
    private func sync() -> SessionStep {
        switch random.below(4) {
        case 0:
            let h = random.next()
            book.notes.insert(
                Notebook.Note(id: book.makeID(), title: Synth.sentence(h, words: 2 + Int(h % 4)), text: ""),
                at: random.below(book.notes.count + 1))
        case 1:
            if !book.notes.isEmpty {
                book.notes[random.below(book.notes.count)].title = Synth.sentence(random.next(), words: random.within(1...5))
            }
        default:
            if !book.notes.isEmpty { book.notes[random.below(book.notes.count)].archived.toggle() }
        }
        return SessionStep(action: "sync")
    }

    /// A press and release of the left button on `text` where it is drawn, or
    /// nothing when it is not on the screen.
    private func click(_ text: String, action: String) -> SessionStep {
        guard let (x, y) = locate(text) else { return SessionStep(action: action) }
        return SessionStep(
            action: action,
            mouse: [
                MouseEvent(button: .left, phase: .pressed, x: x, y: y),
                MouseEvent(button: .left, phase: .released, x: x, y: y),
            ])
    }

    /// A few notches of the wheel over a row of the list.
    private func wheel() -> SessionStep {
        guard let (x, y) = locate("#") else { return SessionStep(action: "wheel") }
        let button: MouseButton = random.below(3) == 0 ? .scrollUp : .scrollDown
        return SessionStep(
            action: "wheel",
            mouse: Array(repeating: MouseEvent(button: button, phase: .scrolled, x: x, y: y), count: random.within(1...4)))
    }

    /// Where `text` is first drawn on the screen, in cells.
    private func locate(_ text: String) -> (x: Int, y: Int)? {
        for (y, line) in screen.enumerated() {
            if let range = line.range(of: text) {
                return (line.distance(from: line.startIndex, to: range.lowerBound), y)
            }
        }
        return nil
    }

    /// What must be on the screen: the modal that is up, the open note, or the
    /// count over whichever list is showing.
    func check(_ screen: [String], after index: Int) -> String? {
        func shows(_ text: String) -> Bool { screen.contains { $0.contains(text) } }
        if book.deleting != nil {
            return shows("Delete note?") ? nil : "a deletion is waiting for an answer, but no alert asks"
        }
        if book.composing {
            return shows("New note") ? nil : "a note is being written, but the sheet is not up"
        }
        if book.tab == 1 {
            let count = "\(book.archived.count) archived"
            return shows(count) ? nil : "the archive is showing, but not \(count)"
        }
        if let id = book.path.last {
            let expected = book.index(of: id) == nil ? "Note #\(id) is gone" : "#\(id)"
            return shows(expected) ? nil : "note #\(id) is open, but its screen does not show \(expected)"
        }
        let count = "\(book.active.count) notes"
        return shows(count) ? nil : "the list is showing, but not \(count)"
    }

    static let descriptor = SessionDescriptor(
        id: "notes",
        summary: "notes opened, written in and closed, a sheet to write one, an alert to delete one, two tabs",
        exercises:
            "navigation push and pop by keyboard and by path, a text editor typed into, a sheet and an alert "
            + "over the page, a tab switched with a mouse click, the wheel over a list, rows changing underneath",
        make: { config, width, height, cold in
            DrivenSession(NotesSession(config: config), width: width, height: height, cold: cold)
        })
}
