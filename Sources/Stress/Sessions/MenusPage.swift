//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenusPage.swift
//
//  The `menus` session's page and model: a document manager whose every
//  command is in a menu of some kind.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The desk

/// Documents, and what the menus have done to them.
@Observable
@MainActor
final class MenuDesk {
    struct Document: Identifiable, Equatable {
        let id: Int
        var name: String
        /// An index into ``MenuDesk/statuses``.
        var status: Int
    }

    /// What a document can be, in order.
    static let statuses = ["draft", "review", "final"]
    /// The status filter's options: every status, or one.
    static let filters = ["Any status", "Drafts only", "In review only", "Finals only"]
    /// The tags the tag field suggests. Words nothing else on the page draws, so
    /// one on the screen with the suggestions closed is the menu's residue.
    static let tags = ["urgent", "undecided", "unfunded", "later", "legal", "lunar", "blocked", "bespoke"]
    /// The zoom levels the View menu steps through.
    static let zooms = [50, 75, 100, 125, 150, 200]

    var documents: [Document]
    var filter = 0
    var tag = ""
    var zoom = 2
    var ascending = true
    /// Every command a menu ran, counted: what "applied exactly once" is
    /// judged by.
    private(set) var applied = 0
    /// The last command run, as the status line shows it.
    private(set) var last = "—"
    /// The documents reopened lately, newest first: the File menu's own items,
    /// which change while it is open.
    var recent: [Int] = []
    private(set) var nextID: Int

    init(documents: [Document]) {
        self.documents = documents
        nextID = documents.count
    }

    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// The documents the filter lets through, in the chosen order.
    var shown: [Document] {
        let kept = filter == 0 ? documents : documents.filter { $0.status == filter - 1 }
        return ascending ? kept : kept.reversed()
    }

    /// Notes that a command ran.
    func ran(_ command: String) {
        applied += 1
        last = command
    }

    func index(of id: Int) -> Int? { documents.firstIndex { $0.id == id } }

    /// The tag suggestions for what has been typed: the tags it is a prefix of.
    var suggestions: [String] {
        tag.isEmpty ? Self.tags : Self.tags.filter { $0.hasPrefix(tag) && $0 != tag }
    }
}

/// Where the focus is, as the page's `@FocusState` reads it — shown on the
/// status line so the session can see where a closed menu left it.
enum MenuDeskFocus: Hashable {
    case file, filter, view, tag, export, help, jump
    case row(Int)

    var name: String {
        switch self {
        case .file: "file"
        case .filter: "filter"
        case .view: "view"
        case .tag: "tag"
        case .export: "export"
        case .help: "help"
        case .jump: "jump"
        case .row(let id): "row \(id)"
        }
    }
}

// MARK: - The page

/// A toolbar of pop-up menus across the top — one at each end — with a status
/// filter drop-down and a tag field that suggests; the documents below, each
/// with a context menu; an inline menu down the side; and two more pop-up
/// menus along the bottom edge, one in each corner. Every command lands on
/// ``MenuDesk/ran(_:)``.
struct MenusPage: View {
    let desk: MenuDesk
    @FocusState private var focus: MenuDeskFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            HStack(alignment: .top, spacing: 1) {
                Menu("Jump") {
                    Button("Jump First") { jump(toFirst: true) }
                    Button("Jump Last") { jump(toFirst: false) }
                }
                .menuStyle(.inline)
                .focused($focus, equals: .jump)
                documentList
            }
            Spacer(minLength: 0)
            bottomBar
            Text(verbatim: statusLine).lineLimit(1)
        }
        .appHeader { Text(verbatim: "Documents · zoom \(MenuDesk.zooms[desk.zoom])%") }
    }

    /// Where the focus is, first — so a narrow terminal cuts the rest — then
    /// what the menus did: the last command in lower case, so a menu's own
    /// label on the screen is never the status line's.
    private var statusLine: String {
        "[\(focus?.name ?? "none")] \(desk.applied) applied · tag \(desk.tag.isEmpty ? "—" : desk.tag) · last "
            + desk.last.lowercased()
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            Menu("File") {
                Button("New Document") {
                    desk.documents.insert(
                        MenuDesk.Document(id: desk.makeID(), name: "untitled", status: 0), at: 0)
                    desk.ran("New Document")
                }
                Button("Sort Ascending") {
                    desk.ascending = true
                    desk.ran("Sort Ascending")
                }
                Button("Sort Descending") {
                    desk.ascending = false
                    desk.ran("Sort Descending")
                }
                if !desk.recent.isEmpty {
                    Divider()
                    ForEach(desk.recent, id: \.self) { id in
                        Button("Reopen #\(id)") { desk.ran("Reopen #\(id)") }
                    }
                }
            }
            .focused($focus, equals: .file)
            Picker("Status", selection: bind(\.filter)) {
                ForEach(MenuDesk.filters.indices, id: \.self) { index in
                    Text(verbatim: MenuDesk.filters[index]).tag(index)
                }
            }
            .pickerStyle(.menu)
            .focused($focus, equals: .filter)
            TextField("Tag", text: bind(\.tag))
                .onSubmit { desk.ran("Tag \(desk.tag)") }
                .textInputSuggestions { ForEach(desk.suggestions, id: \.self) { Text(verbatim: $0) } }
                .focused($focus, equals: .tag)
                .frame(width: 18)
            Spacer()
            Menu("View") {
                Button("Zoom In") {
                    desk.zoom = min(MenuDesk.zooms.count - 1, desk.zoom + 1)
                    desk.ran("Zoom In")
                }
                Button("Zoom Out") {
                    desk.zoom = max(0, desk.zoom - 1)
                    desk.ran("Zoom Out")
                }
                Button("Actual Size") {
                    desk.zoom = 2
                    desk.ran("Actual Size")
                }
            }
            .focused($focus, equals: .view)
        }
    }

    private var documentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(desk.shown) { document in
                    DocumentRow(document: document)
                        .contextMenu {
                            Button("Rename #\(document.id)") { rename(document.id) }
                            Button("Promote #\(document.id)") { promote(document.id) }
                            Divider()
                            Button("Trash #\(document.id)", role: .destructive) { trash(document.id) }
                        }
                        .focused($focus, equals: .row(document.id))
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 1) {
            Menu("Export") {
                Button("Export PDF") { desk.ran("Export PDF") }
                Button("Export HTML") { desk.ran("Export HTML") }
                Button("Export Plain Text") { desk.ran("Export Plain Text") }
                Button("Export Everything As One Long Archive") { desk.ran("Export Archive") }
            }
            .focused($focus, equals: .export)
            Spacer()
            Menu("Help") {
                Button("Show Shortcuts") { desk.ran("Show Shortcuts") }
                Button("About Documents") { desk.ran("About Documents") }
            }
            .focused($focus, equals: .help)
        }
    }

    private func jump(toFirst: Bool) {
        desk.ran(toFirst ? "Jump First" : "Jump Last")
    }

    private func rename(_ id: Int) {
        guard let index = desk.index(of: id) else { return }
        desk.documents[index].name += "!"
        desk.recent.removeAll { $0 == id }
        desk.recent.insert(id, at: 0)
        if desk.recent.count > 3 { desk.recent.removeLast() }
        desk.ran("Rename #\(id)")
    }

    private func promote(_ id: Int) {
        guard let index = desk.index(of: id) else { return }
        desk.documents[index].status = min(MenuDesk.statuses.count - 1, desk.documents[index].status + 1)
        desk.ran("Promote #\(id)")
    }

    private func trash(_ id: Int) {
        guard let index = desk.index(of: id) else { return }
        desk.documents.remove(at: index)
        desk.recent.removeAll { $0 == id }
        desk.ran("Trash #\(id)")
    }

    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<MenuDesk, Value>) -> Binding<Value> {
        Binding(get: { desk[keyPath: keyPath] }, set: { desk[keyPath: keyPath] = $0 })
    }
}

/// A document: its name, its status, and its number — how the session finds
/// it on the screen.
private struct DocumentRow: View {
    let document: MenuDesk.Document

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: document.name)
            Spacer()
            Text(verbatim: MenuDesk.statuses[document.status]).foregroundStyle(Color.gray)
            Text(verbatim: "#\(document.id)")
        }
    }
}

// Every field compared, as the synthesized `==` does. Isolated, as the view is.
extension DocumentRow: @MainActor Equatable {}
