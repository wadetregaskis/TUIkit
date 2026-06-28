//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Dashboard.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Dashboard

/// A dense grid of metric panels — each a `Panel` containing labelled bars and
/// a `ProgressView`. Mixes the labelled-container measure path (`Panel`/`Card`)
/// with flexible-width sharing (`maxWidth: .infinity` across a row) at realistic
/// breadth. This is the closest scenario to a "real, complex" screen, so it
/// doubles as the showy demo — but its job is to stress the container +
/// flexible-frame pipeline together.
enum DashboardScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "dashboard",
        title: "Dashboard",
        blurb: "A grid of N metric Panels (bars + progress) — dense container layout.",
        stresses: "Panel/Card container measure · flexible-width row sharing · mixed leaves",
        make: { config in AnyView(DashboardView(config: config)) }
    )
}

private struct DashboardView: View {
    let config: StressConfig

    var body: some View {
        let cards = config.sized(12)
        let columns = 3
        let rows = (cards + columns - 1) / columns
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.dashboard.heading", cards)).bold()
            Divider()
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                if index < cards {
                                    MetricCard(seed: config.seed, index: index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One metric panel. `internal` so `KitchenSink` can reuse it.
struct MetricCard: View {
    let seed: UInt64
    let index: Int

    var body: some View {
        let h = mix(seed, index)
        Panel(Synth.slug(h)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Synth.name(h)).foregroundStyle(.accent)
                ForEach(0..<4, id: \.self) { metric in
                    let value = Double(mix(h, metric) % 100) / 100
                    HStack {
                        Text("m\(metric)").foregroundStyle(.secondary)
                        Spacer()
                        Text(Synth.bar(value, width: 8))
                    }
                }
                ProgressView(value: Double(h % 100) / 100, total: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
