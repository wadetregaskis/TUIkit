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
    let config: StressConfig

    var body: some View {
        let count = config.sized(2_000)
        VStack(alignment: .leading, spacing: 0) {
            Text("Wide Fanout — \(count) siblings in one VStack").bold()
            Divider()
            // Inside a ScrollView so it's viewable, but the VStack itself is
            // non-lazy: all `count` children are laid out regardless of viewport.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        let h = mix(config.seed, index)
                        HStack {
                            Text("#\(index)").foregroundStyle(.secondary)
                            Text(Synth.slug(h))
                            Spacer()
                            Text(Synth.bar(Double(h % 100) / 100, width: 12)).foregroundStyle(.accent)
                        }
                    }
                }
            }
        }
    }
}
