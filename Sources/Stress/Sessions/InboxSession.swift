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

    var body: some View {
        let shown = inbox.shown
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(shown.count) of \(inbox.items.count) · \(inbox.items.count { $0.done }) done")
            List(selection: Binding(get: { inbox.selection }, set: { inbox.selection = $0 })) {
                ForEach(shown) { item in InboxRow(item: item) }
            }
            .searchable(text: Binding(get: { inbox.query }, set: { inbox.query = $0 }))
        }
        .onKeyPress(keys: [.space]) { _ in
            guard let id = inbox.selection, let index = inbox.items.firstIndex(where: { $0.id == id })
            else { return false }
            inbox.items[index].done.toggle()
            return true
        }
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

// MARK: - The script

/// Someone working through a busy inbox: moving down it, marking things done,
/// searching, while items arrive, leave, move and change underneath.
@MainActor
final class InboxSession: StressSession {
    private let inbox: Inbox
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
            return SessionStep(action: "search", keys: [pending.removeFirst()])
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
            // Into the search field, a few letters that narrow the list, then
            // cleared and back to the list: one key a step, as typed.
            let letters = (0..<random.within(1...3)).map { _ in
                KeyEvent(key: .character(Character(UnicodeScalar(UInt8(97 + random.below(26))))))
            }
            pending = letters + Array(repeating: KeyEvent(key: .backspace), count: letters.count)
                + [KeyEvent(key: .tab)]
            return SessionStep(action: "search", keys: [KeyEvent(key: .tab)])
        case "sort":
            inbox.items.sort { $0.title < $1.title }
            return SessionStep(action: "sort")
        default:
            inbox.items.removeAll { $0.done }
            return SessionStep(action: "sweep")
        }
    }

    /// The counts over the list are the model's: what the search leaves, what
    /// there is, and what is done.
    func check(_ screen: [String], after index: Int) -> String? {
        let counts = "\(inbox.shown.count) of \(inbox.items.count) · \(inbox.items.count { $0.done }) done"
        return screen.contains { $0.hasPrefix(counts) } ? nil : "the counts do not say \(counts)"
    }

    static let descriptor = SessionDescriptor(
        id: "inbox",
        summary: "a searchable, selectable list of items that arrive, leave, move and change underneath",
        exercises:
            "keyed rows inserted, deleted and moved around the selection, the row memo, List windowing, "
            + "a search narrowing and restoring the collection, focus between a field and a list",
        make: { config, width, height, cold in
            DrivenSession(InboxSession(config: config), width: width, height: height, cold: cold)
        })
}
