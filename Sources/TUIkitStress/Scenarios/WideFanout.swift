//  🖥️ TUIKit — Terminal UI Kit for Swift
//  WideFanout.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Wide Fanout

/// A single **non-lazy** `VStack` with thousands of direct children (via
/// `ForEach`). Unlike `List`, a plain stack measures and renders *every* child
/// each frame — even the off-screen ones — so this is the deliberate O(n)
/// worst case for the container measure/distribute path, and the foil to
/// `MegaList`'s O(visible) windowing.
enum WideFanoutScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "fanout",
        title: "Wide Fanout",
        blurb: "One non-lazy VStack with N direct children (every child measured each frame).",
        stresses: "container measure over all children · space distribution · O(n) layout",
        make: { config in AnyView(WideFanoutView(config: config)) }
    )
}

private struct WideFanoutView: View {
    let count: Int
    /// Per-row label / slug / bar strings, synthesised ONCE in `init`.
    private let labels: [String]
    private let slugs: [String]
    private let bars: [String]

    init(config: StressConfig) {
        let count = config.sized(2_000)
        self.count = count
        // Synthesise the row content once, not in `body`. The strings are pure
        // functions of (seed, index); building them inline in `body` re-ran the
        // RNG, `Synth.slug` interpolation, and `Synth.bar` — which is two
        // `String(repeating:)` + a `+` — for all 2000 rows every frame, so the
        // bench measured the harness's transient String churn instead of the
        // container's O(n) layout (the thing this scenario exists to stress).
        var labels: [String] = []
        var slugs: [String] = []
        var bars: [String] = []
        labels.reserveCapacity(count)
        slugs.reserveCapacity(count)
        bars.reserveCapacity(count)
        for index in 0..<count {
            let h = mix(config.seed, index)
            labels.append("#\(index)")
            slugs.append(Synth.slug(h))
            bars.append(Synth.bar(Double(h % 100) / 100, width: 12))
        }
        self.labels = labels
        self.slugs = slugs
        self.bars = bars
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.fanout.heading", count)).bold()
            Divider()
            // Inside a ScrollView so it's viewable, but the VStack itself is
            // non-lazy: all `count` children are laid out regardless of viewport.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        HStack {
                            Text(labels[index]).foregroundStyle(.secondary)
                            Text(slugs[index])
                            Spacer()
                            Text(bars[index]).foregroundStyle(.accent)
                        }
                    }
                }
            }
        }
    }
}
