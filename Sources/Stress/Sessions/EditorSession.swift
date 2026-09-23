//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditorSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The document

/// An editor's document: its lines and where the caret is. What the page
/// reads, and what the page's key handler writes.
@Observable
@MainActor
final class EditorDocument {
    var lines: [String]
    var line = 0
    var column = 0

    init(lines: [String]) {
        self.lines = lines
    }

    /// Applies a key as an editor's key handler does.
    /// - Returns: Whether the key was an editing key.
    func handle(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .character(let character): insert(String(character))
        case .space: insert(" ")
        case .paste(let text): paste(text)
        case .enter: splitLine()
        case .backspace: backspace()
        case .up: moveLine(by: -1)
        case .down: moveLine(by: 1)
        case .pageUp: moveLine(by: -20)
        case .pageDown: moveLine(by: 20)
        case .home: column = 0
        case .end: column = lines[line].count
        default: return false
        }
        return true
    }

    private func insert(_ text: String) {
        var current = lines[line]
        current.insert(contentsOf: text, at: current.index(current.startIndex, offsetBy: column))
        lines[line] = current
        column += text.count
    }

    private func splitLine() {
        let current = lines[line]
        let split = current.index(current.startIndex, offsetBy: column)
        lines[line] = String(current[..<split])
        lines.insert(String(current[split...]), at: line + 1)
        line += 1
        column = 0
    }

    private func paste(_ text: String) {
        for (offset, piece) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if offset > 0 { splitLine() }
            insert(String(piece))
        }
    }

    private func backspace() {
        if column > 0 {
            var current = lines[line]
            current.remove(at: current.index(current.startIndex, offsetBy: column - 1))
            lines[line] = current
            column -= 1
        } else if line > 0 {
            column = lines[line - 1].count
            lines[line - 1] += lines.remove(at: line)
            line -= 1
        }
    }

    private func moveLine(by delta: Int) {
        line = min(max(0, line + delta), lines.count - 1)
        column = min(column, lines[line].count)
    }
}

// MARK: - The page

/// An index-keyed editor: a caret-position line over every line of the
/// document, numbered, in a scroll view that scrolls both ways and follows the
/// caret.
///
/// The shape the content-width bugs of September 2026 lived in. Its rows are
/// keyed by INDEX, so typing leaves the collection's identity alone and moves
/// only what one row draws — the write every kept width has to notice without
/// being told which row it was.
struct EditorPage: View {
    let document: EditorDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Ln \(document.line + 1), Col \(document.column + 1) · \(document.lines.count) lines")
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<document.lines.count, id: \.self) { index in
                            EditorLine(
                                number: index + 1, text: document.lines[index],
                                isCurrent: index == document.line)
                        }
                    }
                }
                .onChange(of: document.line) { _, line in proxy.scrollTo(line) }
            }
        }
        .onKeyPress { document.handle($0) }
    }
}

/// One numbered line; the caret's line numbered in the accent.
private struct EditorLine: View {
    let number: Int
    let text: String
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 1) {
            let label = String(number)
            Text(verbatim: String(repeating: " ", count: max(0, 5 - label.count)) + label)
                .foregroundStyle(isCurrent ? Color.orange : Color.gray)
            Text(verbatim: text)
        }
    }
}

// MARK: - The script

/// Someone writing code: runs of typing, new lines, corrections, the caret
/// moved up and down and paged about, the odd paste of several lines.
@MainActor
final class EditorSession: StressSession {
    private let document: EditorDocument
    private var random: SessionRandom
    /// Characters left in the run being typed.
    private var run = 0
    /// Backspaces left in the correction being made.
    private var erasing = 0

    init(config: StressConfig) {
        let seed = config.seed
        document = EditorDocument(
            lines: (0..<config.sized(300)).map { index in
                let h = mix(seed, index)
                let indent = String(repeating: " ", count: Int(h % 4) * 4)
                // Mostly short, some past a 120-column viewport: code as it is.
                let words = 2 + Int((h >> 8) % 7) + (h.isMultiple(of: 13) ? 18 : 0)
                return indent + Synth.sentence(h >> 16, words: words)
            })
        random = SessionRandom(seed: seed)
    }

    var page: EditorPage { EditorPage(document: document) }

    func step(_ index: Int) -> SessionStep {
        if run > 0 {
            run -= 1
            return SessionStep(action: "type", keys: [typedKey()])
        }
        if erasing > 0 {
            erasing -= 1
            return SessionStep(action: "backspace", keys: [KeyEvent(key: .backspace)])
        }
        switch random.pick([
            ("type", 40), ("newline", 8), ("erase", 8), ("move", 14), ("page", 5),
            ("paste", 3), ("jump", 2), ("end", 4),
        ]) {
        case "type":
            run = random.within(3...40)
            return SessionStep(action: "type", keys: [typedKey()])
        case "newline":
            return SessionStep(action: "newline", keys: [KeyEvent(key: .enter)])
        case "erase":
            erasing = random.within(1...8)
            return SessionStep(action: "backspace", keys: [KeyEvent(key: .backspace)])
        case "move":
            let key: Key = random.below(2) == 0 ? .up : .down
            return SessionStep(
                action: "move", keys: Array(repeating: KeyEvent(key: key), count: random.within(1...3)))
        case "page":
            return SessionStep(action: "page", keys: [KeyEvent(key: random.below(3) == 0 ? .pageUp : .pageDown)])
        case "paste":
            let text = (0..<random.within(2...6))
                .map { _ in Synth.sentence(random.next(), words: random.within(2...9)) }
                .joined(separator: "\n")
            return SessionStep(action: "paste", keys: [KeyEvent(key: .paste(text))])
        case "jump":
            // A search result clicked, or a go-to-line: the caret lands
            // anywhere, which the page follows.
            document.line = random.below(document.lines.count)
            document.column = min(document.column, document.lines[document.line].count)
            return SessionStep(action: "jump")
        default:
            return SessionStep(action: "end-of-line", keys: [KeyEvent(key: .end)])
        }
    }

    /// The next character typed: letters, and a space every so often.
    private func typedKey() -> KeyEvent {
        let roll = random.below(26 + 5)
        guard roll < 26 else { return KeyEvent(key: .space) }
        return KeyEvent(key: .character(Character(UnicodeScalar(UInt8(97 + roll)))))
    }

    static let descriptor = SessionDescriptor(
        id: "editor",
        summary: "an index-keyed code editor in a two-axis scroll view, typed into, paged about and pasted into",
        exercises:
            "a row's width moving under an unchanged collection, the kept all-rows width, "
            + "scrollTo following the caret on both axes, per-keystroke frames",
        make: { config, width, height, cold in
            DrivenSession(EditorSession(config: config), width: width, height: height, cold: cold)
        })
}
