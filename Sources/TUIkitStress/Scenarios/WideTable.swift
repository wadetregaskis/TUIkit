//  🖥️ TUIKit — Terminal UI Kit for Swift
//  WideTable.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Wide Table

/// A `Table` of many rows × eight columns. Unlike `List`, a `Table`
/// materialises its full data array (built once, here, from the seed), and each
/// frame computes column widths across the visible rows from per-cell string
/// closures. Stresses the table layout/measure path and per-cell synthesis.
enum WideTableScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "table",
        title: "Wide Table",
        blurb: "N rows × 8 columns; per-cell strings synthesised from the row hash.",
        stresses: "Table column-width computation · row windowing · per-cell value closures",
        make: { config in AnyView(WideTableView(config: config)) }
    )
}

/// Row model — `Identifiable & Sendable` as `Table` requires. Built once.
struct StressItem: Identifiable, Sendable {
    let id: Int
    let h: UInt64
}

private struct WideTableView: View {
    let rows: [StressItem]

    init(config: StressConfig) {
        let count = config.sized(20_000)
        var built = [StressItem]()
        built.reserveCapacity(count)
        for index in 0..<count {
            built.append(StressItem(id: index, h: mix(config.seed, index)))
        }
        self.rows = built
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wide Table — \(rows.count) rows × 8 columns").bold()
            Divider()
            Table(rows, selection: Binding<Int?>.constant(nil)) {
                TableColumn("ID") { (row: StressItem) in "\(row.id)" }
                TableColumn("Name") { (row: StressItem) in Synth.name(row.h) }
                TableColumn("Slug") { (row: StressItem) in Synth.slug(row.h) }
                TableColumn("Status") { (row: StressItem) in Synth.status(row.h) }
                TableColumn("Score") { (row: StressItem) in "\(row.h % 1000)" }
                TableColumn("Tier") { (row: StressItem) in "T\((row.h >> 8) % 5)" }
                TableColumn("Load") { (row: StressItem) in Synth.bar(Double(row.h % 100) / 100, width: 8) }
                TableColumn("Tag") { (row: StressItem) in Synth.slug(row.h >> 16) }
            }
        }
    }
}
