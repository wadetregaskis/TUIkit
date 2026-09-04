//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PreferenceRows.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Preference Rows

/// Every row publishes a preference, and one collector at the top reads them.
///
/// This is the shape the Example's "Layout System" page took on when its lazy-
/// stack instrumentation was added — a `ForEach` whose every row carries
/// `.preference(key:value:)` — and it made that page render roughly nine times
/// slower than its siblings. The scenario exists to hold that cost measurable
/// and to keep it from coming back.
///
/// What it stresses is not preference *merging*, which is cheap, but what
/// publishing one COSTS a row: a preference write is a render-pass side effect,
/// so the row that carries it declines every value memo above it. A row that
/// cannot be memoized is re-rendered and re-measured in full on every pass, and
/// a whole list of them turns the per-frame cost from O(visible) back into
/// O(rows).
///
/// Compare against `modifiers`, which has a similar row count and a heavier
/// per-row modifier chain but publishes nothing.
enum PreferenceRowsScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "preferences",
        title: "Preference Rows",
        blurb: "N rows, each publishing a preference to one collector.",
        stresses: "preference side-effect declaration · value-memo defeat · per-row re-measure",
        make: { config in AnyView(PreferenceRowsView(config: config)) }
    )
}

/// Collects the row indices that published, so the collector is real work
/// rather than a discarded value.
private struct RowIndexKey: PreferenceKey {
    static var defaultValue: [Int] { [] }

    static func reduce(value: inout [Int], nextValue: () -> [Int]) {
        value.append(contentsOf: nextValue())
    }
}

private struct PreferenceRowsView: View {
    let config: StressConfig

    @State private var collected: Int = 0

    var body: some View {
        let count = config.sized(400)
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.preferences.heading", count, collected)).bold()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        Text(Synth.slug(mix(config.seed, index)))
                            .preference(key: RowIndexKey.self, value: [index])
                    }
                }
            }
        }
        .onPreferenceChange(RowIndexKey.self) { indices in
            collected = indices.count
        }
    }
}
