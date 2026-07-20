//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollFollow.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Scroll Follow

/// The follow-the-log flagship of "Locating things without drawing them" as
/// a steady-state benchmark: a bottom-anchored `ScrollView` over N rows of
/// **variable height** (so the anchored seek path — rebind, advance, running
/// pitch estimate, band assembly — is engaged, not uniform arithmetic), with
/// one row appended every tick. Every frame pays the windowed pipeline end
/// to end at the tail: tail estimate → band render at the new maximum →
/// re-glue. Per-frame cost must be O(window), independent of N — this
/// scenario exists so a regression back toward O(N) shows up in `--bench`
/// numbers rather than in a user's million-line log viewer.
enum ScrollFollowScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "scrollfollow",
        title: "Scroll Follow",
        blurb: "Bottom-anchored ScrollView over N variable-height rows; a row appends every tick.",
        stresses: "windowed band render · anchor advance · tail estimate · O(window) at any N",
        make: { config in AnyView(ScrollFollowView(config: config)) }
    )
}

private struct ScrollFollowView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(1_000_000) + clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.scrollfollow.heading", count)).bold()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        ScrollFollowRow(seed: config.seed, index: index)
                    }
                }
            }
            .defaultScrollAnchor(.bottom)
        }
    }
}

/// One synthesised log line, 1–3 cells tall (`Equatable` so unchanged rows
/// value-memoize, exactly like an app's rows would).
private struct ScrollFollowRow: View, Equatable {
    let seed: UInt64
    let index: Int

    var body: some View {
        let h = mix(seed, index)
        Text("#\(index) \(Synth.slug(h)) \(Synth.status(h))")
            .foregroundStyle(statusColor(h))
            .frame(height: Int(h % 3) + 1)
    }
}
