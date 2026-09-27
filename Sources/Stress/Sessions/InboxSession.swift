//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InboxSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The inbox

/// A list of items that arrive, leave, move, change and are marked done — and
/// the selection and search query over it. What the page reads, and what its
/// controls and the session write.
@Observable
@MainActor
final class Inbox {
    struct Item: Identifiable, Equatable {
        let id: Int
        var title: String
        var tag: String
        var done = false
    }

    var items: [Item]
    var selection: Int?
    var query = ""
    private(set) var nextID: Int

    init(items: [Item]) {
        self.items = items
        nextID = items.count
        selection = items.first?.id
    }

    /// A new item's id, never used before.
    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// The items the query leaves, in order.
    var shown: [Item] {
        query.isEmpty ? items : items.filter { $0.title.contains(query) }
    }

    /// Words from the titles that begin with what has been typed — at most
    /// five, and none until something has been — as a search field offers
    /// completions. Empty as often as not, so the field's menu comes and goes.
    var suggestedWords: [String] {
        guard !query.isEmpty else { return [] }
        var words: [String] = []
        for item in items {
            for word in item.title.split(separator: " ") where word.hasPrefix(query) && word != query {
                let word = String(word)
                if !words.contains(word) { words.append(word) }
                if words.count == 5 { return words }
            }
        }
        return words
    }
}

// MARK: - The page

/// A count over a searchable, selectable list of items; Space marks the
/// selected one done.
///
/// Keyed by the items' stable ids, so rows keep their identity as others
/// arrive, leave and move around them — the case the row memo is keyed for —
/// while a search narrows the collection and widens it again.
struct InboxPage: View {
    let inbox: Inbox
    /// Whether the selection is bound through `@Bindable`, as an app binds an
    /// `@Observable`'s property (`inbox-observable`), rather than through a
    /// closure pair.
    var bindsThroughBindable = false

    var body: some View {
        let shown = inbox.shown
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(shown.count) of \(inbox.items.count) · \(inbox.items.count { $0.done }) done")
            List(selection: selection) {
                ForEach(shown) { item in InboxRow(item: item) }
            }
            .searchable(text: Binding(get: { inbox.query }, set: { inbox.query = $0 }))
            .searchSuggestions {
                ForEach(inbox.suggestedWords, id: \.self) { word in Text(verbatim: word) }
            }
        }
        .onKeyPress(keys: [.space]) { _ in
            guard let id = inbox.selection, let index = inbox.items.firstIndex(where: { $0.id == id })
            else { return false }
            inbox.items[index].done.toggle()
            return true
        }
    }
}

extension InboxPage {
    /// The list's selection binding.
    private var selection: Binding<Int?> {
        bindsThroughBindable
            ? Bindable(inbox).selection : Binding(get: { inbox.selection }, set: { inbox.selection = $0 })
    }
}

/// One item: done or not, its title, and its tag at the trailing edge.
private struct InboxRow: View {
    let item: Inbox.Item

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: item.done ? "[x]" : "[ ]")
            Text(verbatim: item.title)
            Spacer()
            Text(verbatim: item.tag).foregroundStyle(Color.gray)
        }
    }
}

// Every field compared, as the synthesized `==` does: a row equal to the one
// drawn draws the same, which is what Option C asks of a row before it
// re-checks it after a write above it. Isolated, as the view is.
extension InboxRow: @MainActor Equatable {}

// MARK: - The script

/// Someone working through a busy inbox: moving down it, marking things done,
/// searching, while items arrive, leave, move and change underneath.
@MainActor
final class InboxSession: StressSession {
    let inbox: Inbox
    /// Whether the counts may be drawn anywhere on a line rather than at its
    /// start: inside a pushed screen or a sheet, which the variants put the
    /// page in.
    var countsAnywhere = false
    /// Whether the script types into the search field. A variant whose focus
    /// cycle is not the page's own (a pushed screen adds its crumb bar) leaves
    /// it out: its search steps are quiet, but as many and making the same
    /// draws, so every other step is the one `inbox` plays at that index.
    var searches = true
    private var random: SessionRandom
    /// The keys still to come of a search being typed and then cleared.
    private var pending: [KeyEvent] = []

    init(config: StressConfig) {
        let seed = config.seed
        inbox = Inbox(
            items: (0..<config.sized(400)).map { index in
                let h = mix(seed, index)
                return Inbox.Item(
                    id: index, title: Synth.sentence(h, words: 2 + Int(h % 6)), tag: Synth.status(h))
            })
        random = SessionRandom(seed: seed ^ 0x1B0C)
    }

    var page: InboxPage { InboxPage(inbox: inbox) }

    func step(_ index: Int) -> SessionStep {
        // The search field is the first focusable view, so it holds the focus
        // when the page opens; the list is a Tab away.
        if index == 0 {
            return SessionStep(action: "focus", keys: [KeyEvent(key: .tab)])
        }
        if !pending.isEmpty {
            let key = pending.removeFirst()
            return searches ? SessionStep(action: "search", keys: [key]) : SessionStep(action: "quiet")
        }
        switch random.pick([
            ("down", 22), ("up", 8), ("page", 5), ("toggle", 10), ("arrive", 12), ("leave", 6),
            ("move", 8), ("rename", 10), ("search", 5), ("sort", 2), ("sweep", 2),
        ]) {
        case "down", "up":
            // The arrows move the list's cursor; Return makes the row under it
            // the selection, which Space then marks done.
            let key: Key = index.isMultiple(of: 4) ? .up : .down
            return SessionStep(
                action: "select",
                keys: Array(repeating: KeyEvent(key: key), count: random.within(1...3)) + [KeyEvent(key: .enter)])
        case "page":
            return SessionStep(action: "page", keys: [KeyEvent(key: random.below(3) == 0 ? .pageUp : .pageDown)])
        case "toggle":
            return SessionStep(action: "toggle", keys: [KeyEvent(key: .space)])
        case "arrive":
            let h = random.next()
            inbox.items.insert(
                Inbox.Item(id: inbox.makeID(), title: Synth.sentence(h, words: 2 + Int(h % 6)), tag: Synth.status(h)),
                at: random.below(inbox.items.count + 1))
            return SessionStep(action: "arrive")
        case "leave":
            guard !inbox.items.isEmpty else { return SessionStep(action: "leave") }
            inbox.items.remove(at: random.below(inbox.items.count))
            return SessionStep(action: "leave")
        case "move":
            guard inbox.items.count > 1 else { return SessionStep(action: "move") }
            let item = inbox.items.remove(at: random.below(inbox.items.count))
            inbox.items.insert(item, at: random.below(inbox.items.count + 1))
            return SessionStep(action: "move")
        case "rename":
            guard !inbox.items.isEmpty else { return SessionStep(action: "rename") }
            let h = random.next()
            inbox.items[random.below(inbox.items.count)].title = Synth.sentence(h, words: 1 + Int(h % 9))
            return SessionStep(action: "rename")
        case "search":
            return search()
        case "sort":
            inbox.items.sort { $0.title < $1.title }
            return SessionStep(action: "sort")
        default:
            inbox.items.removeAll { $0.done }
            return SessionStep(action: "sweep")
        }
    }

    /// Into the search field, a few letters that narrow the list, then
    /// cleared and back to the list: one key a step, as typed. When the
    /// session does not search, the same letters are drawn and as many steps
    /// are quiet, so the script goes on as `inbox`'s does: typing depends on
    /// where the Tab cycle lands, which a pushed screen's crumb bar changes,
    /// and `inbox-pushed` leaves it out.
    private func search() -> SessionStep {
        let letters = (0..<random.within(1...3)).map { _ in
            KeyEvent(key: .character(Character(UnicodeScalar(UInt8(97 + random.below(26))))))
        }
        pending = letters + Array(repeating: KeyEvent(key: .backspace), count: letters.count)
            + [KeyEvent(key: .tab)]
        return searches ? SessionStep(action: "search", keys: [KeyEvent(key: .tab)]) : SessionStep(action: "quiet")
    }

    /// The counts over the list are the model's: what the search leaves, what
    /// there is, and what is done.
    func check(_ screen: [String], after index: Int) -> String? {
        let counts = "\(inbox.shown.count) of \(inbox.items.count) · \(inbox.items.count { $0.done }) done"
        return screen.contains { countsAnywhere ? $0.contains(counts) : $0.hasPrefix(counts) }
            ? nil : "the counts do not say \(counts)"
    }

    static let descriptor = SessionDescriptor(
        id: "inbox",
        summary: "a searchable, selectable list of items that arrive, leave, move and change underneath",
        exercises:
            "keyed rows inserted, deleted and moved around the selection, the row memo, List windowing, "
            + "a search narrowing and restoring the collection, search suggestions that come and go as "
            + "the query is typed, focus between a field and a list",
        make: { config, width, height, cold in
            DrivenSession(InboxSession(config: config), width: width, height: height, cold: cold)
        })
}
