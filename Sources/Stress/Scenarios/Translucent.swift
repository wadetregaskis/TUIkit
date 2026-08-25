//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Translucent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Translucent

/// A faded panel over a busy, changing destination — the worst case for
/// composite-time opacity, and the one nothing else here measures.
///
/// `.opacity(_:)` marks its subtree and the compositor resolves each of its
/// cells against the cell beneath, which means decomposing BOTH sides into
/// cells, blending, and re-emitting. The cost is a function of the faded
/// layer's AREA and of how often what is behind it changes: a pre-baked fade
/// over a still page pays once, while a fade over something that redraws every
/// frame pays every frame.
///
/// So this scenario makes both parts as unhelpful as possible: the destination
/// is a grid of coloured cells that changes with the harness's frame counter,
/// and the faded layers cover a large fraction of it. Half the rows also carry
/// a nested fade, because nesting multiplies at the stamp and the resolution
/// then takes the innermost region per cell — a lookup per cell that a single
/// flat region would not need.
enum TranslucentScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "translucent",
        title: "Translucent",
        blurb: "A large faded panel over a destination that redraws every frame.",
        stresses: "cell decomposition of both sides · per-cell region lookup · SGR re-emission",
        make: { config in AnyView(TranslucentView(config: config)) }
    )
}

private struct TranslucentView: View {
    let config: StressConfig

    /// The harness's frame counter. Driving the DESTINATION from it is the
    /// point: a faded layer over a still page can be composited once and
    /// replayed, so a benchmark whose destination never moved would measure the
    /// cheap case and report it as the expensive one.
    @Environment(StressClock.self) private var clock

    var body: some View {
        let rows = config.sized(120)
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.translucent.heading", rows)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { index in
                        row(index, tick: tick)
                    }
                }
            }
        }
    }

    /// One busy row with a faded label laid over it.
    ///
    /// The `ZStack` is what makes this a composite rather than a root
    /// resolution: the label's region is resolved against the band's cells, so
    /// both sides are decomposed. A faded view over the bare page would take
    /// the much cheaper path where the destination is a colour rather than a
    /// buffer.
    @ViewBuilder
    private func row(_ index: Int, tick: Int) -> some View {
        let shade = Int(mix(config.seed, index &+ tick) % 6)
        let alpha = 0.35 + Double(mix(config.seed, index) % 60) / 100.0
        ZStack(alignment: .leading) {
            Text(String(repeating: " ", count: 60))
                .background(Self.shades[shade])
            label(index, alpha: alpha, nested: index.isMultiple(of: 2))
        }
    }

    @ViewBuilder
    private func label(_ index: Int, alpha: Double, nested: Bool) -> some View {
        let text = Text(Synth.slug(mix(config.seed, index)))
            .foregroundStyle(.rgb(255, 240, 180))
        if nested {
            // Nesting multiplies at the stamp, so the cell is covered by two
            // regions and the resolution has to pick the innermost.
            text.opacity(alpha).padding(.leading, 2).opacity(0.8)
        } else {
            text.opacity(alpha).padding(.leading, 2)
        }
    }

    /// Six backgrounds far enough apart that a blend toward any of them lands
    /// somewhere different — a destination of one colour would let the SGR
    /// re-emission collapse to nothing.
    private static let shades: [Color] = [
        .rgb(30, 30, 60), .rgb(60, 30, 30), .rgb(30, 60, 30),
        .rgb(60, 60, 30), .rgb(30, 60, 60), .rgb(60, 30, 60),
    ]
}
