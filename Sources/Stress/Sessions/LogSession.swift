//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LogSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUIkit

// MARK: - The log

/// A log that grows, and which line the viewer shows at its top.
@Observable
@MainActor
final class LogModel {
    struct Line: Identifiable, Equatable {
        let id: Int
        let level: String
        let text: String
    }

    var lines: [Line]
    /// The line at the top of the viewport, as the scroll view reports it.
    var topLine: Int?

    init(lines: [Line]) {
        self.lines = lines
    }
}

// MARK: - The page

/// A status line over a log in a scroll view that opens at its end, stays
/// there while lines arrive, and reports which line is at its top.
struct LogPage: View {
    let log: LogModel
    /// Whether the top line is bound through `@Bindable`, as an app binds an
    /// `@Observable`'s property (`log-observable`), rather than through a
    /// closure pair.
    var bindsThroughBindable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(log.lines.count) lines · top \(log.topLine.map(String.init) ?? "-")")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(log.lines) { line in LogRow(line: line) }
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition(id: topLine)
        }
    }
}

extension LogPage {
    /// The scroll view's top-line binding.
    private var topLine: Binding<Int?> {
        bindsThroughBindable ? Bindable(log).topLine : Binding(get: { log.topLine }, set: { log.topLine = $0 })
    }
}

/// One line: its number, its level coloured by severity, then the message,
/// which wraps. The number is how the session tells which lines are on the
/// screen.
struct LogRow: View {
    let line: LogModel.Line

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(verbatim: "\(line.id)").frame(width: 6, alignment: .trailing).foregroundStyle(Color.gray)
            Text(verbatim: line.level)
                .foregroundStyle(line.level == "ERROR" ? Color.red : line.level == "WARN" ? Color.yellow : Color.gray)
            Text(verbatim: line.text)
        }
    }
}

// Every field compared, as the synthesized `==` does: a row equal to the one
// drawn draws the same, which is what Option C asks of a row before it
// re-checks it after a write above it. Isolated, as the view is.
extension LogRow: @MainActor Equatable {}

// MARK: - The script

/// A build or a server tailing its log: lines in bursts, the odd long one that
/// wraps, a reader who scrolls back to look at something and returns to the end.
@MainActor
final class LogSession: StressSession {
    let log: LogModel
    private var random: SessionRandom
    /// Whether the reader is following the log: `true` at its end, where the
    /// anchor keeps it as lines arrive, `false` once they page back, and `nil`
    /// after a page down, which may or may not have reached the end again.
    private var following: Bool? = true

    init(config: StressConfig) {
        let seed = config.seed
        log = LogModel(lines: (0..<config.sized(500)).map { Self.line(id: $0, hash: mix(seed, $0)) })
        random = SessionRandom(seed: seed ^ 0x106)
    }

    private static func line(id: Int, hash h: UInt64) -> LogModel.Line {
        let level = h.isMultiple(of: 17) ? "ERROR" : h.isMultiple(of: 7) ? "WARN" : "INFO"
        // Mostly one line; one in eleven long enough to wrap.
        let words = h.isMultiple(of: 11) ? 30 + Int(h % 20) : 3 + Int(h % 9)
        return LogModel.Line(id: id, level: level, text: Synth.sentence(h >> 8, words: words))
    }

    var page: LogPage { LogPage(log: log) }

    func step(_ index: Int) -> SessionStep {
        // The scroll view is the only focusable view, so it holds the focus and
        // the paging keys reach it.
        switch random.pick([("line", 45), ("burst", 15), ("quiet", 15), ("back", 10), ("forward", 8), ("end", 7)]) {
        case "line":
            append(1)
            return SessionStep(action: "line")
        case "burst":
            append(random.within(5...40))
            return SessionStep(action: "burst")
        case "back":
            following = false
            return SessionStep(
                action: "scroll", keys: Array(repeating: KeyEvent(key: .pageUp), count: random.within(1...3)))
        case "forward":
            following = following == true ? true : nil
            return SessionStep(action: "scroll", keys: [KeyEvent(key: .pageDown)])
        case "end":
            following = true
            return SessionStep(action: "end", keys: [KeyEvent(key: .end)])
        default:
            return SessionStep(action: "quiet")
        }
    }

    private func append(_ count: Int) {
        let next = log.lines.count
        log.lines += (0..<count).map { Self.line(id: next + $0, hash: random.next()) }
    }

    /// The count is right, and while the log is being followed its newest line
    /// is on the screen, its number starting a row.
    func check(_ screen: [String], after index: Int) -> String? {
        let count = "\(log.lines.count) lines"
        guard screen.contains(where: { $0.hasPrefix(count) }) else {
            return "the header does not say \(count)"
        }
        guard following == true, let newest = log.lines.last else { return nil }
        let number = "\(newest.id) "
        if screen.contains(where: { $0.drop { $0 == " " }.hasPrefix(number) }) { return nil }
        // A line taller than the viewport, followed to its end, shows its end
        // and not its number. Then every row the log draws is that line's —
        // none starts with a number of its own — and what they draw, read in
        // order, is how its text ends.
        let absent = "following the log, but its newest line (\(newest.id)) is not on the screen"
        guard let header = screen.firstIndex(where: { $0.hasPrefix(count) }) else { return absent }
        let rows = screen[(header + 1)...].filter { $0.hasPrefix(" ") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ▲▼▁▂▃▄▅▆▇█")) }
            .filter { !$0.isEmpty }
        guard !rows.isEmpty, !rows.contains(where: { $0.contains(/^\d+ (INFO|WARN|ERROR)\b/) }) else { return absent }
        let unspaced = { (text: String) in text.filter { $0 != " " } }
        return unspaced(newest.text).hasSuffix(unspaced(rows.joined())) ? nil : absent
    }

    static let descriptor = SessionDescriptor(
        id: "log",
        summary: "a log viewer following its end while lines arrive in bursts, and a reader paging back",
        exercises:
            "a bottom-anchored lazy stack growing under the viewport, wrapped lines of unequal height, "
            + "scrollPosition(id:) reporting the top line, paging away from the end and back",
        make: { config, width, height, cold in
            DrivenSession(LogSession(config: config), width: width, height: height, cold: cold)
        })
}
