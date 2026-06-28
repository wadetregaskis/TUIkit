//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableGroups.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Table Groups

/// Two matched scenarios that compose *several* `Table`s in a container — a
/// ScrollView in one, a plain VStack in the other. Where ``WideTableScenario``
/// stresses one enormous table, these stress the *multiplicity*: every table is
/// a separate measure/render unit that materialises its rows and recomputes its
/// column widths each frame, so N tables = N times that work plus the container's
/// own layout over them.
///
/// The pair is deliberately built from identical data (same `makeStressTables`),
/// so the only variable is the container — the point is to compare:
///   • **ScrollView** gives the stack unbounded height, so every table renders
///     all its rows (no per-table windowing) and the ScrollView windows the
///     combined buffer — the heavy "render everything, clip once" shape.
///   • **VStack** has no scroll, so each table is measured and laid out directly
///     by the stack (each table still windows its own rows to the height it is
///     offered) — the multi-child container-measure shape.
enum TablesInScrollViewScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "tables-scroll",
        title: "Tables in a ScrollView",
        blurb: "N tables stacked in a ScrollView; each materialises its rows and computes its own column widths.",
        stresses: "Multiple Table instances · per-table column-width computation · ScrollView windowing over the combined buffer",
        make: { config in AnyView(TablesInScrollViewView(config: config)) }
    )
}

enum TablesInVStackScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "tables-vstack",
        title: "Tables in a VStack",
        blurb: "N tables stacked directly in a VStack (no scroll); the stack measures and lays out every table.",
        stresses: "Multiple Table instances · per-table column-width computation · VStack measure/layout over many children",
        make: { config in AnyView(TablesInVStackView(config: config)) }
    )
}

// MARK: - Shared data

/// Builds `config.sized(8)` tables of 25 rows each, every row a ``StressItem``
/// (reused from ``WideTableScenario``) hashed from a *global* index so no two
/// rows — within or across tables — share content. Built once, in the view's
/// `init`, because a `Table` materialises its data array (see the README's
/// "Adding a scenario" note). `--scale` multiplies the table *count* (the axis
/// these scenarios add over the single-table `table` scenario).
@MainActor
private func makeStressTables(config: StressConfig) -> [[StressItem]] {
    let tableCount = config.sized(8)
    let rowsPerTable = 25
    var tables: [[StressItem]] = []
    tables.reserveCapacity(tableCount)
    var globalIndex = 0
    for _ in 0..<tableCount {
        var rows: [StressItem] = []
        rows.reserveCapacity(rowsPerTable)
        for _ in 0..<rowsPerTable {
            rows.append(StressItem(id: globalIndex, h: mix(config.seed, globalIndex)))
            globalIndex += 1
        }
        tables.append(rows)
    }
    return tables
}

/// One stress table: a titled `Table` of five per-cell-synthesised columns.
/// Shared by both grouping scenarios so the only difference between them is the
/// container the tables sit in.
private struct StressTable: View {
    let title: String
    let rows: [StressItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).bold()
            Table(rows, selection: Binding<Int?>.constant(nil)) {
                TableColumn("ID") { (row: StressItem) in "\(row.id)" }
                TableColumn("Name") { (row: StressItem) in Synth.name(row.h) }
                TableColumn("Status") { (row: StressItem) in Synth.status(row.h) }
                TableColumn("Score") { (row: StressItem) in "\(row.h % 1000)" }
                TableColumn("Load") { (row: StressItem) in Synth.bar(Double(row.h % 100) / 100, width: 8) }
            }
        }
    }
}

// MARK: - ScrollView case

private struct TablesInScrollViewView: View {
    let tables: [[StressItem]]

    init(config: StressConfig) {
        self.tables = makeStressTables(config: config)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.tables-scroll.heading", tables.count, tables.first?.count ?? 0)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<tables.count, id: \.self) { index in
                        StressTable(title: Lf("stress.scenario.tables.tableLabel", index + 1), rows: tables[index])
                    }
                }
            }
        }
    }
}

// MARK: - VStack case

private struct TablesInVStackView: View {
    let tables: [[StressItem]]

    init(config: StressConfig) {
        self.tables = makeStressTables(config: config)
    }

    var body: some View {
        // No ScrollView — the tables sit directly in the VStack, which measures
        // and lays out each one (the contrast with the ScrollView case).
        VStack(alignment: .leading, spacing: 1) {
            Text(Lf("stress.scenario.tables-vstack.heading", tables.count, tables.first?.count ?? 0)).bold()
            Divider()
            ForEach(0..<tables.count, id: \.self) { index in
                StressTable(title: Lf("stress.scenario.tables.tableLabel", index + 1), rows: tables[index])
            }
        }
    }
}
