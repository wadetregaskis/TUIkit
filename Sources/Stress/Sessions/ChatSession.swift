//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChatSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The conversation

/// A conversation: its messages, and the one being written.
@Observable
@MainActor
final class Conversation {
    struct Message: Identifiable, Equatable {
        let id: Int
        let mine: Bool
        var text: String
        var edited = false
    }

    var messages: [Message]
    var draft = ""
    private(set) var nextID: Int

    init(messages: [Message]) {
        self.messages = messages
        nextID = messages.count
    }

    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Sends the draft, if there is one.
    func send() {
        guard !draft.isEmpty else { return }
        messages.append(Message(id: makeID(), mine: true, text: draft))
        draft = ""
    }
}

// MARK: - The page

/// Messages as bubbles — others' at the leading edge, mine at the trailing —
/// in a scroll view that opens at its end, over a field to write the next.
struct ChatPage: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(conversation.messages.count) messages")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(conversation.messages) { message in Bubble(message: message) }
                }
            }
            .defaultScrollAnchor(.bottom)
            TextField("Message", text: Binding(get: { conversation.draft }, set: { conversation.draft = $0 }))
                .onSubmit { conversation.send() }
        }
    }
}

/// One message in a bordered bubble, pushed to its author's side by a frame
/// that fills the row — the filler a scroll view has to measure sensibly. It
/// ends with the message's number, which is how the session tells which
/// messages are on the screen.
private struct Bubble: View {
    let message: Conversation.Message

    var body: some View {
        Text(verbatim: message.text + (message.edited ? "  (edited)" : "") + "  #\(message.id)")
            .frame(maxWidth: .fixed(60), alignment: .leading)
            .padding(.horizontal, 1)
            .border()
            .frame(maxWidth: .infinity, alignment: message.mine ? .trailing : .leading)
    }
}

// MARK: - The script

/// A busy conversation: messages arrive, some long enough to wrap for lines,
/// earlier ones are edited longer and shorter, and the person writes and
/// sends their own, now and then scrolling back to reread.
@MainActor
final class ChatSession: StressSession {
    private let conversation: Conversation
    private var random: SessionRandom
    /// The keys still to come of a message being typed, or of a reread, each
    /// with the action it is reported under.
    private var pending: [(action: String, key: KeyEvent)] = []
    /// Whether the person is following the conversation: the view at its end,
    /// where the anchor keeps it as messages arrive. Paging up leaves it; End
    /// comes back to it.
    private var following = true

    init(config: StressConfig) {
        let seed = config.seed
        conversation = Conversation(
            messages: (0..<config.sized(200)).map { index in
                let h = mix(seed, index)
                return Conversation.Message(
                    id: index, mine: h.isMultiple(of: 3), text: Synth.sentence(h, words: 2 + Int(h % 24)))
            })
        random = SessionRandom(seed: seed ^ 0xC4A7)
    }

    var page: ChatPage { ChatPage(conversation: conversation) }

    func step(_ index: Int) -> SessionStep {
        // The scroll view is the first focusable view; the field is a Tab away.
        if index == 0 {
            return SessionStep(action: "focus", keys: [KeyEvent(key: .tab)])
        }
        if !pending.isEmpty {
            let next = pending.removeFirst()
            if next.key.key == .pageUp { following = false }
            if next.key.key == .end { following = true }
            return SessionStep(action: next.action, keys: [next.key])
        }
        switch random.pick([("write", 12), ("arrive", 30), ("edit", 14), ("unsend", 4), ("reread", 6), ("quiet", 34)]) {
        case "write":
            // Typed a character at a time, then sent with Return.
            let text = Synth.sentence(random.next(), words: random.within(1...6))
            pending = text.map { ("type", $0 == " " ? KeyEvent(key: .space) : KeyEvent(key: .character($0))) }
                + [("send", KeyEvent(key: .enter))]
            let first = pending.removeFirst()
            return SessionStep(action: first.action, keys: [first.key])
        case "arrive":
            conversation.messages.append(
                Conversation.Message(
                    id: conversation.makeID(), mine: false,
                    text: Synth.sentence(random.next(), words: random.within(1...30))))
            return SessionStep(action: "arrive")
        case "edit":
            // An earlier message rewritten — one row's HEIGHT changing under a
            // collection whose identity does not move.
            let row = random.below(conversation.messages.count)
            conversation.messages[row].text = Synth.sentence(random.next(), words: random.within(1...30))
            conversation.messages[row].edited = true
            return SessionStep(action: "edit")
        case "unsend":
            conversation.messages.remove(at: random.below(conversation.messages.count))
            return SessionStep(action: "unsend")
        case "reread":
            // Back to the conversation to page up through it, usually down to
            // its end again with End, and back to the field to go on writing.
            // Left where it was, the view stays put as messages arrive.
            pending = Array(repeating: ("reread", KeyEvent(key: .pageUp)), count: random.within(1...3))
            if random.below(4) != 0 { pending.append(("reread", KeyEvent(key: .end))) }
            pending.append(("reread", KeyEvent(key: .tab)))
            return SessionStep(action: "reread", keys: [KeyEvent(key: .tab, shift: true)])
        default:
            return SessionStep(action: "quiet")
        }
    }

    /// The count is right, and while the conversation is being followed its
    /// newest message is on the screen: a bottom-anchored view that opened at
    /// its top, or let go of its end as a message arrived, fails here.
    func check(_ screen: [String], after index: Int) -> String? {
        let count = "\(conversation.messages.count) messages"
        guard screen.contains(where: { $0.hasPrefix(count) }) else {
            return "the header does not say \(count)"
        }
        guard following, let newest = conversation.messages.last else { return nil }
        let tag = "#\(newest.id) "
        return screen.contains { $0.contains(tag) }
            ? nil : "following the conversation, but its newest message (\(tag)) is not on the screen"
    }

    static let descriptor = SessionDescriptor(
        id: "chat",
        summary: "a conversation of bubbles arriving at the end, earlier ones edited, the person typing and sending",
        exercises:
            "a bottom-anchored lazy stack of unequal heights, a row's HEIGHT changing under an unchanged "
            + "collection, full-width alignment frames, a text field typed into and submitted",
        make: { config, width, height, cold in
            DrivenSession(ChatSession(config: config), width: width, height: height, cold: cold)
        })
}
