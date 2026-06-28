//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DeepRecursion.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Deep Recursion

/// A single view nested inside itself to a configurable depth, each level
/// wrapping the next in a bordered, padded `VStack`. Builds a long parent chain
/// to stress structural `ViewIdentity` construction (one node per descent), the
/// measure recursion depth, and environment/context propagation down a deep
/// spine — the opposite shape to the wide scenarios.
enum DeepRecursionScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "deep",
        title: "Deep Recursion",
        blurb: "One view nested in itself to depth D (bordered/padded at each level).",
        stresses: "ViewIdentity chain depth · measure recursion · context propagation",
        make: { config in AnyView(DeepRecursionView(depth: config.sized(40), seed: config.seed)) }
    )
}

private struct DeepRecursionView: View {
    let depth: Int
    let seed: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.deep.heading", depth)).bold()
            Divider()
            ScrollView {
                Nest(level: 0, maxDepth: depth, seed: seed)
            }
        }
    }
}

/// A nominal recursive `View`: its `body` contains another `Nest`, so the tree
/// is exactly `maxDepth` levels deep. (Recursion through a nominal type is
/// finite — the opaque body type does not unfold `Nest` itself.)
private struct Nest: View {
    let level: Int
    let maxDepth: Int
    let seed: UInt64

    var body: some View {
        let h = mix(seed, level)
        if level >= maxDepth {
            Text(Lf("stress.scenario.deep.leaf", level, Synth.slug(h))).foregroundStyle(.accent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(Lf("stress.scenario.deep.level", level)).foregroundStyle(level.isMultiple(of: 2) ? .secondary : .primary)
                Self(level: level + 1, maxDepth: maxDepth, seed: seed)
                    .padding(1)
            }
            .border()
        }
    }
}
