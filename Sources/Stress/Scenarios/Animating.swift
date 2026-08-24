//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Animating.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Animating

/// Many rows all animating at once, driven by a value that changes every frame.
///
/// The point is the *animator*, not the drawing. Every row is `Animatable`, so
/// every one of them is looked up in the animation store, interpolated, and
/// re-rendered on every frame — and none of them can be memoized, because a
/// subtree whose picture is a function of time declares itself uncacheable.
/// That is the shape a page full of moving parts actually has, and it is the
/// one that would silently regress if the store's per-view cost grew.
///
/// A quarter of the rows carry a colour animation instead, which takes the
/// other route: colours cannot go through `Animatable` (a semantic colour is
/// not components until it meets a palette), so those rows exercise the
/// render-time path in `ColorAnimation`.
enum AnimatingScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "animating",
        title: "Animating",
        blurb: "N rows interpolating at once, none of them cacheable.",
        stresses: "animation store lookups · uncacheable subtrees · colour resolution per frame",
        make: { config in AnyView(AnimatingView(config: config)) }
    )
}

/// A bar whose fill is one continuous number — the shape an app writes.
private struct AnimatedBar: View, Animatable {
    var fraction: Double
    let width: Int
    let label: String

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        let filled = Int((Double(width) * clamped).rounded())
        HStack(spacing: 1) {
            Text(label)
            Text(String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled))
        }
    }
}

private struct AnimatingView: View {
    let config: StressConfig

    /// The harness's own frame counter, so every frame is a change and the
    /// animator is always mid-flight rather than settled — and deterministic,
    /// which a wall-clock `Task` would not be. A benchmark that measured a
    /// different number of in-flight animations each run would measure nothing.
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(200)
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.animating.heading", count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        row(index, tick: tick)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ index: Int, tick: Int) -> some View {
        let phase = Double(mix(config.seed, index &+ tick) % 100) / 100
        if index.isMultiple(of: 4) {
            // The colour route: resolved and interpolated at render time.
            Text(Synth.slug(mix(config.seed, index)))
                .padding(.leading, 1)
                .background(phase > 0.5 ? .accentColor : .secondary)
                .animation(.easeInOut(duration: 0.4), value: tick)
        } else {
            AnimatedBar(fraction: phase, width: 24, label: Synth.slug(mix(config.seed, index)))
                .animation(.easeInOut(duration: 0.4), value: tick)
        }
    }
}
