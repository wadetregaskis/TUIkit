//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProcessesSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUIkit

// MARK: - The table

/// Running processes and how the monitor shows them: sorted by one column,
/// filtered by a query, one of them selected.
@Observable
@MainActor
final class ProcessTable {
    struct Process: Identifiable, Equatable {
        let id: Int
        var command: String
        var user: String
        var cpu: Double
        var memory: Int
        var state: String
    }

    var processes: [Process]
    var order: [KeyPathComparator<Process>] = [KeyPathComparator(\Process.cpu, order: .reverse)]
    var filter = ""
    var selection: Set<Int> = []
    private(set) var nextID: Int

    init(processes: [Process]) {
        self.processes = processes
        nextID = (processes.map(\.id).max() ?? 0) + 1
    }

    /// A new process's id, never used before.
    func spawnID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// The processes the filter leaves, in the order the table sorts them by.
    ///
    /// Sorted by a closure on the comparator's key path rather than by
    /// `sorted(using:)`, as `Table`'s `sortOrder` documentation advises: through
    /// `KeyPathComparator` the sort was 71% of this session's frame (measured),
    /// and the session is here to measure the table.
    var shown: [Process] {
        let kept = filter.isEmpty ? processes : processes.filter { $0.command.contains(filter) }
        guard let first = order.first else { return kept }
        let forward = first.order == .forward
        switch first.keyPath {
        case \Process.cpu: return kept.sorted { forward ? $0.cpu < $1.cpu : $0.cpu > $1.cpu }
        case \Process.memory: return kept.sorted { forward ? $0.memory < $1.memory : $0.memory > $1.memory }
        case \Process.command: return kept.sorted { forward ? $0.command < $1.command : $0.command > $1.command }
        default: return kept.sorted { forward ? $0.id < $1.id : $0.id > $1.id }
        }
    }
}

// MARK: - The page

/// A load line over a filter field and a sortable, selectable table of
/// processes whose numbers move all the time.
struct ProcessesPage: View {
    let table: ProcessTable

    var body: some View {
        let shown = table.shown
        let load = table.processes.reduce(0.0) { $0 + $1.cpu } / Double(max(1, table.processes.count))
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(shown.count) processes · load \(String(format: "%.1f", load))%")
            TextField("Filter", text: Binding(get: { table.filter }, set: { table.filter = $0 }))
            Table(
                shown, selection: Binding(get: { table.selection }, set: { table.selection = $0 }),
                sortOrder: Binding(get: { table.order }, set: { table.order = $0 })
            ) {
                TableColumn("PID", value: \ProcessTable.Process.id) { "\($0.id)" }
                    .width(.fixed(6)).alignment(.trailing)
                TableColumn("Command", value: \ProcessTable.Process.command)
                TableColumn("User", value: \ProcessTable.Process.user).width(.fit)
                TableColumn("CPU%", value: \ProcessTable.Process.cpu) { String(format: "%.1f", $0.cpu) }
                    .width(.fixed(6)).alignment(.trailing)
                TableColumn("Memory", value: \ProcessTable.Process.memory) { "\($0.memory) KB" }
                    .width(.fit).alignment(.trailing)
                TableColumn("State", value: \ProcessTable.Process.state).width(.fixed(9))
            }
        }
    }
}

// MARK: - The script

/// Someone watching a busy machine: the numbers move on every step, processes
/// start and finish, the table is re-sorted and filtered, the selection moved.
@MainActor
final class ProcessesSession: StressSession {
    private let table: ProcessTable
    private var random: SessionRandom
    /// The keys still to come of a filter being typed and then cleared.
    private var pending: [KeyEvent] = []

    init(config: StressConfig) {
        let seed = config.seed
        table = ProcessTable(
            processes: (0..<config.sized(300)).map { index in
                Self.process(id: 100 + index * 7, hash: mix(seed, index))
            })
        random = SessionRandom(seed: seed ^ 0x9C0F)
    }

    private static func process(id: Int, hash h: UInt64) -> ProcessTable.Process {
        ProcessTable.Process(
            id: id, command: Synth.slug(h) + (h.isMultiple(of: 5) ? " --" + Synth.slug(h >> 20) : ""),
            user: Synth.firstNames[Int((h >> 12) % UInt64(Synth.firstNames.count))].lowercased(),
            cpu: Double(h % 1000) / 10, memory: Int((h >> 16) % 4_000_000), state: Synth.status(h))
    }

    var page: ProcessesPage { ProcessesPage(table: table) }

    func step(_ index: Int) -> SessionStep {
        // The filter field is the first focusable view and holds the focus
        // when the page opens; the table is a Tab away.
        if index == 0 {
            return SessionStep(action: "focus", keys: [KeyEvent(key: .tab)])
        }
        // A sampler's tick: some processes' numbers move on every step, which
        // is what makes the monitor the churn it is.
        for _ in 0..<max(1, table.processes.count / 12) {
            let row = random.below(table.processes.count)
            table.processes[row].cpu = Double(random.below(1000)) / 10
            table.processes[row].memory += random.within(-4096...4096)
        }
        if !pending.isEmpty {
            return SessionStep(action: "filter", keys: [pending.removeFirst()])
        }
        switch random.pick([
            ("tick", 40), ("select", 20), ("page", 5), ("sort", 6), ("spawn", 10), ("exit", 8),
            ("filter", 5), ("state", 6),
        ]) {
        case "select":
            let key: Key = random.below(3) == 0 ? .up : .down
            return SessionStep(
                action: "select", keys: Array(repeating: KeyEvent(key: key), count: random.within(1...3)))
        case "page":
            return SessionStep(action: "page", keys: [KeyEvent(key: random.below(3) == 0 ? .pageUp : .pageDown)])
        case "sort":
            // A header clicked: by another column, or the same one reversed.
            table.order = [
                [KeyPathComparator(\ProcessTable.Process.cpu, order: .reverse)],
                [KeyPathComparator(\ProcessTable.Process.memory, order: .reverse)],
                [KeyPathComparator(\ProcessTable.Process.command)],
                [KeyPathComparator(\ProcessTable.Process.id)],
            ][random.below(4)]
            return SessionStep(action: "sort")
        case "spawn":
            table.processes.append(Self.process(id: table.spawnID(), hash: random.next()))
            return SessionStep(action: "spawn")
        case "exit":
            guard table.processes.count > 1 else { return SessionStep(action: "exit") }
            table.processes.remove(at: random.below(table.processes.count))
            return SessionStep(action: "exit")
        case "filter":
            let letters = (0..<random.within(1...3)).map { _ in
                KeyEvent(key: .character(Character(UnicodeScalar(UInt8(97 + random.below(26))))))
            }
            pending = letters + Array(repeating: KeyEvent(key: .backspace), count: letters.count)
                + [KeyEvent(key: .tab)]
            // Back to the field: from the table, Tab wraps round to it.
            return SessionStep(action: "filter", keys: [KeyEvent(key: .tab)])
        case "state":
            let row = random.below(table.processes.count)
            table.processes[row].state = Synth.status(random.next())
            return SessionStep(action: "state")
        default:
            return SessionStep(action: "tick")
        }
    }

    static let descriptor = SessionDescriptor(
        id: "processes",
        summary: "a sortable, filterable process table whose numbers move on every step",
        exercises:
            "a Table's .fit columns and row memo under continuous churn, re-sorting, a filter "
            + "narrowing the rows, rows appended and removed, selection moved with the keys",
        make: { config, width, height, cold in
            DrivenSession(ProcessesSession(config: config), width: width, height: height, cold: cold)
        })
}
