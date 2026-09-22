//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChurningTable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Tables whose data moves

/// A large `Table` whose data is replaced every frame, but only a small
/// FRACTION of whose rows actually differ.
///
/// The axis the whole Table corpus was missing. Every other Table scenario —
/// `table`, `table-multiline`, `truncate`, `tables-scroll`, `tables-vstack` —
/// synthesises its rows once in `init` and never changes them again, so the
/// performance corpus measures a static table exclusively. The shape that
/// matters in an app is the other one: a big table fed by something live, where
/// each update touches a handful of rows and the rest are exactly what they
/// were.
///
/// That distinction is invisible to `Table` today, which composes every drawn
/// row from scratch on every frame — `--bench`'s `rows/frame` line reads
/// "35 composed, 0 served" for a `Table` against "0 composed, 36 served" for
/// the `List` in `megalist`. These scenarios are what a per-row memo would have
/// to be measured against, and what would show it working.
///
/// **The data really is replaced**, rather than the cell closures reading the
/// clock. An app with a live table receives a new snapshot and hands it over;
/// a closure that quietly returns something different for the same row is the
/// other thing entirely — the captured-data hole — and a scenario built that
/// way would be a trap for a value-keyed memo rather than a measurement of one.
/// Rebuilding the array costs two `Int`s per row per frame; every string is
/// produced by the column closures, which is where the cost being measured is.
enum ChurningTableScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "table-churn",
        title: "Churning Table",
        blurb: "N rows × 6 columns; the data is replaced every frame but ~2% of rows differ.",
        stresses: "per-row re-render of unchanged rows · cell value closures · row-memo headroom",
        make: { config in AnyView(ChurningTableView(config: config)) }
    )
}

/// The wrapped twin, sized to sit BELOW the scrollbar estimator's 256-row
/// limit — where a multi-line table measures EVERY row on every frame, not just
/// the ones it draws.
///
/// Deliberately the small one. A wrapped table of 250 rows builds an order of
/// magnitude more cell values per frame than one of 300, because at or below
/// the limit the extent estimator is exact and walks the whole table (see the
/// two frame-local memos in `_TableCore`'s multi-line composer). That cliff is
/// the most expensive per-frame shape a `Table` has and nothing measured it.
enum ChurningWrappedTableScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "table-churn-wrapped",
        title: "Churning Wrapped Table",
        blurb: "250 wrapped rows below the estimator's limit; ~2% differ per frame.",
        stresses: "multi-line row layout · every-row height measurement · cell value closures",
        make: { config in AnyView(ChurningWrappedTableView(config: config)) }
    )
}

/// A fixed-size window over a growing sequence: every row keeps its content and
/// its identity, and moves up one line per frame.
///
/// The other half of the moving-data axis, and the one that tells two memo
/// designs apart. In `table-churn` a row keeps its position and 2% of rows
/// change content; here NOTHING changes content and every row changes position.
/// A memo keyed by the row's identity serves the whole window on every frame; a
/// memo keyed by its position — the obvious first thing to reach for, since
/// `_TableCore` gives its rows no identity at all — serves none of it, while
/// looking correct, because the bytes it would have served are the bytes some
/// other row wanted.
///
/// This is what a log tailing into a table does, which is the commonest live
/// table an app has.
enum TailingTableScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "table-tail",
        title: "Tailing Table",
        blurb: "A window over a growing sequence: every row keeps its content and moves up one line per frame.",
        stresses: "row identity across positions · per-row re-render of moved rows · cell value closures",
        make: { config in AnyView(TailingTableView(config: config)) }
    )
}

/// One row: an id and a generation. Every string is derived from the pair by
/// the column closures, so a frame's data is two `Int`s per row and the cost
/// under measurement is the table's, not the harness's.
///
/// `Equatable` because that is what decides whether a value memo may key on a
/// row at all — `Table` requires only `Identifiable`, and a scenario whose rows
/// could not be compared would measure the declining path for ever.
struct ChurningRow: Identifiable, Sendable, Equatable {
    let id: Int
    let generation: Int

    var identifier: String { ChurnCell.identifier(self) }
    var name: String { ChurnCell.name(self) }
    var slug: String { ChurnCell.slug(self) }
    var status: String { ChurnCell.status(self) }
    var summary: String { ChurnCell.summary(self, words: 8) }
    var bar: String { ChurnCell.bar(self) }
    var details: String { ChurnCell.summary(self, words: 18) }
}

/// How many rows change per frame: one in this many.
///
/// Sixty-four, so at the default scale about 2% of the table differs each
/// frame and — more to the point — about two of the ~35 rows on SCREEN do. A
/// memo that serves the other thirty-three is the hypothesis; a scenario where
/// everything changes (`churn`) or nothing does (`table`) cannot test it.
private let churnPeriod = 64

private func churningRows(config: StressConfig, count: Int, tick: Int) -> [ChurningRow] {
    (0..<count).map { index in
        // The row's generation only advances on the frames its slot comes up,
        // so most rows hand back a value equal to last frame's.
        ChurningRow(id: index, generation: (tick &+ churnPeriod &- 1 &- index % churnPeriod) / churnPeriod)
    }
}

/// The cells, reached by KEY PATH from the columns below.
///
/// Deliberate, and it is what these scenarios are for: a `Table` may keep a row
/// across frames only when every column NAMES its value rather than computing
/// one, because a key path cannot capture what a closure captures. `table` and
/// `truncate` keep their closure columns and are the control — between them the
/// catalogue now has two scenarios on each side of that line.
///
/// Every one of these is a pure function of `(id, generation)`, which is what
/// the key path's premise requires and what an app's own row properties
/// normally are.
///
/// Cells of deliberately different expense, because a row memo's saving is
/// (rows served) × (cost of a row) and every existing Table fixture sits at the
/// cheap end.
private enum ChurnCell {
    static func identifier(_ row: ChurningRow) -> String { "\(row.id)" }

    static func name(_ row: ChurningRow) -> String {
        Synth.name(mix(UInt64(row.id), row.generation))
    }

    static func slug(_ row: ChurningRow) -> String {
        Synth.slug(mix(UInt64(row.id &* 31), row.generation))
    }

    /// The expensive end: a sentence rebuilt from the word tables.
    static func summary(_ row: ChurningRow, words: Int) -> String {
        Synth.sentence(mix(UInt64(row.id &* 131), row.generation), words: words)
    }

    /// A styled cell, which the byte-wise clip has to decline.
    static func status(_ row: ChurningRow) -> String {
        let hash = mix(UInt64(row.id &* 17), row.generation)
        return "\u{1B}[3\(hash % 6 + 1)m\(Synth.status(hash))\u{1B}[0m"
    }

    static func bar(_ row: ChurningRow) -> String {
        Synth.bar(Double(mix(UInt64(row.id), row.generation) % 100) / 100, width: 8)
    }
}

private struct ChurningTableView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(5_000)
        let rows = churningRows(config: config, count: count, tick: clock.tick)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.table-churn.heading", count, churnPeriod)).bold()
            Divider()
            Table(rows, selection: Binding<Int?>.constant(nil)) {
                TableColumn("ID", value: \ChurningRow.identifier)
                    .width(.fixed(7))
                TableColumn("Name", value: \ChurningRow.name)
                TableColumn("Slug", value: \ChurningRow.slug)
                TableColumn("Status", value: \ChurningRow.status)
                TableColumn("Summary", value: \ChurningRow.summary)
                TableColumn("Load", value: \ChurningRow.bar)
                    .width(.fixed(8))
            }
        }
    }
}

private struct TailingTableView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(5_000)
        let tick = clock.tick
        // The id TRAVELS with the content — `tick + index`, not `index` — which
        // is what makes this a shift rather than a churn. Give every row the
        // same id every frame and changing its content would be the other
        // scenario; give it a moving id and the content follows it up the table.
        let rows = (0..<count).map { ChurningRow(id: tick &+ $0, generation: 0) }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.table-tail.heading", count)).bold()
            Divider()
            Table(rows, selection: Binding<Int?>.constant(nil)) {
                TableColumn("Seq", value: \ChurningRow.identifier)
                    .width(.fixed(9))
                TableColumn("Source", value: \ChurningRow.slug)
                TableColumn("Level", value: \ChurningRow.status)
                TableColumn("Message", value: \ChurningRow.summary)
            }
        }
    }
}

private struct ChurningWrappedTableView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        // NOT `config.sized(…)`: the whole point of this scenario is the side of
        // the estimator's 256-row limit it sits on, and a scale multiplier would
        // move it to the other one.
        let count = 250
        let rows = churningRows(config: config, count: count, tick: clock.tick)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.table-churn-wrapped.heading", count, churnPeriod)).bold()
            Divider()
            Table(rows, selection: Binding<Int?>.constant(nil)) {
                TableColumn("ID") { ChurnCell.identifier($0) }
                    .width(.fixed(7))
                TableColumn("Name") { ChurnCell.name($0) }
                TableColumn("Details") { ChurnCell.summary($0, words: 18) }
                    .lineLimit(3)
            }
        }
    }
}
