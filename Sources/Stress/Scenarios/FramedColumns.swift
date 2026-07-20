//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FramedColumns.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Framed Columns

/// The GitHub issue #7 shape at stress scale: fixed-size `.frame`s wrapped
/// around interactive content (a selectable `List`, `Card`s of `Toggle` rows),
/// nested inside stacks that are themselves framed, beside a `Panel`-hosted
/// `ScrollView` log. Every non-infinity frame is measured by each ancestor
/// level, and the interactive rows decline the value memos — so this tree is
/// the canary for the nested-frame measure cascade (which once fully
/// re-rendered the framed subtree 15× per idle frame).
enum FramedColumnsScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "framedcolumns",
        title: "Framed Columns",
        blurb: "Fixed-frame columns of interactive rows (List, Toggle Cards, a log Panel).",
        stresses: "non-infinity .frame measure · frames-in-stacks-in-frames cascade · uncacheable interactive rows",
        make: { config in AnyView(FramedColumnsView(config: config)) }
    )
}

private struct FramedColumnsView: View {
    let config: StressConfig

    var body: some View {
        let rowsPerCard = config.sized(5)
        VStack {
            Text(Lf("stress.scenario.framedcolumns.heading", rowsPerCard)).bold()
            HStack {
                Button(Synth.name(mix(config.seed, 1))) {}
                Button(Synth.name(mix(config.seed, 2))) {}
            }
            .padding()
            HStack {
                ToggleColumn(seed: mix(config.seed, 3), rows: rowsPerCard)
                ToggleColumn(seed: mix(config.seed, 4), rows: rowsPerCard)
                VStack {
                    Panel(Synth.name(mix(config.seed, 5)), padding: EdgeInsets(horizontal: 1)) {
                        ScrollView(showsIndicators: true) {
                            VStack(alignment: .leading) {
                                ForEach(0..<rowsPerCard * 2, id: \.self) { line in
                                    Text(Synth.name(mix(config.seed, 100 + line)))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

/// One fixed-width column: a selectable `List` and a `Card` of `Toggle` rows,
/// each pinned with a fixed-height `.frame` — the exact nesting whose measure
/// used to compound renders multiplicatively.
private struct ToggleColumn: View {
    let seed: UInt64
    let rows: Int

    var body: some View {
        VStack {
            List(Synth.name(mix(seed, 0)), selection: .constant(String?.none)) {
                ForEach(0..<rows, id: \.self) { row in
                    Text(Synth.name(mix(seed, 10 + row)))
                }
            }
            .frame(height: rows + 3)

            Card(title: Synth.name(mix(seed, 1)), padding: .init(horizontal: 1)) {
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            Toggle(
                                isOn: .constant(mix(seed, 20 + row).isMultiple(of: 2))
                            ) { Text(Synth.name(mix(seed, 30 + row))) }
                            Spacer()
                            Text(mix(seed, 40 + row).isMultiple(of: 2) ? "●" : "◌")
                        }
                    }
                }
            }
            .frame(height: rows + 3)

            Spacer()
        }
        .frame(width: 30)
    }
}
