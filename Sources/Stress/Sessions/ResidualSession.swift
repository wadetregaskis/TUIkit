//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ResidualSession.swift
//
//  Rows that draw what is NOT their element. A `ForEach` row is memoized by
//  its element, so a row is right to be served only while everything it draws
//  comes from that element — and three ordinary shapes draw something else:
//
//  - an INDEX-keyed row reading `document.lines[index]`, whose key does not
//    move when the line under it is retyped, or when a line inserted above it
//    shifts every line below it along;
//  - a row computing `isSelected: item.id == selection` in the `ForEach`
//    closure, from a selection that is not part of any row;
//  - rows under a parent's `.disabled(busy)` and `.bold(busy)`, which write
//    the environment directly rather than through a noted modifier.
//
//  Today each is right because the write that changes it — an `@Observable`
//  read by the page's body, or the page's own `@State` — clears everything
//  below the page. That clear is what a value-trusting memo (Option C, or the
//  priced "trust the row keys" Option B) takes away, and when it goes these
//  are the rows that go wrong: the step-0 experiments drew the editor wrong on
//  1,494 of 1,500 frames, and a throwaway session of the third shape wrong on
//  337 of 400. This session puts all three on one page, so a change to what
//  survives an ancestor's write has its oracle before it is written: the
//  cache-cleared twin of `--verify`, and the page's own check of what the
//  model says it must show.
//
//  The rows say they are `Equatable`, because that is what Option C asks of a
//  row before it re-checks one: it serves an `Equatable` row whose rebuilt
//  value equals the one it drew, under an environment that has not moved, and
//  refuses every other row, drawing it again as today. Rows that were not
//  `Equatable` would all be refused, and the page would pass whatever C's
//  serve did. `residual-opaque` is the same page with the conformance taken
//  away — the rows C must leave exactly as they are.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The model

/// What the page shows: lines keyed by index, items to pick from, and tasks
/// that the page can make busy.
@Observable
@MainActor
final class ResidualModel {
    /// A pickable item or a task. `Equatable`, so its row is memoized by it.
    struct Item: Identifiable, Equatable {
        let id: Int
        var title: String
    }

    var lines: [String]
    var items: [Item]
    var tasks: [Item]

    init(lines: [String], items: [Item], tasks: [Item]) {
        self.lines = lines
        self.items = items
        self.tasks = tasks
    }
}

// MARK: - What the rows say they are

/// Whether the page's rows say they are `Equatable` — the one thing Option C
/// asks of a row before it re-checks it after a write above it.
///
/// A marker rather than two copies of each row: the rows are the same structs,
/// and conform only under ``EquatableRows``.
protocol ResidualRowKind {
    /// The session's id.
    static var sessionID: String { get }
    /// What the rows are, for `--sessions`.
    static var rowsSummary: String { get }
}

/// Rows that are `Equatable`: re-checked by Option C after a write above them.
enum EquatableRows: ResidualRowKind {
    static let sessionID = "residual"
    static let rowsSummary = "rows that say they are Equatable"
}

/// Rows that are not: refused by Option C, and drawn again as today.
enum OpaqueRows: ResidualRowKind {
    static let sessionID = "residual-opaque"
    static let rowsSummary = "the same rows, not Equatable"
}

// MARK: - The page

/// Where the columns sit.
enum ResidualColumns {
    /// How wide the lines column is; the items column starts one cell after it.
    static let linesWidth = 36
    /// How wide the items column is.
    static let itemsWidth = 24
}

/// A status line over three columns: numbered lines keyed by index, items with
/// the selection marked, and tasks the page disables and bolds while it is
/// busy. `selection` and `busy` are the page's own `@State`, moved by `j`/`k`
/// and flipped by `b`.
struct ResidualPage<Kind: ResidualRowKind>: View {
    let model: ResidualModel
    @State private var selection = 0
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "#\(selection) selected · \(busy ? "busy" : "idle") · \(model.lines.count) lines")
            HStack(alignment: .top, spacing: 1) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<model.lines.count, id: \.self) { index in
                        LineRow<Kind>(number: index + 1, text: model.lines[index])
                    }
                }
                .frame(width: ResidualColumns.linesWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.items) { item in
                        PickRow<Kind>(title: item.title, isSelected: item.id == selection)
                    }
                }
                .frame(width: ResidualColumns.itemsWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.tasks) { task in TaskRow<Kind>(task: task) }
                }
                .disabled(busy)
                .bold(busy)
            }
        }
        .onKeyPress(keys: [.character("j"), .character("k"), .character("b")]) { event in
            let count = max(1, model.items.count)
            switch event.key {
            case .character("j"): selection = (selection + 1) % count
            case .character("k"): selection = (selection + count - 1) % count
            default: busy.toggle()
            }
            return true
        }
    }
}

/// The label a line is drawn with: its number, right-aligned in three cells.
private func lineLabel(_ number: Int) -> String {
    let digits = String(number)
    return String(repeating: " ", count: max(0, 3 - digits.count)) + digits + " "
}

/// A numbered line: whatever text is at its index now.
private struct LineRow<Kind: ResidualRowKind>: View {
    let number: Int
    let text: String

    var body: some View {
        Text(verbatim: lineLabel(number) + text)
    }
}

/// An item, marked when it is the selection.
private struct PickRow<Kind: ResidualRowKind>: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(verbatim: (isSelected ? "> " : "  ") + title)
    }
}

/// A task: its number and a button, both dimmed and bolded by the page.
private struct TaskRow<Kind: ResidualRowKind>: View {
    let task: ResidualModel.Item

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "#\(task.id)")
            Button(task.title) {}
        }
    }
}

// Every field of every row compared, as the synthesized `==` does: a row that
// equals the one drawn draws the same. Isolated, as the views are.
extension LineRow: @MainActor Equatable where Kind == EquatableRows {}
extension PickRow: @MainActor Equatable where Kind == EquatableRows {}
extension TaskRow: @MainActor Equatable where Kind == EquatableRows {}

// MARK: - The script

/// Someone working a page of three panes: retyping lines, inserting and
/// deleting them, walking the selection, making the page busy and idle,
/// renaming items and tasks, and moving the focus among the tasks.
@MainActor
final class ResidualSession<Kind: ResidualRowKind>: StressSession {
    private let model: ResidualModel
    private var random: SessionRandom
    /// The page's `selection` and `busy`, as the keys sent so far set them:
    /// what the check expects to see.
    private var selection = 0
    private var busy = false
    /// How few and how many lines there may be.
    private let lineRange: ClosedRange<Int>

    init(config: StressConfig) {
        let seed = config.seed
        let lineCount = config.sized(24)
        lineRange = max(4, lineCount / 3)...lineCount
        model = ResidualModel(
            lines: (0..<lineCount).map { Self.line(mix(seed, $0)) },
            items: (0..<config.sized(16)).map { ResidualModel.Item(id: $0, title: Self.title($0, mix(seed ^ 0x17E, $0))) },
            tasks: (0..<config.sized(10)).map { ResidualModel.Item(id: $0, title: Synth.slug(mix(seed ^ 0x7A5, $0))) })
        random = SessionRandom(seed: seed ^ 0x2E51)
    }

    /// A line short enough never to be cut by its column.
    private static func line(_ h: UInt64) -> String {
        String(Synth.sentence(h, words: 2 + Int(h % 3)).prefix(ResidualColumns.linesWidth - 6))
    }

    /// An item's title: its number, and a slug cut to fit its column.
    private static func title(_ id: Int, _ h: UInt64) -> String {
        String("\(id) \(Synth.slug(h))".prefix(ResidualColumns.itemsWidth - 2))
    }

    var page: ResidualPage<Kind> { ResidualPage(model: model) }

    func step(_ index: Int) -> SessionStep {
        switch random.pick([
            ("select", 22), ("busy", 12), ("edit", 20), ("insert", 8), ("remove", 6), ("rename", 8),
            ("retask", 6), ("focus", 6), ("quiet", 12),
        ]) {
        case "select":
            let forward = random.below(3) != 0
            let presses = random.within(1...3)
            let count = model.items.count
            selection = (selection + (forward ? presses : count * presses - presses)) % count
            return SessionStep(
                action: "select",
                keys: Array(repeating: KeyEvent(key: .character(forward ? "j" : "k")), count: presses))
        case "busy":
            busy.toggle()
            return SessionStep(action: "busy", keys: [KeyEvent(key: .character("b"))])
        case "edit":
            // Retyped in place: the row keeps its index, and so its key.
            model.lines[random.below(model.lines.count)] = Self.line(random.next())
            return SessionStep(action: "edit")
        case "insert":
            // Every line below the insertion now reads the line above it.
            guard model.lines.count < lineRange.upperBound else { return SessionStep(action: "quiet") }
            model.lines.insert(Self.line(random.next()), at: random.below(model.lines.count + 1))
            return SessionStep(action: "insert")
        case "remove":
            guard model.lines.count > lineRange.lowerBound else { return SessionStep(action: "quiet") }
            model.lines.remove(at: random.below(model.lines.count))
            return SessionStep(action: "remove")
        case "rename":
            let at = random.below(model.items.count)
            model.items[at].title = Self.title(model.items[at].id, random.next())
            return SessionStep(action: "rename")
        case "retask":
            model.tasks[random.below(model.tasks.count)].title = Synth.slug(random.next())
            return SessionStep(action: "retask")
        case "focus":
            return SessionStep(action: "focus", keys: [KeyEvent(key: .tab)])
        default:
            return SessionStep(action: "quiet")
        }
    }

    /// The status line says what the keys set and how many lines there are;
    /// every line on the screen is the model's line at that index, numbered;
    /// and every item on the screen is marked exactly when it is the
    /// selection. What `busy` does to the tasks is styling, which a stripped
    /// screen cannot show: the twin compares it.
    ///
    /// Read relative to the status line, wherever the window centres the page,
    /// and only as far down as the page is drawn and above the app's status
    /// bar, whose top border ends what a larger scale may have clipped.
    func check(_ screen: [String], after index: Int) -> String? {
        let status = "#\(selection) selected · \(busy ? "busy" : "idle") · \(model.lines.count) lines"
        guard let top = screen.firstIndex(where: { $0.contains(status) }),
            let found = screen[top].range(of: status)
        else { return "the status line does not say \(status)" }
        let left = screen[top].distance(from: screen[top].startIndex, to: found.lowerBound)
        let tall = max(model.lines.count, model.items.count, model.tasks.count)
        let below = screen[(top + 1)...]
        let bar = below.firstIndex { $0.drop { $0 == " " }.hasPrefix("╭") } ?? screen.count
        for (offset, line) in below.prefix(min(tall, bar - top - 1)).enumerated() {
            let row = Array(line.dropFirst(left))
            if offset < model.lines.count {
                let expected = lineLabel(offset + 1) + model.lines[offset]
                guard String(row.prefix(expected.count)) == expected else {
                    return "line \(offset + 1) does not read \"\(expected)\": \(String(row))"
                }
            }
            if offset < model.items.count {
                let item = model.items[offset]
                let expected = (item.id == selection ? "> " : "  ") + item.title
                let start = ResidualColumns.linesWidth + 1
                let drawn = row.count > start ? String(row[start...].prefix(expected.count)) : ""
                guard drawn == expected else {
                    return "item \(item.id) is drawn \"\(drawn)\" where \"\(expected)\" belongs"
                }
            }
        }
        return nil
    }

    static var descriptor: SessionDescriptor {
        SessionDescriptor(
            id: Kind.sessionID,
            summary: "rows that draw what is not their element: lines by index, a selection mark, a parent's "
                + "busy — \(Kind.rowsSummary)",
            exercises:
                "index-keyed rows reading document.lines[i] retyped, inserted above and removed; a row "
                + "computing selection == item.id; a parent @State driving .disabled and .bold into rows; "
                + "each right today only because the write clears everything below the page",
            make: { config, width, height, cold in
                DrivenSession(ResidualSession(config: config), width: width, height: height, cold: cold)
            })
    }
}
