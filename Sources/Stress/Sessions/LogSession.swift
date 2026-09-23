//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LogSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(log.lines.count) lines · top \(log.topLine.map(String.init) ?? "-")")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(log.lines) { line in LogRow(line: line) }
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition(id: Binding(get: { log.topLine }, set: { log.topLine = $0 }))
        }
    }
}

/// One line: its level, coloured by severity, then the message, which wraps.
private struct LogRow: View {
    let line: LogModel.Line

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(verbatim: line.level)
                .foregroundStyle(line.level == "ERROR" ? Color.red : line.level == "WARN" ? Color.yellow : Color.gray)
            Text(verbatim: line.text)
        }
    }
}

// MARK: - The script

/// A build or a server tailing its log: lines in bursts, the odd long one that
/// wraps, a reader who scrolls back to look at something and returns to the end.
@MainActor
final class LogSession: StressSession {
    private let log: LogModel
    private var random: SessionRandom

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
            return SessionStep(
                action: "scroll", keys: Array(repeating: KeyEvent(key: .pageUp), count: random.within(1...3)))
        case "forward":
            return SessionStep(action: "scroll", keys: [KeyEvent(key: .pageDown)])
        case "end":
            return SessionStep(action: "end", keys: [KeyEvent(key: .end)])
        default:
            return SessionStep(action: "quiet")
        }
    }

    private func append(_ count: Int) {
        let next = log.lines.count
        log.lines += (0..<count).map { Self.line(id: next + $0, hash: random.next()) }
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
