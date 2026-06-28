//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KitchenSink.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Kitchen Sink

/// Everything at once: a `NavigationSplitView` with a large scrolling list in
/// the sidebar and a dense panel grid in the detail column. The point is the
/// combination — split layout + list windowing + container grid in one tree —
/// which is the kind of full-screen worst case a real complex TUI hits.
enum KitchenSinkScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "kitchensink",
        title: "Kitchen Sink",
        blurb: "Split view: big list sidebar + dense panel-grid detail, together.",
        stresses: "split-view layout + list windowing + container grid simultaneously",
        make: { config in AnyView(KitchenSinkView(config: config)) }
    )
}

private struct KitchenSinkView: View {
    let config: StressConfig

    var body: some View {
        let listCount = config.sized(2_000)
        let cards = config.sized(9)
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Lf("stress.scenario.kitchensink.heading.items", listCount)).bold()
                Divider()
                List {
                    ForEach(0..<listCount, id: \.self) { index in
                        let h = mix(config.seed, index)
                        HStack {
                            Text("#\(index)").foregroundStyle(.secondary)
                            Text(Synth.slug(h))
                            Spacer()
                            Text(Synth.status(h)).foregroundStyle(statusColor(h))
                        }
                    }
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("stress.scenario.kitchensink.heading.metrics")).bold()
                Divider()
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(0..<((cards + 2) / 3), id: \.self) { row in
                            HStack(spacing: 1) {
                                ForEach(0..<3, id: \.self) { column in
                                    let index = row * 3 + column
                                    if index < cards {
                                        MetricCard(seed: config.seed &+ 0x51, index: index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
