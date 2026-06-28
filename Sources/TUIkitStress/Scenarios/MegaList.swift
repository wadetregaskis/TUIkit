//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MegaList.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Mega List

/// A `List` of up to a million rows whose content is **synthesised per index**
/// (`mix(seed, i)`), so the data set costs O(1) memory and zero disk — there is
/// no backing array. Exercises the windowed `List`/`ForEach` path: row-id
/// resolution over a huge range, the lazy per-row content box, and the
/// element-keyed memo (the row element is `Int`, so unchanged rows are served
/// from the render cache).
enum MegaListScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "megalist",
        title: "Mega List",
        blurb: "Windowed List of N rows; content hashed per index (no backing array).",
        stresses: "List/ForEach windowing · row-id resolution · lazy row content · per-row memo",
        make: { config in AnyView(MegaListView(config: config)) }
    )
}

private struct MegaListView: View {
    let config: StressConfig

    var body: some View {
        let count = config.sized(50_000)
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.megalist.heading", count)).bold()
            Divider()
            List {
                ForEach(0..<count, id: \.self) { index in
                    MegaRow(seed: config.seed, index: index)
                }
            }
        }
    }
}

/// `Equatable` so the row also value-memoizes; content is a pure function of
/// `(seed, index)`.
private struct MegaRow: View, Equatable {
    let seed: UInt64
    let index: Int

    var body: some View {
        let h = mix(seed, index)
        HStack {
            Text("#\(index)").foregroundStyle(.secondary)
            Text(Synth.slug(h))
            Spacer()
            Text(Synth.status(h)).foregroundStyle(statusColor(h))
            Text(Synth.bar(Double(h % 100) / 100, width: 10)).foregroundStyle(.accent)
        }
    }
}

/// Maps a synthesised status to a palette colour.
func statusColor(_ h: UInt64) -> Color {
    switch Synth.status(h) {
    case "active", "synced": return .success
    case "failed": return .error
    case "queued", "syncing": return .warning
    default: return .secondary
    }
}
