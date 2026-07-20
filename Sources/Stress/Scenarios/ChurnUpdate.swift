//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ChurnUpdate.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Churn Update

/// A large row set whose content depends on the shared `StressClock.tick`, so
/// **every** row changes on every frame. This is the worst case for re-render
/// and cache invalidation: there are no unchanged subtrees to memoise, so each
/// frame pays the full measure + render cost. Drive it with `--autopilot` (or
/// the in-app autopilot toggle) to get a continuous, steady stream of
/// all-invalidating frames to profile.
enum ChurnUpdateScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "churn",
        title: "Churn Update",
        blurb: "N rows whose content changes every frame (tick-driven) — no memo hits.",
        stresses: "full re-render per frame · cache invalidation · measure with no memo",
        make: { config in AnyView(ChurnUpdateView(config: config)) }
    )
}

private struct ChurnUpdateView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(300)
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.churn.heading", tick, count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        // Folding `tick` into the hash makes the row differ every
                        // frame, so nothing memoises.
                        let h = mix(config.seed, index &+ tick)
                        HStack {
                            Text("#\(index)").foregroundStyle(.secondary)
                            Text(Synth.slug(h))
                            Spacer()
                            Text(Synth.bar(Double(h % 100) / 100, width: 14)).foregroundStyle(.accent)
                        }
                    }
                }
            }
        }
    }
}
