//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MultiLineTable.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Multi-line Table

/// A `Table` whose `Details` column wraps to up to three lines, so each row's
/// height varies. Exercises the multi-line render path (`buildMultiLineContent`),
/// which sizes rows lazily — wrapping only the visible window plus the bottom
/// suffix that fixes the furthest scroll, rather than every off-screen row, since
/// no scrollbar is shown to expose the total extent.
enum MultiLineTableScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "table-multiline",
        title: "Multi-line Table",
        blurb: "N rows × 4 columns; a Details column wraps to ≤3 lines, so rows vary in height.",
        stresses: "Multi-line cell wrapping · lazy row sizing (window + suffix only) · variable-height windowing",
        make: { config in AnyView(MultiLineTableView(config: config)) }
    )
}

private struct MultiLineTableView: View {
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
            Text("Multi-line Table — \(rows.count) rows, Details wraps to ≤3 lines").bold()
            Divider()
            Table(rows, selection: Binding<Int?>.constant(nil)) {
                TableColumn("ID") { (row: StressItem) in "\(row.id)" }
                TableColumn("Name") { (row: StressItem) in Synth.name(row.h) }
                TableColumn("Status") { (row: StressItem) in Synth.status(row.h) }
                TableColumn("Details") { (row: StressItem) in Self.details(row.h) }
                    .lineLimit(3)
            }
        }
    }

    /// A long, deterministic description that wraps to two or three lines at a
    /// normal column width.
    nonisolated static func details(_ hash: UInt64) -> String {
        "\(Synth.name(hash)) — \(Synth.slug(hash)) \(Synth.slug(hash >> 8)) "
            + "\(Synth.slug(hash >> 16)) \(Synth.status(hash)) \(Synth.slug(hash >> 24)) "
            + "\(Synth.slug(hash >> 32))"
    }
}
